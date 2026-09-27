import '../../core/solo_ai.dart';

const _G = 10;

class SuderseeslachAI extends SoloAI {
  // Hunt/target state
  final _shots = <String>{};        // cells already shot: 'r,c'
  List<List<int>> _targets = [];    // known hit cells to finish off

  SuderseeslachAI(super.difficulty);

  /// Place AI ships randomly. Returns list of [row, col, horiz] per ship,
  /// matching the ship lengths in [shipLengths].
  List<List<dynamic>> placeShips(List<int> shipLengths) {
    final placed = <List<dynamic>>[];
    final occupied = <String>{};

    for (final len in shipLengths) {
      while (true) {
        final horiz = rng.nextBool();
        final maxRow = horiz ? _G : _G - len;
        final maxCol = horiz ? _G - len : _G;
        final row = rng.nextInt(maxRow);
        final col = rng.nextInt(maxCol);

        final cells = List.generate(len, (i) => horiz ? '$row,${col+i}' : '${row+i},$col');
        if (cells.any((c) => occupied.contains(c))) continue;
        occupied.addAll(cells);
        placed.add([row, col, horiz]);
        break;
      }
    }
    return placed;
  }

  /// Pick the next cell to fire at. Returns [row, col].
  List<int> pickShot() {
    if (_targets.isNotEmpty) {
      return _targetShot();
    }
    return _huntShot();
  }

  List<int> _huntShot() {
    // Parity hunt on hard: only shoot even-sum cells (checkerboard — minimum cells needed)
    final useCheckerboard = difficulty == SoloDifficulty.hard;
    final candidates = <List<int>>[];
    for (int r = 0; r < _G; r++) {
      for (int c = 0; c < _G; c++) {
        if (_shots.contains('$r,$c')) continue;
        if (useCheckerboard && (r + c) % 2 != 0) continue;
        candidates.add([r, c]);
      }
    }
    if (candidates.isEmpty) {
      // Fall back to any unshot cell
      for (int r = 0; r < _G; r++) {
        for (int c = 0; c < _G; c++) {
          if (!_shots.contains('$r,$c')) return [r, c];
        }
      }
      return [-1, -1]; // every cell shot — caller falls back to its own grid
    }
    return candidates[rng.nextInt(candidates.length)];
  }

  List<int> _targetShot() {
    // Try to extend in a line from known hits
    if (_targets.length >= 2) {
      // Determine direction from first two hits
      final dr = _targets[1][0] - _targets[0][0];
      final dc = _targets[1][1] - _targets[0][1];
      // Try both ends of the line
      for (final end in [_targets.last, _targets.first]) {
        final nr = end[0] + (end == _targets.last ? dr : -dr);
        final nc = end[1] + (end == _targets.last ? dc : -dc);
        if (_inBounds(nr, nc) && !_shots.contains('$nr,$nc')) return [nr, nc];
      }
    }

    // Only one hit: try adjacent cells
    final hit = _targets[0];
    const dirs = [[-1,0],[1,0],[0,-1],[0,1]];
    for (final d in dirs) {
      final nr = hit[0]+d[0], nc = hit[1]+d[1];
      if (_inBounds(nr, nc) && !_shots.contains('$nr,$nc')) return [nr, nc];
    }

    // No good adjacent — clear targets and hunt
    _targets.clear();
    return _huntShot();
  }

  /// Register the result of a shot.
  void registerResult(int r, int c, bool hit, bool sunk) {
    _shots.add('$r,$c');
    if (hit && !sunk) {
      _targets.add([r, c]);
    } else if (sunk) {
      _targets.clear(); // Ship sunk — back to hunt mode
    }
  }

  void reset() {
    _shots.clear();
    _targets.clear();
  }

  bool _inBounds(int r, int c) => r >= 0 && r < _G && c >= 0 && c < _G;
}
