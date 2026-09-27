import 'dart:isolate';
import 'dart:math' as math;
import '../../core/solo_ai.dart';

class FjouwerOpInRigeAI extends SoloAI {
  FjouwerOpInRigeAI(super.difficulty);

  void takeTurn(List<List<int>> board) {
    scheduleMove(() async {
      final depth = switch (difficulty) {
        SoloDifficulty.easy   => 0,
        SoloDifficulty.medium => 3,
        SoloDifficulty.hard   => 6,
      };

      final input = <String, dynamic>{
        'board': board.map((r) => r.toList()).toList(),
        'depth': depth,
        'seed': rng.nextInt(0x7FFFFFFF),
      };

      Map<String, int>? result;
      try {
        result = await Isolate.run(() => _computeFjouwerOpInRigeMove(input))
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        result = _computeFjouwerOpInRigeMove(input);
      }

      if (result == null) return;
      net.injectMessage('FJO_DROP', {'col': result['col'], 'piece': 2});
    });
  }
}

// ── Top-level compute function for Isolate ───────────────────────────────

const _rows = 6, _cols = 7;

Map<String, int>? _computeFjouwerOpInRigeMove(Map<String, dynamic> input) {
  final rawBoard = input['board'] as List;
  final board = rawBoard.map((r) => List<int>.from(r as List)).toList();
  final depth = input['depth'] as int;
  final seed = input['seed'] as int;
  final rng = math.Random(seed);

  final valid = [for (int c = 0; c < _cols; c++) if (board[0][c] == 0) c];
  if (valid.isEmpty) return null;

  if (depth == 0) return {'col': valid[rng.nextInt(valid.length)]};
  final col = _alphaBeta(board, depth, -99999, 99999, true).col;
  return {'col': col};
}

({int col, int score}) _alphaBeta(
    List<List<int>> board, int depth, int alpha, int beta, bool maximising) {
  final w = _checkWinner(board);
  if (w == 2) return (col: -1, score: 1000 + depth);
  if (w == 1) return (col: -1, score: -1000 - depth);
  if (depth == 0 || _isFull(board)) return (col: -1, score: _score(board, 2));

  final valid = [for (int c = 0; c < _cols; c++) if (board[0][c] == 0) c];
  int best = maximising ? -99999 : 99999;
  int bestCol = valid[0];

  for (final c in valid) {
    final b2 = _copyBoard(board);
    _drop(b2, c, maximising ? 2 : 1);
    final s = _alphaBeta(b2, depth - 1, alpha, beta, !maximising).score;
    if (maximising ? s > best : s < best) { best = s; bestCol = c; }
    if (maximising) alpha = alpha > best ? alpha : best;
    else            beta  = beta  < best ? beta  : best;
    if (beta <= alpha) break;
  }
  return (col: bestCol, score: best);
}

void _drop(List<List<int>> b, int col, int piece) {
  for (int r = _rows - 1; r >= 0; r--) {
    if (b[r][col] == 0) { b[r][col] = piece; return; }
  }
}

List<List<int>> _copyBoard(List<List<int>> b) =>
    b.map((r) => r.toList()).toList();

bool _isFull(List<List<int>> b) => b[0].every((c) => c != 0);

int _checkWinner(List<List<int>> b) {
  for (int r = 0; r < _rows; r++) {
    for (int c = 0; c < _cols; c++) {
      final p = b[r][c]; if (p == 0) continue;
      for (final d in [[0,1],[1,0],[1,1],[1,-1]]) {
        int count = 1;
        int nr = r+d[0], nc = c+d[1];
        while (nr>=0&&nr<_rows&&nc>=0&&nc<_cols&&b[nr][nc]==p) {
          count++; nr+=d[0]; nc+=d[1];
        }
        if (count >= 4) return p;
      }
    }
  }
  return 0;
}

int _score(List<List<int>> b, int piece) {
  int s = 0;
  for (int r = 0; r < _rows; r++) {
    if (b[r][3] == piece) s += 3;
  }
  for (int r = 0; r < _rows; r++) {
    for (int c = 0; c < _cols; c++) {
      for (final d in [[0,1],[1,0],[1,1],[1,-1]]) {
        final window = <int>[];
        for (int i = 0; i < 4; i++) {
          final nr = r+d[0]*i, nc = c+d[1]*i;
          if (nr>=0&&nr<_rows&&nc>=0&&nc<_cols) window.add(b[nr][nc]);
        }
        if (window.length == 4) s += _scoreWindow(window, piece);
      }
    }
  }
  return s;
}

int _scoreWindow(List<int> w, int piece) {
  final opp = piece == 1 ? 2 : 1;
  final pc = w.where((x) => x == piece).length;
  final ec = w.where((x) => x == 0).length;
  final oc = w.where((x) => x == opp).length;
  if (oc > 0) return 0;
  if (pc == 4) return 100;
  if (pc == 3 && ec == 1) return 5;
  if (pc == 2 && ec == 2) return 2;
  return 0;
}
