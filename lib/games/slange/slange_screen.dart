import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/wake_lock.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import '../../core/solo_ai.dart';
import '../../l10n/app_localizations.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const _kCols = 22;
const _kRows = 30;

// Tick interval in ms — lower = faster
const _kTickMs  = 140; // base (medium)
const _kTickFast = 100;
const _kTickSlow = 180;

typedef _Pos = ({int r, int c});

enum _Dir { up, down, left, right }

_Dir _opposite(_Dir d) => switch (d) {
  _Dir.up    => _Dir.down,
  _Dir.down  => _Dir.up,
  _Dir.left  => _Dir.right,
  _Dir.right => _Dir.left,
};

_Pos _step(_Pos p, _Dir d) => switch (d) {
  _Dir.up    => (r: (p.r - 1 + _kRows) % _kRows, c: p.c),
  _Dir.down  => (r: (p.r + 1) % _kRows,           c: p.c),
  _Dir.left  => (r: p.r, c: (p.c - 1 + _kCols) % _kCols),
  _Dir.right => (r: p.r, c: (p.c + 1) % _kCols),
};


// ── Slange AI ─────────────────────────────────────────────────────────────────
class _SlangeAI extends SoloAI {
  _SlangeAI(super.difficulty);

  _Dir computeDir(
      List<_Pos> myBody, List<_Pos> other, _Pos food, _Dir current) {
    final head = myBody.first;
    final dirs = [_Dir.up, _Dir.down, _Dir.left, _Dir.right]
        .where((d) => d != _opposite(current))
        .toList();

    // Safe dirs = no body, no other snake (walls wrap so never unsafe)
    final occupied = {...myBody.map((p) => '${p.r},${p.c}'),
                      ...other.map((p) => '${p.r},${p.c}')};

    List<_Dir> safe = dirs.where((d) {
      final np = _step(head, d);
      return !occupied.contains('${np.r},${np.c}');
    }).toList();

    if (safe.isEmpty) return current; // no choice — let it die

    // Prefer direction toward food
    safe.sort((a, b) {
      final na = _step(head, a);
      final nb = _step(head, b);
      final da = (na.r - food.r).abs() + (na.c - food.c).abs();
      final db = (nb.r - food.r).abs() + (nb.c - food.c).abs();
      return da.compareTo(db);
    });

    // Hard: always best direction; medium: 80% best; easy: 60% best
    final rngVal = rng.nextDouble();
    final threshold = switch (difficulty) {
      SoloDifficulty.hard   => 0.0,
      SoloDifficulty.medium => 0.20,
      SoloDifficulty.easy   => 0.40,
    };
    if (rngVal < threshold && safe.length > 1) {
      return safe[rng.nextInt(safe.length - 1) + 1]; // random non-best
    }
    return safe.first;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────
class SlangeScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const SlangeScreen(
      {super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<SlangeScreen> createState() => _SlangeState();
}

class _SlangeState extends State<SlangeScreen>
    with GameMixin, SingleTickerProviderStateMixin {
  final _net  = Network();

  // My snake (always the one I control)
  List<_Pos> _mySnake  = [];
  _Dir       _myDir    = _Dir.right;
  bool       _myAlive  = true;

  // Opponent snake (host=snake1, joiner=snake2 in multiplayer)
  List<_Pos> _opSnake  = [];
  _Dir       _opDir    = _Dir.left;
  bool       _opAlive  = true;

  // Food positions (host-authoritative)
  List<_Pos> _food = [];

  // Scores
  int _myScore = 0;
  int _opScore = 0;

  // Game state
  bool _started = false;
  bool _over    = false;
  int  _winner  = 0; // 0=playing, 1=p1, 2=p2, -1=draw

  // Ticker (host-side physics)
  Ticker? _ticker;
  int     _lastTickMs = 0;

  // Solo
  bool       _isSolo  = false;
  _SlangeAI?  _ai;

  // Personal best (solo only)
  int  _personalBest = 0;
  bool _newBest      = false;

  // Pending queued direction (only 1 buffered)
  _Dir? _bufferedDir;
  // Host: joiner's pending direction (only 1 buffered, applied on next tick)
  _Dir? _opBufferedDir;

  bool get _isHost => _net.isHost;

  @override List<Player> get gamePlayers => widget.players;

  @override
  void initState() {
    super.initState();
    _isSolo = _net.isSolo;
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = _SlangeAI(d);
      _loadBest();
    }
    if (_isHost) {
      _initPositions();
      _ticker = createTicker(_hostTick)..start();
    }
  }

  @override
  void dispose() {
    msgSub?.cancel();
    _ticker?.dispose();
    WakeLock.release();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _personalBest = p.getInt('slange_best') ?? 0);
  }

  Future<void> _saveBest(int score) async {
    if (score > _personalBest) {
      final p = await SharedPreferences.getInstance();
      await p.setInt('slange_best', score);
      if (mounted) setState(() { _personalBest = score; _newBest = true; });
      SoundPlayer.i.newBest();
    }
  }

  // ── Initialization ────────────────────────────────────────────────────────────
  void _initPositions() {
    _mySnake = [
      (r: _kRows ~/ 2, c: 4),
      (r: _kRows ~/ 2, c: 3),
      (r: _kRows ~/ 2, c: 2),
    ];
    _myDir = _Dir.right;
    _myAlive = true;

    // Always init opSnake — used by AI in solo mode too
    _opSnake = [
      (r: _kRows ~/ 2, c: _kCols - 5),
      (r: _kRows ~/ 2, c: _kCols - 4),
      (r: _kRows ~/ 2, c: _kCols - 3),
    ];
    _opDir = _Dir.left;
    _opAlive = true; // alive in both solo (AI) and multiplayer

    // Drop any direction tapped after game over / before reset
    _bufferedDir   = null;
    _opBufferedDir = null;

    _food = [];
    _spawnFood();

    _myScore = 0;
    _opScore = 0;
    _started = false;
    _over    = false;
    _winner  = 0;
  }

  void _spawnFood() {
    if (_food.length >= 2) return; // max 2 food items
    final rng = math.Random();
    final occupied = {
      ..._mySnake.map((p) => '${p.r},${p.c}'),
      ..._opSnake.map((p) => '${p.r},${p.c}'),
      ..._food.map((p) => '${p.r},${p.c}'),
    };
    _Pos pos;
    int tries = 0;
    do {
      pos = (r: rng.nextInt(_kRows), c: rng.nextInt(_kCols));
      tries++;
    } while (occupied.contains('${pos.r},${pos.c}') && tries < 200);
    _food.add(pos);
  }

  // ── Host tick (physics) ───────────────────────────────────────────────────────
  void _hostTick(Duration elapsed) {
    if (!mounted || _over) return;
    final nowMs = elapsed.inMilliseconds;
    if (!_started) return;

    final tickMs = switch (widget.extra?['difficulty'] as int? ?? 1) {
      0 => _kTickSlow,
      2 => _kTickFast,
      _ => _kTickMs,
    };

    if (nowMs - _lastTickMs < tickMs) return;
    _lastTickMs = nowMs;

    // Apply buffered direction
    if (_bufferedDir != null) {
      _myDir = _bufferedDir!;
      _bufferedDir = null;
    }
    // Apply joiner's buffered direction (validated against _opDir on receipt)
    if (_opBufferedDir != null) {
      _opDir = _opBufferedDir!;
      _opBufferedDir = null;
    }

    // AI direction (computed before move)
    if (_isSolo && _ai != null && _opAlive) {
      _opDir = _ai!.computeDir(
        _opSnake, _mySnake,
        _food.isNotEmpty ? _food.first : (r: _kRows ~/ 2, c: _kCols ~/ 2),
        _opDir);
    }

    // Move snakes simultaneously (joiner snake or AI snake = op)
    _advanceSnakes();

    // Broadcast
    if (!_isSolo) _broadcastState();

    // Check game over
    _checkGameOver();
    setState(() {});
  }

  /// Advances both snakes at once: new heads are computed first, then all
  /// collisions are resolved simultaneously so neither snake has priority.
  /// A tail cell counts as free when that snake moves and does not eat
  /// (same rule for own tail and the other snake's tail). Head-on → both die.
  void _advanceSnakes() {
    bool same(_Pos a, _Pos b) => a.r == b.r && a.c == b.c;
    bool hits(_Pos h, List<_Pos> cells) => cells.any((p) => same(p, h));
    bool isFood(_Pos h) => _food.any((f) => same(f, h));

    final myMoving = _myAlive && _mySnake.isNotEmpty;
    final opMoving = _opAlive && _opSnake.isNotEmpty;
    final myHead = myMoving ? _step(_mySnake.first, _myDir) : null;
    final opHead = opMoving ? _step(_opSnake.first, _opDir) : null;
    final myAte = myHead != null && isFood(myHead);
    final opAte = opHead != null && isFood(opHead);

    // Body cells (excluding the new head) a snake occupies after this tick
    List<_Pos> bodyAfter(List<_Pos> snake, bool moves, bool ate) =>
        moves && !ate ? snake.sublist(0, snake.length - 1) : snake;

    bool myDies = false, opDies = false;
    // Deaths only ever get added, so this settles within a few passes
    // (a snake that dies stays put, so its tail no longer frees up).
    while (true) {
      final myMoves = myMoving && !myDies;
      final opMoves = opMoving && !opDies;
      final myBody = bodyAfter(_mySnake, myMoves, myAte);
      final opBody = bodyAfter(_opSnake, opMoves, opAte);
      final newMyDeath = myMoves &&
          (hits(myHead!, myBody) || hits(myHead, opBody) ||
           (opMoves && same(myHead, opHead!)));
      final newOpDeath = opMoves &&
          (hits(opHead!, opBody) || hits(opHead, myBody) ||
           (myMoves && same(opHead, myHead!)));
      if (!newMyDeath && !newOpDeath) break;
      if (newMyDeath) myDies = true;
      if (newOpDeath) opDies = true;
    }

    if (myDies || opDies) {
      if (myDies) _myAlive = false;
      if (opDies) _opAlive = false;
      SoundPlayer.i.rupsenBust();
      HapticFeedback.heavyImpact();
    }

    // Move survivors
    if (myMoving && !myDies) {
      final newSnake = [myHead!, ..._mySnake];
      if (!myAte) newSnake.removeLast();
      _mySnake = newSnake;
    }
    if (opMoving && !opDies) {
      final newSnake = [opHead!, ..._opSnake];
      if (!opAte) newSnake.removeLast();
      _opSnake = newSnake;
    }

    // Food (after both moved, so respawn avoids the new positions)
    int eaten = 0;
    if (myMoving && !myDies && myAte) {
      _food.removeWhere((f) => same(f, myHead));
      _myScore++;
      eaten++;
    }
    if (opMoving && !opDies && opAte) {
      _food.removeWhere((f) => same(f, opHead));
      _opScore++;
      eaten++;
    }
    if (eaten > 0) {
      SoundPlayer.i.rupsenClaim();
      HapticFeedback.lightImpact();
      for (int i = 0; i < eaten; i++) {
        _spawnFood();
      }
    }
  }

  void _checkGameOver() {
    final myDead = !_myAlive;
    final opDead = !_opAlive;

    if (_isSolo) {
      if (myDead) {
        _over   = true;
        _winner = 2; // player lost — AI wins
        _saveBest(_myScore);
      } else if (opDead) {
        // AI died — player wins
        _over   = true;
        _winner = 1;
        _saveBest(_myScore);
      }
    } else {
      if (myDead && opDead) {
        _over   = true;
        _winner = _myScore > _opScore ? (_isHost ? 1 : 2)
                : _myScore < _opScore ? (_isHost ? 2 : 1) : -1;
        _broadcastState();
        _net.send('SLA_OVER', {'w': _winner});
      } else if (myDead) {
        _over   = true;
        _winner = _isHost ? 2 : 1;
        _broadcastState();
        _net.send('SLA_OVER', {'w': _winner});
      } else if (opDead) {
        _over   = true;
        _winner = _isHost ? 1 : 2;
        _broadcastState();
        _net.send('SLA_OVER', {'w': _winner});
      }
    }
  }

  // ── Network ───────────────────────────────────────────────────────────────────
  void _broadcastState() {
    // Send full state (compact encoding)
    _net.send('SLA_STATE', {
      's1': _posListToJson(_isHost ? _mySnake : _opSnake),
      's2': _posListToJson(_isHost ? _opSnake : _mySnake),
      'f':  _posListToJson(_food),
      'sc1': _isHost ? _myScore : _opScore,
      'sc2': _isHost ? _opScore : _myScore,
      'a1': _isHost ? _myAlive : _opAlive,
      'a2': _isHost ? _opAlive : _myAlive,
    });
  }

  List<List<int>> _posListToJson(List<_Pos> list) =>
      list.map((p) => [p.r, p.c]).toList();

  List<_Pos> _jsonToPosList(List<dynamic> list) =>
      list.map((e) => (r: e[0] as int, c: e[1] as int)).toList();

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {

      case 'SLA_START':
        if (!_isHost) {
          final s1 = _jsonToPosList(msg['s1'] as List);
          final s2 = _jsonToPosList(msg['s2'] as List);
          final f  = _jsonToPosList(msg['f'] as List);
          setState(() {
            _mySnake = s2;  // joiner = snake2
            _opSnake = s1;
            _food    = f;
            _started = true;
          });
        }
        break;

      case 'SLA_STATE':
        if (!_isHost) {
          setState(() {
            _opSnake = _jsonToPosList(msg['s1'] as List);
            _mySnake = _jsonToPosList(msg['s2'] as List);
            _food    = _jsonToPosList(msg['f'] as List);
            _opScore = msg['sc1'] as int;
            _myScore = msg['sc2'] as int;
            _opAlive = msg['a1'] as bool;
            _myAlive = msg['a2'] as bool;
          });
        }
        break;

      case 'SLA_DIR':
        // Host receives joiner's direction. Validate against the direction the
        // joiner's snake actually moved last tick (_opDir only changes on a
        // tick) and buffer a single pending turn — same as the host's own input.
        if (_isHost && !_isSolo && !_over) {
          final d = _Dir.values[msg['d'] as int];
          if (d != _opposite(_opDir)) _opBufferedDir = d;
        }
        break;

      case 'SLA_OVER':
        if (!_isHost) {
          setState(() {
            _over   = true;
            _winner = msg['w'] as int;
          });
        }
        break;

      case 'SLA_READY':
        // Joiner tapped to start (ignored after game over, before reset)
        if (_isHost && !_over) {
          setState(() => _started = true);
          _net.send('SLA_START', {
            's1': _posListToJson(_mySnake),
            's2': _posListToJson(_opSnake),
            'f':  _posListToJson(_food),
          });
        }
        break;

      case 'SLA_SYNC_REQ':
        if (_isHost) {
          _net.send('SLA_STATE', {
            's1': _posListToJson(_mySnake),
            's2': _posListToJson(_opSnake),
            'f':  _posListToJson(_food),
            'sc1': _myScore, 'sc2': _opScore,
            'a1': _myAlive, 'a2': _opAlive,
          });
        }
        break;

      case 'GAME_RESET':
        if (!_isHost) {
          resetConfetti();
          resetStats();
          setState(() {
            _mySnake = [];
            _opSnake = [];
            _food = [];
            _myScore = 0;
            _opScore = 0;
            _myAlive = true;
            _opAlive = true;
            _myDir = _Dir.right;
            _opDir = _Dir.left;
            _bufferedDir = null;
            _started = false;
            _over = false;
            _winner = 0;
            _newBest = false;
            _lastTickMs = 0;
          });
          // No auto SLA_READY: like the first game, the round starts when a
          // player taps a direction ("tap to start").
        }
        break;

    }
  }

