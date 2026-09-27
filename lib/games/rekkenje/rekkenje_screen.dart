import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network.dart';
import '../../widgets/game_mixin.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../core/wake_lock.dart';
import '../../screens/lobby_screen.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/reconnect_dialog.dart';
import 'rekkenje_state.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../core/sound_player.dart';

// ── Screen phases ─────────────────────────────────────────────────────────────
enum _Phase { countdown, playing, roundEnd, gameEnd }

class RekkenjeScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final RekkenjeConfig config;

  const RekkenjeScreen({super.key,
    required this.players,
    required this.firstPlayer,
    required this.config});

  @override State<RekkenjeScreen> createState() => _RekkenjeScreenState();
}

class _RekkenjeScreenState extends State<RekkenjeScreen>
    with TickerProviderStateMixin, GameMixin {

  final _net     = Network();
  int  get _myIdx => _net.myIdx.clamp(0, widget.players.length - 1);

  // ── Round state ───────────────────────────────────────────────────────────
  _Phase _phase        = _Phase.countdown;
  int    _currentRound = 1;
  int    _countdown    = 3;

  // Questions (same seed across all devices so questions are identical)
  late List<RekkenjeQuestion> _questions;
  int  _qIdx       = 0;           // which question am I on
  String _input    = '';           // current keypad input
  String _feedback = '';           // 'correct' | 'incorrect' | ''
  bool   _feedbackCorrect = false;
  Timer? _feedbackTimer;

  // Round timer
  int    _secondsLeft = 0;
  int    _lastSeed     = 0; // stored so host can replay REK_START_ROUND on request
  int    _roundVersion = 0; // incremented each round; cancels stale countdown loops
  bool   _nextRoundPending = false; // guards "Next round" double tap during delay
  Timer? _roundTimer;

  // My answers this round
  final List<PlayerAnswer> _myAnswers = [];

  // Round stats for all players (filled at round end)
  // playerIdx → PlayerRoundStats
  final Map<int, PlayerRoundStats> _roundStats = {};

  // Accumulated totals
  final List<PlayerTotalStats> _totals = [];

  // Who has finished all questions this round (playerIdx set)
  final Set<int> _finished = {};

  // Animations
  late AnimationController _countdownCtrl;
  late Animation<double>   _countdownScale;
  late AnimationController _feedbackCtrl;
  late Animation<double>   _feedbackScale;

  // Countdown bounce colors
  static const _countdownColors = [
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    kPurple,
  ];

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();

    // Animated controllers
    _countdownCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _countdownScale = Tween(begin: 0.3, end: 1.2)
        .animate(CurvedAnimation(parent: _countdownCtrl, curve: Curves.elasticOut));

    _feedbackCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _feedbackScale = Tween(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _feedbackCtrl, curve: Curves.easeOut));

    // Init totals
    for (int i = 0; i < widget.players.length; i++) {
      _totals.add(PlayerTotalStats());
    }

    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };

    // Host drives countdown start; delay so all joiners finish initState first
    if (_net.isHost) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _startCountdown();
      });
    } else {
      // Joiner: request current state in case we missed REK_START_ROUND
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _phase == _Phase.countdown && _countdown == 3) {
          _net.send('REK_SYNC_REQ', {});
        }
      });
    }
  }

  @override void dispose() {
    msgSub?.cancel();
    _countdownCtrl.dispose();
    _feedbackCtrl.dispose();
    _roundTimer?.cancel();
    _feedbackTimer?.cancel();
    WakeLock.release();
    super.dispose();
  }

  // ── Network ───────────────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    final type = msg['type'] as String? ?? '';
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (type) {
      case 'REK_SYNC_REQ':
        // Joiner missed REK_START_ROUND — resend it along with accumulated totals
        if (_net.isHost) {
          _net.sendTo(fromIdx, 'REK_START_ROUND', {
            'round': _currentRound,
            'seed':  _lastSeed,
          });
          // Also send accumulated totals so the rejoiner's scoreboard is correct
          _net.sendTo(fromIdx, 'REK_TOTALS_SYNC', {
            'totals': _totals.map((t) => {
              'correct': t.correct,
              'total':   t.total,
              'points':  t.points,
            }).toList(),
            'round': _currentRound,
          });
        }
        break;

      case 'REK_START_ROUND':
        _receiveStartRound(msg);
        break;
      case 'REK_TOTALS_SYNC':
        if (!_net.isHost) {
          final rawTotals = msg['totals'] as List;
          setState(() {
            for (int i = 0; i < rawTotals.length && i < _totals.length; i++) {
              final t = rawTotals[i] as Map<String, dynamic>;
              _totals[i].correct = t['correct'] as int;
              _totals[i].total   = t['total']   as int;
              _totals[i].points  = t['points']  as int;
            }
            _currentRound = msg['round'] as int;
          });
        }
        break;
      case 'REK_ANSWER':
        // Host collects all answers for leaderboard display
        if (_net.isHost) _hostReceiveAnswer(msg, fromIdx);
        break;
      case 'REK_ROUND_END':
        _receiveRoundEnd(msg);
        break;
      case 'GAME_RESET':
        // Host's "Play Again" (GameOverActions) broadcasts GAME_RESET —
        // joiner resets exactly like a local reset (totals, confetti, stats).
        if (!_net.isHost) _resetGame();
        break;
    }
  }

  // ── Round lifecycle ───────────────────────────────────────────────────────

  void _startCountdown({int? preSeed}) async {
    // Use pre-generated seed if provided (avoids race with REK_SYNC_REQ during delay),
    // otherwise generate one now (first round / reset path).
    final seed = preSeed ?? DateTime.now().millisecondsSinceEpoch;
    _lastSeed  = seed;
    _roundVersion++;
    _questions = _generateWithSeed(seed);

    // Tell joiners to start countdown with same seed
    _net.send('REK_START_ROUND', {
      'round': _currentRound,
      'seed':  seed,
    });

    setState(() {
      _phase      = _Phase.countdown;
      _countdown  = 3;
      _qIdx       = 0;
      _input      = '';
      _feedback   = '';
      _myAnswers.clear();
      _finished.clear();
      _roundStats.clear();
    });

    final myVersion = _roundVersion;
    await _runCountdown(myVersion);
    if (mounted && _roundVersion == myVersion) _beginPlaying();
  }

  void _receiveStartRound(Map<String, dynamic> msg) async {
    final seed = msg['seed'] as int;
    if (seed == _lastSeed) return; // already started this round, ignore duplicate
    _lastSeed = seed;
    _roundVersion++; // cancel any stale countdown loop
    final myVersion = _roundVersion;
    _questions = _generateWithSeed(seed);
    setState(() {
      _phase        = _Phase.countdown;
      _currentRound = msg['round'] as int;
      _countdown    = 3;
      _qIdx         = 0;
      _input        = '';
      _feedback     = '';
      _myAnswers.clear();
      _finished.clear();
      _roundStats.clear();
    });
    await _runCountdown(myVersion);
    if (mounted && _roundVersion == myVersion) _beginPlaying();
  }

  List<RekkenjeQuestion> _generateWithSeed(int seed) {
    // Use same seed so all devices get identical question list
    final r = math.Random(seed);
    final cfg = widget.config;
    final count = cfg.questionsPerRound;
    final questions = <RekkenjeQuestion>[];
    final max = cfg.maxVal;

    for (int i = 0; i < count; i++) {
      int a, b;
      switch (cfg.op) {
        case RekkenjeOp.addition:
          a = r.nextInt(max + 1);
          b = r.nextInt(max - a + 1);
          break;
        case RekkenjeOp.subtraction:
          a = r.nextInt(max + 1);
          b = r.nextInt(a + 1);
          break;
        case RekkenjeOp.multiplication:
          a = r.nextInt(max ~/ 2 + 1).clamp(1, max);
          final maxB = (max ~/ a).clamp(1, max);
          b = r.nextInt(maxB) + 1;
          break;
        case RekkenjeOp.division:
          final halfMax = math.max(1, max ~/ 2);
          b = (r.nextInt(halfMax) + 2).clamp(2, max);
          final maxQ = max ~/ b;
          a = maxQ < 1 ? b : b * (r.nextInt(maxQ) + 1);
          break;
      }
      questions.add(RekkenjeQuestion(a: a, b: b, op: cfg.op));
    }
    return questions;
  }

  Future<void> _runCountdown([int? version]) async {
    for (int i = 3; i >= 1; i--) {
      if (!mounted) return;
      if (version != null && _roundVersion != version) return;
      setState(() => _countdown = i);
      _countdownCtrl.reset();
      _countdownCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 900));
    }
    // "GO!"
    if (!mounted) return;
    if (version != null && _roundVersion != version) return;
    setState(() => _countdown = 0);
    _countdownCtrl.reset();
    _countdownCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 600));
  }

  void _beginPlaying() {
    SoundPlayer.i.rekkenjeQuestion();
    if (!mounted) return;
    setState(() {
      _phase       = _Phase.playing;
      _secondsLeft = widget.config.secondsPerRound;
    });
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _endRound();
      }
    });
  }

  void _endRound() {
    _roundTimer?.cancel();
    if (_phase != _Phase.playing) return;

    // Build my own stats
    final myStats = PlayerRoundStats();
    for (final a in _myAnswers) myStats.add(a);

    // If host: collect and broadcast stats, then start next round or end game
    if (_net.isHost) {
      _roundStats[_myIdx] = myStats;
      _checkAllSubmitted();
    } else {
      // Send my stats to host
      _net.send('REK_ANSWER', {
        'playerIdx': _myIdx,
        'correct':   myStats.correct,
        'total':     myStats.total,
        'points':    myStats.points,
      });
    }
  }

  void _hostReceiveAnswer(Map<String, dynamic> msg, int fromIdx) {
    // sound handled per-result
    final stats = PlayerRoundStats()
      ..correct = msg['correct'] as int
      ..total   = msg['total']   as int
      ..points  = msg['points']  as int;
    _roundStats[fromIdx] = stats;
    _checkAllSubmitted();
  }

  void _checkAllSubmitted() {
    // In solo mode only the human player (idx 0) submits; skip AI slots
    final required = _net.isSolo ? 1 : widget.players.length;
    if (_roundStats.length < required) return;
    _broadcastRoundEnd();
  }

  void _broadcastRoundEnd() {
    final statsPayload = <String, dynamic>{};
    for (int i = 0; i < widget.players.length; i++) {
      final s = _roundStats[i] ?? PlayerRoundStats();
      statsPayload['$i'] = {'c': s.correct, 't': s.total, 'p': s.points};
    }
    final isLast = _currentRound >= widget.config.rounds;
    _net.send('REK_ROUND_END', {
      'round':  _currentRound,
      'stats':  statsPayload,
      'isLast': isLast,
    });
    _applyRoundEnd(statsPayload, isLast);
  }

  void _receiveRoundEnd(Map<String, dynamic> msg) {
    final statsMap = msg['stats'] as Map<String, dynamic>;
    final isLast   = msg['isLast'] as bool;
    _applyRoundEnd(statsMap, isLast);
    // Safety net: if we miss REK_START_ROUND for the next round, request a resend
    if (!isLast && !_net.isHost) {
      final versionAtEnd = _roundVersion;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _roundVersion == versionAtEnd && _phase == _Phase.roundEnd) {
          _net.send('REK_SYNC_REQ', {});
        }
      });
    }
  }

  void _applyRoundEnd(Map<String, dynamic> statsMap, bool isLast) {
    _roundTimer?.cancel();
    setState(() {
      _roundStats.clear();
      for (int i = 0; i < widget.players.length; i++) {
        final m   = (statsMap['$i'] ?? statsMap[i.toString()]) as Map<String, dynamic>?;
        final rs  = PlayerRoundStats()
          ..correct = (m?['c'] as int?) ?? 0
          ..total   = (m?['t'] as int?) ?? 0
          ..points  = (m?['p'] as int?) ?? 0;
        _roundStats[i] = rs;
        _totals[i].addRound(rs);
      }
      _phase = isLast ? _Phase.gameEnd : _Phase.roundEnd;
    });
  }

  void _nextRound() {
    if (!_net.isHost) return;
    if (_nextRoundPending || _phase != _Phase.roundEnd) return;
    _nextRoundPending = true;
    // Generate the seed now so REK_SYNC_REQ responses during the delay use the correct seed
    final nextSeed = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _currentRound++;
      _lastSeed = nextSeed;
    });
    // Small delay so joiners finish processing REK_ROUND_END before REK_START_ROUND arrives
    Future.delayed(const Duration(milliseconds: 400), () {
      _nextRoundPending = false;
      if (mounted) _startCountdown(preSeed: nextSeed);
    });
  }

  void _resetGame() {
    resetConfetti();
    resetStats();
    _roundTimer?.cancel();
    setState(() {
      _currentRound = 1;
      _phase        = _Phase.countdown;
      _countdown    = 3;
      _input        = '';
      _feedback     = '';
      _myAnswers.clear();
      _finished.clear();
      _roundStats.clear();
      for (final t in _totals) { t.correct = 0; t.total = 0; t.points = 0; }
    });
    if (_net.isHost) _startCountdown();
  }

  // ── Answering ─────────────────────────────────────────────────────────────

  KeyEventResult _handleHwKey(LogicalKeyboardKey key) {
    final digits = {
      LogicalKeyboardKey.digit0: '0', LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2', LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4', LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6', LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8', LogicalKeyboardKey.digit9: '9',
      LogicalKeyboardKey.numpad0: '0', LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2', LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4', LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6', LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8', LogicalKeyboardKey.numpad9: '9',
    };
    if (digits.containsKey(key)) { _keyTap(digits[key]!); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _keyTap('⌫'); return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _keyTap('✓'); return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _keyTap(String key) {
    if (_phase != _Phase.playing) return;
    if (_qIdx >= _questions.length) return;
    setState(() {
      if (key == '⌫') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
      } else if (key == '✓') {
        _submitAnswer();
      } else {
        if (_input.length < 5) _input += key;
      }
    });
  }

  void _submitAnswer() {
    if (_input.isEmpty) return;
    final q       = _questions[_qIdx];
    final given   = int.tryParse(_input) ?? -999;
    final correct = given == q.answer;

    final ans = PlayerAnswer(
      questionIdx: _qIdx,
      given:       given,
      correct:     correct,
      secondsLeft: _secondsLeft,
    );
    _myAnswers.add(ans);

    // Feedback flash
    _feedbackTimer?.cancel();
    _feedbackCtrl.reset();
    _feedbackCtrl.forward();
    setState(() {
      _feedback        = correct ? L.rekkenje.correct : L.rekkenje.incorrect.fmt({'ans': q.answer});
      _feedbackCorrect = correct;
      _input           = '';
      _qIdx++;
    });

    _feedbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _feedback = '');
    });

    // If all questions done
    if (_qIdx >= _questions.length) {
      _finished.add(_myIdx);
      _endRound();
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override Widget build(BuildContext context) {
    Widget body;
    if (_phase == _Phase.countdown)     body = _buildCountdown();
    else if (_phase == _Phase.playing)  body = _buildPlaying();
    else if (_phase == _Phase.gameEnd)  body = _buildRoundEnd(isLast: true);
    else                                body = _buildRoundEnd(isLast: false);
    return GameScaffold(
        key: scaffoldKey,
      title: L.rekkenje.gameName,
      players: widget.players, chatMessages: chatMessages, onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.rekkenje.rules,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          return _handleHwKey(event.logicalKey);
        },
        child: body,
      ),
    );
  }

  // ── Countdown ─────────────────────────────────────────────────────────────
  Widget _buildCountdown() {
    final isGo = _countdown == 0;
    final colorIdx = isGo ? 3 : (3 - _countdown).clamp(0, 3);
    final color = _countdownColors[colorIdx];
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center, radius: 0.8,
          colors: [color.withValues(alpha: .25), kBg])),
      child: Center(child: ScaleTransition(
        scale: _countdownScale,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            isGo ? L.rekkenje.goBtn : '$_countdown',
            style: TextStyle(
              fontSize: isGo ? 80 : 120,
              fontWeight: FontWeight.w900,
              color: color,
              shadows: [Shadow(color: color.withValues(alpha: .5),
                blurRadius: 30)]),
          ),
          const SizedBox(height: 12),
          Text(L.rekkenje.roundOf.fmt({'cur': _currentRound, 'total': widget.config.rounds}),
            style: const TextStyle(color: kMuted, fontSize: 18)),
          const SizedBox(height: 8),
          Text(kOpLabel[widget.config.op]!,
            style: TextStyle(color: color.withValues(alpha: .8), fontSize: 14,
              fontWeight: FontWeight.bold)),
        ]),
      )),
    );
  }

  // ── Playing ───────────────────────────────────────────────────────────────
  Widget _buildPlaying() {
    final q       = _qIdx < _questions.length ? _questions[_qIdx] : null;
    final total   = _questions.length;
    final progress = total == 0 ? 0.0 : _qIdx / total;
    final timeRatio = _secondsLeft / widget.config.secondsPerRound;
    final timerColor = timeRatio > .5 ? kGreen
        : timeRatio > .25 ? const Color(0xFFF97316) : Colors.red;

    return Column(children: [
      // Scores bar
      PlayerBar(
        players: widget.players,
        activeIdx: -1, // simultaneous game, no single active player
        scores: List.generate(widget.players.length, (i) => _totals[i].points),
        scoreLabel: ' ${L.rekkenje.pointsLabel}',
      ),
      const GameStatusBar(),
      // Top bar: round info + timer
      Container(
        color: Colors.black45,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(children: [
          Text(L.rekkenje.roundShort.fmt({'cur': _currentRound, 'total': widget.config.rounds}),
            style: const TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(width: 12),
          Text(L.rekkenje.questionShort.fmt({'n': _qIdx + 1, 'total': total}),
            style: const TextStyle(color: kText, fontSize: 12,
              fontWeight: FontWeight.bold)),
          const Spacer(),
          // Timer pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: timerColor.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: timerColor.withValues(alpha: .5))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.timer, color: timerColor, size: 14),
              const SizedBox(width: 4),
              Text(L.rekkenje.secondsLeft.fmt({'n': _secondsLeft}),
                style: TextStyle(color: timerColor, fontSize: 13,
                  fontWeight: FontWeight.bold)),
            ])),
          const SizedBox(width: 12),
          // Progress bar
          SizedBox(width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress, minHeight: 8,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(kPurple)))),
        ]),
      ),

      Expanded(child: OrientationBuilder(builder: (context, orientation) {
        final isPortrait = orientation == Orientation.portrait;
        final questionAndKeypad = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Feedback
              SizedBox(
                height: 60,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _feedback.isNotEmpty ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: ScaleTransition(
                      scale: _feedbackScale,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: (_feedbackCorrect ? kGreen : Colors.red).withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _feedbackCorrect ? kGreen : Colors.red)),
                        child: Text(
                          _feedback.isNotEmpty ? _feedback : ' ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _feedbackCorrect ? kGreen : Colors.red,
                            fontSize: 18, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ),
              ),

              if (q != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPurple2.withValues(alpha: .3), kBg2],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kBorder, width: 2)),
                  child: Text(q.questionText,
                    style: const TextStyle(fontSize: 38,
                      fontWeight: FontWeight.w900, color: kText))),
                const SizedBox(height: 20),
                Container(
                  width: 180,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: kBg2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _input.isEmpty ? kBorder : kPurple, width: 2)),
                  child: Text(
                    _input.isEmpty ? '?' : _input,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold,
                      color: _input.isEmpty ? kMuted : kText))),
                const SizedBox(height: 16),
                _buildKeypad(),
              ] else ...[
                const SizedBox(height: 40),
                Text(L.rekkenje.waitingRoundEnd,
                  style: TextStyle(color: kMuted, fontSize: 16,
                    fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        );

        final scoreboard = SizedBox(
          width: isPortrait ? double.infinity : 160,
          child: _buildLiveScoreboard());

        if (isPortrait) {
          return Column(children: [
            Expanded(child: SingleChildScrollView(child: questionAndKeypad)),
            scoreboard,
          ]);
        } else {
          return Row(children: [
            Expanded(flex: 3, child: SingleChildScrollView(child: questionAndKeypad)),
            scoreboard,
          ]);
        }
      })),
    ]);
  }

  Widget _buildKeypad() {
    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['⌫', '0', '✓'],
    ];
    return Column(mainAxisSize: MainAxisSize.min,
      children: rows.map((row) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(mainAxisSize: MainAxisSize.min,
          children: row.map((k) {
            final isSubmit  = k == '✓';
            final isDelete  = k == '⌫';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _keyTap(k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width: 56, height: 52,
                  decoration: BoxDecoration(
                    color: isSubmit ? kPurple2
                        : isDelete  ? Colors.white.withValues(alpha: .06)
                        :             kBg2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSubmit ? kPurple : kBorder,
                      width: isSubmit ? 2 : 1),
                    boxShadow: [BoxShadow(
                      color: isSubmit ? kPurple.withValues(alpha: .3) : Colors.black26,
                      blurRadius: 4, offset: const Offset(0, 2))]),
                  child: Center(child: Text(k,
                    style: TextStyle(
                      fontSize: isSubmit ? 20 : 22,
                      fontWeight: FontWeight.bold,
                      color: isSubmit ? Colors.white
                          : isDelete  ? kMuted : kText))))));
          }).toList()))).toList());
  }

  Widget _buildLiveScoreboard() => Container(
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: kBorder))),
    padding: const EdgeInsets.all(10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(L.rekkenje.playersLabel, style: const TextStyle(color: kMuted, fontSize: 9,
        letterSpacing: 1, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...widget.players.asMap().entries
        .where((e) => !(_net.isSolo && e.key > 0))
        .map((e) {
        final p      = e.value;
        final done   = e.key == _myIdx ? _qIdx : null;
        final isDone = _finished.contains(e.key);
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: p.color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.color.withValues(alpha: .3))),
          child: Row(children: [
            Container(width: 6, height: 6,
              decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(child: Text(p.name,
              style: TextStyle(color: kText, fontSize: 11,
                fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis)),
            if (isDone)
              const Text('✓', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], color: kGreen, fontSize: 12))
            else if (e.key == _myIdx)
              Text(L.rekkenje.answeredOf.fmt({'done': done ?? 0, 'total': _questions.length}),
                style: const TextStyle(color: kMuted, fontSize: 10)),
          ]));
      }),
      const Spacer(),
      // Op reminder
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: kPurple.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(kOpSymbol[widget.config.op]!,
            style: const TextStyle(color: kPurple, fontSize: 20,
              fontWeight: FontWeight.w900)),
          Text(L.rekkenje.range.fmt({'max': widget.config.maxVal}),
            style: const TextStyle(color: kMuted, fontSize: 10)),
        ])),
    ]));

  // ── Round/Game end ─────────────────────────────────────────────────────────
  Widget _buildRoundEnd({required bool isLast}) {
    // Sort players by round points (this round)
    final sorted = List.generate(widget.players.length, (i) => i)
      ..sort((a, b) =>
        (_roundStats[b]?.points ?? 0).compareTo(_roundStats[a]?.points ?? 0));

    // Sort by total points for game end
    final sortedTotal = List.generate(widget.players.length, (i) => i)
      ..sort((a, b) => _totals[b].points.compareTo(_totals[a].points));
    // Winner (0-based) or -1 for a draw when the top totals are equal.
    // In solo mode only the human (idx 0) is ranked (AI slots are placeholders).
    final ranked = sortedTotal.where((i) => !(_net.isSolo && i > 0)).toList();
    final winnerIdx = ranked.length > 1 &&
            _totals[ranked[0]].points == _totals[ranked[1]].points
        ? -1 : ranked[0];

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter, radius: 1.2,
          colors: [kPurple2.withValues(alpha: .3), kBg])),
      child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // Title
          if (isLast)
            GameResultBanner(
              players: widget.players,
              winnerIdx: winnerIdx,
            onFirstRender: () { fireConfettiOnce(winnerIdx); recordResult('rekkenje', winnerIdx); if (_net.isHost) SessionState().advanceGame(); },
              scores: sortedTotal.map((i) =>
                (label: widget.players[i].name, value: '${_totals[i].points} pts'),
              ).toList(),
            )
          else
            Text(L.rekkenje.roundDone.fmt({'n': _currentRound}),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
                color: kText)),
          const SizedBox(height: 8),

          // Round stats table
          Container(
            decoration: BoxDecoration(
              color: kBg2, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder)),
            child: Column(children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Expanded(child: Text(L.rekkenje.playerLabel,
                    style: TextStyle(color: kMuted, fontSize: 11,
                      fontWeight: FontWeight.bold))),
                  _colHdr(L.rekkenje.thisRound, 80),
                  if (isLast) _colHdr(L.rekkenje.totalLabel, 60),
                  _colHdr(L.rekkenje.accuracy, 60),
                  _colHdr(L.rekkenje.pointsLabel, 56),
                ])),
              const Divider(color: kBorder, height: 1),
              ...sorted
                .where((idx) => !(_net.isSolo && idx > 0))
                .toList()
                .asMap().entries.map((e) {
                final rank = e.key;
                final idx  = e.value;
                final p    = widget.players[idx];
                final rs   = _roundStats[idx] ?? PlayerRoundStats();
                final tot  = _totals[idx];
                return _buildResultRow(rank, idx, p, rs, tot, isLast);
              }),
            ])),

          const SizedBox(height: 20),

          // Buttons
          if (isLast) ...[
            GameOverActions(players: widget.players, onReset: _resetGame),
          ] else ...[
            if (_net.isHost)
              ElevatedButton.icon(
                onPressed: _nextRoundPending ? null : _nextRound,
                icon: const Text('▶', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 14)),
                label: Text(L.rekkenje.nextRound.fmt({'n': _currentRound + 1})),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPurple2, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
                  textStyle: const TextStyle(fontSize: 16,
                    fontWeight: FontWeight.bold)))
            else
              Text(L.rekkenje.waitingNextRound,
                style: TextStyle(color: kMuted, fontStyle: FontStyle.italic)),
          ],
        ]))));
  }

  Widget _colHdr(String t, double w) => SizedBox(width: w,
    child: Text(t, textAlign: TextAlign.center,
      style: const TextStyle(color: kMuted, fontSize: 10,
        fontWeight: FontWeight.bold)));

  Widget _buildResultRow(int rank, int idx, Player p,
      PlayerRoundStats rs, PlayerTotalStats tot, bool showTotal) {
    final medals = ['1.', '2.', '3.'];
    final medal  = rank < 3 ? medals[rank] : '   ';
    final isMe   = idx == _myIdx;
    return Container(
      decoration: BoxDecoration(
        color: isMe ? p.color.withValues(alpha: .07) : Colors.transparent,
        border: const Border(bottom: BorderSide(color: Colors.white10))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Text(medal, style: const TextStyle(fontSize: 16, fontFamilyFallback: ['NotoColorEmoji'])),
        const SizedBox(width: 6),
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Expanded(child: Text(p.name,
          style: TextStyle(color: p.color, fontSize: 13,
            fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis)),
        SizedBox(width: 80, child: Center(child: Text(
          '${rs.correct}/${rs.total}',
          style: const TextStyle(color: kText, fontSize: 12)))),
        if (showTotal) SizedBox(width: 60, child: Center(child: Text(
          '${tot.correct}/${tot.total}',
          style: const TextStyle(color: kMuted, fontSize: 11)))),
        SizedBox(width: 60, child: Center(child: Text(
          rs.accuracyStr,
          style: TextStyle(
            color: rs.total == 0 ? kMuted
                : rs.correct == rs.total ? kGreen
                : rs.correct > rs.total ~/ 2 ? const Color(0xFFF97316)
                : Colors.red,
            fontSize: 12, fontWeight: FontWeight.bold)))),
        SizedBox(width: 56, child: Center(child: Text(
          '+${rs.points}',
          style: TextStyle(color: p.color, fontSize: 13,
            fontWeight: FontWeight.w900)))),
      ]));
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          // Joiner requests full state; host re-responds naturally via REK_SYNC_REQ handler
          if (!_net.isHost) _net.send('REK_SYNC_REQ', {});
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

}
