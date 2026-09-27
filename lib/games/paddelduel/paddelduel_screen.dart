import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/network.dart';
import '../../widgets/game_mixin.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import '../../core/session.dart';
import '../../core/wake_lock.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../l10n/app_localizations.dart';
import 'paddelduel_ai.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';

// ── Game constants (all in normalised 0‥1 coords) ────────────────────────────
const _winScore    = 5;
const _paddleW     = 0.018;   // half-width of paddle  (field-width fraction)
const _paddleH     = 0.10;    // half-height of paddle (field-height fraction)
const _aspect      = 1.6;     // field width / height
const _ballR       = 0.022;   // ball radius            (field-width fraction, x-axis)
const _ballRy      = _ballR * _aspect; // same radius in field-height units (y-axis)
const _initSpeed   = 0.42;    // initial ball speed     (field-widths / sec)
const _maxSpeed    = 0.90;
const _speedUp     = 0.035;   // speed bump per rally hit

class PaddelduelScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const PaddelduelScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<PaddelduelScreen> createState() => _PaddelduelState();
}

class _PaddelduelState extends State<PaddelduelScreen>
    with GameMixin, SingleTickerProviderStateMixin {
  final _net = Network();

  // Ball (host-authoritative)
  double _bx = 0.5, _by = 0.5;
  double _vx = 0.0, _vy = 0.0;

  // Paddle centres (0‥1 vertically); left = host, right = joiner
  double _lpy = 0.5, _rpy = 0.5;
  PaddelduelAI? _paddelduelAI;

  // Scores
  int _lScore = 0, _rScore = 0, _winner = 0;

  // Serve phase
  bool _serving = true;

  // Ticker (host only)
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  // Drag tracking (my own paddle only)
  double? _dragStartFieldY;   // normalised field Y at drag start
  double? _dragStartPaddleY;  // paddle Y at drag start

  // Net throttle
  int _netFrame = 0;

  bool get _iAmLeft => _net.myIdx == 0;

  @override List<Player> get gamePlayers => widget.players;

  @override void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _paddelduelAI = PaddelduelAI(d);
    }
    if (_net.isHost) {
      _ticker = createTicker(_hostTick)..start();
      _launchBall(leftServes: widget.firstPlayer == 1);
    }
  }

  @override void dispose() {
    msgSub?.cancel();
    _ticker?.dispose();
    WakeLock.release();
    super.dispose();
  }

  // ── Ball launch ─────────────────────────────────────────────────────────────
  void _launchBall({required bool leftServes}) {
    SoundPlayer.i.paddelduelStart();
    final rng = math.Random();
    final angle = (rng.nextDouble() * 0.6 - 0.3); // small vertical variance
    final dir = leftServes ? 1.0 : -1.0;
    _bx = leftServes ? 0.25 : 0.75;
    _by = 0.5;
    _vx = dir * _initSpeed * math.cos(angle);
    _vy = _initSpeed * math.sin(angle);
    _serving = false;
  }

  // ── Host physics tick ────────────────────────────────────────────────────────
  void _hostTick(Duration elapsed) {
    if (!mounted || _winner != 0 || _serving) return;
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    double bx = _bx + _vx * dt;
    double by = _by + _vy * dt;
    double vx = _vx, vy = _vy;

    // Top/bottom wall
    if (by - _ballRy <= 0) { by = _ballRy; vy = vy.abs(); }
    if (by + _ballRy >= 1) { by = 1 - _ballRy; vy = -vy.abs(); }

    // Left paddle  (x = _paddleW, centre y = _lpy)
    final lx = _paddleW * 2;
    if (vx < 0 && bx - _ballR <= lx &&
        (by - _lpy).abs() < _paddleH + _ballRy) {
      bx = lx + _ballR;
      final rel = (by - _lpy) / _paddleH;
      final speed = math.min(
          math.sqrt(vx * vx + vy * vy) + _speedUp, _maxSpeed);
      final outAngle = rel * 0.8; // max ~46° deflection
      vx =  speed * math.cos(outAngle);
      vy =  speed * math.sin(outAngle);
    }

    // Right paddle (x = 1 - _paddleW*2, centre y = _rpy)
    final rx = 1.0 - _paddleW * 2;
    if (vx > 0 && bx + _ballR >= rx &&
        (by - _rpy).abs() < _paddleH + _ballRy) {
      bx = rx - _ballR;
      final rel = (by - _rpy) / _paddleH;
      final speed = math.min(
          math.sqrt(vx * vx + vy * vy) + _speedUp, _maxSpeed);
      final outAngle = math.pi - rel * 0.8;
      vx =  speed * math.cos(outAngle);
      vy =  speed * math.sin(outAngle);
    }

    // Scoring
    bool scored = false;
    if (bx < 0) {
      setState(() { _rScore++; scored = true; });
    } else if (bx > 1) {
      setState(() { _lScore++; scored = true; });
    }

    if (scored) {
      HapticFeedback.heavyImpact();
      final lWon = _lScore >= _winScore;
      final rWon = _rScore >= _winScore;
      setState(() {
        if (lWon) { _winner = 1; }
        else if (rWon) { _winner = 2; }
        else {
          _serving = true;
          _bx = 0.5; _by = 0.5; _vx = 0; _vy = 0;
          // Loser serves next
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted && _winner == 0) {
              setState(() => _launchBall(leftServes: bx < 0));
            }
          });
        }
      });
      _net.send('PAD_STATE', _stateMap());
      return;
    }

    setState(() { _bx = bx; _by = by; _vx = vx; _vy = vy; });

    // In solo mode, AI controls the right paddle each tick
    if (_net.isSolo && _paddelduelAI != null) {
      setState(() {
        _rpy = _paddelduelAI!.computePaddleY(_by, _vx, _rpy, dt,
            minY: _paddleH, maxY: 1 - _paddleH);
      });
    }

    // Broadcast ball state every 2 frames (~30Hz)
    _netFrame++;
    if (_netFrame % 4 == 0) {  // ~15Hz instead of ~30Hz
      _net.send('PAD_STATE', _stateMap());
    }
  }

  Map<String, dynamic> _stateMap() => {
    'bx': _bx, 'by': _by, 'vx': _vx, 'vy': _vy,
    'ls': _lScore, 'rs': _rScore, 'w': _winner, 'srv': _serving,
  };

  // ── Paddle drag ─────────────────────────────────────────────────────────────
  void _onDragStart(DragStartDetails d, Size fieldSize) {
    final fy = d.localPosition.dy / fieldSize.height;
    _dragStartFieldY  = fy;
    _dragStartPaddleY = _iAmLeft ? _lpy : _rpy;
  }

  void _onDragUpdate(DragUpdateDetails d, Size fieldSize) {
    if (_dragStartFieldY == null) return;
    final fy   = d.localPosition.dy / fieldSize.height;
    final delta = fy - _dragStartFieldY!;
    final newY  = (_dragStartPaddleY! + delta).clamp(_paddleH, 1 - _paddleH).toDouble();
    setState(() {
      if (_iAmLeft) _lpy = newY; else _rpy = newY;
    });
    // Send paddle update every update (paddle is cheap)
    _net.send('PAD_PADDLE', {'py': newY});
  }

  // ── Message handling ─────────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'PAD_STATE':
        if (!_net.isHost) {
          setState(() {
            _bx = (msg['bx'] as num).toDouble();
            _by = (msg['by'] as num).toDouble();
            _vx = (msg['vx'] as num).toDouble();
            _vy = (msg['vy'] as num).toDouble();
            _lScore  = msg['ls'] as int;
            _rScore  = msg['rs'] as int;
            _winner  = msg['w']  as int;
            _serving = msg['srv'] as bool;
          });
        }
        break;

      case 'PAD_PADDLE':
        setState(() {
          final y = (msg['py'] as num).toDouble();
          // fromIdx 0 = host = left, fromIdx 1 = joiner = right
          if (fromIdx == 0) _lpy = y; else _rpy = y;
        });
        break;

      case 'GAME_RESET':
        if (!_net.isHost) {
          resetConfetti();
          resetStats();
          setState(_resetLocal);
        }
        break;

      case 'PAD_SYNC_REQ':
        if (_net.isHost) _net.send('PAD_STATE', _stateMap());
        break;

    }
  }

  void _resetLocal() {
    _lScore = 0; _rScore = 0; _winner = 0;
    _lpy = 0.5; _rpy = 0.5;
    _serving = true; _bx = 0.5; _by = 0.5; _vx = 0; _vy = 0;
    _lastTick = Duration.zero;
  }

  void _reset() {
    final lastWinner = _winner;
    resetConfetti();
    resetStats();
    setState(_resetLocal);
    if (_net.isHost) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _launchBall(leftServes: lastWinner != 1));
      });
    }
  }


  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _net.send('PAD_STATE', _stateMap());
          else _net.send('PAD_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override Widget build(BuildContext context) {
    final p1 = widget.players[0];
    final p2 = widget.players[1];

    return GameScaffold(
        key: scaffoldKey,
      title: L.paddelduel.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.paddelduel.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: -1,
          scores: [_lScore, _rScore],
          scoreLabel: null,
        ),
        GameStatusBar(
          text: _winner == 0 && _serving ? '…' : null,
        ),

        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: AspectRatio(
            aspectRatio: _aspect,
            child: LayoutBuilder(builder: (_, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final fieldSize = Size(w, h);

              return GestureDetector(
                onVerticalDragStart: (d) => _onDragStart(d, fieldSize),
                onVerticalDragUpdate: (d) => _onDragUpdate(d, fieldSize),
                child: CustomPaint(
                  size: fieldSize,
                  painter: _PaddelduelPainter(
                    bx: _bx, by: _by,
                    lpy: _lpy, rpy: _rpy,
                    p1Color: p1.color, p2Color: p2.color,
                    serving: _serving,
                    iAmLeft: _iAmLeft,
                  ),
                ),
              );
            }),
          ),
        ))),

        if (_winner != 0) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winner - 1,
            onFirstRender: () { fireConfettiOnce(_winner - 1); recordResult('paddelduel', _winner - 1); if (_net.isHost) SessionState().advanceGame(); },
            scores: [
              (label: widget.players[0].name, value: '$_lScore'),
              (label: widget.players[1].name, value: '$_rScore'),
            ],
          ),
          GameOverActions(players: widget.players, onReset: _reset),
        ] else const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────
