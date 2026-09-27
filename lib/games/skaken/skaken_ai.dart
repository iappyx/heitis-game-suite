import 'dart:isolate';
import 'dart:math' as math;
import '../../core/solo_ai.dart';

// Piece constants — match skaken_screen.dart
const _E = 0, _P = 1, _N = 2, _B = 3, _R = 4, _Q = 5, _K = 6;

/// Material values for evaluation heuristic
const _value = [0, 100, 320, 330, 500, 900, 20000];

class SkakenAI extends SoloAI {
  SkakenAI(super.difficulty);

  /// Called after human move. State must already be applied to board.
  /// [board]      8x8, positive=white, negative=black
  /// [whiteTurn]  should be FALSE (AI is black)
  /// [wKMoved] etc. — castling rights
  void takeTurn({
    required List<List<int>> board,
    required bool whiteTurn,
    required bool wKMoved, required bool wRaMoved, required bool wRhMoved,
    required bool bKMoved, required bool bRaMoved, required bool bRhMoved,
    required int? epCol,
  }) {
    scheduleMove(() async {
      final depth = switch (difficulty) {
        SoloDifficulty.easy   => 0,
        SoloDifficulty.medium => 2,
        SoloDifficulty.hard   => 3,
      };

      final input = <String, dynamic>{
        'board':     board.map((r) => r.toList()).toList(),
        'whiteTurn': whiteTurn,
        'wKMoved':   wKMoved,  'wRaMoved': wRaMoved, 'wRhMoved': wRhMoved,
        'bKMoved':   bKMoved,  'bRaMoved': bRaMoved, 'bRhMoved': bRhMoved,
        'epCol':     epCol,
        'depth':     depth,
        'seed':      rng.nextInt(0x7FFFFFFF),
      };

      // Try isolate with a strict timeout. On some devices Isolate.run
      // hangs indefinitely (never throws, never returns), so we race it
      // against a 3-second deadline and always fall back to synchronous.
      Map<String, int>? result;
      try {
        result = await Isolate.run(() => _computeSkakenMove(input))
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Isolate failed, timed out, or isn't supported — compute synchronously.
        result = _computeSkakenMove(input);
      }

      if (result == null) return;
      net.injectMessage('SKA_MOVE', {
        'fr': result['fr'], 'fc': result['fc'],
        'tr': result['tr'], 'tc': result['tc'],
        'promote': _Q,
      });
    });
  }

}

// ── Top-level isolate entry point ─────────────────────────────────────────
// Must be a top-level function (not a method) to be sendable to Isolate.run.
Map<String, int>? _computeSkakenMove(Map<String, dynamic> input) {
  final rawBoard  = input['board']    as List;
  final board     = rawBoard.map((r) => List<int>.from(r as List)).toList();
  final whiteTurn = input['whiteTurn'] as bool;
  final depth     = input['depth']    as int;
  final seed      = input['seed']     as int;
  final rng       = math.Random(seed);

  final state = _State(
    board: board, whiteTurn: whiteTurn,
    wKMoved:  input['wKMoved']  as bool,
    wRaMoved: input['wRaMoved'] as bool,
    wRhMoved: input['wRhMoved'] as bool,
    bKMoved:  input['bKMoved']  as bool,
    bRaMoved: input['bRaMoved'] as bool,
    bRhMoved: input['bRhMoved'] as bool,
    epCol:    input['epCol']    as int?,
  );

  final moves = _allMoves(state);
  if (moves.isEmpty) return null;

  _Move best;
  if (depth == 0) {
    best = moves[rng.nextInt(moves.length)];
  } else {
    best = moves[0];
    int bestScore = -999999;
    for (final m in moves) {
      final next = _apply(state, m);
      final score = -_skakenAlphaBeta(next, depth - 1, -999999, 999999);
      if (score > bestScore) { bestScore = score; best = m; }
    }
  }
  return {'fr': best.fr, 'fc': best.fc, 'tr': best.tr, 'tc': best.tc};
}

// Renamed to avoid conflict with any class method; used only by the isolate.
int _skakenAlphaBeta(_State state, int depth, int alpha, int beta) {
  if (depth == 0) return _skakenEvaluate(state);
  final moves = _allMoves(state);
  if (moves.isEmpty) {
    return _isInCheck(state, state.whiteTurn) ? -10000 - depth : 0;
  }
  for (final m in moves) {
    final next = _apply(state, m);
    final score = -_skakenAlphaBeta(next, depth - 1, -beta, -alpha);
    if (score >= beta) return beta;
    if (score > alpha) alpha = score;
  }
  return alpha;
}

