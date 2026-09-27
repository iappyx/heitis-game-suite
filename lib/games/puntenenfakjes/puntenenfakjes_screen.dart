import 'package:flutter/material.dart';
import '../../core/network.dart';
import '../../widgets/game_mixin.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import '../../core/session.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../l10n/app_localizations.dart';
import 'puntenenfakjes_ai.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/sound_player.dart';

// Grid is N×N boxes, so (N+1)×(N+1) dots.
// Horizontal lines: hLines[row][col] — row 0..N, col 0..N-1
// Vertical   lines: vLines[row][col] — row 0..N-1, col 0..N
const _N = 5; // 5×5 boxes

class PuntenEnFakjesScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const PuntenEnFakjesScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<PuntenEnFakjesScreen> createState() => _PuntenEnFakjesState();
}

class _PuntenEnFakjesState extends State<PuntenEnFakjesScreen> with GameMixin {
  final _net = Network();
  final _session = SessionState();
  PuntenEnFakjesAI? _ai;

  // Lines: 0=unset, 1=host, 2=joiner
  late List<List<int>> _hLines; // [N+1][N]
  late List<List<int>> _vLines; // [N][N+1]
  // Boxes: 0=unclaimed, 1=host, 2=joiner
  late List<List<int>> _boxes; // [N][N]
  int _turn = 1;
  int _score1 = 0, _score2 = 0;

