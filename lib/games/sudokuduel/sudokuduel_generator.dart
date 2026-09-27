import 'dart:isolate';
import 'dart:math' as math;

/// A complete Sudoku solution + a puzzle (with holes).
class SudokuPuzzle {
  final List<List<int>> solution;
  final List<List<int>> puzzle;
  SudokuPuzzle(this.solution, this.puzzle);

  Map<String, dynamic> toJson() => {
    'sol': solution.map((r) => r.toList()).toList(),
    'puz': puzzle.map((r) => r.toList()).toList(),
  };

  factory SudokuPuzzle.fromJson(Map<String, dynamic> j) => SudokuPuzzle(
    (j['sol'] as List).map((r) => List<int>.from(r as List)).toList(),
    (j['puz'] as List).map((r) => List<int>.from(r as List)).toList(),
  );
}

/// Generate a puzzle in a background Isolate — never blocks the UI thread.
Future<SudokuPuzzle> generatePuzzleAsync({int holes = 46}) async {
  return await Isolate.run(() => _generateSync(holes));
}

// ── Internal (runs inside isolate) ───────────────────────────────────────────
SudokuPuzzle _generateSync(int holes) {
  final rng = math.Random();
  final sol  = _makeFullGrid(rng);
  final puz  = _punchHoles(sol, holes, rng);
  return SudokuPuzzle(sol, puz);
}

List<List<int>> _makeFullGrid(math.Random rng) {
  final g = List.generate(9, (_) => List.filled(9, 0));
  _fill(g, rng);
  return g;
}

bool _fill(List<List<int>> g, math.Random rng) {
  for (int r = 0; r < 9; r++) {
    for (int c = 0; c < 9; c++) {
      if (g[r][c] != 0) continue;
      final nums = List.generate(9, (i) => i + 1)..shuffle(rng);
      for (final n in nums) {
        if (_ok(g, r, c, n)) {
          g[r][c] = n;
          if (_fill(g, rng)) return true;
          g[r][c] = 0;
        }
      }
      return false;
    }
  }
  return true;
}

bool _ok(List<List<int>> g, int row, int col, int n) {
  if (g[row].contains(n)) return false;
  for (int r = 0; r < 9; r++) { if (g[r][col] == n) return false; }
  final br = (row ~/ 3) * 3, bc = (col ~/ 3) * 3;
  for (int r = br; r < br + 3; r++)
    for (int c = bc; c < bc + 3; c++)
      if (g[r][c] == n) return false;
  return true;
}

List<List<int>> _punchHoles(List<List<int>> sol, int holes, math.Random rng) {
  final puz   = sol.map((r) => r.toList()).toList();
  final cells = List.generate(81, (i) => i)..shuffle(rng);
  int removed = 0;
  for (final idx in cells) {
    if (removed >= holes) break;
    final r = idx ~/ 9, c = idx % 9;
    final backup = puz[r][c];
    puz[r][c] = 0;
    // Keep if still uniquely solvable
    if (_countSolutions(puz, 0) == 1) {
      removed++;
    } else {
      puz[r][c] = backup; // restore — would break uniqueness
    }
  }
  return puz;
}

/// Count solutions up to limit 2 (we only need to know if it's 0, 1, or 2+).
int _countSolutions(List<List<int>> g, int count) {
  for (int r = 0; r < 9; r++) {
    for (int c = 0; c < 9; c++) {
      if (g[r][c] != 0) continue;
      for (int n = 1; n <= 9; n++) {
        if (_ok(g, r, c, n)) {
          g[r][c] = n;
          count = _countSolutions(g, count);
          g[r][c] = 0;
          if (count >= 2) return count;
        }
      }
      return count;
    }
  }
  return count + 1; // fully filled = one solution found
}
