import 'package:flutter/material.dart';
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
import 'skaken_ai.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';

// Piece glyphs — white pieces only; piece.abs() used for both sides
// \uFE0E forces text (not emoji) rendering
const _glyphs = {
  6: '\u2654\uFE0E',  5: '\u2655\uFE0E',  4: '\u2656\uFE0E',
  3: '\u2657\uFE0E',  2: '\u2658\uFE0E',  1: '\u2659\uFE0E',
};

// ── Piece constants ────────────────────────────────────────────────────────
// Positive = white (host), Negative = black (joiner)
// |value|: 1=pawn 2=knight 3=bishop 4=rook 5=queen 6=king
const _EMPTY = 0, _P = 1, _N = 2, _B = 3, _R = 4, _Q = 5, _K = 6;

class SkakenScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const SkakenScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<SkakenScreen> createState() => _SkakenState();
}

class _SkakenState extends State<SkakenScreen> with GameMixin {
  final _net = Network();
  final _session = SessionState();
  SkakenAI? _ai;

  late List<List<int>> _board;
  int? _selRow, _selCol;
  List<List<int>> _validMoves = [];
  bool _whiteTurn = true; // white = host
  int _winner = 0;        // 0=none, 1=white(host), 2=black(joiner)
  String _statusMsg = '';

  // castling rights & en passant
  bool _wKMoved = false, _wRaMoved = false, _wRhMoved = false;
  bool _bKMoved = false, _bRaMoved = false, _bRhMoved = false;
  int? _epCol; // en-passant target column after a double pawn push
  int _halfMoves = 0; // half-moves since last capture or pawn move (50-move rule)