  int get _myId => _net.myIdx == 0 ? 1 : 2;
  bool get _isMyTurn => _turn == _myId;
  bool get _gameOver => _score1 + _score2 == _N * _N;

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _initGame(widget.firstPlayer);
    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = PuntenEnFakjesAI(d);
    }
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_net.isSolo && widget.firstPlayer == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ai?.takeTurn(
          hLines: _hLines.map((r) => r.toList()).toList(),
          vLines: _vLines.map((r) => r.toList()).toList(),
          player: 2,
        );
      });
    }
  }

  @override void dispose() { _ai?.cancel(); super.dispose(); }

  void _initGame([int first = 1]) {
    resetConfetti();
    resetStats();
    _hLines = List.generate(_N + 1, (_) => List.filled(_N, 0));
    _vLines = List.generate(_N, (_) => List.filled(_N + 1, 0));
    _boxes  = List.generate(_N, (_) => List.filled(_N, 0));
    _turn = first; _score1 = 0; _score2 = 0;
  }

  // Returns true if placing this line completes ≥1 box (player keeps turn)
  bool _claimLine(bool horiz, int row, int col, int player, {bool broadcast = true}) {
    if (horiz) {
      if (_hLines[row][col] != 0) return false;
      _hLines[row][col] = player;
    } else {
      if (_vLines[row][col] != 0) return false;
      _vLines[row][col] = player;
    }
    if (broadcast) _net.send('PUN_LINE', {'h': horiz, 'r': row, 'c': col, 'p': player});

    int claimed = 0;
    // Check boxes adjacent to this line
    for (int br = 0; br < _N; br++) {
      for (int bc = 0; bc < _N; bc++) {
        if (_boxes[br][bc] != 0) continue;
        // Top=hLines[br][bc], Bottom=hLines[br+1][bc],
        // Left=vLines[br][bc], Right=vLines[br][bc+1]
        if (_hLines[br][bc] != 0 && _hLines[br+1][bc] != 0 &&
            _vLines[br][bc] != 0 && _vLines[br][bc+1] != 0) {
          _boxes[br][bc] = player;
          claimed++;
        }
      }
    }
    if (player == 1) _score1 += claimed; else _score2 += claimed;
    if (claimed == 0) _turn = player == 1 ? 2 : 1; // switch turn
    return claimed > 0;
  }

  void _onLineTap(bool horiz, int row, int col) {
    SoundPlayer.i.puntenEnFakjesLine();
    if (!_isMyTurn || _gameOver) return;
    setState(() => _claimLine(horiz, row, col, _myId));
    // In solo mode trigger AI when it becomes AI's turn
    if (_net.isSolo && _turn == 2 && !_gameOver) {
      _ai?.takeTurn(
        hLines: _hLines.map((r) => r.toList()).toList(),
        vLines: _vLines.map((r) => r.toList()).toList(),
        player: 2,
      );
    }
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'PUN_LINE':
        final horiz = msg['h'] as bool;
        final row = msg['r'] as int;
        final col = msg['c'] as int;
        // Bounds check: hLines is [N+1][N], vLines is [N][N+1]
        if (horiz) {
          if (row < 0 || row > _N || col < 0 || col >= _N) break;
        } else {
          if (row < 0 || row >= _N || col < 0 || col > _N) break;
        }
        setState(() => _claimLine(
          horiz, row, col,
          msg['p'] as int, broadcast: false));
        if (_isMyTurn && !_gameOver) turnChanged();
        // In solo mode: if AI claimed a box it goes again
        if (_net.isSolo && _turn == 2 && !_gameOver) {
          _ai?.takeTurn(
            hLines: _hLines.map((r) => r.toList()).toList(),
            vLines: _vLines.map((r) => r.toList()).toList(),
            player: 2,
          );
        }
        break;
      case 'GAME_RESET':
        if (!_net.isHost) setState(() => _initGame(msg['first'] as int? ?? 1));
        break;
      case 'PUN_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;
      case 'PUN_SYNC':
        if (!_net.isHost) _applySync(msg);
        break;
    }
  }


  void _sendSync() {
    _net.send('PUN_SYNC', {
      'hLines': _hLines.map((r) => r.toList()).toList(),
      'vLines': _vLines.map((r) => r.toList()).toList(),
      'boxes':  _boxes.map((r)  => r.toList()).toList(),
      'turn': _turn, 's1': _score1, 's2': _score2,
    });
  }

  void _applySync(Map<String, dynamic> msg) {
    setState(() {
      final h = msg['hLines'] as List;
      final v = msg['vLines'] as List;
      final b = msg['boxes']  as List;
      _hLines = List.generate(h.length,  (r) => List<int>.from(h[r] as List));
      _vLines = List.generate(v.length,  (r) => List<int>.from(v[r] as List));
      _boxes  = List.generate(b.length,  (r) => List<int>.from(b[r] as List));
      _turn   = msg['turn'] as int;
      _score1 = msg['s1']   as int;
      _score2 = msg['s2']   as int;
    });
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _sendSync();
          else _net.send('PUN_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (r) => false)));
  }

  @override Widget build(BuildContext context) {
    final p1 = widget.players[0];
    final p2 = widget.players[1];
    int winner = 0;
    if (_gameOver) winner = _score1 > _score2 ? 1 : _score2 > _score1 ? 2 : 3;

    return GameScaffold(
        key: scaffoldKey,
      title: L.puntenenfakjes.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.puntenenfakjes.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: _gameOver ? -1 : _turn - 1,
          scores: [_score1, _score2],
          scoreLabel: L.common.boxesLabel,
        ),
        GameStatusBar(
          text: _gameOver ? null
              : (_isMyTurn ? L.puntenenfakjes.yourTurnExcl : L.puntenenfakjes.opponentTurn.fmt({'player': _turn == 1 ? p1.name : p2.name})),
          textColor: !_gameOver && _isMyTurn ? kGreen : null,
        ),

        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(16),
          child: AspectRatio(aspectRatio: 1, child: CustomPaint(
            painter: _PuntenEnFakjesHoverPainter(
              hLines: _hLines, vLines: _vLines, boxes: _boxes,
              p1Color: p1.color, p2Color: p2.color,
              myId: _myId, isMyTurn: _isMyTurn && !_gameOver,
            ),
            child: _PuntenEnFakjesTapLayer(
              hLines: _hLines, vLines: _vLines,
              onLineTap: _onLineTap,
              isMyTurn: _isMyTurn && !_gameOver,
            ),
          )),
        ))),

        if (_gameOver) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: winner == 3 ? -1 : winner - 1,
            onFirstRender: () { final wi = winner == 3 ? -1 : winner - 1; fireConfettiOnce(wi); recordResult('puntenenfakjes', wi); },
            scores: [
              (label: widget.players[0].name, value: '$_score1'),
              (label: widget.players[1].name, value: '$_score2'),
            ],
          ),
          GameOverActions(players: widget.players, sendReset: false, onReset: () {
            _ai?.cancel();
            final first = _session.nextStarterFor(2);
            _session.advanceGame();
            _net.send('GAME_RESET', {'first': first});
            setState(() => _initGame(first));
            if (_net.isSolo && first == 2) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _ai?.takeTurn(
                  hLines: _hLines.map((r) => r.toList()).toList(),
                  vLines: _vLines.map((r) => r.toList()).toList(),
                  player: 2,
                );
              });
            }
          }),
        ] else const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────────

class _PuntenEnFakjesHoverPainter extends CustomPainter {
  final List<List<int>> hLines, vLines, boxes;
  final Color p1Color, p2Color;
  final int myId;
  final bool isMyTurn;
  _PuntenEnFakjesHoverPainter({required this.hLines, required this.vLines, required this.boxes,
    required this.p1Color, required this.p2Color, required this.myId, required this.isMyTurn});

