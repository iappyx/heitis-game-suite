import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/network.dart';
import '../core/player.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/wake_lock.dart';
import '../core/games_registry.dart';
import '../l10n/app_localizations.dart';
import '../screens/waiting_screen.dart';
import '../screens/lobby_screen.dart';
import '../widgets/reconnect_dialog.dart';

// ── Tournament model ──────────────────────────────────────────────────────────

class TournamentRound {
  final String gameId;
  final int firstPlayer; // 1-based
  int? winnerIdx;        // 0-based index into players, -1 = draw, null = not played
  TournamentRound({required this.gameId, required this.firstPlayer, this.winnerIdx});
  TournamentRound withResult(int? w) =>
      TournamentRound(gameId: gameId, firstPlayer: firstPlayer, winnerIdx: w);
}

class Tournament {
  final List<Player> players;
  final List<TournamentRound> rounds;
  int currentRound; // 0-based

  Tournament({required this.players, required this.rounds, this.currentRound = 0});

  bool get isOver => currentRound >= rounds.length;
  TournamentRound? get current => isOver ? null : rounds[currentRound];

  /// Cumulative win counts per player index.
  List<int> get scores {
    final s = List.filled(players.length, 0);
    for (final r in rounds) {
      if (r.winnerIdx != null && r.winnerIdx! >= 0) {
        s[r.winnerIdx!]++;
      }
    }
    return s;
  }

  /// 0-based index of overall winner, -1 if tie at end.
  int get champion {
    final s = scores;
    final mx = s.reduce(max);
    final top = s.where((v) => v == mx).length;
    if (top > 1) return -1;
    return s.indexOf(mx);
  }
}

// ── Network messages ──────────────────────────────────────────────────────────
// TOURNEY_START  { rounds: [{game, first}], players: [...] }
// TOURNEY_RESULT { round: int, winnerIdx: int }   (-1 = draw)
// TOURNEY_POP    {}   — host tells clients to pop back from game to tournament screen
// TOURNEY_ABORT  {}   — host only

// ── Setup screen (host only) ──────────────────────────────────────────────────

class TournamentSetupScreen extends StatefulWidget {
  final List<Player> players;
  const TournamentSetupScreen({super.key, required this.players});
  @override State<TournamentSetupScreen> createState() => _TSetupState();
}

class _TSetupState extends State<TournamentSetupScreen> {
  int _numRounds = 5;
  final _rng = Random();
  bool _starting = false; // guards against a fast double tap on Start
  bool _leaving  = false; // navigating back to WaitingScreen
  final _net = Network();
  StreamSubscription<(Map<String, dynamic>, int)>? _msgSub;

  // This screen REPLACES WaitingScreen (nothing lies underneath), so leaving
  // always pushes a fresh WaitingScreen — which also compacts the roster and
  // pulls in anyone who joined meanwhile (they wait in their lobby until then).
  @override void initState() {
    super.initState();
    _msgSub = _net.listen(_onMsg);
  }

