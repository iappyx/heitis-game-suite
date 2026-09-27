import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/animated_die.dart';
import '../../core/network.dart';
import '../../widgets/game_mixin.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../screens/lobby_screen.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../widgets/game_over_actions.dart';
import 'boppeslach_state.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';

class BoppeslachScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  const BoppeslachScreen({super.key, required this.players, required this.firstPlayer});
  @override State<BoppeslachScreen> createState() => _BoppeslachScreenState();
}

class _BoppeslachScreenState extends State<BoppeslachScreen> with GameMixin {
  late final BoppeslachState _state;
  final _net = Network();
  final _rolling = List.filled(5, false);
  int get _myIdx => _net.myIdx.clamp(0, widget.players.length - 1);
  Player get _me => widget.players[_myIdx];

  bool get _isMyTurn => _state.currentPlayer.id == _me.id;
  bool get _anyRolling => _rolling.any((r) => r);

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _state = BoppeslachState(widget.players);
    _state.currentPlayerIdx = widget.firstPlayer - 1;
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    final type = msg['type'] as String? ?? '';
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (type) {
      case 'BOP_ROLL':
        // Validate it's from the actual current player before rolling
        if (_net.isHost && fromIdx == _state.currentPlayerIdx) _executeRoll();
        break;
      case 'BOP_SCORE':
        if (_net.isHost) {
          final cat = BoppeslachCategory.values[msg['cat'] as int];
          if (!_state.currentCard.hasScored(cat) && _state.rollsLeft < 3) {
            setState(() => _state.scoreCategory(cat));
            _skipSoloAiTurns();
            _net.send('BOP_SYNC', _state.toSyncJson());
          }
        }
        break;
      case 'BOP_HOLD':
        if (_net.isHost) {
          setState(() => _state.held[msg['i'] as int] = msg['held'] as bool);
          _net.send('BOP_SYNC', _state.toSyncJson());
        }
        break;
      case 'BOP_SYNC':
        _receivedSync(msg);
        break;
      case 'BOP_SYNC_REQ':
        if (_net.isHost) _net.send('BOP_SYNC', _state.toSyncJson());
        break;
      case 'GAME_RESET':
        if (!_net.isHost) _resetGame();
        break;

    }
  }

  // Bumped for every sync: a roll sync waits for the dice animation, and a
  // newer sync arriving meanwhile (full state) must not be undone by it.
  int _syncGen = 0;

  Future<void> _receivedSync(Map<String, dynamic> msg) async {
    if (!mounted) return;
    final gen = ++_syncGen;
    final wasMyTurn = _isMyTurn;
    final newRolls = msg['rollsLeft'] as int? ?? _state.rollsLeft;
    final newHeld  = List<bool>.from(msg['held'] as List);
    // If rollsLeft decreased, a roll happened — animate ALL non-held dice.
    // Don't use value comparison: first die might keep same value by chance.
    final wasRoll = newRolls < _state.rollsLeft;
    if (wasRoll) {
      setState(() { for (int i = 0; i < 5; i++) if (!newHeld[i]) _rolling[i] = true; });
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted || gen != _syncGen) return; // overtaken by a newer sync
    }
    setState(() {
      _state.applySyncJson(msg);
      for (int i = 0; i < 5; i++) _rolling[i] = false;
    });
    if (!wasMyTurn && _isMyTurn && !_state.gameOver) turnChanged();
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _net.send('BOP_SYNC', _state.toSyncJson());
          else _net.send('BOP_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (r) => false)));
  }

  Future<void> _executeRoll() async {
    // Animate non-held dice, roll, then broadcast authoritative state to all
    setState(() { for (int i = 0; i < 5; i++) if (!_state.held[i]) _rolling[i] = true; });
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    _state.roll();
    setState(() { for (int i = 0; i < 5; i++) _rolling[i] = false; });
    _net.send('BOP_SYNC', _state.toSyncJson());
  }

  void _roll() {
    if (!_isMyTurn || _state.rollsLeft <= 0 || _state.gameOver || _anyRolling) return;
    SoundPlayer.i.diceRoll();
    HapticFeedback.mediumImpact();
    if (_net.isHost) {
      _executeRoll();
    } else {
      // Joiner: just send request. Host rolls authoritatively and broadcasts
      // BOP_SYNC which drives the animation on ALL devices via _receivedSync.
      _net.send('BOP_ROLL');
    }
  }

  void _toggleHold(int i) {
    if (!_isMyTurn || _state.rollsLeft == 3 || _anyRolling) return;
    if (_net.isHost) {
      setState(() => _state.held[i] = !_state.held[i]);
      _net.send('BOP_SYNC', _state.toSyncJson());
    } else {
      final nv = !_state.held[i];
      setState(() => _state.held[i] = nv);  // optimistic local update
      _net.send('BOP_HOLD', {'i': i, 'held': nv});
    }
  }

  void _score(BoppeslachCategory cat) {
    if (!_isMyTurn || _state.gameOver || _anyRolling) return;
    SoundPlayer.i.boppeslachScoreFill();
    HapticFeedback.lightImpact();
    if (_state.currentCard.hasScored(cat) || _state.rollsLeft == 3) return;
    if (_net.isHost) {
      // Host is authoritative: apply and broadcast to all
      setState(() => _state.scoreCategory(cat));
      _skipSoloAiTurns(); // no-op in multiplayer
      _net.send('BOP_SYNC', _state.toSyncJson());
    } else {
      // Joiner: send score request to host; host will apply and broadcast
      _net.send('BOP_SCORE', {'cat': BoppeslachCategory.values.indexOf(cat)});
    }
  }

  /// In solo mode: if it is now the AI player's turn, auto-score them
  /// (scratch the first available unscored category) until it's human again.
  void _skipSoloAiTurns() {
    if (!_net.isSolo) return;
    int safety = 0;
    while (!_state.gameOver &&
           _state.currentPlayer.id != _me.id &&
           safety++ < 14) {
      // Find the first unscored category and scratch it (score 0)
      final cat = BoppeslachCategory.values.firstWhere(
        (c) => !_state.currentCard.hasScored(c),
        orElse: () => BoppeslachCategory.values.first,
      );
      _state.scoreCategory(cat);
    }
  }

  void _resetGame() {
    resetConfetti();
    resetStats();
    setState(() {
      _state.currentPlayerIdx = widget.firstPlayer - 1;
      _state.dice      = [1, 1, 1, 1, 1];
      _state.held      = [false, false, false, false, false];
      _state.rollsLeft = 3;
      _state.gameOver  = false;
      _state.message   = '';
      for (final sc in _state.scorecards) sc.reset();
      for (int i = 0; i < 5; i++) _rolling[i] = false;
    });
  }


  @override Widget build(BuildContext context) => GameScaffold(
        key: scaffoldKey,
    title: L.boppeslach.gameName,
    players: widget.players, chatMessages: chatMessages, onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.boppeslach.rules,
    child: Column(children: [
      PlayerBar(
        players: widget.players,
        activeIdx: _state.currentPlayerIdx,
        scores: _state.scorecards.map((sc) => sc.total).toList(),
        scoreLabel: ' ${L.boppeslach.ptsUnit}',
      ),
      GameStatusBar(
        text: _state.gameOver ? null
            : _isMyTurn ? L.boppeslach.tapToHold : L.boppeslach.waitingOpponent,
        textColor: _isMyTurn ? kGreen : null,
      ),
      Expanded(child: Row(children: [
        Expanded(flex: 3, child: _buildDiceArea()),
        Expanded(flex: 4, child: _buildScorecard()),
      ])),
      if (_state.gameOver) _buildWinBanner(),
    ]),
  );

  Widget _sectionHdr(String l) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    color: kPurple2.withValues(alpha: .2),
    child: Text(l, style: const TextStyle(color: kPurple, fontSize: 10,
      fontWeight: FontWeight.bold, letterSpacing: 1)));

  Widget _scoreRow(BoppeslachCategory cat, bool canScore) {
    final preview = canScore && !_state.currentCard.hasScored(cat)
        ? calcScore(cat, _state.dice) : null;
    return InkWell(
      onTap: (canScore && !_state.currentCard.hasScored(cat)) ? () => _score(cat) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          border: const Border(bottom: BorderSide(color: Colors.white10)),
          color: (canScore && preview != null && preview > 0 && !_state.currentCard.hasScored(cat))
              ? kPurple.withValues(alpha: .07) : Colors.transparent),
        child: Row(children: [
          Expanded(child: Text(kCategoryNames[cat]!,
            style: const TextStyle(color: kText, fontSize: 11))),
          ...widget.players.asMap().entries.map((e) {
            final sc = _state.scorecards[e.key];
            final isCur = e.key == _state.currentPlayerIdx;
            final scored = sc.scores[cat];
            return SizedBox(width: 40, child: Center(child: scored != null
              ? Text('$scored', style: TextStyle(color: e.value.color,
                  fontSize: 12, fontWeight: FontWeight.bold))
              : (isCur && preview != null)
                ? Text('$preview', style: TextStyle(
                    color: preview > 0 ? kGreen.withValues(alpha: .8) : Colors.red.withValues(alpha: .5),
                    fontSize: 11, fontStyle: FontStyle.italic))
              : const Text('—', style: TextStyle(color: Colors.white24, fontSize: 11))));
          }),
        ]),
      ));
  }

  Widget _bonusRow() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.white10)), color: Color(0x0AFFFFFF)),
    child: Row(children: [
      Expanded(child: Text(L.boppeslach.bonus,
        style: TextStyle(color: kMuted, fontSize: 11, fontStyle: FontStyle.italic))),
      ...widget.players.asMap().entries.map((e) {
        final sc = _state.scorecards[e.key];
        return SizedBox(width: 40, child: Center(child: Text(
          sc.bonus > 0 ? '+35' : '${sc.upperTotal}/63',
          style: TextStyle(color: sc.bonus > 0 ? kGreen : kMuted, fontSize: 10))));
      }),
    ]));

  Widget _totalRow() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    color: kPurple2.withValues(alpha: .15),
    child: Row(children: [
      Expanded(child: Text(L.boppeslach.total,
        style: TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.bold))),
      ...widget.players.asMap().entries.map((e) => SizedBox(width: 40,
        child: Center(child: Text('${_state.scorecards[e.key].total}',
          style: TextStyle(color: e.value.color, fontSize: 13, fontWeight: FontWeight.bold))))),
    ]));

  // ── Dice area (left panel) ────────────────────────────────────────────────
  Widget _buildDiceArea() {
    final canRoll = _isMyTurn && _state.rollsLeft > 0 && !_state.gameOver && !_anyRolling;
    return Column(children: [
      const SizedBox(height: 12),
      // 5 dice in a wrap
      Wrap(
        spacing: 8, runSpacing: 8,
        alignment: WrapAlignment.center,
        children: List.generate(5, (i) {
          final held = _state.held[i];
          return GestureDetector(
            onTap: () => _toggleHold(i),
            child: AnimatedDie(
              value: _state.dice[i],
              rolling: _rolling[i],
              held: held,
              size: 52,
            ),
          );
        }),
      ),
      const SizedBox(height: 16),
      // Roll button
      GestureDetector(
        onTap: canRoll ? _roll : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: canRoll ? kPurple : kBg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: canRoll ? kPurple : kBorder),
            boxShadow: canRoll ? [BoxShadow(color: kPurple.withValues(alpha: .4), blurRadius: 8)] : [],
          ),
          child: Text(
            _state.rollsLeft == 3
                ? L.boppeslach.rollBtnShort
                : L.boppeslach.rollsLeft.fmt({'n': '${_state.rollsLeft}'}),
            style: TextStyle(
              color: canRoll ? Colors.white : kMuted,
              fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        _isMyTurn ? L.boppeslach.tapToHold : L.boppeslach.waitingOpponent,
        style: const TextStyle(color: kMuted, fontSize: 11)),
    ]);
  }

  // ── Scorecard (right panel) ───────────────────────────────────────────────
  Widget _buildScorecard() {
    final canScore = _isMyTurn && _state.rollsLeft < 3 && !_state.gameOver && !_anyRolling;
    return Container(
      decoration: BoxDecoration(
        color: kBg2, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder)),
      child: Column(children: [
        _sectionHdr(L.boppeslach.sectionHdrUpper),
        ...kUpperCategories.map((cat) => _scoreRow(cat, canScore)),
        _bonusRow(),
        _sectionHdr(L.boppeslach.sectionHdrLower),
        ...kLowerCategories.map((cat) => _scoreRow(cat, canScore)),
        _totalRow(),
      ]),
    );
  }

  Widget _buildWinBanner() {
    final winnerIdx = _state.winnerIdx;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GameResultBanner(
        players: widget.players,
        winnerIdx: winnerIdx,
            onFirstRender: () { fireConfettiOnce(winnerIdx); recordResult('boppeslach', winnerIdx); if (_net.isHost) SessionState().advanceGame(); },
        scores: _state.scorecards.asMap().entries.map((e) =>
          (label: widget.players[e.key].name, value: '${e.value.total} ${L.boppeslach.ptsUnit}'),
        ).toList(),
      ),
      GameOverActions(players: widget.players, sendReset: false, onReset: () {
        _resetGame();
        if (_net.isHost) {
          _net.send('GAME_RESET');
          _net.send('BOP_SYNC', _state.toSyncJson());
        }
      }),
    ]);
  }
}