  bool get _iAmWhite => _net.myIdx == 0;
  bool get _isMyTurn => _whiteTurn == _iAmWhite && _winner == 0;

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _initBoard();
    _whiteTurn = true; // white (host/player 0) always opens
    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = SkakenAI(d);
    }
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
  }

  @override void dispose() {
    msgSub?.cancel();
    _ai?.cancel();
    WakeLock.release();
    super.dispose();
  }

  void _initBoard() {
    _ai?.cancel();
    resetConfetti();
    resetStats();
    _board = [
      [-_R,-_N,-_B,-_Q,-_K,-_B,-_N,-_R],
      List.filled(8, -_P),
      List.filled(8, _EMPTY), List.filled(8, _EMPTY),
      List.filled(8, _EMPTY), List.filled(8, _EMPTY),
      List.filled(8, _P),
      [_R,_N,_B,_Q,_K,_B,_N,_R],
    ];
    _selRow = _selCol = null; _validMoves = [];
    _whiteTurn = true; _winner = 0; _epCol = null; _halfMoves = 0;
    _wKMoved = _wRaMoved = _wRhMoved = false;
    _bKMoved = _bRaMoved = _bRhMoved = false;
    _statusMsg = '';
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'SKA_MOVE':
        if (!mounted || _winner != 0) break;
        final fr = msg['fr'] as int, fc = msg['fc'] as int;
        final tr = msg['tr'] as int, tc = msg['tc'] as int;
        if (fr < 0 || fr > 7 || fc < 0 || fc > 7 ||
            tr < 0 || tr > 7 || tc < 0 || tc > 7) break;
        setState(() {
          _applyMove(fr, fc, tr, tc,
            promote: msg['promote'] as int?,
            broadcast: false,
          );
        });
        if (_isMyTurn && _winner == 0) turnChanged();
        break;
      case 'GAME_RESET':
        if (!_net.isHost) setState(() => _initBoard());
        break;
      case 'SKA_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;
      case 'SKA_SYNC':
        if (!_net.isHost) _applySync(msg);
        break;
    }
  }

  // ── Move logic ─────────────────────────────────────────────────────────────

  bool _isWhite(int p) => p > 0;
  bool _isBlack(int p) => p < 0;
  bool _friendly(int p) => _whiteTurn ? _isWhite(p) : _isBlack(p);
  bool _enemy(int p)    => _whiteTurn ? _isBlack(p) : _isWhite(p);

  List<List<int>> _movesFor(int r, int c, {bool checkSafety = true, bool castling = true}) {
    final p = _board[r][c];
    if (p == _EMPTY) return [];
    if (_isWhite(p) != _whiteTurn) return [];
    final moves = <List<int>>[];
    final abs = p.abs();

    void add(int tr, int tc) {
      if (tr < 0 || tr > 7 || tc < 0 || tc > 7) return;
      if (_friendly(_board[tr][tc])) return;
      moves.add([tr, tc]);
    }

    void slide(List<List<int>> dirs) {
      for (final d in dirs) {
        int nr = r + d[0], nc = c + d[1];
        while (nr >= 0 && nr <= 7 && nc >= 0 && nc <= 7) {
          if (_friendly(_board[nr][nc])) break;
          moves.add([nr, nc]);
          if (_board[nr][nc] != _EMPTY) break;
          nr += d[0]; nc += d[1];
        }
      }
    }

    switch (abs) {
      case _P:
        final dir = _isWhite(p) ? -1 : 1;
        final start = _isWhite(p) ? 6 : 1;
        final nr = r + dir;
        if (nr < 0 || nr > 7) break; // already at back rank (promoted) — no pawn moves
        // Forward
        if (_board[nr][c] == _EMPTY) {
          moves.add([nr, c]);
          if (r == start && (r+dir*2) >= 0 && (r+dir*2) <= 7 && _board[r+dir*2][c] == _EMPTY) moves.add([r+dir*2, c]);
        }
        // Captures
        for (final dc in [-1, 1]) {
          final tc = c + dc;
          if (tc < 0 || tc > 7) continue;
          if (_enemy(_board[nr][tc])) moves.add([nr, tc]);
          // En passant
          if (_epCol == tc && r == (dir == -1 ? 3 : 4)) moves.add([nr, tc]);
        }
        break;
      case _N:
        for (final d in [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]]) add(r+d[0], c+d[1]);
        break;
      case _B: slide([[-1,-1],[-1,1],[1,-1],[1,1]]); break;
      case _R: slide([[-1,0],[1,0],[0,-1],[0,1]]); break;
      case _Q: slide([[-1,-1],[-1,1],[1,-1],[1,1],[-1,0],[1,0],[0,-1],[0,1]]); break;
      case _K:
        for (final d in [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]]) add(r+d[0], c+d[1]);
        // Castling — skipped when scanning for check (castling=false) to prevent recursion
        if (castling) {
          if (_isWhite(p) && !_wKMoved && !_isInCheck(true)) {
            if (!_wRhMoved && _board[7][5] == 0 && _board[7][6] == 0
                && !_wouldLeaveInCheck(r, c, 7, 5) && !_wouldLeaveInCheck(r, c, 7, 6))
              moves.add([7, 6]);
            if (!_wRaMoved && _board[7][3] == 0 && _board[7][2] == 0 && _board[7][1] == 0
                && !_wouldLeaveInCheck(r, c, 7, 3) && !_wouldLeaveInCheck(r, c, 7, 2))
              moves.add([7, 2]);
          } else if (_isBlack(p) && !_bKMoved && !_isInCheck(false)) {
            if (!_bRhMoved && _board[0][5] == 0 && _board[0][6] == 0
                && !_wouldLeaveInCheck(r, c, 0, 5) && !_wouldLeaveInCheck(r, c, 0, 6))
              moves.add([0, 6]);
            if (!_bRaMoved && _board[0][3] == 0 && _board[0][2] == 0 && _board[0][1] == 0
                && !_wouldLeaveInCheck(r, c, 0, 3) && !_wouldLeaveInCheck(r, c, 0, 2))
              moves.add([0, 2]);
          }
        }
        break;
    }

    if (!checkSafety) return moves;
    // Filter moves that leave own king in check
    return moves.where((m) => !_wouldLeaveInCheck(r, c, m[0], m[1])).toList();
  }

  bool _wouldLeaveInCheck(int fr, int fc, int tr, int tc) {
    final saved = _board[fr][fc];
    final savedTarget = _board[tr][tc];
    _board[tr][tc] = saved;
    _board[fr][fc] = _EMPTY;
    // En passant: also remove the captured pawn (same rank as fr, same col as tc)
    final isEP = saved.abs() == _P && fc != tc && savedTarget == _EMPTY;
    int? epSavedPiece;
    if (isEP) { epSavedPiece = _board[fr][tc]; _board[fr][tc] = _EMPTY; }
    final inCheck = _isInCheck(_whiteTurn);
    _board[fr][fc] = saved;
    _board[tr][tc] = savedTarget;
    if (isEP) _board[fr][tc] = epSavedPiece!;
    return inCheck;
  }

  bool _isInCheck(bool white) {
    // Find king
    final king = white ? _K : -_K;
    int kr = -1, kc = -1;
    outer: for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (_board[r][c] == king) { kr = r; kc = c; break outer; }
      }
    }
    if (kr == -1) return true; // king captured = in check
    // Check if any enemy piece can reach the king.
    // We need moves from the enemy's perspective, so temporarily override
    // _whiteTurn via a dedicated helper that takes an explicit turn argument.
    return _anyEnemyCanReach(kr, kc, white);
  }

  /// Returns true if any piece belonging to the enemy of [white] can move to (tr, tc).
  /// Uses [_movesForAs] which accepts an explicit whiteTurn argument to avoid
  /// mutating the shared [_whiteTurn] field.
  bool _anyEnemyCanReach(int tr, int tc, bool white) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (white ? _isBlack(_board[r][c]) : _isWhite(_board[r][c])) {
          final ms = _movesForAs(r, c, !white, checkSafety: false, castling: false);
          if (ms.any((m) => m[0] == tr && m[1] == tc)) return true;
        }
      }
    }
    return false;
  }

  /// Like [_movesFor] but uses [asWhite] as the turn instead of [_whiteTurn].
  List<List<int>> _movesForAs(int r, int c, bool asWhite,
      {bool checkSafety = true, bool castling = true}) {
    final saved = _whiteTurn;
    _whiteTurn = asWhite;
    final result = _movesFor(r, c, checkSafety: checkSafety, castling: castling);
    _whiteTurn = saved;
    return result;
  }

  bool _hasAnyMove(bool white) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if ((white ? _isWhite(_board[r][c]) : _isBlack(_board[r][c])) &&
            _movesForAs(r, c, white).isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  /// Dead position: K v K, K+minor v K, or only bishops left that all stand
  /// on the same square colour (covers K+B v K+B with same-coloured bishops).
  bool _insufficientMaterial() {
    final others = <List<int>>[]; // [absPiece, squareColour]
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = _board[r][c];
        if (p == _EMPTY || p.abs() == _K) continue;
        others.add([p.abs(), (r + c) % 2]);
      }
    }
    if (others.isEmpty) return true;
    if (others.length == 1) return others[0][0] == _N || others[0][0] == _B;
    return others.every((o) => o[0] == _B && o[1] == others[0][1]);
  }

  void _applyMove(int fr, int fc, int tr, int tc, {int? promote, bool broadcast = true}) {
    final captured = _board[tr][tc] != _EMPTY ||
        (_board[fr][fc].abs() == _P && fc != tc && _board[tr][tc] == _EMPTY); // en passant
    final piece = _board[fr][fc];
    final absPiece = piece.abs();

    // En passant capture
    if (absPiece == _P && fc != tc && _board[tr][tc] == _EMPTY) {
      _board[fr][tc] = _EMPTY; // captured pawn
    }
    // Castling
    if (absPiece == _K && (tc - fc).abs() == 2) {
      if (tc == 6) { _board[fr][5] = _board[fr][7]; _board[fr][7] = _EMPTY; }
      else         { _board[fr][3] = _board[fr][0]; _board[fr][0] = _EMPTY; }
    }

    _board[tr][tc] = piece;
    _board[fr][fc] = _EMPTY;

    // Promotion
    if (absPiece == _P && (tr == 0 || tr == 7)) {
      final prom = promote ?? _Q;
      _board[tr][tc] = _isWhite(piece) ? prom : -prom;
    }

    // Update castling flags — rook moved, king moved, OR rook's home square was captured
    if (piece == _K) _wKMoved = true;
    if (piece == -_K) _bKMoved = true;
    if (piece == _R && fr == 7 && fc == 7) _wRhMoved = true;
    if (piece == _R && fr == 7 && fc == 0) _wRaMoved = true;
    if (piece == -_R && fr == 0 && fc == 7) _bRhMoved = true;
    if (piece == -_R && fr == 0 && fc == 0) _bRaMoved = true;
    // If a piece captures on a rook's home square, that rook is gone — revoke castling right
    if (tr == 7 && tc == 7) _wRhMoved = true;
    if (tr == 7 && tc == 0) _wRaMoved = true;
    if (tr == 0 && tc == 7) _bRhMoved = true;
    if (tr == 0 && tc == 0) _bRaMoved = true;

    // 50-move rule clock: reset on capture or pawn move
    _halfMoves = (captured || absPiece == _P) ? 0 : _halfMoves + 1;

    // En passant target
    _epCol = (absPiece == _P && (tr - fr).abs() == 2) ? fc : null;

    _whiteTurn = !_whiteTurn;
    _selRow = _selCol = null;
    _validMoves = [];

    // Check game over
    if (!_hasAnyMove(_whiteTurn)) {
      if (_isInCheck(_whiteTurn)) {
        _winner = _whiteTurn ? 2 : 1; // checkmate
        _statusMsg = L.skaken.checkmate.fmt({'player': _winner == 1 ? widget.players[0].name : widget.players[1].name});
      } else {
        _winner = 3; // stalemate
        _statusMsg = L.skaken.stalemate;
      }
    } else if (_insufficientMaterial()) {
      _winner = 3;
      _statusMsg = L.skaken.drawInsufficient;
    } else if (_halfMoves >= 100) {
      _winner = 3;
      _statusMsg = L.skaken.drawFiftyMoves;
    } else if (_isInCheck(_whiteTurn)) {
      _statusMsg = L.skaken.check;
    } else {
      _statusMsg = '';
    }

    // Sound feedback — pick the most important event
    if (_winner == 1 || _winner == 2) {
      SoundPlayer.i.skakenCheckmate();
      HapticFeedback.heavyImpact();
    } else if (_isInCheck(_whiteTurn)) {
      SoundPlayer.i.skakenCheck();
      HapticFeedback.heavyImpact();
    } else if (captured) {
      SoundPlayer.i.skakenCapture();
      HapticFeedback.mediumImpact();
    } else {
      SoundPlayer.i.skakenPlace();
      HapticFeedback.mediumImpact();
    }

    if (broadcast) {
      _net.send('SKA_MOVE', {'fr': fr, 'fc': fc, 'tr': tr, 'tc': tc, 'promote': promote});
    }
  }

  void _onTapSquare(int r, int c) {
    if (!_isMyTurn) return;
    if (_selRow == null) {
      // Select a piece
      if (_friendly(_board[r][c])) {
        final ms = _movesFor(r, c);
        SoundPlayer.i.skakenPick();
        HapticFeedback.selectionClick();
        setState(() { _selRow = r; _selCol = c; _validMoves = ms; });
      }
    } else {
      // Try to move
      final isValid = _validMoves.any((m) => m[0] == r && m[1] == c);
      if (isValid) {
        setState(() => _applyMove(_selRow!, _selCol!, r, c));
        if (_net.isSolo && _winner == 0) {
          _ai?.takeTurn(
            board: _board.map((row) => row.toList()).toList(),
            whiteTurn: _whiteTurn,
            wKMoved: _wKMoved, wRaMoved: _wRaMoved, wRhMoved: _wRhMoved,
            bKMoved: _bKMoved, bRaMoved: _bRaMoved, bRhMoved: _bRhMoved,
            epCol: _epCol,
          );
        }
      } else if (_friendly(_board[r][c])) {
        // Re-select
        final ms = _movesFor(r, c);
        SoundPlayer.i.skakenPick();
        HapticFeedback.selectionClick();
        setState(() { _selRow = r; _selCol = c; _validMoves = ms; });
      } else {
        setState(() { _selRow = _selCol = null; _validMoves = []; });
      }
    }
  }


  void _sendSync() {
    _net.send('SKA_SYNC', {
      'board':    _board.map((r) => r.toList()).toList(),
      'white':    _whiteTurn ? 1 : 0,
      'winner':   _winner,
      'wKM':  _wKMoved  ? 1 : 0, 'wRaM': _wRaMoved ? 1 : 0, 'wRhM': _wRhMoved ? 1 : 0,
      'bKM':  _bKMoved  ? 1 : 0, 'bRaM': _bRaMoved ? 1 : 0, 'bRhM': _bRhMoved ? 1 : 0,
      'ep': _epCol,
      'hm': _halfMoves,
      'status': _statusMsg,
    });
  }

  void _applySync(Map<String, dynamic> msg) {
    setState(() {
      final raw = msg['board'] as List;
      _board = List.generate(8, (r) => List<int>.from(raw[r] as List));
      _whiteTurn  = (msg['white']  as int) == 1;
      _winner     = msg['winner']  as int;
      _wKMoved    = (msg['wKM']  as int) == 1;
      _wRaMoved   = (msg['wRaM'] as int) == 1;
      _wRhMoved   = (msg['wRhM'] as int) == 1;
      _bKMoved    = (msg['bKM']  as int) == 1;
      _bRaMoved   = (msg['bRaM'] as int) == 1;
      _bRhMoved   = (msg['bRhM'] as int) == 1;
      _epCol      = msg['ep'] as int?;
      _halfMoves  = msg['hm'] as int? ?? 0;
      _statusMsg  = msg['status'] as String? ?? '';
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
          else _net.send('SKA_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (r) => false)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override Widget build(BuildContext context) {
    final p1 = widget.players[0]; // white
    final p2 = widget.players[1]; // black

    // Joiner sees board flipped (black at bottom)
    final flipped = !_iAmWhite;

    return GameScaffold(
        key: scaffoldKey,
      title: L.skaken.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.skaken.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: _winner != 0 ? -1 : (_whiteTurn ? 0 : 1),
        ),
        GameStatusBar(
          text: _statusMsg.isNotEmpty ? _statusMsg
              : _winner != 0 ? null
              : (_isMyTurn ? L.skaken.yourMove : L.skaken.yourTurn.fmt({'player': (_whiteTurn ? widget.players[0].name : widget.players.length > 1 ? widget.players[1].name : 'AI')})),
          textColor: _statusMsg.isEmpty && _winner == 0 && _isMyTurn ? kGreen : null,
        ),

        // Board
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(8),
          child: AspectRatio(aspectRatio: 1, child: _buildBoard(flipped, p1, p2)),
        ))),

        if (_winner != 0) ...[ 
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winner == 3 ? -1 : _winner - 1,
            onFirstRender: () { final wi = _winner == 3 ? -1 : _winner - 1; fireConfettiOnce(wi); recordResult('skaken', wi); if (_net.isHost) _session.advanceGame(); },
          ),
          GameOverActions(players: widget.players, onReset: () {
            setState(() => _initBoard());
            if (_net.isSolo && !_iAmWhite && _winner == 0) {
              _ai?.takeTurn(
                board: _board.map((row) => row.toList()).toList(),
                whiteTurn: _whiteTurn,
                wKMoved: _wKMoved, wRaMoved: _wRaMoved, wRhMoved: _wRhMoved,
                bKMoved: _bKMoved, bRaMoved: _bRaMoved, bRhMoved: _bRhMoved,
                epCol: _epCol,
              );
            }
          }),
        ] else const SizedBox(height: 4),
      ]),
    );
  }

  Widget _buildBoard(bool flipped, Player p1, Player p2) {
    // Compute check state ONCE before rendering — _isInCheck mutates _whiteTurn internally
    // and must never be called inside the GridView itemBuilder
    final whiteInCheck = _winner == 0 && _isInCheck(true);
    final blackInCheck = _winner == 0 && _isInCheck(false);

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
            final displayRow = idx ~/ 8;
            final displayCol = idx % 8;
            // Map display position to board position
            final r = flipped ? 7 - displayRow : displayRow;
            final c = flipped ? 7 - displayCol : displayCol;
            final piece = _board[r][c];
            final isLight = (r + c) % 2 == 0;
            final isSel = _selRow == r && _selCol == c;
            final isValid = _validMoves.any((m) => m[0] == r && m[1] == c);
            final isInCheck  = piece == _K  && whiteInCheck;
            final isInCheckB = piece == -_K && blackInCheck;

            Color bg = isLight ? sqLight : sqDark;
            if (isSel) bg = Color.lerp(bg, Colors.yellow, 0.5)!;
            if (isInCheck || isInCheckB) bg = Color.lerp(bg, Colors.red, 0.5)!;
            final pieceColor  = piece > 0 ? col1 : col2;
            final shadowColor = piece > 0 ? col2.withValues(alpha: 0.7) : col1.withValues(alpha: 0.7);

            return GestureDetector(
              onTap: () => _onTapSquare(r, c),
              child: Container(
                color: bg,
                child: Stack(children: [
                  if (isValid) Center(child: Container(
                    width: piece != _EMPTY ? double.infinity : 18,
                    height: piece != _EMPTY ? double.infinity : 18,
                    decoration: BoxDecoration(
                      shape: piece != _EMPTY ? BoxShape.rectangle : BoxShape.circle,
                      color: Colors.black.withValues(alpha: .2),
                      border: piece != _EMPTY
                        ? Border.all(color: Colors.black38, width: 3)
                        : null,
                    ))),
                  if (piece != _EMPTY) Positioned.fill(child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.82, heightFactor: 0.82,
                      child: FittedBox(fit: BoxFit.contain,
                        child: Text(
                          _glyphs[piece.abs()]!, // same glyphs for both sides
                          style: TextStyle(
                            fontSize: 64,
                            height: 1.0,
                            color: pieceColor,
                            fontFamily: 'Arial',
                            shadows: [
                              Shadow(color: shadowColor, blurRadius: 3, offset: const Offset(1, 1)),
                              Shadow(color: Colors.black54, blurRadius: 1),
                            ]))))))
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

