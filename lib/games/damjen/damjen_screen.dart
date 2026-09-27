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
import 'damjen_ai.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';

// ── Piece model ───────────────────────────────────────────────────────────────
class DamjenPiece {
  int owner;   // 1 = host (moves up, row 7→0), 2 = joiner (moves down, row 0→7)
  bool king;
  DamjenPiece(this.owner, {this.king = false});
  DamjenPiece clone() => DamjenPiece(owner, king: king);
}

class DamjenScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const DamjenScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<DamjenScreen> createState() => _DamjenState();
}

class _DamjenState extends State<DamjenScreen> with GameMixin {
  final _net = Network();
  final _session = SessionState();
  DamjenAI? _ai;

  // board[row][col] — null = empty. Dark squares only (row+col odd).
  late List<List<DamjenPiece?>> _board;
  int _turn = 1;              // 1=host, 2=joiner
  int? _selRow, _selCol;
  List<_Move> _validMoves = [];
  int _winner = 0;            // 0=none, 1/2=player, 3=draw
  // If a piece just jumped and can jump again, it must continue
  int? _forcedRow, _forcedCol;
  // Completed turns (both sides) in a row with no capture and no man move.
  // Draw when this reaches 2 * _drawQuietMovesEach.
  static const _drawQuietMovesEach = 40;
  int _quietMoves = 0;