int _skakenEvaluate(_State s) {
  int score = 0;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final p = s.board[r][c];
      if (p == _E) continue;
      final v = _value[p.abs()];
      score += s.whiteTurn ? (p > 0 ? v : -v) : (p < 0 ? v : -v);
    }
  }
  return score;
}

// ── State ──────────────────────────────────────────────────────────────────
class _State {
  final List<List<int>> board;
  final bool whiteTurn;
  final bool wKMoved, wRaMoved, wRhMoved;
  final bool bKMoved, bRaMoved, bRhMoved;
  final int? epCol;

  const _State({
    required this.board, required this.whiteTurn,
    required this.wKMoved, required this.wRaMoved, required this.wRhMoved,
    required this.bKMoved, required this.bRaMoved, required this.bRhMoved,
    required this.epCol,
  });
}

class _Move {
  final int fr, fc, tr, tc;
  const _Move(this.fr, this.fc, this.tr, this.tc);
}

// ── Move generation ────────────────────────────────────────────────────────
List<_Move> _allMoves(_State s) {
  final moves = <_Move>[];
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final p = s.board[r][c];
      if (p == _E) continue;
      if (s.whiteTurn ? p < 0 : p > 0) continue;
      for (final t in _movesFor(s, r, c)) {
        if (!_wouldLeaveInCheck(s, r, c, t[0], t[1])) {
          moves.add(_Move(r, c, t[0], t[1]));
        }
      }
    }
  }
  return moves;
}

List<List<int>> _movesFor(_State s, int r, int c, {bool castling = true}) {
  final p = s.board[r][c];
  final abs = p.abs();
  final moves = <List<int>>[];

  bool friendly(int x) => x != _E && (p > 0 ? x > 0 : x < 0);
  bool enemy(int x)    => x != _E && (p > 0 ? x < 0 : x > 0);
  bool inBounds(int r, int c) => r >= 0 && r <= 7 && c >= 0 && c <= 7;

  void add(int tr, int tc) {
    if (!inBounds(tr, tc)) return;
    if (friendly(s.board[tr][tc])) return;
    moves.add([tr, tc]);
  }

  void slide(List<List<int>> dirs) {
    for (final d in dirs) {
      int nr = r+d[0], nc = c+d[1];
      while (inBounds(nr, nc)) {
        if (friendly(s.board[nr][nc])) break;
        moves.add([nr, nc]);
        if (s.board[nr][nc] != _E) break;
        nr += d[0]; nc += d[1];
      }
    }
  }

  switch (abs) {
    case _P:
      final dir = p > 0 ? -1 : 1;
      final start = p > 0 ? 6 : 1;
      if (inBounds(r+dir, c) && s.board[r+dir][c] == _E) {
        moves.add([r+dir, c]);
        if (r == start && inBounds(r+dir*2, c) && s.board[r+dir*2][c] == _E) moves.add([r+dir*2, c]);
      }
      for (final dc in [-1, 1]) {
        final tc = c + dc;
        if (!inBounds(r+dir, tc)) continue;
        if (enemy(s.board[r+dir][tc])) moves.add([r+dir, tc]);
        if (s.epCol == tc && r == (p > 0 ? 3 : 4)) moves.add([r+dir, tc]);
      }
      break;
    case _N:
      for (final d in [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]])
        add(r+d[0], c+d[1]);
      break;
    case _B: slide([[-1,-1],[-1,1],[1,-1],[1,1]]); break;
    case _R: slide([[-1,0],[1,0],[0,-1],[0,1]]); break;
    case _Q: slide([[-1,-1],[-1,1],[1,-1],[1,1],[-1,0],[1,0],[0,-1],[0,1]]); break;
    case _K:
      for (final d in [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]])
        add(r+d[0], c+d[1]);
      // Castling — disabled when scanning for check to prevent recursion
      if (castling) {
        if (p > 0 && !s.wKMoved && !_isInCheck(s, true)) {
          if (!s.wRhMoved && s.board[7][5]==0 && s.board[7][6]==0
              && !_wouldLeaveInCheck(s, 7, 4, 7, 5) && !_wouldLeaveInCheck(s, 7, 4, 7, 6)) moves.add([7,6]);
          if (!s.wRaMoved && s.board[7][3]==0 && s.board[7][2]==0 && s.board[7][1]==0
              && !_wouldLeaveInCheck(s, 7, 4, 7, 3) && !_wouldLeaveInCheck(s, 7, 4, 7, 2)) moves.add([7,2]);
        } else if (p < 0 && !s.bKMoved && !_isInCheck(s, false)) {
          if (!s.bRhMoved && s.board[0][5]==0 && s.board[0][6]==0
              && !_wouldLeaveInCheck(s, 0, 4, 0, 5) && !_wouldLeaveInCheck(s, 0, 4, 0, 6)) moves.add([0,6]);
          if (!s.bRaMoved && s.board[0][3]==0 && s.board[0][2]==0 && s.board[0][1]==0
              && !_wouldLeaveInCheck(s, 0, 4, 0, 3) && !_wouldLeaveInCheck(s, 0, 4, 0, 2)) moves.add([0,2]);
        }
      }
      break;
  }
  return moves;
}