  @override void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    switch (msg['type'] as String?) {
      case 'PLAYER_LEFT':
        // A listed player left: the list is stale — back to game select
        final leftId = msg['id'] as String?;
        if (leftId != null && !widget.players.any((p) => p.id == leftId)) break;
        _backToWaiting(leftName: msg['name'] as String?);
        break;
    }
  }

  void _backToWaiting({String? leftName}) {
    if (_leaving || _starting || !mounted) return;
    _leaving = true;
    Navigator.pushAndRemoveUntil(context, fadeScaleRoute(
      WaitingScreen(players: widget.players, isHost: true, leftName: leftName)),
      (_) => false);
  }

  List<GameInfo> _eligibleGames() {
    final n = widget.players.length;
    return kGames.where((g) => g.maxPlayers == null || n <= g.maxPlayers!).toList();
  }

  List<TournamentRound> _buildRounds() {
    final eligible = _eligibleGames();
    final picks = <GameInfo>[];
    final pool = [...eligible]..shuffle(_rng);
    for (int i = 0; i < _numRounds; i++) {
      // When we've exhausted the pool, re-shuffle for the next cycle
      if (i % pool.length == 0 && i > 0) pool.shuffle(_rng);
      picks.add(pool[i % pool.length]);
    }
    return picks.asMap().entries.map((e) => TournamentRound(
      gameId:      e.value.id,
      firstPlayer: (e.key % widget.players.length) + 1,
    )).toList();
  }

  @override Widget build(BuildContext context) {
    final eligible = _eligibleGames();
    return PopScope(
      canPop: false, // root route: system back returns to game select
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _backToWaiting(); },
      child: Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment.topCenter, radius: 1.2,
            colors: [Color(0xFF2D1060), kBg])),
        child: SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(children: [
              // Back button row
              Row(children: [
                GestureDetector(
                  onTap: _backToWaiting,
                  child: Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                    child: const Icon(Icons.arrow_back, color: kText, size: 18)),
                ),
              ]),
              const SizedBox(height: 12),
              const Text('🏆', style: TextStyle(fontSize: 40, fontFamilyFallback: ['NotoColorEmoji'])),
              const SizedBox(height: 8),
              Text(L.common.tournament, style: const TextStyle(color: kText, fontSize: 22,
                fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${widget.players.length} ${L.common.humanPlayers} · ${eligible.length} ${L.common.chooseGame.toLowerCase()}',
                style: const TextStyle(color: kMuted, fontSize: 13)),
              const SizedBox(height: 16),

              Container(
                decoration: cardDecoration(),
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Players
                  Text(L.common.humanPlayers.toUpperCase(), style: const TextStyle(color: kMuted, fontSize: 12,
                    fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6,
                    children: widget.players.map((p) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: p.color.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.color.withValues(alpha: .4))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8,
                          decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(p.name, style: const TextStyle(color: kText, fontSize: 13)),
                      ]),
                    )).toList()),
                  const SizedBox(height: 20),

                  // Number of rounds
                  Text(L.common.numberOfRounds.toUpperCase(), style: const TextStyle(color: kMuted, fontSize: 12,
                    fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [3, 5, 7, 10].map((n) {
                    final sel = _numRounds == n;
                    return GestureDetector(
                      onTap: () => setState(() => _numRounds = n),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 56, height: 40,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: sel ? kPurple2.withValues(alpha: .3) : Colors.white.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? kPurple2 : kBorder, width: sel ? 2 : 1)),
                        child: Center(child: Text('$n', style: TextStyle(
                          color: sel ? kText : kMuted,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                          fontSize: 16)))),
                    );
                  }).toList()),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _startTournament(context),
                      icon: const Text('🏆', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'])),
                      label: Text(L.common.startTournament,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPurple2, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ))),
      ),
    ));
  }

  void _startTournament(BuildContext context) {
    if (_starting || _leaving) return;
    _starting = true;
    final rounds = _buildRounds();
    final tourney = Tournament(players: widget.players, rounds: rounds);
    final net = Network();
    net.send('TOURNEY_START', {
      'rounds': rounds.map((r) => {'game': r.gameId, 'first': r.firstPlayer}).toList(),
      'players': widget.players.map((p) => p.toJson()).toList(),
    });
    if (context.mounted) Navigator.pushReplacement(context, fadeScaleRoute(
      TournamentScreen(tournament: tourney)));
  }
}

// ── Tournament conductor screen ───────────────────────────────────────────────

class TournamentScreen extends StatefulWidget {
  final Tournament tournament;
  const TournamentScreen({super.key, required this.tournament});
  @override State<TournamentScreen> createState() => _TournamentState();
}

class _TournamentState extends State<TournamentScreen> {
  late Tournament _t;
  final _net = Network();
  StreamSubscription<(Map<String, dynamic>, int)>? _msgSub;
  final _session = SessionState();
  int _previousLeader = -1;
  bool _leaving = false; // navigating back to WaitingScreen / lobby

  @override void initState() {
    super.initState();
    _t = widget.tournament;
    _msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
  }

