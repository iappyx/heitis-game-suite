import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../core/session.dart';
import '../../core/wake_lock.dart';
import '../../core/sound_player.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../screens/lobby_screen.dart';
import '../../screens/solo_setup_screen.dart';
import 'lofthockey_ai.dart';

// ── Constants (normalised 0..1 coordinates) ──────────────────────────────────
const _winScore   = 7;
const _puckR      = 0.034;   // puck radius (fraction of field width)
const _malletR    = 0.060;   // mallet radius (fraction of field width)
const _goalWidth  = 0.40;    // goal width as fraction of field width
const _initSpeed  = 0.35;    // initial puck speed (normalised / sec)
const _maxSpeed   = 0.90;    // maximum puck speed
const _friction   = 0.995;   // velocity multiplier per frame
const _goalPause  = Duration(milliseconds: 1200);

class LofthockeyScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const LofthockeyScreen({
    super.key,
    required this.players,
    required this.firstPlayer,
    this.extra,
  });
  @override State<LofthockeyScreen> createState() => _LofthockeyState();
}

class _LofthockeyState extends State<LofthockeyScreen>
    with SingleTickerProviderStateMixin, GameMixin {
  final _net = Network();

  // Puck state (normalised)
  double _px = 0.5, _py = 0.5;
  double _pvx = 0.0, _pvy = 0.0;

  // Mallet positions (normalised)
  // Player 1 = bottom (index 0), Player 2 = top (index 1)
  double _m1x = 0.5, _m1y = 0.80; // bottom mallet
  double _m2x = 0.5, _m2y = 0.20; // top mallet

  // Previous mallet positions for velocity calculation (saved at END of tick)
  double _prevM1x = 0.5, _prevM1y = 0.80;
  double _prevM2x = 0.5, _prevM2y = 0.20;

  // Haptic debounce — avoid constant buzzing during overlapping frames
  int _lastHapticMs = 0;

  // Collision cooldown — prevents puck sticking to mallet on repeated ticks
  bool _m1InContact = false;
  bool _m2InContact = false;

  // Aspect ratio: width / height of the field (updated each build)
  double _aspect = 0.6;

  // Scores
  int _score1 = 0, _score2 = 0;
  int _winner = 0; // 0 = none, 1 or 2
  bool _paused = true; // pause after goal or at start

  // Ticker
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  int _netFrame = 0;

  // AI
  LofthockeyAI? _ai;

  // Touch tracking — support multitouch for local shared-tablet play
  // In network mode: only my mallet. In solo: player 1 only.
  // We track pointer ID -> which mallet (1 or 2)
  final Map<int, int> _pointerToMallet = {};

  @override List<Player> get gamePlayers => widget.players;

  @override
  void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };

    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = LofthockeyAI(d);
    }

    if (_net.isHost) {
      _ticker = createTicker(_hostTick)..start();
      // Brief pause then launch
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _launchPuck(towardBottom: widget.firstPlayer == 1));
      });
    }
  }

  @override
  void dispose() {
    msgSub?.cancel();
    _ticker?.dispose();
    WakeLock.release();
    super.dispose();
  }

  // ── Puck launch ────────────────────────────────────────────────────────────
  void _launchPuck({required bool towardBottom}) {
    SoundPlayer.i.paddelduelStart();
    final rng = math.Random();
    final angle = (rng.nextDouble() * 0.8 - 0.4); // horizontal variance
    final dir = towardBottom ? 1.0 : -1.0;
    _px = 0.5;
    _py = 0.5;
    _pvx = _initSpeed * math.sin(angle) * 0.5;
    _pvy = dir * _initSpeed * math.cos(angle).abs();
    _paused = false;
  }

  // ── Host physics tick ──────────────────────────────────────────────────────
  void _hostTick(Duration elapsed) {
    if (!mounted || _winner != 0 || _paused) return;
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    // AI controls top mallet
    if (_net.isSolo && _ai != null) {
      final result = _ai!.computeMallet(_px, _py, _pvx, _pvy, _m2x, _m2y, dt);
      _m2x = result.x;
      _m2y = result.y;
    }

    double px = _px + _pvx * dt;
    double py = _py + _pvy * dt;
    double vx = _pvx;
    double vy = _pvy;

    // Friction
    vx *= _friction;
    vy *= _friction;

    // Wall bounces (left/right)
    if (px - _puckR <= 0) {
      px = _puckR;
      vx = vx.abs();
      SoundPlayer.i.paddelduelWall();
    }
    if (px + _puckR >= 1) {
      px = 1 - _puckR;
      vx = -vx.abs();
      SoundPlayer.i.paddelduelWall();
    }

    // Top/bottom wall bounces (outside goal zones)
    final goalLeft  = (1 - _goalWidth) / 2;
    final goalRight = 1 - goalLeft;

    // Top wall (y=0)
    if (py - _puckR <= 0) {
      if (px >= goalLeft && px <= goalRight) {
        _onGoal(1);
        return;
      } else {
        py = _puckR;
        vy = vy.abs();
        SoundPlayer.i.paddelduelWall();
      }
    }

    // Bottom wall (y=1)
    if (py + _puckR >= 1) {
      if (px >= goalLeft && px <= goalRight) {
        _onGoal(2);
        return;
      } else {
        py = 1 - _puckR;
        vy = -vy.abs();
        SoundPlayer.i.paddelduelWall();
      }
    }

    // Mallet-puck collisions
    // isPlayer: true for the local player's mallet (haptic), false for AI/remote
    final isP1Mine = _net.isSolo || _net.isHost;
    final isP2Mine = !_net.isSolo && !_net.isHost;
    final r1 = _malletCollision(px, py, vx, vy, _m1x, _m1y, _prevM1x, _prevM1y,
        dt, _aspect, isP1Mine, _m1InContact);
    px = r1.px; py = r1.py; vx = r1.vx; vy = r1.vy; _m1InContact = r1.inContact;

    final r2 = _malletCollision(px, py, vx, vy, _m2x, _m2y, _prevM2x, _prevM2y,
        dt, _aspect, isP2Mine, _m2InContact);
    px = r2.px; py = r2.py; vx = r2.vx; vy = r2.vy; _m2InContact = r2.inContact;

    // Anti-stuck: if puck is nearly stationary near a wall, nudge toward center
    final spd = math.sqrt(vx * vx + vy * vy);
    final nearWall = px < 0.08 || px > 0.92 || py < 0.08 || py > 0.92;
    if (nearWall && spd < _initSpeed * 0.3) {
      vx += (0.5 - px) * 0.15;
      vy += (0.5 - py) * 0.15;
    }

    // Speed cap
    final speed = math.sqrt(vx * vx + vy * vy);
    if (speed > _maxSpeed) {
      vx = vx / speed * _maxSpeed;
      vy = vy / speed * _maxSpeed;
    }

    setState(() { _px = px; _py = py; _pvx = vx; _pvy = vy; });

    // Save mallet positions for next tick's velocity calculation
    _prevM1x = _m1x; _prevM1y = _m1y;
    _prevM2x = _m2x; _prevM2y = _m2y;

    // Broadcast every 3 frames
    _netFrame++;
    if (_netFrame % 3 == 0) {
      _net.send('LOF_STATE', _stateMap());
    }
  }

  /// Mallet-puck collision with correct aspect ratio, push-based velocity,
  /// and contact cooldown to prevent sticking.
  ///
  /// Radii are defined as fraction of field WIDTH. The field is typically
  /// taller than wide (aspect < 1), so vertical distances in normalised
  /// coords represent MORE pixels than horizontal. To compare correctly,
  /// scale dy by h/w = 1/aspect.
  ({double px, double py, double vx, double vy, bool inContact}) _malletCollision(
    double px, double py, double vx, double vy,
    double mx, double my, double prevMx, double prevMy,
    double dt, double aspect, bool isPlayerMallet, bool wasInContact,
  ) {
    final hOverW = 1.0 / aspect.clamp(0.3, 3.0); // h/w — converts normalised Y to width-proportional space
    final dx = px - mx;
    final dys = (py - my) * hOverW; // dy in width-proportional ("square") space
    final minDist = _puckR + _malletR;
    final dist = math.sqrt(dx * dx + dys * dys);

    // Not touching — clear contact flag
    if (dist >= minDist * 1.05) {
      return (px: px, py: py, vx: vx, vy: vy, inContact: false);
    }

    // Degenerate overlap — push puck away vertically
    if (dist < 0.001) {
      final pushDir = py >= my ? 1.0 : -1.0;
      return (
        px: mx,
        py: (my + pushDir * (minDist + 0.005) / hOverW).clamp(_puckR, 1 - _puckR),
        vx: vx,
        vy: pushDir * _initSpeed,
        inContact: true,
      );
    }

    // Collision normal in square space
    final nx = dx / dist;
    final nys = dys / dist;

    // Push puck just outside mallet (convert Y back to normalised)
    final sep = minDist + 0.005;
    final newPx = (mx + nx * sep).clamp(_puckR, 1 - _puckR);
    final newPy = (my + (nys * sep) / hOverW).clamp(_puckR, 1 - _puckR);

    // Already in contact from previous frame — prevent dragging.
    // If the mallet is chasing the puck (moving in the same direction),
    // push the puck away so it can't be carried along.
    if (wasInContact) {
      final mvx = dt > 0 ? (mx - prevMx) / dt : 0.0;
      final mvy = dt > 0 ? (my - prevMy) / dt : 0.0;
      // Check if mallet is moving toward puck (dot product of mallet velocity and collision normal)
      final nyNorm = nys / hOverW;
      final nLen = math.sqrt(nx * nx + nyNorm * nyNorm);
      final chaseDir = (mvx * (nx / nLen) + mvy * (nyNorm / nLen));
      if (chaseDir > 0.05) {
        // Mallet is chasing — push puck away along the normal at mallet speed
        final pushSpeed = chaseDir * 1.2;
        return (px: newPx, py: newPy,
                vx: (nx / nLen) * pushSpeed, vy: (nyNorm / nLen) * pushSpeed,
                inContact: true);
      }
      return (px: newPx, py: newPy, vx: vx, vy: vy, inContact: true);
    }

    // ── New collision — blend paddle direction with bounce normal ──
    final mvx = dt > 0 ? (mx - prevMx) / dt : 0.0;
    final mvy = dt > 0 ? (my - prevMy) / dt : 0.0;
    final malletSpeed = math.sqrt(mvx * mvx + mvy * mvy);

    // Collision normal in normalised space
    final nyNorm = nys / hOverW;
    final nLen = math.sqrt(nx * nx + nyNorm * nyNorm);
    final fnx = nx / nLen;
    final fny = nyNorm / nLen;

    double newVx, newVy;

    if (malletSpeed > 0.05) {
      // Moving mallet — blend paddle direction (60%) with collision normal (40%)
      // so the puck goes roughly where you push it
      final mdx = mvx / malletSpeed;
      final mdy = mvy / malletSpeed;
      var bx = mdx * 0.6 + fnx * 0.4;
      var by = mdy * 0.6 + fny * 0.4;
      final bLen = math.sqrt(bx * bx + by * by);
      bx /= bLen;
      by /= bLen;

      // Speed: elastic impulse magnitude + mallet contribution
      final relDotN = (vx - mvx) * fnx + (vy - mvy) * fny;
      const e = 0.85;
      const massRatio = 5.0 / 6.0;
      final impulseMag = (-(1 + e) * massRatio * relDotN).abs();
      final hitSpeed = (impulseMag + malletSpeed * 0.3).clamp(0.0, _maxSpeed);

      newVx = bx * hitSpeed;
      newVy = by * hitSpeed;
    } else {
      // Stationary mallet — pure reflection off collision normal
      final dot = vx * fnx + vy * fny;
      newVx = vx - 2 * dot * fnx;
      newVy = vy - 2 * dot * fny;
    }

    SoundPlayer.i.paddelduelPaddle();
    if (isPlayerMallet) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastHapticMs > 80) {
        _lastHapticMs = now;
        HapticFeedback.mediumImpact();
      }
    }

    return (px: newPx, py: newPy, vx: newVx, vy: newVy, inContact: true);
  }

  // ── Goal handling ──────────────────────────────────────────────────────────
  void _onGoal(int scorer) {
    HapticFeedback.heavyImpact();
    SoundPlayer.i.paddelduelScore();
    setState(() {
      if (scorer == 1) _score1++; else _score2++;
      _paused = true;
      _px = 0.5; _py = 0.5; _pvx = 0; _pvy = 0;
    });

    _net.send('LOF_GOAL', {'scorer': scorer, 's1': _score1, 's2': _score2});

    final s1Won = _score1 >= _winScore;
    final s2Won = _score2 >= _winScore;
    if (s1Won || s2Won) {
      setState(() { _winner = s1Won ? 1 : 2; });
      _net.send('LOF_STATE', _stateMap());
      return;
    }

    // Resume after pause — loser gets the puck
    Future.delayed(_goalPause, () {
      if (mounted && _winner == 0) {
        setState(() => _launchPuck(towardBottom: scorer == 2));
        _net.send('LOF_STATE', _stateMap());
      }
    });
  }

  Map<String, dynamic> _stateMap() => {
    'px': _px, 'py': _py, 'pvx': _pvx, 'pvy': _pvy,
    'm1x': _m1x, 'm1y': _m1y, 'm2x': _m2x, 'm2y': _m2y,
    's1': _score1, 's2': _score2, 'w': _winner, 'p': _paused,
  };

  // ── Touch handling ─────────────────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent event, Size fieldSize) {
    final ny = event.localPosition.dy / fieldSize.height;
    final nx = event.localPosition.dx / fieldSize.width;

    if (_net.isSolo) {
      // Solo: player controls bottom mallet only (AI controls top)
      if (ny > 0.5) {
        _pointerToMallet[event.pointer] = 1;
        setState(() { _m1x = nx.clamp(0.05, 0.95); _m1y = ny.clamp(0.55, 0.95); });
      }
    } else if (_net.isHost) {
      // Host in network play: only controls bottom mallet (mallet 1)
      if (ny > 0.5) {
        _pointerToMallet[event.pointer] = 1;
        setState(() { _m1x = nx.clamp(0.05, 0.95); _m1y = ny.clamp(0.55, 0.95); });
      }
    } else {
      // Joiner: controls bottom half of their screen → sends as mallet 2 (top on host)
      if (ny > 0.5) {
        _pointerToMallet[event.pointer] = 2;
        final clampedX = nx.clamp(0.05, 0.95);
        // Joiner's bottom maps to host's top: mirror Y
        final clampedY = (1.0 - ny).clamp(0.05, 0.45);
        setState(() { _m2x = clampedX; _m2y = clampedY; });
        _net.send('LOF_MALLET', {'x': _m2x, 'y': _m2y});
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event, Size fieldSize) {
    final mallet = _pointerToMallet[event.pointer];
    if (mallet == null) return;

    final ny = event.localPosition.dy / fieldSize.height;
    final nx = event.localPosition.dx / fieldSize.width;

    setState(() {
      if (mallet == 1) {
        _m1x = nx.clamp(0.05, 0.95);
        _m1y = ny.clamp(0.55, 0.95);
      } else {
        _m2x = nx.clamp(0.05, 0.95);
        // Joiner's bottom maps to host's top: mirror Y
        _m2y = (1.0 - ny).clamp(0.05, 0.45);
        _net.send('LOF_MALLET', {'x': _m2x, 'y': _m2y});
      }
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerToMallet.remove(event.pointer);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerToMallet.remove(event.pointer);
  }

  // ── Network messages ───────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'LOF_STATE':
        if (!_net.isHost) {
          setState(() {
            _px  = (msg['px']  as num).toDouble();
            _py  = (msg['py']  as num).toDouble();
            _pvx = (msg['pvx'] as num).toDouble();
            _pvy = (msg['pvy'] as num).toDouble();
            _m1x = (msg['m1x'] as num).toDouble();
            _m1y = (msg['m1y'] as num).toDouble();
            // m2 is the joiner's own mallet: it stays locally controlled.
            // Applying the host's (older) copy would snap it back behind
            // the finger. The host uses our LOF_MALLET reports for physics.
            _score1 = msg['s1'] as int;
            _score2 = msg['s2'] as int;
            _winner = msg['w'] as int;
            _paused = msg['p'] as bool;
          });
        }

      case 'LOF_MALLET':
        if (_net.isHost) {
          setState(() {
            final x = (msg['x'] as num).toDouble();
            final y = (msg['y'] as num).toDouble();
            // fromIdx 1 = joiner = mallet 2 (top)
            if (fromIdx == 1) {
              _m2x = x; _m2y = y;
            } else if (fromIdx == 0) {
              _m1x = x; _m1y = y;
            }
          });
        }

      case 'LOF_GOAL':
        if (!_net.isHost) {
          HapticFeedback.heavyImpact();
          SoundPlayer.i.paddelduelScore();
          setState(() {
            _score1 = msg['s1'] as int;
            _score2 = msg['s2'] as int;
            _paused = true;
            _px = 0.5; _py = 0.5; _pvx = 0; _pvy = 0;
          });
        }

      case 'LOF_SYNC_REQ':
        if (_net.isHost) _net.send('LOF_STATE', _stateMap());

      case 'GAME_RESET':
        if (!_net.isHost) {
          resetConfetti();
          resetStats();
          setState(_resetLocal);
        }
    }
  }

  void _resetLocal() {
    _score1 = 0; _score2 = 0; _winner = 0;
    _m1x = 0.5; _m1y = 0.80;
    _m2x = 0.5; _m2y = 0.20;
    _prevM1x = 0.5; _prevM1y = 0.80;
    _prevM2x = 0.5; _prevM2y = 0.20;
    _px = 0.5; _py = 0.5; _pvx = 0; _pvy = 0;
    _m1InContact = false; _m2InContact = false;
    _paused = true;
    _lastTick = Duration.zero;
  }

  void _reset() {
    final lastWinner = _winner;
    resetConfetti();
    resetStats();
    setState(_resetLocal);
    if (_net.isHost) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _launchPuck(towardBottom: lastWinner != 1));
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
          if (_net.isHost) _net.send('LOF_STATE', _stateMap());
          else _net.send('LOF_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  bool get _isJoiner => !_net.isHost && !_net.isSolo;

  @override
  Widget build(BuildContext context) {
    final p1 = widget.players[0];
    final p2 = widget.players.length > 1 ? widget.players[1] : p1;

    // For joiner: flip the display so their mallet is at the bottom
    final myName  = _isJoiner ? p2.name  : p1.name;
    final myScore = _isJoiner ? _score2  : _score1;
    final myColor = _isJoiner ? p2.color : p1.color;
    final opName  = _isJoiner ? p1.name  : p2.name;
    final opScore = _isJoiner ? _score1  : _score2;
    final opColor = _isJoiner ? p1.color : p2.color;

    return GameScaffold(
      key: scaffoldKey,
      title: L.lofthockey.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.lofthockey.rules,
      child: Column(children: [
        // Score display at top
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            // Opponent (top of field) score - on the left
            _ScoreChip(name: opName, score: opScore, color: opColor),
            const Spacer(),
            Text(L.lofthockey.firstTo7,
              style: const TextStyle(color: kMuted, fontSize: 12)),
            const Spacer(),
            // Me (bottom of field) score - on the right
            _ScoreChip(name: myName, score: myScore, color: myColor),
          ]),
        ),
        const GameStatusBar(),

        // Playing field — fixed 3:5 aspect ratio so both devices see the same field
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Center(child: AspectRatio(
            aspectRatio: 3 / 5, // width : height — tall field like a real air hockey table
            child: LayoutBuilder(builder: (_, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final fieldSize = Size(w, h);
              _aspect = w / h; // always ~0.6

              // For joiner: flip Y and swap mallets so their mallet appears at bottom
              final dpx  = _isJoiner ? _px       : _px;
              final dpy  = _isJoiner ? 1.0 - _py : _py;
              final dm1x = _isJoiner ? _m2x              : _m1x;
              final dm1y = _isJoiner ? 1.0 - _m2y        : _m1y;
              final dm2x = _isJoiner ? _m1x              : _m2x;
              final dm2y = _isJoiner ? 1.0 - _m1y        : _m2y;
              final dc1  = _isJoiner ? p2.color          : p1.color;
              final dc2  = _isJoiner ? p1.color          : p2.color;

              return Listener(
                onPointerDown: (e) => _onPointerDown(e, fieldSize),
                onPointerMove: (e) => _onPointerMove(e, fieldSize),
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: CustomPaint(
                  size: fieldSize,
                  painter: _LofthockeyPainter(
                    px: dpx, py: dpy,
                    m1x: dm1x, m1y: dm1y,
                    m2x: dm2x, m2y: dm2y,
                    p1Color: dc1, p2Color: dc2,
                    paused: _paused,
                    goalWidth: _goalWidth,
                  ),
                ),
              );
            }),
          )),
        )),

        if (_winner != 0) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winner - 1,
            onFirstRender: () {
              fireConfettiOnce(_winner - 1);
              recordResult('lofthockey', _winner - 1);
              if (_net.isHost) SessionState().advanceGame();
            },
            scores: [
              (label: widget.players[0].name, value: '$_score1'),
              if (widget.players.length > 1)
                (label: widget.players[1].name, value: '$_score2'),
            ],
          ),
          GameOverActions(players: widget.players, onReset: _reset),
        ] else
          const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Score chip widget ────────────────────────────────────────────────────────