class _PaddelduelPainter extends CustomPainter {
  final double bx, by, lpy, rpy;
  final Color p1Color, p2Color;
  final bool serving, iAmLeft;

  const _PaddelduelPainter({
    required this.bx, required this.by,
    required this.lpy, required this.rpy,
    required this.p1Color, required this.p2Color,
    required this.serving, required this.iAmLeft,
  });

  @override void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Background
    final bgPaint = Paint()..color = const Color(0xFF0D0621);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Centre dashed line
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 2;
    double dy = 0;
    while (dy < h) {
      canvas.drawLine(Offset(w / 2, dy), Offset(w / 2, math.min(dy + 10, h)), dashPaint);
      dy += 18;
    }

    // Field border
    final borderPaint = Paint()
      ..color = kBorder
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(8)),
      borderPaint);

    // Paddles
    _drawPaddle(canvas, w, h, _paddleW * 2 * w, lpy * h, p1Color, iAmLeft);
    _drawPaddle(canvas, w, h, (1 - _paddleW * 2) * w, rpy * h, p2Color, !iAmLeft);

    // Ball (only when not serving)
    if (!serving) {
      final cx = bx * w, cy = by * h;
      final r  = _ballR * w; // == _ballRy * h (field is _aspect:1)

      // Glow
      final glowPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawCircle(Offset(cx, cy), r * 2.5, glowPaint);

      // Ball
      final ballGrad = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        colors: [Colors.white, Colors.white70],
      );
      final ballPaint = Paint()
        ..shader = ballGrad.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, ballPaint);
    }
  }

  void _drawPaddle(Canvas canvas, double w, double h,
      double cx, double cy, Color color, bool isMyPaddle) {
    final pw = _paddleW * w;
    final ph = _paddleH * h;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: pw * 2, height: ph * 2),
      const Radius.circular(6));

    // Glow for own paddle
    if (isMyPaddle) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawRRect(rect, glowPaint);
    }

    final grad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(color, Colors.white, 0.35)!,
        color,
        Color.lerp(color, Colors.black, 0.25)!,
      ],
    );
    final paint = Paint()
      ..shader = grad.createShader(Rect.fromCenter(
          center: Offset(cx, cy), width: pw * 2, height: ph * 2));
    canvas.drawRRect(rect, paint);
  }

  @override bool shouldRepaint(_PaddelduelPainter old) =>
    old.bx != bx || old.by != by || old.lpy != lpy || old.rpy != rpy ||
    old.serving != serving;
}