  /// Game screens pushed on top install their own onDisconnected handler (and
  /// some clear it in dispose(), which runs after the pop transition), so
  /// re-claim it each time a round's game returns to this screen.
  void _reclaimDisconnect() {
    if (!mounted) return;
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _net.onDisconnected == null) {
        _net.onDisconnected = () { if (mounted) _showReconnect(); };
      }
    });
  }

  /// Joiners may not abort the tournament (that would desync from the host);
  /// they can only leave the session entirely, like on the waiting screen.
  void _confirmLeaveSession() {
    showDialog(context: context, builder: (dCtx) => AlertDialog(
      backgroundColor: kBg2,
      title: Text(L.common.leaveGame, style: const TextStyle(color: kText)),
      content: Text(L.common.leaveGameContent, style: const TextStyle(color: kMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx),
          child: Text(L.common.stay, style: const TextStyle(color: kMuted))),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(dCtx);
            _net.onDisconnected = null;
            await _net.leaveSession();
            _session.reset();
            await WakeLock.release();
            if (mounted) {
              Navigator.pushAndRemoveUntil(context,
                fadeScaleRoute(const LobbyScreen()), (_) => false);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
          child: Text(L.common.backToLobby, style: const TextStyle(color: Colors.white))),
      ],
    ));
  }

  @override void dispose() {
    _msgSub?.cancel();
    _net.onDisconnected = null;
    super.dispose();
  }

  void _showReconnect() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          _msgSub?.cancel();
          _msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false),
      ),
    );
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    switch (msg['type'] as String) {
      case 'START_GAME':
        // Client receives START_GAME — because we use a broadcast stream,
        // the tournament screen hears this even while a game screen is on top.
        // We guard: only act if we're not already in a game.
        if (!_net.isHost && mounted && !_net.isTournament && !_leaving &&
            _session.listIncludesMe(msg['players'] as List?, _net.myIdx)) {
          _net.isTournament = true;
          WakeLock.acquire();
          Navigator.push(context, fadeScaleRoute(
            buildGameScreen(
              msg['game'] as String,
              (msg['first'] as int?) ?? 1,
              _t.players,
              msg['cfg'] as Map<String, dynamic>?,
            ),
          )).then((_) {
            _net.isTournament = false;
            _reclaimDisconnect();
          });
        }
        break;
      case 'TOURNEY_RESULT':
        if (!_net.isHost) _applyResult(msg['round'] as int, msg['winnerIdx'] as int);
        break;
      case 'TOURNEY_ABORT':
        if (!_net.isHost && mounted) _exitToWaiting(leftName: msg['leftName'] as String?);
        break;
      case 'PLAYER_LEFT':
        // Host, between rounds: a tournament player left — abort like a game
        // does; everyone goes back to WaitingScreen, which renumbers joiners.
        // During a round the game screen on top handles PLAYER_LEFT itself.
        // Someone who isn't in the tournament (waiting in their lobby) is
        // ignored.
        if (!_net.isHost || !mounted || _net.isTournament) break;
        final leftId = msg['id'] as String?;
        if (leftId != null && !_t.players.any((p) => p.id == leftId)) break;
        _exitToWaiting(leftName: msg['name'] as String? ?? L.common.defaultPlayer);
        break;
    }
  }

  void _checkLeadChange() {
    final leader = _t.champion;
    if (leader != _previousLeader && leader >= 0 && _previousLeader != -1) {
      final p = _t.players[leader];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('\u{1F389} ${p.name} ${L.common.takesTheLead}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold,
              fontFamilyFallback: ['NotoColorEmoji'])),
          backgroundColor: p.color.withValues(alpha: .85),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
    _previousLeader = leader >= 0 ? leader : _previousLeader;
  }

  void _applyResult(int round, int winnerIdx) {
    if (!mounted) return;
    setState(() {
      _t.rounds[round] = _t.rounds[round].withResult(winnerIdx);
      if (round == _t.currentRound) _t.currentRound++;
    });
    _checkLeadChange();
  }

  void _recordResult(int winnerIdx) {
    final round = _t.currentRound;
    // TOURNEY_POP tells client game screens to pop back.
    // TOURNEY_RESULT updates client tournament scoreboards.
    // Because streams are broadcast, the tournament screen on the client
    // will also receive TOURNEY_RESULT even while buried under the game screen
    // — it's queued until the next event loop tick, by which time the game
    // screen has popped and the setState runs correctly.
    _net.send('TOURNEY_POP');
    _net.send('TOURNEY_RESULT', {'round': round, 'winnerIdx': winnerIdx});
    setState(() {
      _t.rounds[round] = _t.rounds[round].withResult(winnerIdx);
      _t.currentRound++;
    });
    _checkLeadChange();
  }

  Future<void> _launchCurrentGame() async {
    final r = _t.current;
    if (r == null || !_net.isHost) return;
    _session.advanceGame();
    final players = _t.players;
    final payload = {
      'game': r.gameId, 'first': r.firstPlayer,
      'players': players.map((p) => p.toJson()).toList(),
    };
    await _net.sendAndFlush('START_GAME', payload);
    if (!mounted) return;
    _net.isTournament = true;
    WakeLock.acquire();
    Navigator.push(context, fadeScaleRoute(
      buildGameScreen(r.gameId, r.firstPlayer, players),
    )).then((_) {
      _net.isTournament = false;
      _reclaimDisconnect();
      if (mounted && _net.isHost && !_t.isOver) _showResultDialog();
    });
  }

  void _showResultDialog() {
    final players = _t.players;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kBg2,
        title: Text(L.common.whoWon, style: const TextStyle(color: kText)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ...players.asMap().entries.map((e) => ListTile(
            leading: Container(width: 12, height: 12,
              decoration: BoxDecoration(color: e.value.color, shape: BoxShape.circle)),
            title: Text(e.value.name, style: const TextStyle(color: kText)),
            onTap: () { Navigator.pop(context); _recordResult(e.key); },
          )),
          ListTile(
            leading: const Icon(Icons.handshake_outlined, color: kMuted),
            title: Text(L.common.draw, style: const TextStyle(color: kMuted)),
            onTap: () { Navigator.pop(context); _recordResult(-1); },
          ),
        ]),
      ),
    );
  }

  void _exitToWaiting({String? leftName}) {
    if (_leaving) return;
    _leaving = true;
    if (_net.isHost) {
      _net.send('TOURNEY_ABORT', {if (leftName != null) 'leftName': leftName});
    }
    Navigator.pushAndRemoveUntil(context, fadeScaleRoute(
      WaitingScreen(players: _t.players, isHost: _net.isHost, leftName: leftName)),
      (_) => false);
  }

  Future<void> _exitToLobby() async {
    if (_leaving) return;
    _leaving = true;
    if (_net.isHost) _net.send('TOURNEY_ABORT');
    await _net.leaveSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, fadeScaleRoute(
      const LobbyScreen()), (_) => false);
  }

  // ── Results summary (shown when tournament is over) ─────────────────────────

  Widget _buildResultsSummary() {
    final scores  = _t.scores;
    final players = _t.players;
    final champ   = _t.champion;

    // Build sorted player list by score (descending)
    final sorted = players.asMap().entries.toList()
      ..sort((a, b) => scores[b.key].compareTo(scores[a.key]));

    // Build per-player game-win list
    Map<int, List<String>> winsPerPlayer = {};
    for (final r in _t.rounds) {
      if (r.winnerIdx != null && r.winnerIdx! >= 0) {
        final g = kGames.firstWhere((g) => g.id == r.gameId, orElse: () => kGames[0]);
        winsPerPlayer.putIfAbsent(r.winnerIdx!, () => []).add(g.icon);
      }
    }

    final rankEmojis = ['🥇', '🥈', '🥉'];

    return SafeArea(child: Column(children: [
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          const Text('🏆', style: TextStyle(fontSize: 18, fontFamilyFallback: ['NotoColorEmoji'])),
          const SizedBox(width: 6),
          Text(L.common.tournamentResults, style: const TextStyle(color: kText, fontSize: 16,
            fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(L.common.nRounds.fmt({'n': '${_t.rounds.length}'}), style: const TextStyle(color: kMuted, fontSize: 13)),
        ]),
      ),

      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(children: [
            // Champion / tie banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: champ >= 0
                    ? [Colors.amber.withValues(alpha: .2), players[champ].color.withValues(alpha: .15)]
                    : [Colors.amber.withValues(alpha: .15), kPurple.withValues(alpha: .15)]),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: champ >= 0
                    ? Colors.amber.withValues(alpha: .5)
                    : kPurple.withValues(alpha: .4),
                  width: 2)),
              child: Column(children: [
                Text(champ >= 0 ? '🏆' : '🤝',
                  style: const TextStyle(fontSize: 56, fontFamilyFallback: ['NotoColorEmoji'])),
                const SizedBox(height: 8),
                Text(
                  champ >= 0 ? players[champ].name : L.common.itsADraw,
                  style: TextStyle(
                    color: champ >= 0 ? Colors.amber.shade200 : kText,
                    fontSize: 26, fontWeight: FontWeight.w900,
                    shadows: [Shadow(
                      color: (champ >= 0 ? Colors.amber : kPurple).withValues(alpha: .4),
                      blurRadius: 12)]),
                ),
                if (champ >= 0)
                  Text(L.common.winsTheTournament,
                    style: TextStyle(color: kMuted, fontSize: 14)),
                const SizedBox(height: 4),
                Text(L.common.finalScore.fmt({'n': '${scores.reduce(max)}'}),
                  style: TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 16),

            // Final standings with game wins detail
            Container(
              decoration: cardDecoration(),
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(L.common.finalStandings, style: const TextStyle(color: kMuted, fontSize: 11,
                  fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 14),
                ...sorted.asMap().entries.map((rankEntry) {
                  final rank   = rankEntry.key;
                  final pEntry = rankEntry.value;
                  final p      = pEntry.value;
                  final pIdx   = pEntry.key;
                  final score  = scores[pIdx];
                  final isChamp = champ == pIdx;
                  final wins   = winsPerPlayer[pIdx] ?? [];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isChamp
                        ? Colors.amber.withValues(alpha: .1)
                        : Colors.white.withValues(alpha: .04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isChamp ? Colors.amber.withValues(alpha: .4) : kBorder,
                        width: isChamp ? 1.5 : 1)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(rank < 3 ? rankEmojis[rank] : '#${rank + 1}',
                          style: TextStyle(fontSize: rank < 3 ? 22 : 16,
                            fontFamilyFallback: const ['NotoColorEmoji'],
                            color: kMuted)),
                        const SizedBox(width: 10),
                        Container(width: 12, height: 12,
                          decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(p.name,
                          style: TextStyle(
                            color: isChamp ? Colors.amber.shade200 : kText,
                            fontSize: 17, fontWeight: FontWeight.bold))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isChamp
                              ? Colors.amber.withValues(alpha: .2)
                              : kGreen.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(10)),
                          child: Text(L.common.nWins.fmt({'n': '$score'}),
                            style: TextStyle(
                              color: isChamp ? Colors.amber.shade200 : kGreen,
                              fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      if (wins.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 4, runSpacing: 4,
                          children: wins.map((icon) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: p.color.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: p.color.withValues(alpha: .25))),
                            child: Text(icon, style: const TextStyle(fontSize: 16,
                              fontFamilyFallback: ['NotoColorEmoji'])),
                          )).toList()),
                      ] else ...[
                        const SizedBox(height: 6),
                        Text(L.common.noWins, style: TextStyle(color: kMuted, fontSize: 11,
                          fontStyle: FontStyle.italic)),
                      ],
                    ]),
                  );
                }),
              ]),
            ),
            const SizedBox(height: 16),

            // Round-by-round recap
            Container(
              decoration: cardDecoration(),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              child: Column(children: [
                Text(L.common.roundByRound, style: const TextStyle(color: kMuted, fontSize: 11,
                  fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 10),
                ..._t.rounds.asMap().entries.map((e) {
                  final idx = e.key;
                  final r   = e.value;
                  final g   = kGames.firstWhere((g) => g.id == r.gameId,
                      orElse: () => kGames[0]);
                  final winner = r.winnerIdx != null && r.winnerIdx! >= 0
                      ? players[r.winnerIdx!] : null;
                  final isDraw = r.winnerIdx == -1;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBorder.withValues(alpha: .3))),
                    child: Row(children: [
                      SizedBox(width: 22, child: Text('${idx + 1}',
                        style: const TextStyle(color: kMuted, fontSize: 12,
                          fontWeight: FontWeight.bold))),
                      Text(g.icon, style: const TextStyle(fontSize: 18,
                        fontFamilyFallback: ['NotoColorEmoji'])),
                      const SizedBox(width: 8),
                      Expanded(child: Text(g.name,
                        style: const TextStyle(color: kText, fontSize: 13))),
                      if (winner != null) ...[
                        Container(width: 8, height: 8,
                          decoration: BoxDecoration(color: winner.color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(winner.name, style: TextStyle(
                          color: winner.color, fontSize: 12, fontWeight: FontWeight.bold)),
                      ] else if (isDraw) ...[
                        Text(L.common.draw, style: const TextStyle(color: kMuted, fontSize: 12,
                          fontStyle: FontStyle.italic)),
                      ],
                    ]),
                  );
                }),
              ]),
            ),
            const SizedBox(height: 20),

            // Action buttons
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _exitToLobby,
                icon: const Icon(Icons.home_outlined, size: 18),
                label: Text(L.common.backToLobby),
                style: secondaryButton().copyWith(
                  minimumSize: WidgetStatePropertyAll(const Size(0, 48))),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: _exitToWaiting,
                icon: const Text('🎮', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'])),
                label: Text(L.common.playAgainBtn),
                style: primaryButton().copyWith(
                  minimumSize: WidgetStatePropertyAll(const Size(0, 48))),
              )),
            ]),
            const SizedBox(height: 16),
          ]),
        ),
      )),
    ]));
  }

  @override Widget build(BuildContext context) {
    final scores  = _t.scores;
    final players = _t.players;
    final isOver  = _t.isOver;

    // Show dedicated results summary when tournament is complete
    if (isOver) {
      return Scaffold(
        backgroundColor: kBg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment.topCenter, radius: 1.2,
              colors: [Color(0xFF2D1060), kBg])),
          child: _buildResultsSummary(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment.topCenter, radius: 1.2,
            colors: [Color(0xFF2D1060), kBg])),
        child: SafeArea(child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              GestureDetector(
                // Only the host may abort; joiners get a "leave session" dialog.
                onTap: !_net.isHost ? _confirmLeaveSession : () => showDialog(context: context, builder: (_) => AlertDialog(
                  backgroundColor: kBg2,
                  title: Text(L.common.abortTournament, style: const TextStyle(color: kText)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context),
                      child: Text(L.common.cancelBtn, style: const TextStyle(color: kMuted))),
                    ElevatedButton(onPressed: () { Navigator.pop(context); _exitToWaiting(); },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
                      child: Text(L.common.abort, style: const TextStyle(color: Colors.white))),
                  ],
                )),
                child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.black54,
                    borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                  child: const Icon(Icons.close, color: kText, size: 18)),
              ),
              const SizedBox(width: 10),
              const Text('🏆', style: TextStyle(fontSize: 18, fontFamilyFallback: ['NotoColorEmoji'])),
              const SizedBox(width: 6),
              Text(L.common.tournament, style: const TextStyle(color: kText, fontSize: 16,
                fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(L.common.roundNofM.fmt({'n': '${_t.currentRound + 1}', 'm': '${_t.rounds.length}'}),
                style: const TextStyle(color: kMuted, fontSize: 13)),
            ]),
          ),

          // Persistent leaderboard bar
          _LeaderboardBar(players: players, scores: scores, leader: _t.champion),

          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(children: [
                // Round list
                Container(
                  decoration: cardDecoration(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                      child: Row(children: [
                        Text(L.common.rounds, style: const TextStyle(color: kMuted, fontSize: 11,
                          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      ]),
                    ),
                    ..._t.rounds.asMap().entries.map((e) {
                      final idx = e.key;
                      final r   = e.value;
                      final g   = kGames.firstWhere((g) => g.id == r.gameId,
                          orElse: () => kGames[0]);
                      final isCurrent = idx == _t.currentRound;
                      final isDone    = r.winnerIdx != null;
                      final winner    = isDone && r.winnerIdx! >= 0
                          ? players[r.winnerIdx!] : null;

                      return Container(
                        margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isCurrent
                            ? kPurple.withValues(alpha: .12)
                            : isDone ? Colors.white.withValues(alpha: .03) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrent ? kPurple.withValues(alpha: .5)
                              : isDone ? kBorder.withValues(alpha: .4) : kBorder.withValues(alpha: .2))),
                        child: Row(children: [
                          Text('${idx + 1}', style: TextStyle(
                            color: isCurrent ? kPurple : kMuted, fontSize: 12,
                            fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Text(g.icon, style: const TextStyle(fontSize: 20,
                            fontFamilyFallback: ['NotoColorEmoji'])),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(g.name, style: TextStyle(
                              color: isCurrent ? kText : isDone ? kMuted : Colors.white38,
                              fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(L.common.goesFirst.fmt({'player': players[r.firstPlayer - 1].name}),
                              style: const TextStyle(color: kMuted, fontSize: 10)),
                          ])),
                          if (isDone) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: (winner != null ? winner.color : Colors.grey).withValues(alpha: .2),
                                borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                winner != null ? winner.name : L.common.draw,
                                style: TextStyle(
                                  color: winner?.color ?? kMuted, fontSize: 11,
                                  fontWeight: FontWeight.bold))),
                          ] else if (isCurrent && _net.isHost) ...[
                            ElevatedButton(
                              onPressed: _launchCurrentGame,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPurple2, foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                textStyle: const TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                              child: Text(L.common.playBtn),
                            ),
                          ] else if (isCurrent) ...[
                            Text(L.common.waitingForHostResult,
                              style: const TextStyle(color: kMuted, fontSize: 11,
                                fontStyle: FontStyle.italic)),
                          ],
                        ]),
                      );
                    }),
                  ]),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          )),
        ])),
      ),
    );
  }
}

