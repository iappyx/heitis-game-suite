import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/network.dart';
import '../core/wake_lock.dart';
import '../core/player.dart';
import '../core/theme.dart';
import '../core/session.dart';
import '../widgets/chat_overlay.dart';
import '../screens/game_browse_screen.dart';
import '../games/rekkenje/rekkenje_screen.dart';
import '../games/rekkenje/rekkenje_state.dart';
import '../games/rekkenje/rekkenje_config_dialog.dart';
import 'lobby_screen.dart';
import '../widgets/reconnect_dialog.dart';
import '../core/games_registry.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_version.dart';
import 'stats_screen.dart';
import 'tournament_screen.dart';
import '../widgets/web_invite.dart';


class WaitingScreen extends StatefulWidget {
  /// Fallback only — the screen shows the live roster of connected human
  /// players (SessionState().roster, kept by the host and broadcast as
  /// ROSTER). Callers may pass a game's player list; CPU players ('ai-…')
  /// and departed players are never taken from it while a roster exists.
  final List<Player> players;
  final bool isHost;
  final String? leftName; // set when arriving because a player left mid-game
  const WaitingScreen({super.key, required this.players, required this.isHost, this.leftName});
  @override State<WaitingScreen> createState() => _WaitingState();
}

class _WaitingState extends State<WaitingScreen> {
  String _selectedGame = 'boppeslach';
  String _hostSelectedGame = 'boppeslach'; // what joiner sees host has selected
  final _net = Network();
  StreamSubscription<(Map<String, dynamic>, int)>? _msgSub;
  final _session = SessionState();
  bool _showChat = false;
  int _unread = 0;
  // Re-entry guard: a fast double tap on Start must not send START_GAME twice.
  // Stays set once a game launches (this screen is replaced); reset on cancel/failure.
  bool _starting = false;
  // Set once we navigate away to a game/tournament: further START_GAME /
  // TOURNEY_START / chat for this (dying) screen are ignored.
  bool _leaving = false;

  // ── Chat extras (mirrors GameMixin) ──────────────────────────────────────
  String? _typingName;
  Timer?   _typingClearTimer;
  DateTime? _lastTypingSent;
  bool     _avatarSent = false;

  /// Connected human players in network-index order (roster), falling back
  /// to the constructor list without CPU players.
  List<Player> get _players {
    final roster = _session.rosterFor(_net.myIdx);
    if (roster.isNotEmpty) return roster;
    return widget.players.where((p) => !p.id.startsWith('ai-')).toList();
  }

  int get _playerCount => _players.length;

  bool _gameAvailable(GameInfo g) {
    return g.maxPlayers == null || _playerCount <= g.maxPlayers!;
  }