class _ScoreChip extends StatelessWidget {
  final String name;
  final int score;
  final Color color;
  const _ScoreChip({required this.name, required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(name, style: const TextStyle(color: kText, fontSize: 12)),
        const SizedBox(width: 8),
        Text('$score', style: TextStyle(
          color: color, fontSize: 20, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

// ── Painter ──────────────────────────────────────────────────────────────────
class _LofthockeyPainter extends CustomPainter {
  final double px, py, m1x, m1y, m2x, m2y;
  final Color p1Color, p2Color;
  final bool paused;
  final double goalWidth;

  const _LofthockeyPainter({
    required this.px, required this.py,
    required this.m1x, required this.m1y,
    required this.m2x, required this.m2y,
    required this.p1Color, required this.p2Color,
    required this.paused, required this.goalWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Field background
    final bgPaint = Paint()..color = const Color(0xFF0A1628);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h), const Radius.circular(12));
    canvas.drawRRect(rrect, bgPaint);

    // Clip to rounded rect
    canvas.save();
    canvas.clipRRect(rrect);

    // Field surface gradient
    final surfGrad = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF0E1F3D),
        const Color(0xFF0A1628),
        const Color(0xFF0E1F3D),
      ],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = surfGrad.createShader(Rect.fromLTWH(0, 0, w, h)));

    // Center line
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), centerPaint);