  int get _myPiece => _net.myIdx == 0 ? 1 : 2;
  bool get _isMyTurn => _turn == _myPiece && _winner == 0;

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _initBoard();
    _turn = widget.firstPlayer;
    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = DamjenAI(d);
    }
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_net.isSolo && widget.firstPlayer == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerDamjenAI();
      });
    }
  }

  @override void dispose() { _ai?.cancel(); super.dispose(); }

  void _initBoard() {
    resetConfetti();
    resetStats();
    _board = List.generate(8, (_) => List.filled(8, null));
    // Joiner (2) fills rows 0-2, host (1) fills rows 5-7
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 8; c++) {
        if ((r + c) % 2 == 1) _board[r][c] = DamjenPiece(2);
      }
    }
    for (int r = 5; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if ((r + c) % 2 == 1) _board[r][c] = DamjenPiece(1);
      }
    }
    _winner = 0;
    _selRow = _selCol = null; _validMoves = [];
    _forcedRow = _forcedCol = null;
    _quietMoves = 0;
  }

  // ── Move generation ───────────────────────────────────────────────────────

  List<_Move> _movesForPiece(int r, int c, {bool jumpOnly = false}) {
    final piece = _board[r][c];
    if (piece == null || piece.owner != _turn) return [];
    final dirs = <int>[];
    if (piece.owner == 1 || piece.king) dirs.addAll([-1]); // up
    if (piece.owner == 2 || piece.king) dirs.addAll([1]);  // down
    final moves = <_Move>[];
    for (final dr in dirs) {
      for (final dc in [-1, 1]) {
        final nr = r + dr, nc = c + dc;
        if (!_inBounds(nr, nc)) continue;
        if (_board[nr][nc] == null && !jumpOnly) {
          moves.add(_Move(r, c, nr, nc, null, null));
        } else if (_board[nr][nc] != null && _board[nr][nc]!.owner != _turn) {
          final jr = r + dr * 2, jc = c + dc * 2;
          if (_inBounds(jr, jc) && _board[jr][jc] == null) {
            moves.add(_Move(r, c, jr, jc, nr, nc));
          }
        }
      }
    }
    return moves;
  }

  // All jumps available for current player (mandatory jump rule)
  List<_Move> _allJumps() {
    final jumps = <_Move>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (_board[r][c]?.owner == _turn) {
          jumps.addAll(_movesForPiece(r, c, jumpOnly: true));
        }
      }
    }
    return jumps;
  }

  bool _inBounds(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  // ── Apply a move ──────────────────────────────────────────────────────────

  void _applyMove(_Move m, {bool broadcast = true}) {
    final isCapture = m.capR != null;
    final piece = _board[m.fr][m.fc]!;
    final wasMan = !piece.king;
    _board[m.fr][m.fc] = null;
    _board[m.tr][m.tc] = piece;

    // Capture
    if (isCapture) _board[m.capR!][m.capC!] = null;

    // Promotion
    final justPromoted = !piece.king &&
        ((piece.owner == 1 && m.tr == 0) || (piece.owner == 2 && m.tr == 7));
    if (justPromoted) piece.king = true;

    // Sound feedback — pick the most distinctive event
    if (justPromoted) {
      SoundPlayer.i.damjenKing();
      HapticFeedback.heavyImpact();
    } else if (isCapture) {
      SoundPlayer.i.damjenCapture();
      HapticFeedback.mediumImpact();
    } else {
      SoundPlayer.i.damjenMove();
      HapticFeedback.lightImpact();
    }

    _selRow = _selCol = null; _validMoves = [];

    // Multi-jump: if this was a jump check if we can jump again with same piece
    // Standard rules: turn ends immediately on promotion — no continued jump as king
    bool continuedJump = false;
    if (m.capR != null && !justPromoted) {
      final more = _movesForPiece(m.tr, m.tc, jumpOnly: true);
      if (more.isNotEmpty) {
        _forcedRow = m.tr; _forcedCol = m.tc;
        continuedJump = true;
        // Don't switch turn yet
      }
    }
    // Draw clock: any capture or man (non-king) move resets it
    if (isCapture || wasMan) {
      _quietMoves = 0;
    } else if (!continuedJump) {
      _quietMoves++;
    }
    if (!continuedJump) {
      _forcedRow = _forcedCol = null;
      _turn = _turn == 1 ? 2 : 1;
      _checkGameOver();
    }

    if (broadcast) {
      _net.send('DAM_MOVE', {'fr': m.fr, 'fc': m.fc, 'tr': m.tr, 'tc': m.tc,
        'capR': m.capR, 'capC': m.capC});
    }
  }

  void _checkGameOver() {
    // Count pieces + check if current player has any moves
    int p1 = 0, p2 = 0;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (_board[r][c]?.owner == 1) p1++;
        if (_board[r][c]?.owner == 2) p2++;
      }
    }
    if (p1 == 0) { _winner = 2; return; }
    if (p2 == 0) { _winner = 1; return; }
    // Check if current player has any legal moves
    final hasMove = _getAllMovesFor(_turn).isNotEmpty;
    if (!hasMove) { _winner = _turn == 1 ? 2 : 1; return; }
    // No-progress draw: 40 moves each without a capture or man move
    if (_quietMoves >= _drawQuietMovesEach * 2) _winner = 3;
  }

  List<_Move> _getAllMovesFor(int player) {
    final saved = _turn;
    _turn = player;
    final jumps = _allJumps();
    if (jumps.isNotEmpty) { _turn = saved; return jumps; }
    final all = <_Move>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (_board[r][c]?.owner == player) all.addAll(_movesForPiece(r, c));
      }
    }
    _turn = saved;
    return all;
  }

  // ── Tap handling ──────────────────────────────────────────────────────────

  void _onTap(int r, int c) {
    if (!_isMyTurn || _winner != 0) return;

    // Forced continuation jump
    if (_forcedRow != null && !(r == _forcedRow && c == _forcedCol)) {
      // If tapping the destination of forced piece
      final forced = _movesForPiece(_forcedRow!, _forcedCol!, jumpOnly: true);
      final m = forced.where((m) => m.tr == r && m.tc == c).firstOrNull;
      if (m != null) { setState(() => _applyMove(m)); _triggerDamjenAI(); return; }
      return; // must use forced piece
    }

    // Mandatory jump rule
    final jumps = _allJumps();
    final useJumpsOnly = jumps.isNotEmpty;

    if (_selRow == null) {
      final piece = _board[r][c];
      if (piece == null || piece.owner != _myPiece) return;
      List<_Move> moves = useJumpsOnly
          ? _movesForPiece(r, c, jumpOnly: true)
          : _movesForPiece(r, c);
      if (moves.isEmpty && useJumpsOnly) return; // this piece can't jump
      setState(() { _selRow = r; _selCol = c; _validMoves = moves; });
    } else {
      final m = _validMoves.where((m) => m.tr == r && m.tc == c).firstOrNull;
      if (m != null) {
        setState(() => _applyMove(m));
        _triggerDamjenAI();
      } else if (_board[r][c]?.owner == _myPiece) {
        // Re-select
        List<_Move> moves = useJumpsOnly
            ? _movesForPiece(r, c, jumpOnly: true)
            : _movesForPiece(r, c);
        setState(() { _selRow = r; _selCol = c; _validMoves = moves; });
      } else {
        setState(() { _selRow = _selCol = null; _validMoves = []; });
      }
    }
  }

  void _triggerDamjenAI() {
    if (!_net.isSolo || _winner != 0 || _turn != 2) return;
    // Serialise board as List<List<List<int>?>>
    final raw = List<List<List<int>?>>.generate(8, (r) =>
      List<List<int>?>.generate(8, (c) {
        final p = _board[r][c];
        return p == null ? null : [p.owner, p.king ? 1 : 0];
      }));
    _ai?.takeTurn(board: raw, turn: _turn, forcedRow: _forcedRow, forcedCol: _forcedCol);
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'DAM_MOVE':
        setState(() {
          // Clear any forced-jump state from our own previous turn before applying opponent move
          _forcedRow = _forcedCol = null;
          _selRow = _selCol = null; _validMoves = [];
          _applyMove(_Move(
            msg['fr'] as int, msg['fc'] as int,
            msg['tr'] as int, msg['tc'] as int,
            msg['capR'] as int?, msg['capC'] as int?,
          ), broadcast: false);
        });
        if (_isMyTurn && _winner == 0) turnChanged();
        // Re-trigger AI for continued multi-jump or next turn
        _triggerDamjenAI();
        break;
      case 'GAME_RESET':
        if (!_net.isHost) {
          final first = msg['first'] as int? ?? 1;
          setState(() { _initBoard(); _turn = first; });
          if (_net.isSolo && first == 2) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _triggerDamjenAI();
            });
          }
        }
        break;
      case 'DAM_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;
      case 'DAM_SYNC':
        if (!_net.isHost) _applySync(msg);
        break;
    }
  }


  void _sendSync() {
    // Encode board as flat list of 64 ints: 0=empty, 1=host, 2=joiner, 3=host-king, 4=joiner-king
    final flat = <int>[];
    for (int r = 0; r < 8; r++) {
      for (int cc = 0; cc < 8; cc++) {
        final p = _board[r][cc];
        if (p == null) flat.add(0);
        else if (p.owner == 1 && !p.king) flat.add(1);
        else if (p.owner == 2 && !p.king) flat.add(2);
        else if (p.owner == 1 &&  p.king) flat.add(3);
        else flat.add(4);
      }
    }
    _net.send('DAM_SYNC', {
      'board': flat, 'turn': _turn, 'winner': _winner,
      'forceR': _forcedRow, 'forceC': _forcedCol,
      'quiet': _quietMoves,
    });
  }

  void _applySync(Map<String, dynamic> msg) {
    final flat = List<int>.from(msg['board'] as List);
    setState(() {
      for (int r = 0; r < 8; r++) {
        for (int cc = 0; cc < 8; cc++) {
          final v = flat[r * 8 + cc];
          if (v == 0) _board[r][cc] = null;
          else if (v == 1) _board[r][cc] = DamjenPiece(1);
          else if (v == 2) _board[r][cc] = DamjenPiece(2);
          else if (v == 3) _board[r][cc] = DamjenPiece(1, king: true);
          else             _board[r][cc] = DamjenPiece(2, king: true);
        }
      }
      _turn    = msg['turn']   as int;
      _winner  = msg['winner'] as int;
      _forcedRow = msg['forceR'] as int?;
      _forcedCol = msg['forceC'] as int?;
      _quietMoves = msg['quiet'] as int? ?? 0;
      _selRow = _selCol = null; _validMoves = [];
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
          else _net.send('DAM_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (r) => false)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override Widget build(BuildContext context) {
    final p1 = widget.players[0]; // host = red/light
    final p2 = widget.players[1]; // joiner = dark
    final flipped = _net.myIdx != 0; // joiner sees board from their side

    return GameScaffold(
        key: scaffoldKey,
      title: L.damjen.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.damjen.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: _winner != 0 ? -1 : _turn - 1,
        ),
        GameStatusBar(
          text: _winner == 3 ? L.damjen.drawNoProgress
              : _winner != 0 ? null
              : (_isMyTurn ? L.damjen.yourMove : L.damjen.opponentTurn.fmt({'player': _turn == 1 ? p1.name : p2.name})),
          textColor: _winner == 0 && _isMyTurn ? kGreen : null,
        ),

        // Board
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(8),
          child: AspectRatio(aspectRatio: 1, child: _buildBoard(flipped, p1, p2))))),

        if (_winner != 0) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winner == 3 ? -1 : _winner - 1,
            onFirstRender: () { final wi = _winner == 3 ? -1 : _winner - 1; fireConfettiOnce(wi); recordResult('damjen', wi); if (_net.isHost) _session.advanceGame(); },
          ),
          GameOverActions(players: widget.players, sendReset: false, onReset: () {
            _ai?.cancel();
            final first = _session.nextStarterFor(2);
            _net.send('GAME_RESET', {'first': first});
            setState(() { _initBoard(); _turn = first; });
            if (_net.isSolo && first == 2) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _triggerDamjenAI();
              });
            }
          }),
        ] else const SizedBox(height: 4),
      ]),
    );
  }

  Widget _buildBoard(bool flipped, Player p1, Player p2) {
    // Board colours derived from player colours
    final col1 = p1.color;
    final col2 = p2.color;
    Color mixC(Color a, Color b, double t) => Color.fromARGB(255,
      (a.red   * (1-t) + b.red   * t).round().clamp(0, 255),
      (a.green * (1-t) + b.green * t).round().clamp(0, 255),
      (a.blue  * (1-t) + b.blue  * t).round().clamp(0, 255));
    final midColor = mixC(col1, col2, 0.5);
    final sqLight = mixC(midColor, Colors.white, 0.62);
    final sqDark  = mixC(midColor, Colors.black, 0.25);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: kBorder, width: 2),
        borderRadius: BorderRadius.circular(4)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
          itemCount: 64,
          itemBuilder: (_, idx) {
            final dr = idx ~/ 8, dc = idx % 8;
            final r = flipped ? 7 - dr : dr;
            final c = flipped ? 7 - dc : dc;
            final isDark = (r + c) % 2 == 1;
            final piece = _board[r][c];
            final isSel = _selRow == r && _selCol == c;
            final isTarget = _validMoves.any((m) => m.tr == r && m.tc == c);
            final isForced = _forcedRow == r && _forcedCol == c;

            Color bg = isDark ? sqDark : sqLight;
            if (isSel || isForced) bg = Color.lerp(bg, Colors.yellow, 0.5)!;

            return GestureDetector(
              onTap: () => _onTap(r, c),
              child: Container(
                color: bg,
                child: Stack(children: [
                  // Move target dot
                  if (isTarget && isDark) Center(child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.black26))),
                  // Piece
                  if (piece != null) Center(child: _buildPiece(piece, p1, p2, isSel || isForced)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPiece(DamjenPiece piece, Player p1, Player p2, bool selected) {
    final color = piece.owner == 1 ? p1.color : p2.color;
    final crownColor = piece.owner == 1 ? p2.color : p1.color;
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: selected ? Colors.white : Colors.black38,
          width: selected ? 2.5 : 1.5),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: .4), blurRadius: 4, offset: const Offset(1, 2))],
        gradient: RadialGradient(center: const Alignment(-0.3, -0.4), radius: 0.7, colors: [
          Color.lerp(color, Colors.white, .4)!,
          color,
          Color.lerp(color, Colors.black, .3)!,
        ]),
      ),
      child: piece.king
        ? Center(child: Text('\u265B\uFE0E',
            style: TextStyle(fontSize: 14, color: crownColor,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 2)])))
        : null,
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Move {
  final int fr, fc, tr, tc;
  final int? capR, capC;
  const _Move(this.fr, this.fc, this.tr, this.tc, this.capR, this.capC);
}
