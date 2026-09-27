import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/chat_overlay.dart';
import 'player.dart';

const _kChatKey     = 'chat_history';
const _kMaxMessages = 200;

class SessionState {
  SessionState._();
  static final SessionState _instance = SessionState._();
  factory SessionState() => _instance;

  final List<ChatMessage> chat = [];
  Timer? _saveChatTimer;

  int _gameCount = 0;
  /// Returns the next starting player index (1-based) cycling through [playerCount] players.
  int nextStarterFor(int playerCount) => (_gameCount % playerCount) + 1;
  void advanceGame() => _gameCount++;

  String? myAvatarPath;
  // Encoded bytes of OUR avatar (lazy-loaded once per session; cleared on reset)
  String? _myAvatarB64Cache;
  // Per-sender avatar cache: sender name → bytes (populated on first received msg)
  final Map<String, Uint8List> _avatarCache = {};

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Loads persisted chat once per app run. After that the in-memory list is
  /// the source of truth, so re-entering the lobby never drops messages that
  /// are still waiting for the debounced save.
  bool _chatLoaded = false;
  Future<void> loadChat() async {
    if (_chatLoaded) return;
    _chatLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kChatKey);
      if (raw == null) return;
      final list  = jsonDecode(raw) as List;
      final loaded = <ChatMessage>[];
      for (final m in list) {
        final map = m as Map<String, dynamic>;
        final avatarB64 = map['avatar'] as String?;
        loaded.add(ChatMessage(
          sender:      map['sender'] as String,
          text:        map['text']   as String,
          color:       Color(map['color'] as int),
          mine:        map['mine']   as bool,
          avatarBytes: avatarB64 != null ? base64Decode(avatarB64) : null,
          msgId:       map['msgId']  as String?,
          read:        map['read']   as bool? ?? false,
        ));
      }
      // Anything already in memory arrived while prefs were loading — keep it
      // after the persisted history.
      chat.insertAll(0, loaded);
    } catch (_) {}
  }

  // Debounced — batches rapid chat exchanges into a single write
  void _scheduleSaveChat() {
    _saveChatTimer?.cancel();
    _saveChatTimer = Timer(const Duration(seconds: 5), _saveChat);
  }

  Future<void> _saveChat() async {
    try {
      // Keep only the most recent _kMaxMessages
      final toSave = chat.length > _kMaxMessages
          ? chat.sublist(chat.length - _kMaxMessages) : chat;
      final list = toSave.map((m) {
        String? b64;
        if (m.avatarBytes != null) b64 = base64Encode(m.avatarBytes!);
        return {
          'sender': m.sender,
          'text':   m.text,
          'color':  m.color.value,
          'mine':   m.mine,
          'msgId':  m.msgId,
          'read':   m.read,
          if (b64 != null) 'avatar': b64,
        };
      }).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kChatKey, jsonEncode(list));
    } catch (_) {}
  }

  // ── Session lifecycle ─────────────────────────────────────────────────────

  /// Preload avatar bytes asynchronously to avoid blocking the UI thread.
  Future<void> preloadAvatar() async {
    if (_myAvatarB64Cache != null || myAvatarPath == null) return;
    try {
      final bytes = await File(myAvatarPath!).readAsBytes();
      _myAvatarB64Cache = base64Encode(bytes);
    } catch (_) {}
  }

  /// Returns base64 of our avatar. Call [preloadAvatar] first to avoid sync I/O.
  String? get myAvatarB64 {
    if (_myAvatarB64Cache != null) return _myAvatarB64Cache;
    if (myAvatarPath == null) return null;
    // Fallback sync read — should rarely hit if preloadAvatar was called
    try {
      _myAvatarB64Cache = base64Encode(
          File(myAvatarPath!).readAsBytesSync());
    } catch (_) {}
    return _myAvatarB64Cache;
  }

  /// Returns cached avatar bytes for a given sender (null if not received yet).
  Uint8List? avatarFor(String sender) => _avatarCache[sender];

  /// Store received avatar bytes for a sender.
  void cacheAvatar(String sender, Uint8List bytes) {
    _avatarCache[sender] = bytes;
  }

  /// Called when entering lobby — resets game state but keeps chat history.
  void reset() {
    // Flush a pending debounced save instead of dropping it
    if (_saveChatTimer?.isActive ?? false) {
      _saveChatTimer?.cancel();
      _saveChat();
    }
    _saveChatTimer = null;
    _gameCount  = 0;
    myAvatarPath = null;
    _myAvatarB64Cache = null;
    _avatarCache.clear();
    // Chat is intentionally NOT cleared here — persists across sessions.
  }

  // ── Roster — connected HUMAN players, keyed by network index ─────────────
  // Host: maintained by Network (HELLO / PLAYER_LEFT / compaction) and
  // broadcast to joiners as ROSTER. Joiner: replaced on every ROSTER message.
  // CPU players never enter the roster. Cleared by Network.reset().
  final Map<int, Player> _roster = {};

  /// Bumped on every roster change — screens listen to rebuild.
  final rosterRevision = ValueNotifier<int>(0);

  /// Connected human players sorted by network index. After compaction the
  /// list index equals the network index.
  List<Player> get roster {
    final keys = _roster.keys.toList()..sort();
    return [for (final k in keys) _roster[k]!];
  }

  /// Same as [roster], with our own avatar attached to our entry (avatars are
  /// not sent over the network).
  List<Player> rosterFor(int myIdx) {
    final keys = _roster.keys.toList()..sort();
    return [
      for (final k in keys)
        k == myIdx && myAvatarPath != null && _roster[k]!.avatarPath == null
            ? _roster[k]!.copyWith(avatarPath: myAvatarPath)
            : _roster[k]!,
    ];
  }

  Map<int, Player> get rosterByIdx => Map.unmodifiable(_roster);

  void rosterPut(int idx, Player p) { _roster[idx] = p; _bumpRoster(); }

  Player? rosterRemove(int idx) {
    final p = _roster.remove(idx);
    if (p != null) _bumpRoster();
    return p;
  }

  void setRoster(Map<int, Player> players) {
    _roster..clear()..addAll(players);
    _bumpRoster();
  }

  void clearRoster() {
    if (_roster.isEmpty) return;
    _roster.clear();
    _bumpRoster();
  }

  /// Wire format of the ROSTER message: [{'idx','id','name','color'}, …]
  List<Map<String, dynamic>> rosterToJson() {
    final keys = _roster.keys.toList()..sort();
    return [for (final k in keys) {'idx': k, ..._roster[k]!.toJson()}];
  }

  void applyRosterJson(List<dynamic> list) {
    final next = <int, Player>{};
    for (final e in list) {
      try {
        final m = Map<String, dynamic>.from(e as Map);
        final idx = m['idx'] as int;
        final old = _roster[idx];
        final p = Player.fromJson(m);
        // Keep a locally known avatar for the same player
        next[idx] = (old != null && old.id == p.id && old.avatarPath != null)
            ? p.copyWith(avatarPath: old.avatarPath) : p;
      } catch (_) {}
    }
    setRoster(next);
  }

  /// Joiner: true if a host-sent player list (START_GAME / TOURNEY_START
  /// 'players', Player JSON in network-index order, CPU players appended) has
  /// US at our network index. False for a joiner that isn't part of that game
  /// (e.g. joined mid-tournament) — it must ignore the message.
  bool listIncludesMe(List<dynamic>? playersJson, int myIdx) {
    if (playersJson == null) return true; // legacy message without a list
    if (myIdx < 0 || myIdx >= playersJson.length) return false;
    final myId = _roster[myIdx]?.id;
    if (myId == null) return true; // no roster info yet — trust the host
    final entry = playersJson[myIdx];
    return entry is Map && entry['id'] == myId;
  }

  void _bumpRoster() => rosterRevision.value++;

  /// Clears chat history (explicit user action only).
  Future<void> clearChat() async {
    chat.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kChatKey);
  }

  // ── Message helpers ───────────────────────────────────────────────────────

  void addIncoming(String sender, String text, Color color, {Uint8List? avatarBytes, String? msgId}) {
    // Cache avatar bytes for this sender (only the first time we see their avatar)
    if (avatarBytes != null) _avatarCache.putIfAbsent(sender, () => avatarBytes);
    // Reuse cached avatar if the message didn't include one
    final bytes = avatarBytes ?? _avatarCache[sender];
    chat.add(ChatMessage(sender: sender, text: text, color: color,
      mine: false, avatarBytes: bytes, msgId: msgId));
    _scheduleSaveChat();
  }

  void addOutgoing(String sender, String text, Color color, {String? msgId}) {
    chat.add(ChatMessage(sender: sender, text: text, color: color,
      mine: true, avatarPath: myAvatarPath, msgId: msgId));
    _scheduleSaveChat();
  }
}