    // Center circle
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.10,
      Paint()..color = Colors.white.withValues(alpha: 0.08)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // Center dot
    canvas.drawCircle(Offset(w / 2, h / 2), 3,
      Paint()..color = Colors.white.withValues(alpha: 0.15));

    // Goal zones
    final goalLeft  = w * (1 - goalWidth) / 2;
    final goalRight = w - goalLeft;

    // Top goal
    final topGoalRect = Rect.fromLTRB(goalLeft, 0, goalRight, 6);
    canvas.drawRect(topGoalRect, Paint()..color = p2Color.withValues(alpha: 0.3));
    canvas.drawRect(topGoalRect,
      Paint()..color = p2Color.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 2);

    // Bottom goal
    final botGoalRect = Rect.fromLTRB(goalLeft, h - 6, goalRight, h);
    canvas.drawRect(botGoalRect, Paint()..color = p1Color.withValues(alpha: 0.3));
    canvas.drawRect(botGoalRect,
      Paint()..color = p1Color.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 2);

    // Goal zone markings (semi-circles)
    final goalArcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Top goal arc
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w / 2, 0), width: w * goalWidth * 0.7, height: w * 0.15),
      0, math.pi, false, goalArcPaint);

    // Bottom goal arc
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w / 2, h), width: w * goalWidth * 0.7, height: w * 0.15),
      math.pi, math.pi, false, goalArcPaint);

    // Mallets
    _drawMallet(canvas, w, h, m1x * w, m1y * h, p1Color);
    _drawMallet(canvas, w, h, m2x * w, m2y * h, p2Color);

    // Puck
    if (!paused) {
      _drawPuck(canvas, w, h, px * w, py * h);
    } else {
      // Draw puck faded at center
      _drawPuck(canvas, w, h, 0.5 * w, 0.5 * h, faded: true);
    }

    canvas.restore();

    // Field border
    canvas.drawRRect(rrect,
      Paint()..color = kBorder..strokeWidth = 2..style = PaintingStyle.stroke);
  }

  void _drawMallet(Canvas canvas, double w, double h, double cx, double cy, Color color) {
    final r = _malletR * w;

    // Outer glow
    canvas.drawCircle(Offset(cx, cy), r * 1.6,
      Paint()..color = color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));

    // Main circle gradient
    final grad = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      colors: [
        Color.lerp(color, Colors.white, 0.4)!,
        color,
        Color.lerp(color, Colors.black, 0.3)!,
      ],
    );
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()..shader = grad.createShader(
        Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // Inner circle (handle)
    canvas.drawCircle(Offset(cx, cy), r * 0.4,
      Paint()..color = Color.lerp(color, Colors.white, 0.2)!);

    // Rim
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  void _drawPuck(Canvas canvas, double w, double h, double cx, double cy, {bool faded = false}) {
    final r = _puckR * w;
    final opacity = faded ? 0.3 : 1.0;

    // Shadow / glow
    canvas.drawCircle(Offset(cx, cy), r * 2,
      Paint()..color = Colors.white.withValues(alpha: 0.08 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

    // Puck body
    final puckGrad = RadialGradient(
      center: const Alignment(-0.3, -0.4),
      colors: [
        Colors.white.withValues(alpha: opacity),
        Color.fromRGBO(200, 200, 210, opacity),
      ],
    );
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()..shader = puckGrad.createShader(
        Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // Puck rim
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()..color = Colors.white.withValues(alpha: 0.3 * opacity)
        ..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_LofthockeyPainter old) =>
    old.px != px || old.py != py ||
    old.m1x != m1x || old.m1y != m1y ||
    old.m2x != m2x || old.m2y != m2y ||
    old.paused != paused;
}
