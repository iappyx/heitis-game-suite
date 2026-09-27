import 'dart:isolate';
import 'dart:math' as math;
import '../../core/solo_ai.dart';

class DamjenAI extends SoloAI {
  DamjenAI(super.difficulty);

  void takeTurn({
    required List<List<List<int>?>> board, // null or [owner, isKing 0/1]
    required int turn,
    required int? forcedRow,
    required int? forcedCol,
  }) {
    scheduleMove(() async {
      final depth = switch (difficulty) {
        SoloDifficulty.easy   => 0,
        SoloDifficulty.medium => 3,
        SoloDifficulty.hard   => 5,
      };

      final input = <String, dynamic>{
        'board': board.map((row) => row.map((c) => c?.toList()).toList()).toList(),
        'turn': turn,
        'forcedRow': forcedRow,
        'forcedCol': forcedCol,
        'depth': depth,
        'seed': rng.nextInt(0x7FFFFFFF),
      };

      Map<String, dynamic>? result;
      try {
        result = await Isolate.run(() => _computeDamjenMove(input))
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        result = _computeDamjenMove(input);
      }

      if (result == null) return;
      net.injectMessage('DAM_MOVE', result);
    });
  }
}

// ── Top-level types and compute function for Isolate ─────────────────────

class _Piece {
  int owner; bool king;
  _Piece(this.owner, {this.king = false});
  _Piece clone() => _Piece(owner, king: king);
}

class _Move {
  final int fr, fc, tr, tc;
  final int? capR, capC;
  const _Move(this.fr, this.fc, this.tr, this.tc, this.capR, this.capC);
}

Map<String, dynamic>? _computeDamjenMove(Map<String, dynamic> input) {
  final rawBoard = input['board'] as List;
  final board = rawBoard.map((row) =>
    (row as List).map((c) => c == null ? null : List<int>.from(c as List)).toList()
  ).toList();
  final turn = input['turn'] as int;
  final forcedRow = input['forcedRow'] as int?;
  final forcedCol = input['forcedCol'] as int?;
  final depth = input['depth'] as int;
  final seed = input['seed'] as int;
  final rng = math.Random(seed);

  final b = _fromRaw(board);
  final move = _pickMove(b, turn, forcedRow, forcedCol, depth, rng);
  if (move == null) return null;
  return {
    'fr': move.fr, 'fc': move.fc, 'tr': move.tr, 'tc': move.tc,
    'capR': move.capR, 'capC': move.capC,
  };
}

List<List<_Piece?>> _fromRaw(List<List<List<int>?>> raw) =>
  raw.map((row) => row.map((c) => c == null ? null : _Piece(c[0], king: c[1] == 1)).toList()).toList();

List<List<_Piece?>> _clone(List<List<_Piece?>> b) =>
  b.map((row) => row.map((c) => c?.clone()).toList()).toList();

_Move? _pickMove(List<List<_Piece?>> board, int turn, int? forR, int? forC,
    int depth, math.Random rng) {
  final moves = _getMoves(board, turn, forR, forC);
  if (moves.isEmpty) return null;
  if (depth == 0) return moves[rng.nextInt(moves.length)];
  _Move? best;
  int bestScore = -99999;
  for (final m in moves) {
    final b2 = _clone(board);
    final nextTurn = _applyMove(b2, m, turn);
    final contR = nextTurn == turn ? m.tr : null;
    final contC = nextTurn == turn ? m.tc : null;
    // Multi-jump continuation: same side moves again, so no negation
    final score = nextTurn == turn
        ? _minimax(b2, nextTurn, contR, contC, depth - 1, -99999, 99999)
        : -_minimax(b2, nextTurn, contR, contC, depth - 1, -99999, 99999);
    if (score > bestScore) { bestScore = score; best = m; }
  }
  return best;
}

int _minimax(List<List<_Piece?>> board, int turn, int? forR, int? forC,
    int depth, int alpha, int beta) {
  // Negamax: scores are always from the side-to-move's (turn) perspective
  final moves = _getMoves(board, turn, forR, forC);
  if (moves.isEmpty) return -9000 - depth; // no legal moves = loss (sooner is worse)
  if (depth == 0) return _eval(board, turn);
  for (final m in moves) {
    final b2 = _clone(board);
    final nextTurn = _applyMove(b2, m, turn);
    final contR = nextTurn == turn ? m.tr : null;
    final contC = nextTurn == turn ? m.tc : null;
    // Multi-jump continuation: same side moves again, so no negation
    final score = nextTurn == turn
        ? _minimax(b2, nextTurn, contR, contC, depth - 1, alpha, beta)
        : -_minimax(b2, nextTurn, contR, contC, depth - 1, -beta, -alpha);
    if (score >= beta) return beta;
    if (score > alpha) alpha = score;
  }
  return alpha;
}

int _eval(List<List<_Piece?>> b, int aiPlayer) {
  int score = 0;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final p = b[r][c]; if (p == null) continue;
      final v = p.king ? 3 : 1;
      score += p.owner == aiPlayer ? v : -v;
    }
  }
  return score;
}

List<_Move> _getMoves(List<List<_Piece?>> b, int turn, int? forR, int? forC) {
  final jumps = <_Move>[];
  if (forR != null) {
    jumps.addAll(_movesForPiece(b, forR, forC!, turn, jumpOnly: true));
  } else {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (b[r][c]?.owner == turn) {
          jumps.addAll(_movesForPiece(b, r, c, turn, jumpOnly: true));
        }
      }
    }
  }
  if (jumps.isNotEmpty) return jumps;

  final all = <_Move>[];
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      if (b[r][c]?.owner == turn) all.addAll(_movesForPiece(b, r, c, turn));
    }
  }
  return all;
}

List<_Move> _movesForPiece(List<List<_Piece?>> b, int r, int c,
    int turn, {bool jumpOnly = false}) {
  final piece = b[r][c]; if (piece == null || piece.owner != turn) return [];
  final dirs = <int>[];
  if (piece.owner == 1 || piece.king) dirs.add(-1);
  if (piece.owner == 2 || piece.king) dirs.add(1);
  final moves = <_Move>[];
  for (final dr in dirs) {
    for (final dc in [-1, 1]) {
      final nr = r+dr, nc = c+dc;
      if (!_inBounds(nr, nc)) continue;
      if (b[nr][nc] == null && !jumpOnly) {
        moves.add(_Move(r, c, nr, nc, null, null));
      } else if (b[nr][nc] != null && b[nr][nc]!.owner != turn) {
        final jr = r+dr*2, jc = c+dc*2;
        if (_inBounds(jr, jc) && b[jr][jc] == null) {
          moves.add(_Move(r, c, jr, jc, nr, nc));
        }
      }
    }
  }
  return moves;
}

int _applyMove(List<List<_Piece?>> b, _Move m, int turn) {
  final piece = b[m.fr][m.fc]!;
  b[m.tr][m.tc] = piece; b[m.fr][m.fc] = null;
  if (m.capR != null) b[m.capR!][m.capC!] = null;
  if ((piece.owner == 1 && m.tr == 0) || (piece.owner == 2 && m.tr == 7)) {
    piece.king = true;
  }
  if (m.capR != null) {
    final more = _movesForPiece(b, m.tr, m.tc, turn, jumpOnly: true);
    if (more.isNotEmpty) return turn;
  }
  return turn == 1 ? 2 : 1;
}

bool _inBounds(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;
