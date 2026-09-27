import 'dart:isolate';
import 'dart:math' as math;
import '../../core/solo_ai.dart';

const _N = 5; // must match puntenenfakjes_screen.dart

class PuntenEnFakjesAI extends SoloAI {
  PuntenEnFakjesAI(super.difficulty);

  void takeTurn({
    required List<List<int>> hLines,
    required List<List<int>> vLines,
    required int player,
  }) {
    scheduleMove(() async {
      final input = <String, dynamic>{
        'hLines': hLines.map((r) => r.toList()).toList(),
        'vLines': vLines.map((r) => r.toList()).toList(),
        'player': player,
        'difficulty': difficulty.index,
        'seed': rng.nextInt(0x7FFFFFFF),
      };

      Map<String, dynamic>? result;
      try {
        result = await Isolate.run(() => _computePuntenEnFakjesMove(input))
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        result = _computePuntenEnFakjesMove(input);
      }

      if (result == null) return;
      net.injectMessage('PUN_LINE', {
        'h': result['h'], 'r': result['r'], 'c': result['c'], 'p': player,
      });
    });
  }
}

// ── Top-level types and compute function for Isolate ─────────────────────

class _Line {
  final bool horiz;
  final int row, col;
  const _Line(this.horiz, this.row, this.col);
}

Map<String, dynamic>? _computePuntenEnFakjesMove(Map<String, dynamic> input) {
  final rawH = input['hLines'] as List;
  final rawV = input['vLines'] as List;
  final h = rawH.map((r) => List<int>.from(r as List)).toList();
  final v = rawV.map((r) => List<int>.from(r as List)).toList();
  final diffIdx = input['difficulty'] as int;
  final seed = input['seed'] as int;
  final rng = math.Random(seed);
  final difficulty = SoloDifficulty.values[diffIdx];

  final move = _pickMove(h, v, difficulty, rng);
  if (move == null) return null;
  return {'h': move.horiz, 'r': move.row, 'c': move.col};
}

_Line? _pickMove(List<List<int>> h, List<List<int>> v,
    SoloDifficulty difficulty, math.Random rng) {
  final all = _allFree(h, v);
  if (all.isEmpty) return null;
  if (difficulty == SoloDifficulty.easy) return all[rng.nextInt(all.length)];

  // 1) Take any move that immediately completes a box
  for (final line in all) {
    final copy = _clone(h, v);
    _place(copy.$1, copy.$2, line);
    if (_countClaimed(copy.$1, copy.$2) > _countClaimed(h, v)) return line;
  }

  if (difficulty == SoloDifficulty.medium) {
    final safe = all.where((line) {
      final copy = _clone(h, v);
      _place(copy.$1, copy.$2, line);
      return !_hasThreeSided(copy.$1, copy.$2);
    }).toList();
    if (safe.isNotEmpty) return safe[rng.nextInt(safe.length)];
    return all[rng.nextInt(all.length)];
  }

  // Hard: full chain analysis
  final safe = all.where((line) {
    final copy = _clone(h, v);
    _place(copy.$1, copy.$2, line);
    return !_hasThreeSided(copy.$1, copy.$2);
  }).toList();

  if (safe.isNotEmpty) {
    final twoSide = safe.where((line) {
      final copy = _clone(h, v);
      _place(copy.$1, copy.$2, line);
      return _hasTwoSided(copy.$1, copy.$2);
    }).toList();
    final pool = twoSide.isNotEmpty ? twoSide : safe;
    return pool[rng.nextInt(pool.length)];
  }

  int bestGive = 999;
  _Line? bestMove;
  for (final line in all) {
    final copy = _clone(h, v);
    _place(copy.$1, copy.$2, line);
    final give = _countThreeSided(copy.$1, copy.$2);
    if (give < bestGive) { bestGive = give; bestMove = line; }
  }
  return bestMove ?? all[rng.nextInt(all.length)];
}

List<_Line> _allFree(List<List<int>> h, List<List<int>> v) {
  final lines = <_Line>[];
  for (int r = 0; r <= _N; r++) {
    for (int c = 0; c < _N; c++) {
      if (h[r][c] == 0) lines.add(_Line(true, r, c));
    }
  }
  for (int r = 0; r < _N; r++) {
    for (int c = 0; c <= _N; c++) {
      if (v[r][c] == 0) lines.add(_Line(false, r, c));
    }
  }
  return lines;
}

void _place(List<List<int>> h, List<List<int>> v, _Line line) {
  if (line.horiz) h[line.row][line.col] = 1;
  else            v[line.row][line.col] = 1;
}

(List<List<int>>, List<List<int>>) _clone(List<List<int>> h, List<List<int>> v) =>
  (h.map((r) => r.toList()).toList(), v.map((r) => r.toList()).toList());

int _sidesOf(List<List<int>> h, List<List<int>> v, int r, int c) {
  int s = 0;
  if (h[r][c] != 0)   s++;
  if (h[r+1][c] != 0) s++;
  if (v[r][c] != 0)   s++;
  if (v[r][c+1] != 0) s++;
  return s;
}

bool _hasThreeSided(List<List<int>> h, List<List<int>> v) {
  for (int r = 0; r < _N; r++) {
    for (int c = 0; c < _N; c++) {
      if (_sidesOf(h, v, r, c) == 3) return true;
    }
  }
  return false;
}

bool _hasTwoSided(List<List<int>> h, List<List<int>> v) {
  for (int r = 0; r < _N; r++) {
    for (int c = 0; c < _N; c++) {
      if (_sidesOf(h, v, r, c) == 2) return true;
    }
  }
  return false;
}

int _countThreeSided(List<List<int>> h, List<List<int>> v) {
  int count = 0;
  for (int r = 0; r < _N; r++) {
    for (int c = 0; c < _N; c++) {
      if (_sidesOf(h, v, r, c) == 3) count++;
    }
  }
  return count;
}

int _countClaimed(List<List<int>> h, List<List<int>> v) {
  int count = 0;
  for (int r = 0; r < _N; r++) {
    for (int c = 0; c < _N; c++) {
      if (_sidesOf(h, v, r, c) == 4) count++;
    }
  }
  return count;
}