  @override void paint(Canvas canvas, Size size) {
    final step = size.width / _N;
    final dotR = step * 0.08;

    // Boxes
    for (int r = 0; r < _N; r++) {
      for (int c = 0; c < _N; c++) {
        if (boxes[r][c] == 0) continue;
        final color = boxes[r][c] == 1 ? p1Color : p2Color;
        canvas.drawRect(
          Rect.fromLTWH(c * step, r * step, step, step),
          Paint()..color = color.withValues(alpha: .25));
      }
    }

    // Lines
    for (int r = 0; r <= _N; r++) {
      for (int c = 0; c < _N; c++) {
        if (hLines[r][c] == 0) continue;
        final color = hLines[r][c] == 1 ? p1Color : p2Color;
        canvas.drawLine(
          Offset(c * step, r * step), Offset((c+1) * step, r * step),
          Paint()..color = color..strokeWidth = step * 0.12..strokeCap = StrokeCap.round);
      }
    }
    for (int r = 0; r < _N; r++) {
      for (int c = 0; c <= _N; c++) {
        if (vLines[r][c] == 0) continue;
        final color = vLines[r][c] == 1 ? p1Color : p2Color;
        canvas.drawLine(
          Offset(c * step, r * step), Offset(c * step, (r+1) * step),
          Paint()..color = color..strokeWidth = step * 0.12..strokeCap = StrokeCap.round);
      }
    }

    // Dots
    for (int r = 0; r <= _N; r++) {
      for (int c = 0; c <= _N; c++) {
        canvas.drawCircle(
          Offset(c * step, r * step), dotR,
          Paint()..color = const Color(0xFFE0C3FC));
      }
    }
  }

  @override bool shouldRepaint(_PuntenEnFakjesHoverPainter old) =>
    old.hLines != hLines || old.vLines != vLines || old.boxes != boxes || old.isMyTurn != isMyTurn;
}

// ── Tap layer (transparent, sits on top of painter) ───────────────────────────

class _PuntenEnFakjesTapLayer extends StatefulWidget {
  final List<List<int>> hLines, vLines;
  final void Function(bool horiz, int row, int col) onLineTap;
  final bool isMyTurn;
  const _PuntenEnFakjesTapLayer({required this.hLines, required this.vLines,
    required this.onLineTap, required this.isMyTurn});
  @override State<_PuntenEnFakjesTapLayer> createState() => _PuntenEnFakjesTapLayerState();
}

class _PuntenEnFakjesTapLayerState extends State<_PuntenEnFakjesTapLayer> {
  int? _hoverHRow, _hoverHCol; // highlighted potential move
  int? _hoverVRow, _hoverVCol;

  void _onPanUpdate(Offset local, Size size) {
    if (!widget.isMyTurn) return;
    final step = size.width / _N;
    final x = local.dx, y = local.dy;
    final gc = x / step, gr = y / step;
    final ic = gc.round(), ir = gr.round();
    final fc = gc.floor(), fr = gr.floor();
    final dx = (gc - ic).abs(), dy = (gr - ir).abs();

    setState(() {
      _hoverHRow = _hoverHCol = null; _hoverVRow = _hoverVCol = null;
      // Closer to horizontal line
      if (dy < dx && ir >= 0 && ir <= _N && fc >= 0 && fc < _N) {
        _hoverHRow = ir; _hoverHCol = fc;
      } else if (ic >= 0 && ic <= _N && fr >= 0 && fr < _N) {
        _hoverVRow = fr; _hoverVCol = ic;
      }
    });
  }

  @override Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final step = size.width / _N;
      return GestureDetector(
        onTapDown: (d) {
          if (!widget.isMyTurn) return;
          final x = d.localPosition.dx, y = d.localPosition.dy;
          final gc = x / step, gr = y / step;
          final ic = gc.round(), ir = gr.round();
          final fc = gc.floor(), fr = gr.floor();
          final dx = (gc - ic).abs(), dy = (gr - ir).abs();
          if (dy < dx) {
            // Horizontal
            if (ir >= 0 && ir <= _N && fc >= 0 && fc < _N) widget.onLineTap(true, ir, fc);
          } else {
            // Vertical
            if (ic >= 0 && ic <= _N && fr >= 0 && fr < _N) widget.onLineTap(false, fr, ic);
          }
        },
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, size),
        child: CustomPaint(
          painter: _HoverPainter(
            hRow: _hoverHRow, hCol: _hoverHCol,
            vRow: _hoverVRow, vCol: _hoverVCol,
            hLines: widget.hLines, vLines: widget.vLines,
          ),
        ),
      );
    });
  }
}

class _HoverPainter extends CustomPainter {
  final int? hRow, hCol, vRow, vCol;
  final List<List<int>> hLines, vLines;
  _HoverPainter({this.hRow, this.hCol, this.vRow, this.vCol,
    required this.hLines, required this.vLines});
  @override void paint(Canvas canvas, Size size) {
    final step = size.width / _N;
    final paint = Paint()..color = Colors.white.withValues(alpha: .4)
      ..strokeWidth = step * 0.1..strokeCap = StrokeCap.round;
    if (hRow != null && hLines[hRow!][hCol!] == 0) {
      canvas.drawLine(Offset(hCol! * step, hRow! * step),
        Offset((hCol!+1) * step, hRow! * step), paint);
    }
    if (vRow != null && vLines[vRow!][vCol!] == 0) {
      canvas.drawLine(Offset(vCol! * step, vRow! * step),
        Offset(vCol! * step, (vRow!+1) * step), paint);
    }
  }
  @override bool shouldRepaint(_HoverPainter old) =>
    old.hRow != hRow || old.hCol != hCol || old.vRow != vRow || old.vCol != vCol;
}
