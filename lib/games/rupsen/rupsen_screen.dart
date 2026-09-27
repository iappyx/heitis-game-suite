import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/animated_die.dart';
import '../../core/network.dart';
import '../../widgets/game_mixin.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/lobby_screen.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/reconnect_dialog.dart';
import 'rupsen_state.dart';
import 'rupsen_ai.dart';
import '../../core/solo_ai.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../core/sound_player.dart';

const _kRupsenColors = [
  Color(0xFF78350F), // 1 rups — brown
  Color(0xFF166534), // 2 rupsen — green
  Color(0xFF1E40AF), // 3 rupsen — blue
  Color(0xFF7C2D12), // 4 rupsen — dark red
];

class RupsenScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const RupsenScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<RupsenScreen> createState() => _RupsenScreenState();
}

class _RupsenScreenState extends State<RupsenScreen> with GameMixin {
  late final RupsenState _state;
  final _net    = Network();
  final _session = SessionState();
  final _rolling = List.filled(8, false);

  int    get _myIdx    => _net.myIdx.clamp(0, widget.players.length - 1);
  bool   get _isActive => _state.activeIdx == _myIdx;
  bool   get _anyRolling => _rolling.any((r) => r);

  List<RupsenAI> _ais = [];

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _state = RupsenState(widget.players);
    _state.activeIdx = widget.firstPlayer - 1;
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_net.isSolo) {
      final diffIdx = (widget.extra?['difficulty'] as int?) ?? SoloDifficulty.medium.index;
      final diff = SoloDifficulty.values[diffIdx.clamp(0, 2)];
      _ais = List.generate(widget.players.length - 1, (i) {
        final ai = RupsenAI(diff);
        ai.playerIdx = i + 1; // player 0 = human, 1..N = AI
        return ai;
      });
      _maybeScheduleAI();
    }
  }

  void _maybeScheduleAI() {
    if (!_net.isSolo || !mounted || _state.gameOver) return;
    // Only fire when it's actually an AI player's turn
    if (_state.activeIdx == 0) return; // human's turn
    final ai = _activeAI;
    if (ai != null) ai.act(_state);
  }

  RupsenAI? get _activeAI {
    if (_ais.isEmpty) return null;
    final aiPlayerIdx = _state.activeIdx - 1; // AI players start at idx 1
    if (aiPlayerIdx < 0 || aiPlayerIdx >= _ais.length) return null;
    return _ais[aiPlayerIdx];
  }

  // ── Network ──────────────────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    final type = msg['type'] as String? ?? '';
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (type) {
      case 'RUP_ROLL':
        if (_net.isHost && fromIdx == _state.activeIdx) _executeRoll();
        break;
      case 'RUP_ASIDE':
        if (_net.isHost && fromIdx == _state.activeIdx) {
          final face = msg['face'] as int;
          if (_state.setAside(face)) {
            if (_bustIfStuck()) {
              setState(() {});
              _broadcastSync(); // AI (if any) sees busted phase and sends RUP_NEXT
              break;
            }
            setState(() {});
            _broadcastSync(skipAI: true); // AI decides next action itself
            if (_net.isSolo && _state.activeIdx != 0) {
              final ai = _activeAI;
              if (ai != null) ai.decideAfterAside(_state);
            }
          }
        }
        break;
      case 'RUP_CLAIM':
        if (_net.isHost && fromIdx == _state.activeIdx) {
          final result = _state.claim();
          _state.message = result;
          if (_state.phase != RupsenPhase.rolling) {
            setState(() {});
            _broadcastSync();
          }
        }
        break;
      case 'RUP_NEXT':
        if (_net.isHost && fromIdx == _state.activeIdx) {
          setState(() { _state.nextTurn(); });
          _broadcastSync();
          _maybeScheduleAI();
        }
        break;

      case 'RUP_SYNC':
        _receivedSync(msg);
        break;
      case 'RUP_SYNC_REQ':
        if (_net.isHost) _broadcastSync();
        break;
      case 'GAME_RESET':
        if (!_net.isHost) {
          final first = (msg['first'] as int?) ?? (widget.firstPlayer - 1);
          resetConfetti();
          resetStats();
          setState(() {
            _state.resetGame(first);
            for (int i = 0; i < 8; i++) _rolling[i] = false;
          });
        }
        break;
    }
  }

  void _broadcastSync({bool isRoll = false, bool skipAI = false}) {
    _net.send('RUP_SYNC', {..._state.toSyncJson(), 'isRoll': isRoll});
    if (!skipAI) _maybeScheduleAI();
  }

  // Bumped for every sync: a roll sync waits for the dice animation, and a
  // newer sync arriving meanwhile (full state) must not be undone by it.
  int _syncGen = 0;

  Future<void> _receivedSync(Map<String, dynamic> msg) async {
    if (!mounted) return;
    final gen = ++_syncGen;
    final wasActive = _isActive;
    final isRoll = msg['isRoll'] == true;
    if (isRoll) {
      final newHeld = List<bool>.from(msg['held'] as List);
      setState(() { for (int i = 0; i < 8; i++) if (!newHeld[i]) _rolling[i] = true; });
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted || gen != _syncGen) return; // overtaken by a newer sync
    }
    setState(() {
      _state.applySyncJson(msg);
      for (int i = 0; i < 8; i++) _rolling[i] = false;
    });
    if (!wasActive && _isActive && !_state.gameOver) turnChanged();
  }

  Future<void> _executeRoll() async {
    setState(() { for (int i = 0; i < 8; i++) if (!_state.held[i]) _rolling[i] = true; });
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    _state.roll();
    // Check immediate bust
    if (_state.isBusted()) {
      SoundPlayer.i.rupsenBust();
      _state.message = _state.bustTurn(L.rupsen.noNewFacesBust);
      setState(() { for (int i = 0; i < 8; i++) _rolling[i] = false; });
      _broadcastSync(isRoll: true);
      return;
    }
    setState(() { for (int i = 0; i < 8; i++) _rolling[i] = false; });
    _broadcastSync(isRoll: true);
  }

  /// Host only: after a set-aside, if no useful roll is left (all dice held or
  /// all 6 faces used) and nothing can be claimed, the turn busts automatically.
  bool _bustIfStuck() {
    if (_state.phase != RupsenPhase.rolling || _state.canClaim) return false;
    if (_state.freeDiceCount > 0 && _state.usedFaces.length < 6) return false;
    SoundPlayer.i.rupsenBust();
    _state.message = _state.bustTurn(_state.hasRups
        ? L.rupsen.noTileBust.fmt({'n': '${_state.turnScore}'})
        : L.rupsen.noWormBust);
    return true;
  }

  void _roll() {
    SoundPlayer.i.diceRoll();
    if (!_isActive || _state.phase != RupsenPhase.rolling || _anyRolling) return;
    if (_state.needsSetAside) return; // must set aside at least one die first
    if (_state.freeDiceCount == 0) return; // all dice held, must claim
    if (_state.usedFaces.length == 6) return; // all faces used, must claim
    if (_net.isHost) {
      _executeRoll();
    } else {
      _net.send('RUP_ROLL');
    }
  }

  void _setAside(int face) {
    SoundPlayer.i.rupsenSetAside();
    if (!_isActive || _state.phase != RupsenPhase.rolling || _anyRolling) return;
    if (_state.pickedThisRoll) return; // already picked one group, must roll first
    if (_state.usedFaces.contains(face)) return;
    if (!_state.availableFaces.contains(face)) return;
    if (_net.isHost) {
      setState(() {
        if (_state.setAside(face)) _bustIfStuck();
      });
      _broadcastSync();
    } else {
      // Joiner: do NOT apply locally — wait for authoritative sync from host
      _net.send('RUP_ASIDE', {'face': face});
    }
  }

  void _claim() {
    SoundPlayer.i.rupsenClaim();
    if (!_isActive || _anyRolling) return;
    if (_net.isHost) {
      setState(() {
        final result = _state.claim();
        _state.message = result;
      });
      _broadcastSync();
    } else {
      _net.send('RUP_CLAIM');
    }
  }

  void _nextTurn() {
    if (!_isActive || _anyRolling) return;
    if (_net.isHost) {
      setState(() => _state.nextTurn());
      _broadcastSync();
      _maybeScheduleAI();
    } else {
      _net.send('RUP_NEXT');
    }
  }

  @override
  void dispose() {
    for (final ai in _ais) ai.cancel();
    super.dispose();
  }

  void _resetGame() {
    for (final ai in _ais) ai.cancel();
    resetConfetti();
    resetStats();
    final first = _net.isHost ? _session.nextStarterFor(widget.players.length) - 1 : 0;
    if (_net.isHost) _net.send('GAME_RESET', {'first': first});
    setState(() {
      _state.resetGame(first);
      for (int i = 0; i < 8; i++) _rolling[i] = false;
    });
    _maybeScheduleAI();
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _broadcastSync();
          else _net.send('RUP_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }


  // ── Build ─────────────────────────────────────────────────────────────────────
  @override Widget build(BuildContext context) => GameScaffold(
        key: scaffoldKey,
    title: L.rupsen.gameName,
    players: widget.players, chatMessages: chatMessages, onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.rupsen.rules,
    child: Column(children: [
      PlayerBar(
        players: widget.players,
        activeIdx: _state.activeIdx,
        scores: _state.rupsenPlayers.map((wp) => wp.totalRupsen).toList(),
        scoreLabel: '🐛',
      ),
      GameStatusBar(
        text: _state.message.isNotEmpty ? _state.message : null,
      ),
      Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Left: dice area
        SizedBox(width: 220, child: _buildDiceArea()),
        // Right: pool + stacks
        Expanded(child: _buildRightPanel()),
      ])),
      if (_state.gameOver) _buildWinBanner(),
    ]),
  );

  // ── Header ────────────────────────────────────────────────────────────────────

  // ── Dice area (left column) ────────────────────────────────────────────────
  Widget _buildDiceArea() {
    final active = _state.activePlayer;
    final phase  = _state.phase;
    final canAct = _isActive && !_anyRolling && !_state.gameOver;

    // Group non-held dice by face for tap-to-set-aside UI
    final Map<int, List<int>> faceGroups = {}; // face → [die indices]
    for (int i = 0; i < 8; i++) {
      if (!_state.held[i]) {
        faceGroups.putIfAbsent(_state.dice[i], () => []).add(i);
      }
    }
    final availFaces = _state.availableFaces;

    return Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: kBorder))),
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        // Active player label
        Text(
          _isActive ? L.rupsen.yourTurnDice : L.rupsen.opponentTurnDice.fmt({'player': active.player.name}),
          style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        // Dice grid: 8 dice in 4×2
        ...[
          // Held dice row
          if (_state.usedFaces.isNotEmpty) ...[
            Text(L.rupsen.setAsideBtn, style: TextStyle(color: kMuted, fontSize: 9,
              letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(spacing: 5, runSpacing: 5, alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < 8; i++)
                  if (_state.held[i])
                    AnimatedDie(
                      key: ValueKey('die_held_$i'),
                      value: _state.dice[i],
                      rolling: _rolling[i],
                      held: true,
                      size: 36,
                      rupsFace: true,
                      bgColor: _state.dice[i] == kRupsFace ? const Color(0xFF2D6A00) : null,
                    ),
              ]),
            const SizedBox(height: 8),
          ],

          // Rolling dice — grouped by face, tappable
          Text(L.rupsen.rollingLabel, style: const TextStyle(color: kMuted, fontSize: 9,
            letterSpacing: 1, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(spacing: 5, runSpacing: 5, alignment: WrapAlignment.center,
            children: [
              for (int i = 0; i < 8; i++)
                if (!_state.held[i])
                  _buildRollingDie(i, availFaces, canAct && phase == RupsenPhase.rolling),
            ]),
          const SizedBox(height: 4),
          // Score tally
          if (_state.turnScore > 0 || _state.hasRups)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(L.rupsen.scoreLabel.fmt({'n': _state.turnScore}),
                style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 6),
              if (_state.hasRups)
                const Text('🐛', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 13)),
            ]),
        ],

        const SizedBox(height: 8),

        // Roll button / set-aside instruction / claim / next-turn
        if (!_state.gameOver) ...[
          if (phase == RupsenPhase.rolling) ...[
            if (_isActive) ...[
              ElevatedButton(
                onPressed: (canAct && !_state.needsSetAside && _state.freeDiceCount > 0) ? _roll : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPurple2, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                child: Text(_state.usedFaces.isEmpty ? L.rupsen.rollBtn : L.rupsen.rollAgainBtn,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              // After picking a group: show Roll Again + optional Claim
              if (_state.pickedThisRoll) ...[
                const SizedBox(height: 4),
                if (_state.canClaim)
                  OutlinedButton(
                    onPressed: canAct ? _claim : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kGreen,
                      side: const BorderSide(color: kGreen),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                    child: Text(L.rupsen.claimBtn.fmt({'n': '${_state.peekClaimValue}'}),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                          fontFamilyFallback: ['NotoColorEmoji']))),
              ] else if (availFaces.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(L.rupsen.tapToSetAside,
                    style: const TextStyle(color: kMuted, fontSize: 11,
                      fontStyle: FontStyle.italic))),
            ] else
              Text(L.rupsen.isChoosing.fmt({"player": active.player.name}),
                style: const TextStyle(color: kMuted, fontStyle: FontStyle.italic, fontSize: 12)),
          ] else if (phase == RupsenPhase.busted || phase == RupsenPhase.claimed) ...[
            Text(phase == RupsenPhase.busted ? L.rupsen.bust : L.rupsen.gotOne,
              style: TextStyle(
                color: phase == RupsenPhase.busted ? Colors.redAccent : kGreen,
                fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (_isActive)
              ElevatedButton(
                onPressed: canAct ? _nextTurn : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPurple2, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                child: Text(L.rupsen.nextTurn,
                  style: TextStyle(fontWeight: FontWeight.bold)))
            else
              Text(L.rupsen.waitingFor.fmt({"player": active.player.name}),
                style: const TextStyle(color: kMuted, fontStyle: FontStyle.italic, fontSize: 12)),
          ],
        ],

        // Faces used legend
        if (_state.usedFaces.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center,
            children: [1,2,3,4,5,kRupsFace].map((f) {
              final used = _state.usedFaces.contains(f);
              return Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: used ? Colors.white12 : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: used ? Colors.white38 : Colors.white12)),
                child: Center(child: Text(
                  f == kRupsFace ? '🐛' : '$f',
                  style: TextStyle(fontSize: 10,
                    color: used ? kMuted : Colors.white24))));
            }).toList()),
          const SizedBox(height: 2),
          Text(L.rupsen.usedFaces, style: const TextStyle(color: Colors.white24, fontSize: 9)),
        ],
      ]),
    );
  }

  Widget _buildRollingDie(int i, List<int> availFaces, bool canAct) {
    final face = _state.dice[i];
    final isAvail = availFaces.contains(face);
    final isRups  = face == kRupsFace;
    return AnimatedDie(
      key: ValueKey('die_roll_$i'),
      value: face,
      rolling: _rolling[i],
      size: 40,
      rupsFace: true,
      bgColor: isRups ? const Color(0xFF1A3A00) : null,
      onTap: (canAct && isAvail && !_state.pickedThisRoll) ? () => _setAside(face) : null,
    );
  }

  // ── Right panel: pool + player stacks ────────────────────────────────────────
  Widget _buildRightPanel() => Column(children: [
    // Tile pool
    Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(L.rupsen.tilePool, style: const TextStyle(color: kMuted, fontSize: 10,
          fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 6),
        _buildTilePool(),
      ])),
    const Divider(color: kBorder, height: 1),
    // Player stacks
    Expanded(child: SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L.rupsen.stacksLabel, style: const TextStyle(color: kMuted, fontSize: 10,
            fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 6),
          ...widget.players.asMap().entries.map((e) =>
            _buildPlayerStack(e.key, e.value)),
        ]))),
  ]);

  Widget _buildTilePool() {
    // Show tiles 21-36 in a grid. Face-down = greyed out, face-up = colored by rups count
    return Wrap(spacing: 4, runSpacing: 4,
      children: _state.pool.map((tile) {
        final rupsen = tile.rupsen;
        final color = _kRupsenColors[rupsen - 1];
        final isDown = tile.faceDown;
        return Container(
          width: 34, height: 40,
          decoration: BoxDecoration(
            color: isDown ? Colors.white.withValues(alpha: .04)
                         : color.withValues(alpha: .7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDown ? Colors.white12 : color,
              width: 1.5)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(isDown ? '—' : '${tile.value}',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold,
                color: isDown ? Colors.white24 : Colors.white)),
            if (!isDown)
              Text('🐛' * rupsen, style: const TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 7)),
          ]),
        );
      }).toList());
  }

  Widget _buildPlayerStack(int idx, Player p) {
    final wp   = _state.rupsenPlayers[idx];
    final isMe = idx == _myIdx;
    final isActive = idx == _state.activeIdx;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isActive ? p.color.withValues(alpha: .08) : Colors.white.withValues(alpha: .03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? p.color.withValues(alpha: .5) : Colors.white.withValues(alpha: .08),
          width: isActive ? 1.5 : 1)),
      child: Row(children: [
        // Player name + rups total
        SizedBox(width: 72, child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 7, height: 7,
                decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Flexible(child: Text(p.name,
                style: TextStyle(color: isMe ? p.color : kText,
                  fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 2),
            Text('${wp.totalRupsen} 🐛',
              style: TextStyle(color: p.color, fontSize: 12,
                fontWeight: FontWeight.w900, fontFamilyFallback: ['NotoColorEmoji'])),
          ])),
        const SizedBox(width: 8),
        // Stack of tiles — show as fanned stack, top tile most visible
        Expanded(child: wp.stack.isEmpty
          ? Text(L.rupsen.noTiles, style: TextStyle(color: Colors.white24, fontSize: 11,
              fontStyle: FontStyle.italic))
          : _buildFannedStack(wp, p)),
      ]),
    );
  }

  Widget _buildFannedStack(RupsenPlayer wp, Player p) {
    // Show tiles as a horizontal fan. Top of stack (last) rightmost and fully visible.
    const tileW = 32.0;
    const tileH = 38.0;
    const overlap = 14.0; // how much each tile hides the one before
    final tiles = wp.stack;
    final count = tiles.length;
    final totalW = tileW + (count - 1) * overlap;

    return SizedBox(height: tileH, width: totalW.clamp(tileW, 200),
      child: Stack(children: [
        for (int i = 0; i < count; i++)
          Positioned(
            left: i * overlap,
            child: Container(
              width: tileW, height: tileH,
              decoration: BoxDecoration(
                color: _kRupsenColors[(tiles[i].rupsen - 1)].withValues(alpha: 0.4 + 0.1 * i), // top tile brighter
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: i == count - 1 ? p.color : Colors.white24,
                  width: i == count - 1 ? 2 : 1),
                boxShadow: i == count - 1
                  ? [BoxShadow(color: p.color.withValues(alpha: .3),
                      blurRadius: 6, offset: const Offset(0, 2))]
                  : null),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${tiles[i].value}',
                  style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.bold, color: Colors.white)),
                Text('🐛' * tiles[i].rupsen,
                  style: const TextStyle(fontSize: 6, fontFamilyFallback: ['NotoColorEmoji'])),
              ]),
            )),
      ]));
  }

  // ── Win banner ────────────────────────────────────────────────────────────────
  Widget _buildWinBanner() {
    final winnerIdx = _state.winnerIdx;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GameResultBanner(
        players: widget.players,
        winnerIdx: winnerIdx,
            onFirstRender: () { fireConfettiOnce(winnerIdx); recordResult('rupsen', winnerIdx); if (_net.isHost) _session.advanceGame(); },
        scores: _state.rupsenPlayers.map((wp) =>
          (label: wp.player.name, value: '${wp.totalRupsen} 🐛 (${wp.stack.length} tiles)'),
        ).toList(),
      ),
      GameOverActions(players: widget.players, onReset: _resetGame, sendReset: false),
    ]);
  }
}