// ── Leaderboard bar (always visible above round list) ─────────────────────────

class _LeaderboardBar extends StatelessWidget {
  final List<Player> players;
  final List<int> scores;
  final int leader; // -1 if tied

  const _LeaderboardBar({required this.players, required this.scores, required this.leader});

  @override
  Widget build(BuildContext context) {
    // Sort indices by score descending
    final indices = List.generate(players.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kBg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: indices.map((i) {
        final p = players[i];
        final isLeader = i == leader;
        return Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (isLeader)
            const Text('\u{1F947} ', style: TextStyle(fontSize: 13,
              fontFamilyFallback: ['NotoColorEmoji']))
          else
            Container(width: 8, height: 8,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(color: p.color, shape: BoxShape.circle,
                boxShadow: isLeader ? [BoxShadow(color: p.color.withValues(alpha: .6), blurRadius: 6)] : null)),
          Flexible(child: Text(p.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isLeader ? kText : kMuted, fontSize: 12,
              fontWeight: isLeader ? FontWeight.bold : FontWeight.normal))),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isLeader ? kGreen.withValues(alpha: .15) : Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(6)),
            child: Text('${scores[i]}',
              style: TextStyle(color: isLeader ? kGreen : kMuted,
                fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
        ]));
      }).toList()),
    );
  }
}
