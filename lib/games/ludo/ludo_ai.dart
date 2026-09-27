import '../../core/solo_ai.dart';

// Mirror constants from ludo_screen.dart (can't import directly without cycle)
const _kPosNest   = -1;
const _kHomeStart = 40;
const _kHomeEnd   = 43;
// Ludo AI — uses the same greedy strategy as real players:
//   1. If a 6 is rolled and a piece is in nest, enter it
//   2. Capture an opponent piece if possible
//   3. Move piece closest to home
//   4. Move furthest-back piece (spread risk)
class LudoAI extends SoloAI {
  LudoAI(super.difficulty);

  void takeTurn({
    required int slot,
    required int roll,
    required bool rolled,
    required bool canPass,
    required List<List<int>> pieces,
    required List<int> slots,
  }) {
    scheduleMove(() {
      if (!rolled) {
        // Need to roll
        net.injectMessage('LUD_ROLL', {});
        return;
      }

      // Compute valid moves
      final valid = <int>[];
      for (int pi = 0; pi < 4; pi++) {
        if (_canMove(slot, pi, roll, pieces)) valid.add(pi);
      }

      if (valid.isEmpty) {
        // No moves — must pass
        net.injectMessage('LUD_PASS', {});
        return;
      }

      final pi = _choosePiece(slot, roll, valid, pieces, slots);
      net.injectMessage('LUD_MOVE', {'slot': slot, 'pi': pi});
    });
  }

  int _choosePiece(int slot, int roll,
      List<int> valid, List<List<int>> pieces, List<int> slots) {
    // HARD: score each move and pick best
    // MEDIUM: capture if possible, else advance best
    // EASY: random
    if (difficulty == SoloDifficulty.easy) {
      return valid[rng.nextInt(valid.length)];
    }

    int? captureMove;
    int? exitNestMove;
    int bestAdvance = -1;
    int bestAdvancePi = valid.first;
    int farthestBack = 99999;
    int farthestBackPi = valid.first;

    for (final pi in valid) {
      final pos = pieces[slot][pi];

      // Entering from nest → exit
      if (pos == _kPosNest) {
        exitNestMove = pi;
        continue;
      }

      // Skip pieces already in the home column for advance/capture scoring
      if (pos >= _kHomeStart) continue;

      final target = _computeTarget(slot, pos, roll);

      // Check if landing on opponent piece (capture)
      if (target < _kHomeStart) {
        for (final s in slots) {
          if (s == slot) continue;
          for (int p2 = 0; p2 < 4; p2++) {
            if (pieces[s][p2] == target) {
              captureMove = pi;
              break;
            }
          }
          if (captureMove != null) break;
        }
      }

      // Advance: pick piece with highest current position (closest to home)
      if (pos > bestAdvance) {
        bestAdvance   = pos;
        bestAdvancePi = pi;
      }
      // Farthest back (lowest pos on outer track)
      if (pos < farthestBack) {
        farthestBack   = pos;
        farthestBackPi = pi;
      }
    }

    if (difficulty == SoloDifficulty.hard) {
      // Priority: capture > advance to home > exit nest > advance furthest > spread
      if (captureMove != null) return captureMove;
      if (bestAdvance >= 35) return bestAdvancePi; // almost home
      if (exitNestMove != null) return exitNestMove;
      // Spread: if all pieces in nest, exit; else advance
      if (bestAdvance > 0) return bestAdvancePi;
      return farthestBackPi;
    } else {
      // Medium: capture > exit nest > advance
      if (captureMove != null) return captureMove;
      if (exitNestMove != null) return exitNestMove;
      return bestAdvancePi;
    }
  }
}

// Minimal _canMove clone (identical logic to ludo_screen.dart)
bool _canMove(int slot, int pi, int roll, List<List<int>> pieces) {
  final pos = pieces[slot][pi];
  if (pos == _kPosNest) return roll == 6;
  if (pos == _kHomeEnd) return false;
  final target = _computeTarget(slot, pos, roll);
  if (target == pos) return false;
  if (target >= _kHomeStart) {
    for (int p2 = 0; p2 < 4; p2++) {
      if (p2 != pi && pieces[slot][p2] == target) return false;
    }
  }
  return true;
}

const _kTurnOff = [39, 9, 19, 29];

int _computeTarget(int slot, int pos, int steps) {
  int cur = pos;
  for (int s = 0; s < steps; s++) {
    if (cur >= _kHomeStart) {
      cur++;
      if (cur > _kHomeEnd) cur = _kHomeEnd - (cur - _kHomeEnd);
    } else if (cur == _kTurnOff[slot]) {
      cur = _kHomeStart;
    } else {
      cur = (cur + 1) % 40;
    }
  }
  return cur;
}
