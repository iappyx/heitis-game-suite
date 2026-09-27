import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/network.dart';
import '../core/player.dart';
import '../core/session.dart';
import '../core/sound_player.dart';
import '../core/wake_lock.dart';
import '../core/theme.dart';
import '../core/stats_store.dart';
import '../core/profile_store.dart';
import '../l10n/app_localizations.dart';
import '../screens/waiting_screen.dart';
import '../screens/lobby_screen.dart';
import '../core/games_registry.dart';
import 'chat_overlay.dart';
import 'game_over_actions.dart';
import 'game_scaffold.dart';
import 'reconnect_dialog.dart';

/// Shared logic for all game screens:
///  - PLAYER_LEFT / BACK_TO_SELECT handlers
///  - Chat send/receive
///  - Typing indicator (send + receive)
///  - Read receipts (CHAT_READ send + receive)
mixin GameMixin<T extends StatefulWidget> on State<T> {
  final _net     = Network();
  final _session = SessionState();

  /// Subscription to the network message stream. Set in each game's initState
  /// via `msgSub = _net.listen(_onMsg)`. Cancelled automatically in dispose().
  StreamSubscription<(Map<String, dynamic>, int)>? msgSub;

  /// Key passed to GameScaffold — allows calling triggerConfetti() at game end.
  final scaffoldKey = GlobalKey<GameScaffoldState>();

  /// Fire confetti from the GameScaffold overlay.
  /// Call at game-over: triggerWinConfetti() for a win, triggerWinConfetti(isDraw:true) for draw.
  void triggerWinConfetti({bool isDraw = false}) {
    scaffoldKey.currentState?.triggerConfetti(isDraw: isDraw);
  }

  // ── Stats + Confetti guards ─────────────────────────────────────────────────
  bool _confettiFired = false;
  bool _statRecorded  = false;

  /// Fires confetti exactly once per game. winnerIdx: 0-based, or -1 for draw.
  void fireConfettiOnce(int winnerIdx) {
    if (_confettiFired || gamePlayers.isEmpty) return;
    _confettiFired = true;
    final myIdx = _net.myIdx.clamp(0, gamePlayers.length - 1);
    if (winnerIdx < 0) {
      SoundPlayer.i.gameDraw();
      HapticFeedback.heavyImpact();
    } else if (winnerIdx == myIdx) {
      SoundPlayer.i.gameWin();
      HapticFeedback.heavyImpact();
    } else {
      SoundPlayer.i.gameLoss();
      HapticFeedback.heavyImpact();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      triggerWinConfetti(isDraw: winnerIdx < 0);
    });
  }

  /// Reset the confetti guard (call in game reset).
  void resetConfetti() => _confettiFired = false;

  /// Record stats for the local player once per game.
  void recordResult(String gameId, int winnerIdx) {
    if (_statRecorded || gamePlayers.isEmpty) return;
    _statRecorded = true;
    final myIdx  = _net.myIdx.clamp(0, gamePlayers.length - 1);
    final String result;
    if (winnerIdx < 0) {
      result = 'draw';
    } else if (winnerIdx == myIdx) {
      result = 'win';
    } else {
      result = 'loss';
    }
    // Key by stable profile ID; fall back to player name for legacy/guest sessions
    final profileId = ProfileStore().active?.id ?? gamePlayers[myIdx].name;
    StatsStore().record(profileId, gameId, result);
  }

  /// Reset stats recording guard (call in game reset).
  void resetStats() => _statRecorded = false;

  /// Call when it becomes the local player's turn.
  /// Plays a chime sound and triggers haptic feedback.
  void turnChanged() {
    SoundPlayer.i.uiSelect(); // short chime
    HapticFeedback.mediumImpact();
  }
  // Who among remote players is currently typing (shown in UI)
  String? _typingName;
  String? get typingName => _typingName;

  Timer? _typingClearTimer;  // clears _typingName after 4s of silence
  DateTime? _lastTypingSent; // throttle: don't send more than once per 2s

  // Avatar is only sent once per session — receiver caches it
  bool _avatarSent = false;

  // ── Subclass hooks ────────────────────────────────────────────────────────
  List<Player> get gamePlayers;

  // Set once this screen starts navigating back to WaitingScreen / to another
  // game, so a second BACK_TO_SELECT / PLAYER_LEFT / START_GAME is ignored.
  bool _leavingGame = false;

  /// Player list handed to WaitingScreen. WaitingScreen shows the live roster
  /// of connected humans anyway; this is only its fallback (never CPU players).
  List<Player> get _waitingPlayers {
    final roster = _session.roster;
    if (roster.isNotEmpty) return roster;
    return gamePlayers.where((p) => !p.id.startsWith('ai-')).toList();
  }

  // ── Standardised sync ──────────────────────────────────────────────────────
  // Override these two methods to opt in to the generic GAME_SYNC_REQ /
  // GAME_SYNC message pair.  Games that already have custom sync messages
  // (e.g. BUT_SYNC_REQ / BUT_SYNC) keep working — this is purely opt-in.

  /// Build the full game-state payload that the host sends to joiners.
  /// Return null to signal "nothing to sync" (the message won't be sent).
  /// Override this (and [applySyncPayload]) to opt in to the standardised
  /// GAME_SYNC_REQ / GAME_SYNC message pair handled by [handleCommonMessages].
  Map<String, dynamic>? buildSyncPayload() => null;

  /// Apply a sync payload received from the host.  Called inside setState()
  /// by [handleCommonMessages] when a GAME_SYNC message arrives.
  void applySyncPayload(Map<String, dynamic> payload) {}

  /// Send a full sync to all joiners (host only).
  /// Calls [buildSyncPayload]; if the result is non-null, sends GAME_SYNC.
  void sendGameSync() {
    if (!_net.isHost) return;
    final payload = buildSyncPayload();
    if (payload == null) return;
    _net.send('GAME_SYNC', payload);
  }

  /// Request a full sync from the host (joiner only).
  void requestGameSync() {
    if (_net.isHost) return;
    _net.send('GAME_SYNC_REQ');
  }

  /// Single source of truth for chat history — backed by SessionState.
  /// Games no longer maintain a local copy; this getter suffices for
  /// ChatOverlay and all mixin methods.
  List<ChatMessage> get chatMessages => _session.chat;

  // Called by game's _onMsg router — returns true if GameMixin consumed it
  bool handleChatMessage(String type, Map<String, dynamic> msg, int fromIdx) {
    switch (type) {
      case 'CHAT':
        handleIncomingChat(msg);
        return true;
      case 'CHAT_TYPING':
        _handleTyping(msg);
        return true;
      case 'CHAT_READ':
        _handleReadAck(msg);
        return true;
      default:
        return false;
    }
  }

  /// Call at the top of every game's _onMsg. Returns true if the message was
  /// handled by the mixin so the game can skip its own switch.
  ///
  /// Handles: CHAT, CHAT_TYPING, CHAT_READ, PLAYER_LEFT, BACK_TO_SELECT,
  ///          TOURNEY_POP, START_GAME, REMATCH_REQ (joiner→host quick rematch).
  bool handleCommonMessages(Map<String, dynamic> msg, int fromIdx) {
    final type = msg['type'] as String? ?? '';
    // Chat family — delegate to existing handleChatMessage which returns bool
    if (handleChatMessage(type, msg, fromIdx)) {
      if (type == 'CHAT') clearTyping();
      return true;
    }
    switch (type) {
      case 'PLAYER_LEFT':
        handlePlayerLeft(msg, fromIdx);
        return true;
      case 'PLAYER_AWAY':
      case 'PLAYER_BACK':
        // Hosted mode: a browser player's phone went dark / came back — the
        // host holds its seat meanwhile, so the game simply continues
        if (mounted) {
          final name = msg['name'] as String? ?? L.common.defaultPlayer;
          final away = msg['type'] == 'PLAYER_AWAY';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text((away ? L.common.playerAway : L.common.playerBack)
                .fmt({'player': name})),
            backgroundColor: away ? Colors.orange.shade800 : kPurple2,
            duration: Duration(seconds: away ? 6 : 2)));
        }
        return true;
      case 'BACK_TO_SELECT':
        handleBackToSelect(msg, fromIdx);
        return true;
      case 'TOURNEY_POP':
        handleTourneyPop();
        return true;
      case 'CLEAR_CHAT':
        _session.clearChat();
        if (mounted) setState(() {});
        return true;
      case 'START_GAME':
        // Non-host: host selected a different game — navigate away.
        // In tournament mode this is handled by TournamentScreen; skip here.
        if (!_net.isHost && mounted && !_net.isTournament && !_leavingGame) {
          final game  = msg['game'] as String?;
          final first = (msg['first'] as int?) ?? 1;
          if (game != null) {
            // Host sends the exact player list; fall back to the roster
            final playersJson = msg['players'] as List?;
            final players = playersJson != null
                ? playersJson.map((p) => Player.fromJson(
                    Map<String, dynamic>.from(p as Map))).toList()
                : _waitingPlayers;
            _net.currentGameInfo = {
              'game': game, 'first': first,
              'players': players.map((p) => p.toJson()).toList(),
              if (msg['cfg'] != null) 'cfg': msg['cfg'],
            };
            _leavingGame = true;
            WakeLock.acquire();
            Navigator.pushAndRemoveUntil(context, fadeScaleRoute(
              buildGameScreen(
                game, first, players, msg['cfg'] as Map<String, dynamic>?)),
              (_) => false);
          }
        }
        return true;

      // ── Joiner on game select while we (host) are in a game ────────────────
      // It missed START_GAME (e.g. in the one-frame gap between its lobby and
      // WaitingScreen subscriptions): resend it the running game — only if
      // it is part of that game at the index it has now.
      case 'WAITING_SYNC_REQ':
        final info = _net.currentGameInfo;
        if (_net.isHost && !_net.isTournament && info != null && fromIdx > 0) {
          final list = info['players'] as List?;
          final id = _session.rosterByIdx[fromIdx]?.id;
          if (list != null && fromIdx < list.length && id != null &&
              list[fromIdx] is Map && (list[fromIdx] as Map)['id'] == id) {
            _net.sendTo(fromIdx, 'START_GAME', Map<String, dynamic>.from(info));
          }
        }
        return true;

      // ── Rematch request (joiner → host) ────────────────────────────────────
      // Joiner tapped "Play Again" — host triggers the same reset as if the
      // host had pressed Play Again themselves.  The callback is registered by
      // GameOverActions when it builds.
      case 'REMATCH_REQ':
        if (_net.isHost) {
          final cb = GameOverActions.activeOnReset;
          if (cb != null) {
            if (GameOverActions.activeSendReset) _net.send('GAME_RESET');
            cb();
          }
        }
        return true;

      // ── Standardised game-state sync ──────────────────────────────────────
      // Games opt in by overriding buildSyncPayload() / applySyncPayload().
      // If buildSyncPayload() returns null the messages are silently ignored,
      // so games with custom sync (BUT_SYNC, KLA_STATE, etc.) are unaffected.
      case 'GAME_SYNC_REQ':
        if (_net.isHost) sendGameSync();
        return true;
      case 'GAME_SYNC':
        if (!_net.isHost) {
          setState(() => applySyncPayload(msg));
        }
        return true;

      default:
        return false;
    }
  }

  // ── PLAYER_LEFT ───────────────────────────────────────────────────────────
  // A player dropped mid-game: the game is abandoned and everyone goes back to
  // WaitingScreen, which shows the remaining connected players (roster) and
  // renumbers joiner indices there (host side).
  void handlePlayerLeft(Map<String, dynamic> msg, int fromIdx) {
    if (_leavingGame) return;
    final leftIdx  = msg['idx'] as int? ?? -1;
    final leftId   = msg['id'] as String?;
    // Someone who wasn't part of this game (e.g. waiting in their lobby) left
    if (leftId != null && !gamePlayers.any((p) => p.id == leftId)) return;
    final leftName = msg['name'] as String? ??
        (leftIdx >= 0 && leftIdx < gamePlayers.length
            ? gamePlayers[leftIdx].name : L.common.defaultPlayer);
    if (_net.isHost && mounted) {
      _leavingGame = true;
      _net.currentGameInfo = null;
      _net.send('BACK_TO_SELECT', {'leftName': leftName});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.common.playerLeftReturning.fmt({'player': leftName})),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 2)));
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) Navigator.pushAndRemoveUntil(context, fadeScaleRoute(
          WaitingScreen(
            players: _waitingPlayers, isHost: true, leftName: leftName)),
          (_) => false);
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.common.playerLeftGame.fmt({'player': leftName})),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 2)));
    }
  }

  // ── BACK_TO_SELECT ────────────────────────────────────────────────────────
  void handleBackToSelect(Map<String, dynamic> msg, int fromIdx) {
    if (!mounted || _leavingGame) return;
    if (_net.isSolo) return; // solo mode handles navigation via GameOverActions/GameScaffold
    _leavingGame = true;
    if (_net.isHost) {
      _net.currentGameInfo = null;
      _net.send('BACK_TO_SELECT');
      final name = _session.rosterByIdx[fromIdx]?.name ??
          (fromIdx < gamePlayers.length ? gamePlayers[fromIdx].name : L.common.defaultPlayer);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.common.playerWentSelect.fmt({'player': name})),
        backgroundColor: kPurple2));
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        WakeLock.release();
        Navigator.pushAndRemoveUntil(context, fadeScaleRoute(
          WaitingScreen(players: _waitingPlayers, isHost: true)),
          (_) => false);
      });
    } else {
      _net.currentGameInfo = null;
      WakeLock.release();
      Navigator.pushAndRemoveUntil(context, fadeScaleRoute(
        WaitingScreen(players: _waitingPlayers, isHost: false,
          leftName: msg['leftName'] as String?)),
        (_) => false);
    }
  }

  // ── TOURNEY_POP ────────────────────────────────────────────────────────────
  // Host sends this when recording a tournament result — tells clients to pop
  // back from the game screen to the TournamentScreen underneath.
  // TournamentScreen keeps its stream subscription active throughout, so it
  // will receive TOURNEY_RESULT regardless of timing.
  void handleTourneyPop() {
    if (!mounted || !_net.isTournament) return;
    WakeLock.release();
    Navigator.pop(context);
  }

  // ── Chat send ─────────────────────────────────────────────────────────────
  void sendChat(String t) {
    if (gamePlayers.isEmpty) return;
    final me = gamePlayers[_net.myIdx.clamp(0, gamePlayers.length - 1)];
    final msg = ChatMessage(sender: me.name, text: t, color: me.color,
        mine: true, avatarPath: _session.myAvatarPath);
    // Include avatar only on the first message — receiver caches it
    String? avatarB64;
    if (!_avatarSent) {
      avatarB64 = _session.myAvatarB64;
      if (avatarB64 != null) _avatarSent = true;
    }
    _net.send('CHAT', {
      'name': me.name, 'text': t, 'color': me.color.value,
      'msgId': msg.msgId,
      if (avatarB64 != null) 'avatar': avatarB64,
    });
    _session.addOutgoing(me.name, t, me.color, msgId: msg.msgId);
    if (mounted) setState(() {});
  }

  // ── Chat receive ──────────────────────────────────────────────────────────
  void handleIncomingChat(Map<String, dynamic> msg) {
    if (!mounted) return;
    final senderRaw = msg['name'] as String? ?? '';
    final sender = senderRaw.length > 50 ? senderRaw.substring(0, 50) : senderRaw;
    final textRaw = msg['text'] as String? ?? '';
    final rawText = textRaw.length > 200 ? textRaw.substring(0, 200) : textRaw;
    final color  = Color(msg['color'] as int? ?? 0xFF888888);
    final msgId  = msg['msgId'] as String?;
    if (msg['avatar'] != null) {
      final b64 = msg['avatar'] as String;
      if (b64.length <= 500 * 1024) {
        final bytes = base64Decode(b64);
        _session.cacheAvatar(sender, bytes);
      }
    }
    final bytes = _session.avatarFor(sender);
    _session.addIncoming(sender, rawText, color, avatarBytes: bytes, msgId: msgId);
    if (mounted) setState(() {});
  }

  // ── Typing: send ──────────────────────────────────────────────────────────
  /// Call this whenever the local user types a character in the chat input.
  void onLocalTyping() {
    if (gamePlayers.isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!).inMilliseconds < 2000) return;
    _lastTypingSent = now;
    final me = gamePlayers[_net.myIdx.clamp(0, gamePlayers.length - 1)];
    _net.send('CHAT_TYPING', {'name': me.name});
  }

  // ── Typing: receive ───────────────────────────────────────────────────────
  void _handleTyping(Map<String, dynamic> msg) {
    if (!mounted) return;
    final name = msg['name'] as String? ?? '';
    _typingClearTimer?.cancel();
    setState(() => _typingName = name);
    // Auto-clear after 4 s of no new CHAT_TYPING
    _typingClearTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _typingName = null);
    });
  }

  /// Call this when the remote player sends an actual CHAT message,
  /// to immediately clear their typing indicator.
  void clearTyping() {
    _typingClearTimer?.cancel();
    if (_typingName != null && mounted) setState(() => _typingName = null);
  }

  // ── Read receipts: send ───────────────────────────────────────────────────
  /// Called by GameScaffold when chat panel opens (or new messages arrive while open).
  /// Sends ACK for all incoming message IDs so senders can show ✓✓.
  void sendReadAck(List<String> msgIds) {
    if (msgIds.isEmpty) return;
    _net.send('CHAT_READ', {'ids': msgIds});
  }

  // ── Read receipts: receive ────────────────────────────────────────────────
  void _handleReadAck(Map<String, dynamic> msg) {
    if (!mounted) return;
    final ids = (msg['ids'] as List).cast<String>().toSet();
    bool changed = false;
    // Mark in local list
    for (final m in chatMessages) {
      if (m.mine && !m.read && ids.contains(m.msgId)) {
        m.read = true;
        changed = true;
      }
    }
    // Also mark in session list so the flag survives screen transitions
    for (final m in _session.chat) {
      if (m.mine && !m.read && ids.contains(m.msgId)) {
        m.read = true;
      }
    }
    if (changed) setState(() {});
  }

  // ── Reconnect helper ────────────────────────────────────────────────────────
  // Standard reconnect dialog that re-subscribes to the network stream and
  // automatically sends/requests a GAME_SYNC.  Games that override
  // buildSyncPayload()/applySyncPayload() get sync for free.
  //
  // [onMsg]           — the game's _onMsg handler to re-subscribe to.
  // [onReconnected]   — optional extra callback run after re-subscribing
  //                     (e.g. restart timers). Runs AFTER the sync send/request.
  // [onExit]          — optional override for the Exit button. Defaults to
  //                     navigating to LobbyScreen.
  void showReconnectDialog({
    required void Function(Map<String, dynamic>, int) onMsg,
    VoidCallback? onReconnected,
    VoidCallback? onExit,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(onMsg);
          _net.onDisconnected = () {
            if (mounted) {
              showReconnectDialog(
                onMsg: onMsg,
                onReconnected: onReconnected,
                onExit: onExit,
              );
            }
          };
          // Automatically sync using the standardised helpers.
          if (_net.isHost) {
            sendGameSync();
          } else {
            requestGameSync();
          }
          onReconnected?.call();
        },
        onExit: onExit ?? () => Navigator.pushAndRemoveUntil(
          context,
          fadeScaleRoute(const LobbyScreen()),
          (_) => false,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _typingClearTimer?.cancel();
    msgSub?.cancel(); // cancel network message subscription
    // Each game screen holds its own msgSub and cancels it here via the
    // generated dispose() from the conversion script. No global handler to null.
    WakeLock.release();
    super.dispose();
  }
}