  // ── D-pad input ───────────────────────────────────────────────────────────────
  Widget _buildDpad() {
    return Opacity(
      opacity: 0.75,
      child: SizedBox(
        width: 132, height: 132,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _dpadBtn(Icons.arrow_drop_up_rounded, _Dir.up),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _dpadBtn(Icons.arrow_left_rounded,    _Dir.left),
            const SizedBox(width: 44, height: 44), // centre gap
            _dpadBtn(Icons.arrow_right_rounded,   _Dir.right),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _dpadBtn(Icons.arrow_drop_down_rounded, _Dir.down),
          ]),
        ]),
      ),
    );
  }

  Widget _dpadBtn(IconData icon, _Dir dir) {
    return GestureDetector(
      onTap: () => _handleDirInput(dir),
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }

  void _handleDirInput(_Dir dir) {
    if (_over) return; // ignore taps after game over (would leak into next game)
    if (_isHost) {
      // Validate against the direction actually moved last tick
      if (dir == _opposite(_myDir)) return; // can't reverse
      _bufferedDir = dir;
    } else {
      // Joiner: send to host, which validates against the snake's real
      // last-moved direction (local _myDir is not authoritative)
      _myDir = dir;
      _net.send('SLA_DIR', {'d': dir.index});
    }
    if (!_started) {
      // First swipe starts the game
      _started = true;
      if (_isHost) {
        _net.send('SLA_START', {
          's1': _posListToJson(_mySnake),
          's2': _posListToJson(_opSnake),
          'f':  _posListToJson(_food),
        });
      } else {
        _net.send('SLA_READY');
      }
    }
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_isHost) {
            _net.send('SLA_STATE', {
              's1': _posListToJson(_mySnake),
              's2': _posListToJson(_opSnake),
              'f':  _posListToJson(_food),
              'sc1': _myScore, 'sc2': _opScore,
              'a1': _myAlive, 'a2': _opAlive,
            });
          } else {
            _net.send('SLA_SYNC_REQ');
          }
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  void _reset() {
    resetConfetti();
    resetStats();
    setState(() {
      _initPositions();
      _newBest = false;
      _lastTickMs = 0;
    });
    // Show the fresh positions on the joiner; play starts on the next tap
    if (_isHost && !_isSolo) _broadcastState();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = L.slange;

    return GameScaffold(
      key: scaffoldKey,
      title: s.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: (t) => sendChat(t),
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: s.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: -1,
          scores: _isSolo
              ? [_myScore]
              : (_isHost ? [_myScore, _opScore] : [_opScore, _myScore]),
          scoreLabel: null,
        ),
        GameStatusBar(text: _over ? null : (!_started ? s.tapToStart : null)),

        Expanded(child: Stack(children: [
          // Game canvas
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AspectRatio(
              aspectRatio: _kCols / _kRows,
              child: LayoutBuilder(builder: (_, c) {
                return CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _SlangePainter(
                    mySnake:  _mySnake,
                    opSnake:  _opSnake,
                    food:     _food,
                    myColor:  _isHost
                        ? widget.players[0].color
                        : widget.players[1 % widget.players.length].color,
                    opColor:  _isSolo
                        ? Colors.grey
                        : (_isHost
                            ? widget.players[1 % widget.players.length].color
                            : widget.players[0].color),
                    showOp:   !_isSolo || _opSnake.isNotEmpty,
                    myAlive:  _myAlive,
                    opAlive:  _opAlive,
                    started:  _started,
                  ),
                );
              }),
            ),
          )),
          // D-pad overlay (bottom-right corner)
          Positioned(
            right: 12, bottom: 12,
            child: _buildDpad(),
          ),
        ])),

        // Personal best (solo)
        if (_isSolo && _personalBest > 0 && !_over)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(s.personalBest.fmt({'score': _personalBest}),
              style: const TextStyle(color: kMuted, fontSize: 13)),
          ),

        // Game over
        if (_over && _winner != 0) ...[
          if (_isSolo) ...[
            Center(child: Column(children: [
              Text(s.scoreLabel.fmt({'score': _myScore}),
                style: const TextStyle(color: kText, fontSize: 20,
                  fontWeight: FontWeight.bold)),
              if (_newBest)
                Text(s.newBest,
                  style: const TextStyle(color: kPurple2, fontSize: 15,
                    fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
            ])),
          ] else
            GameResultBanner(
              players: widget.players,
              winnerIdx: _winner == -1 ? -1 : _winner - 1,
              onFirstRender: () {
                fireConfettiOnce(_winner == -1 ? -1 : _winner - 1);
                recordResult('slange', _winner == -1 ? -1 : _winner - 1);
                if (_isHost) SessionState().advanceGame();
              },
              scores: [
                (label: widget.players[0].name,
                 value: '${_isHost ? _myScore : _opScore}'),
                (label: widget.players[1 % widget.players.length].name,
                 value: '${_isHost ? _opScore : _myScore}'),
              ],
            ),
          GameOverActions(players: widget.players, onReset: _reset),
        ] else
          const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────
class _SlangePainter extends CustomPainter {
  final List<_Pos> mySnake, opSnake, food;
  final Color myColor, opColor;
  final bool showOp, myAlive, opAlive, started;

  const _SlangePainter({
    required this.mySnake, required this.opSnake,
    required this.food,
    required this.myColor, required this.opColor,
    required this.showOp, required this.myAlive,
    required this.opAlive, required this.started,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width  / _kCols;
    final ch = size.height / _kRows;

    // Background grid
    final bgPaint = Paint()..color = const Color(0xFF0B1120);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    for (int r = 0; r <= _kRows; r++) {
      canvas.drawLine(Offset(0, r * ch), Offset(size.width, r * ch), gridPaint);
    }
    for (int c = 0; c <= _kCols; c++) {
      canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, size.height), gridPaint);
    }

    // Border
    final borderPaint = Paint()
      ..color = kBorder
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);

    // Food
    for (final f in food) {
      _drawFood(canvas, f, cw, ch);
    }

    // Opponent snake
    if (showOp) {
      _drawSnake(canvas, opSnake, opColor, cw, ch, opAlive);
    }

    // My snake (drawn on top)
    _drawSnake(canvas, mySnake, myColor, cw, ch, myAlive);

    // Overlay if not started
    if (!started) {
      final overlay = Paint()..color = Colors.black.withValues(alpha: 0.45);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), overlay);
    }
  }

  void _drawSnake(Canvas canvas, List<_Pos> snake, Color color,
      double cw, double ch, bool alive) {
    if (snake.isEmpty) return;
    final alpha = alive ? 1.0 : 0.4;
    final paint = Paint()..color = color.withValues(alpha: alpha);
    final headPaint = Paint()
      ..color = Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: alpha);
    final gap = 1.5;

    for (int i = 0; i < snake.length; i++) {
      final p = snake[i];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(p.c * cw + gap, p.r * ch + gap,
            cw - gap * 2, ch - gap * 2),
        Radius.circular(cw * 0.3));
      canvas.drawRRect(rect, i == 0 ? headPaint : paint);

      // Eyes on head
      if (i == 0) {
        final eyePaint = Paint()..color = Colors.black.withValues(alpha: 0.7 * alpha);
        final eyeR = cw * 0.13;
        final ex = p.c * cw + cw * 0.35;
        final ey = p.r * ch + ch * 0.3;
        canvas.drawCircle(Offset(ex, ey), eyeR, eyePaint);
        canvas.drawCircle(Offset(ex + cw * 0.3, ey), eyeR, eyePaint);
      }
    }
  }

  void _drawFood(Canvas canvas, _Pos f, double cw, double ch) {
    final cx = f.c * cw + cw / 2;
    final cy = f.r * ch + ch / 2;
    final r  = cw * 0.35;

    // Glow
    final glowPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(cx, cy), r * 1.8, glowPaint);

    // Apple
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [Colors.red.shade300, Colors.red.shade700],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // Stem
    final stemPaint = Paint()
      ..color = Colors.green.shade600
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, cy - r),
      Offset(cx + cw * 0.15, cy - r - ch * 0.2),
      stemPaint);
  }

  @override
  bool shouldRepaint(_SlangePainter old) => true;
}