  @override void initState() {
    super.initState();
    WakeLock.release(); // re-acquired in _launch/_startRekkenje when a game begins
    // Auto-select first available game
    final first = kGames.firstWhere((g) => _gameAvailable(g), orElse: () => kGames[0]);
    _selectedGame = first.id;

    _msgSub?.cancel(); _msgSub = _net.listen(_onMsg);
    // Show reconnect dialog on disconnect for both host and joiner
    _net.onDisconnected = () {
      if (mounted) _showReconnect();
    };
    _session.rosterRevision.addListener(_onRosterChanged);
    if (_net.isHost) {
      // Back at game select: nobody is in a game any more.
      _net.currentGameInfo = null;
      _net.ensureDiscoverable(); // let players (re)join from their lobby
      // After the first frame (roster listeners may call setState): renumber
      // joiners to 1..n-1 (drops departed players), re-broadcast the roster,
      // then pull in anyone still on a game screen or waiting in their lobby.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _leaving) return;
        if (!_net.compactRoster()) {
          _net.send('ROSTER', {'players': _session.rosterToJson()});
        }
        _net.send('BACK_TO_SELECT');
        _net.send('WAITING_SYNC', {'id': _selectedGame});
      });
    } else {
      // Ask the host which game is selected (we may have missed GAME_SELECTED)
      _net.send('WAITING_SYNC_REQ', {});
    }

    // Show who caused the return to game select
    if (widget.leftName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.common.playerLeft.fmt({'player': widget.leftName ?? '?'})),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 3)));
      });
    }
  }

  void _onRosterChanged() {
    if (!mounted) return;
    setState(() {});
    // Host: a joiner arrived and the selected game no longer fits
    if (_net.isHost && !_leaving) {
      final gi = kGames.where((g) => g.id == _selectedGame);
      if (gi.isNotEmpty && !_gameAvailable(gi.first)) {
        final first = kGames.firstWhere((g) => _gameAvailable(g), orElse: () => kGames[0]);
        _selectedGame = first.id;
        _net.send('GAME_SELECTED', {'id': first.id});
      }
    }
  }

  /// Navigate to a game / tournament, replacing EVERYTHING (also a StatsScreen
  /// or other route pushed on top of this one) so this screen can't linger
  /// underneath with a live message subscription.
  void _leaveTo(Widget page) {
    _leaving = true;
    Navigator.pushAndRemoveUntil(context, fadeScaleRoute(page), (_) => false);
  }

  @override void dispose() {
    _session.rosterRevision.removeListener(_onRosterChanged);
    _msgSub?.cancel();
    _typingClearTimer?.cancel();
    _net.onDisconnected = null;
    super.dispose();
  }

  void _showReconnect() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          _msgSub?.cancel(); _msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          // Joiner asks host to resend selected game so UI is back in sync
          if (!_net.isHost) _net.send('WAITING_SYNC_REQ', {});
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false),
      ),
    );
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (_leaving) return;
    final type = msg['type'] as String;
    if (type == 'HELLO') {
      // Host: a player (re)joined while we're on game select — Network already
      // added them to the roster; bring them to this screen as a normal player.
      if (_net.isHost) {
        _net.sendTo(fromIdx, 'BACK_TO_SELECT');
        _net.sendTo(fromIdx, 'WAITING_SYNC', {'id': _selectedGame});
      }
      return;
    }
    if (type == 'PLAYER_LEFT') {
      // Host: nobody is in a game — renumber the remaining joiners right away.
      // Not while a start is in progress (START_GAME may already be out; a
      // REINDEX now would desync the game): the start paths compact right
      // before sending, and a cancelled start compacts in its finally.
      if (_net.isHost && !_starting) _net.compactRoster();
      final name = msg['name'] as String?;
      if (name != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.common.playerLeft.fmt({'player': name})),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 3)));
      }
      return;
    }
    if (type == 'WAITING_SYNC_REQ') {
      // Joiner reconnected — host resends the currently selected game
      if (_net.isHost) _net.send('WAITING_SYNC', {'id': _selectedGame});
      return;
    }
    if (type == 'WAITING_SYNC') {
      // Host told us which game is currently selected
      if (!_net.isHost && mounted) {
        setState(() => _hostSelectedGame = msg['id'] as String? ?? _hostSelectedGame);
      }
      return;
    }
    if (type == 'GAME_SELECTED') {
      if (mounted) setState(() => _hostSelectedGame = msg['id'] as String);
      return;
    }
    if (type == 'TOURNEY_START') {
      if (!_net.isHost && mounted) {
        // Use the host's player list (captured when it opened the setup) so
        // both sides agree on the indices; ignore a tournament we're not in.
        final playersJson = msg['players'] as List?;
        if (!_session.listIncludesMe(playersJson, _net.myIdx)) return;
        final rawRounds = msg['rounds'] as List;
        final rounds = rawRounds.map((r) => TournamentRound(
          gameId:      r['game'] as String,
          firstPlayer: r['first'] as int,
        )).toList();
        final players = playersJson != null
            ? _withMyAvatar(playersJson
                .map((p) => Player.fromJson(Map<String, dynamic>.from(p as Map)))
                .toList())
            : _players;
        final tourney = Tournament(players: players, rounds: rounds);
        _leaveTo(TournamentScreen(tournament: tourney));
      }
      return;
    }
    if (type == 'START_GAME') {
      if (_net.isHost) return;
      final extra = msg['cfg'] as Map<String, dynamic>?;
      // The host sends the exact player list of the game (roster, plus CPU
      // players for some games) — use it so both sides agree on the indices.
      final playersJson = msg['players'] as List?;
      // A game we're not part of (e.g. we joined while it was being started)
      if (!_session.listIncludesMe(playersJson, _net.myIdx)) return;
      if (playersJson != null) {
        final allPlayers = _withMyAvatar(playersJson
            .map((p) => Player.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList());
        _net.currentGameInfo = {
          'game': msg['game'] as String, 'first': msg['first'] as int,
          'players': playersJson,
          if (extra != null) 'cfg': extra,
        };
        WakeLock.acquire();
        if (mounted) {
          _leaveTo(buildGameScreen(
              msg['game'] as String, msg['first'] as int, allPlayers, extra));
        }
      } else {
        _launch(msg['game'] as String, msg['first'] as int, extra);
      }
      return;
    }
    if (type == 'CHAT') {
      setState(() {
        final sender = msg['name'] as String;
        final color  = Color(msg['color'] as int);
        final msgId  = msg['msgId'] as String?;
        if (msg['avatar'] != null) {
          _session.cacheAvatar(sender, base64Decode(msg['avatar'] as String));
        }
        _session.addIncoming(sender, msg['text'] as String, color,
            avatarBytes: _session.avatarFor(sender), msgId: msgId);
        if (!_showChat) _unread++;
      });
      // Clear typing indicator when the actual message arrives
      _typingClearTimer?.cancel();
      if (_typingName != null && mounted) setState(() => _typingName = null);
      // Send read ACK if chat is open
      if (_showChat) _sendReadAck();
      return;
    }
    if (type == 'CHAT_TYPING') {
      final name = msg['name'] as String;
      _typingClearTimer?.cancel();
      if (mounted) setState(() => _typingName = name);
      _typingClearTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _typingName = null);
      });
      return;
    }
    if (type == 'CLEAR_CHAT') {
      _session.clearChat();
      if (mounted) setState(() { _unread = 0; });
      return;
    }
    if (type == 'CHAT_READ') {
      final ids = (msg['ids'] as List).cast<String>().toSet();
      bool changed = false;
      for (final m in _session.chat) {
        if (m.mine && !m.read && ids.contains(m.msgId)) {
          m.read = true;
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
      return;
    }
  }

  /// Players decoded from the network have no avatar — attach ours locally.
  List<Player> _withMyAvatar(List<Player> list) {
    final myId = _session.rosterByIdx[_net.myIdx]?.id;
    final path = _session.myAvatarPath;
    if (myId == null || path == null) return list;
    return [for (final p in list) p.id == myId ? p.copyWith(avatarPath: path) : p];
  }

  /// Games that support adding CPU players in multiplayer.
  static const _cpuGames = {'ienentritich'};

  Future<void> _startGame() async {
    if (_starting) return;
    if (!_gameAvailable(kGames.firstWhere((g) => g.id == _selectedGame))) return;
    if (_selectedGame == 'rekkenje') { _startRekkenje(); return; }

    _starting = true;
    bool launched = false;
    try {
      // For games that support adding CPU players in multiplayer
      if (_cpuGames.contains(_selectedGame)) {
        final gi = kGames.firstWhere((g) => g.id == _selectedGame);
        final maxCpu = (gi.maxPlayers ?? 4) - _players.length;
        if (maxCpu > 0) {
          final cpuCount = await _showCpuCountDialog(maxCpu);
          if (cpuCount == null || !mounted) return; // cancelled
          if (cpuCount > 0) {
            await _startGameWithCpu(cpuCount);
            launched = true;
            return;
          }
        }
      }

      // Renumber first (a player may have left while a dialog was open —
      // PLAYER_LEFT doesn't compact while _starting), then take the list.
      _net.compactRoster();
      final players = _players;
      final first = _session.nextStarterFor(players.length);
      _session.advanceGame();
      await _net.sendAndFlush('START_GAME', {
        'game': _selectedGame, 'first': first,
        'players': players.map((p) => p.toJson()).toList(),
      });
      _launch(_selectedGame, first, null, players);
      launched = true;
    } finally {
      if (!launched) _startAborted();
    }
  }

  /// A start was cancelled or failed: allow a new one and catch up on the
  /// compaction PLAYER_LEFT skipped while _starting was set.
  void _startAborted() {
    _starting = false;
    if (_net.isHost && mounted && !_leaving) _net.compactRoster();
  }

  Future<int?> _showCpuCountDialog(int maxCpu) {
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: kBg2,
          title: Text(L.common.addComputers, style: const TextStyle(color: kText, fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${_players.length} ${L.common.humanPlayers}',
              style: const TextStyle(color: kMuted, fontSize: 13)),
            const SizedBox(height: 12),
            ...List.generate(maxCpu + 1, (i) {
              final label = i == 0
                  ? L.common.noComputers
                  : '$i ${i == 1 ? L.common.computer : L.common.computers}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: SizedBox(width: double.infinity, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple2,
                    foregroundColor: kText,
                  ),
                  onPressed: () => Navigator.pop(ctx, i),
                  child: Text(label),
                )),
              );
            }),
          ]),
        );
      },
    );
  }

  Future<void> _startGameWithCpu(int cpuCount) async {
    final aiColors = [
      const Color(0xFF9E9E9E),
      const Color(0xFFFF7043),
      const Color(0xFF29B6F6),
    ];
    final aiNames = [
      L.common.soloComputerName,
      '${L.common.soloComputerName} 2',
      '${L.common.soloComputerName} 3',
    ];
    _net.compactRoster(); // see _startGame
    final allPlayers = [
      ..._players,
      ...List.generate(cpuCount, (i) => Player(
        id: 'ai-$i', name: aiNames[i], color: aiColors[i])),
    ];
    final first = _session.nextStarterFor(allPlayers.length);
    _session.advanceGame();
    final extra = {'cpuCount': cpuCount, 'difficulty': 1};
    await _net.sendAndFlush('START_GAME', {
      'game': _selectedGame, 'first': first, 'cfg': extra,
      'players': allPlayers.map((p) => p.toJson()).toList(),
    });
    // Launch with expanded player list
    _net.currentGameInfo = {
      'game': _selectedGame, 'first': first,
      'players': allPlayers.map((p) => p.toJson()).toList(),
      'cfg': extra,
    };
    WakeLock.acquire();
    if (!mounted) return;
    _leaveTo(buildGameScreen(_selectedGame, first, allPlayers, extra));
  }

  Future<void> _startRekkenje() async {
    if (_starting) return;
    _starting = true;
    bool launched = false;
    try {
      final cfg = await showDialog<RekkenjeConfig>(
        context: context, builder: (_) => const RekkenjeConfigDialog());
      if (cfg == null || !mounted) return;
      _net.compactRoster(); // see _startGame
      final players = _players;
      final first = _session.nextStarterFor(players.length);
      _session.advanceGame();
      await _net.sendAndFlush('START_GAME', {
        'game': 'rekkenje', 'first': first, 'cfg': cfg.toJson(),
        'players': players.map((p) => p.toJson()).toList(),
      });
      _net.currentGameInfo = {
        'game': 'rekkenje', 'first': first,
        'players': players.map((p) => p.toJson()).toList(),
        'cfg': cfg.toJson(),
      };
      WakeLock.acquire();
      if (!mounted) return;
      _leaveTo(RekkenjeScreen(players: players, firstPlayer: first, config: cfg));
      launched = true;
    } finally {
      if (!launched) _startAborted();
    }
  }

  /// Host: open the tournament setup REPLACING this screen (like a game
  /// launch), so no hidden WaitingScreen keeps handling HELLO / PLAYER_LEFT
  /// (compaction, BACK_TO_SELECT) underneath the tournament. Every way out
  /// of setup/tournament pushes a fresh WaitingScreen.
  void _openTournamentSetup() {
    if (_starting || _leaving) return;
    _net.compactRoster(); // list index must equal network index
    _leaveTo(TournamentSetupScreen(players: _players));
  }

  void _launch(String game, int firstPlayer,
      [Map<String, dynamic>? extra, List<Player>? players]) {
    if (!mounted) return;
    final list = players ?? _players;
    // Store current game info (marks "in a game"; also used for the Hero
    // animation icon in GameScaffold).
    _net.currentGameInfo = {
      'game':    game,
      'first':   firstPlayer,
      'players': list.map((p) => p.toJson()).toList(),
      if (extra != null) 'cfg': extra,
    };
    WakeLock.acquire();
    _leaveTo(buildGameScreen(game, firstPlayer, list, extra));
  }

  void _sendChat(String text) {
    final players = _players;
    if (players.isEmpty) return;
    final me = players[_net.myIdx.clamp(0, players.length - 1)];
    // ChatMessage auto-generates a device-prefixed msgId — use the same id everywhere
    final cm = ChatMessage(sender: me.name, text: text, color: me.color,
        mine: true, avatarPath: _session.myAvatarPath);
    // Send avatar only on first message — receiver caches it
    String? avatarB64;
    if (!_avatarSent) {
      avatarB64 = _session.myAvatarB64;
      if (avatarB64 != null) _avatarSent = true;
    }
    _net.send('CHAT', {
      'name': me.name, 'text': text, 'color': me.color.value,
      'msgId': cm.msgId,
      if (avatarB64 != null) 'avatar': avatarB64,
    });
    setState(() {
      _session.addOutgoing(me.name, text, me.color, msgId: cm.msgId);
    });
  }

  void _onLocalTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!).inMilliseconds < 2000) return;
    _lastTypingSent = now;
    final players = _players;
    if (players.isEmpty) return;
    _net.send('CHAT_TYPING', {'name': players[_net.myIdx.clamp(0, players.length - 1)].name});
  }

  void _sendReadAck() {
    final unread = _session.chat
        .where((m) => !m.mine && !m.read && m.msgId.isNotEmpty)
        .toList();
    if (unread.isEmpty) return;
    final ids = unread.map((m) => m.msgId).toList();
    for (final m in unread) { m.read = true; }
    _net.send('CHAT_READ', {'ids': ids});
  }

  @override Widget build(BuildContext ctx) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment.topCenter, radius: 1.2,
          colors: [Color(0xFF2D1060), kBg])),
      child: SafeArea(child: Stack(children: [
        Center(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Container(
              decoration: cardDecoration(),
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // Connected badge + version
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: kGreen.withValues(alpha: .15), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kGreen.withValues(alpha: .4))),
                    child: Text(L.common.playersConnected.fmt({'n': _playerCount}),
                      style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold, fontSize: 13))),
                  const SizedBox(width: 8),
                  const AppVersionLabel(),
                ]),
                const SizedBox(height: 12),

                // Player chips
                Wrap(spacing: 8, runSpacing: 6,
                  children: _players.map((p) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
                      Text(p.name, style: const TextStyle(color: kText, fontSize: 12)),
                    ]))).toList()),
                const SizedBox(height: 16),

                if (widget.isHost) ...[
                  // Turn indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .06), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      L.common.nextGameFirst.fmt({'player': _players[_session.nextStarterFor(_playerCount) - 1].name}),
                      style: const TextStyle(color: kMuted, fontSize: 11))),
                  const SizedBox(height: 12),

                  // Compact game picker strip → opens GameBrowseScreen
                  GamePickerStrip(
                    selectedId:  _selectedGame,
                    playerCount: _playerCount,
                    isHost:      true,
                    onSelect: (id) {
                      setState(() => _selectedGame = id);
                      _net.send('GAME_SELECTED', {'id': id});
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _startGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPurple2, foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text(L.common.startGame,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 8),
                  // Tournament mode button
                  OutlinedButton.icon(
                    onPressed: _openTournamentSetup,
                    icon: const Text('🏆', style: TextStyle(
                      fontSize: 14, fontFamilyFallback: ['NotoColorEmoji'])),
                    label: Text(L.common.tournamentMode,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber,
                      side: BorderSide(color: Colors.amber.withValues(alpha: .6)),
                      minimumSize: const Size(double.infinity, 42),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                  // Hosted mode: show the QR code again for browser players
                  if (Network().webUrls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => WebInviteCard.show(context),
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: Text(L.common.webInviteBtn,
                        style: const TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kMuted,
                        side: const BorderSide(color: kBorder),
                        minimumSize: const Size(double.infinity, 42),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                  ],
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () async {
                      await Network().leaveSession();
                      SessionState().reset();
                      await WakeLock.release();
                      if (mounted) Navigator.pushAndRemoveUntil(context,
                        fadeScaleRoute(const LobbyScreen()),
                        (_) => false);
                    },
                    child: Text(L.common.lobby,
                      style: const TextStyle(color: kMuted, fontSize: 12))),
                ] else ...[
                  // Joiner sees compact strip, read-only
                  GamePickerStrip(
                    selectedId:  _hostSelectedGame,
                    playerCount: _playerCount,
                    isHost:      false,
                  ),
                  const SizedBox(height: 8),
                  Text(L.common.waitingForHostStart,
                    style: const TextStyle(color: kMuted, fontStyle: FontStyle.italic, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () async {
                      await Network().leaveSession();
                      SessionState().reset();
                      await WakeLock.release();
                      if (mounted) Navigator.pushAndRemoveUntil(context,
                        fadeScaleRoute(const LobbyScreen()),
                        (_) => false);
                    },
                    child: Text(L.common.lobby,
                      style: const TextStyle(color: kMuted, fontSize: 12))),
                ],

                // Recent chat preview
                if (_session.chat.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(color: kBorder),
                  const SizedBox(height: 6),
                  ..._session.chat.reversed.take(2).toList().reversed.map((m) =>
                    Padding(padding: const EdgeInsets.only(bottom: 3),
                      child: Row(children: [
                        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(color: m.color, shape: BoxShape.circle)),
                        Text(m.mine ? L.common.you : m.sender,
                          style: TextStyle(color: m.color, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Expanded(child: Text(m.text,
                          style: const TextStyle(color: kMuted, fontSize: 10),
                          overflow: TextOverflow.ellipsis)),
                      ]))),
                ],
              ]),
            ),
          ),
        )),

        // Chat panel
        if (_showChat) Positioned(
          right: 8, top: 8, bottom: 60,
          child: SizedBox(width: 260, child: ChatOverlay(
            messages: _session.chat,
            onSend: _sendChat,
            onClose: () => setState(() { _showChat = false; }),
            typingName: _typingName,
            onTyping: _onLocalTyping,
          ))),

        // Back-to-lobby button — always visible for joiners (not just buried in scroll)
        if (!widget.isHost) Positioned(top: 8, left: 8,
          child: GestureDetector(
            onTap: () async {
              HapticFeedback.selectionClick();
              await Network().leaveSession();
              SessionState().reset();
              await WakeLock.release();
              if (context.mounted) Navigator.pushAndRemoveUntil(context,
                fadeScaleRoute(const LobbyScreen()), (_) => false);
            },
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle,
                border: Border.all(color: kBorder),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)]),
              child: const Icon(Icons.arrow_back, color: kText, size: 20)))),

        // Stats trophy FAB
        Positioned(bottom: 12, left: 12,
          child: GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); Navigator.push(ctx,
              fadeScaleRoute(const StatsScreen())); },
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle,
                border: Border.all(color: kBorder),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)]),
              child: const Icon(Icons.emoji_events_outlined, color: kMuted, size: 22)))),

        // Chat FAB
        Positioned(bottom: 12, right: 12,
          child: Stack(children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _showChat = !_showChat;
                  _unread = 0;
                });
                if (_showChat) _sendReadAck();
              },
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: kPurple2, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: kPurple2.withValues(alpha: .5), blurRadius: 10)]),
                child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20))),
            if (_unread > 0) Positioned(right: 0, top: 0,
              child: Container(width: 17, height: 17,
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Center(child: Text('$_unread',
                  style: const TextStyle(color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.bold))))),
          ])),
      ])),
    ),
  );
}