bool _wouldLeaveInCheck(_State s, int fr, int fc, int tr, int tc) {
  final b = s.board.map((r) => r.toList()).toList();
  final piece = b[fr][fc];
  b[tr][tc] = piece; b[fr][fc] = _E;
  // Apply promotion so the simulated board is accurate for check detection
  if (piece.abs() == _P && (tr == 0 || tr == 7)) {
    b[tr][tc] = piece > 0 ? _Q : -_Q;
  }
  // En passant: also remove the captured pawn (same rank as fr, same col as tc)
  if (piece.abs() == _P && fc != tc && s.board[tr][tc] == _E) {
    b[fr][tc] = _E;
  }
  final s2 = _State(board: b, whiteTurn: s.whiteTurn,
    wKMoved: s.wKMoved, wRaMoved: s.wRaMoved, wRhMoved: s.wRhMoved,
    bKMoved: s.bKMoved, bRaMoved: s.bRaMoved, bRhMoved: s.bRhMoved,
    epCol: s.epCol);
  return _isInCheck(s2, s.whiteTurn);
}

bool _isInCheck(_State s, bool white) {
  final king = white ? _K : -_K;
  int kr = -1, kc = -1;
  outer: for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      if (s.board[r][c] == king) { kr = r; kc = c; break outer; }
    }
  }
  if (kr == -1) return true;
  final enemy = _State(board: s.board, whiteTurn: !white,
    wKMoved: s.wKMoved, wRaMoved: s.wRaMoved, wRhMoved: s.wRhMoved,
    bKMoved: s.bKMoved, bRaMoved: s.bRaMoved, bRhMoved: s.bRhMoved,
    epCol: s.epCol);
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final p = s.board[r][c];
      if (p == _E) continue;
      if (white ? p > 0 : p < 0) continue;
      if (_movesFor(enemy, r, c, castling: false).any((m) => m[0] == kr && m[1] == kc)) return true;
    }
  }
  return false;
}

_State _apply(_State s, _Move m) {
  final b = s.board.map((r) => r.toList()).toList();
  final piece = b[m.fr][m.fc];
  final abs = piece.abs();
  int? newEp;

  // En passant capture
  if (abs == _P && m.fc != m.tc && b[m.tr][m.tc] == _E) b[m.fr][m.tc] = _E;
  // Castling rook
  if (abs == _K && (m.tc - m.fc).abs() == 2) {
    if (m.tc == 6) { b[m.fr][5] = b[m.fr][7]; b[m.fr][7] = _E; }
    else           { b[m.fr][3] = b[m.fr][0]; b[m.fr][0] = _E; }
  }
  // En passant flag
  if (abs == _P && (m.tr - m.fr).abs() == 2) newEp = m.tc;
  // Pawn promotion (always queen)
  if (abs == _P && (m.tr == 0 || m.tr == 7)) {
    b[m.tr][m.tc] = piece > 0 ? _Q : -_Q;
  } else {
    b[m.tr][m.tc] = piece;
  }
  b[m.fr][m.fc] = _E;

  return _State(
    board: b, whiteTurn: !s.whiteTurn,
    wKMoved: s.wKMoved || (piece == _K),
    wRaMoved: s.wRaMoved || (m.fr == 7 && m.fc == 0) || (m.tr == 7 && m.tc == 0),
    wRhMoved: s.wRhMoved || (m.fr == 7 && m.fc == 7) || (m.tr == 7 && m.tc == 7),
    bKMoved: s.bKMoved || (piece == -_K),
    bRaMoved: s.bRaMoved || (m.fr == 0 && m.fc == 0) || (m.tr == 0 && m.tc == 0),
    bRhMoved: s.bRhMoved || (m.fr == 0 && m.fc == 7) || (m.tr == 0 && m.tc == 7),
    epCol: newEp,
  );
}
