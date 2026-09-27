import '../../core/solo_ai.dart';

/// AI opponent for Ien-en-tritich (Thirty-One).
///
/// Called by the game screen when it is a CPU player's turn.
/// The AI evaluates possible swaps and decides whether to swap 1 card,
/// swap all 3, or knock.
class IenEnTritichAI extends SoloAI {
  IenEnTritichAI(super.difficulty);

  /// Take a turn for the given [aiIdx] player.
  ///
  /// [hand] and [center] are encoded as list of {suit, rank} maps.
  /// [currentScore] is the AI's current hand score.
  /// [canKnock] is false if someone already knocked this round.
  int _turnsWithoutImprovement = 0;

  void resetRound() => _turnsWithoutImprovement = 0;

  void takeTurn({
    required int aiIdx,
    required List<Map<String, int>> hand,
    required List<Map<String, int>> center,
    required double currentScore,
    required bool canKnock,
    bool humanEliminated = false,
  }) {
    scheduleMove(() {
      final result = _decide(hand, center, currentScore, canKnock, humanEliminated);
      final action = result.$1;
      final hIdx = result.$2;
      final cIdx = result.$3;

      // Track if we're just spinning wheels
      if (action != _AiActionType.knock) {
        _turnsWithoutImprovement++;
      }

      switch (action) {
        case _AiActionType.knock:
          _turnsWithoutImprovement = 0;
          net.injectMessage('IEN_KNOCK', {'idx': aiIdx}, aiIdx);
        case _AiActionType.pass:
          net.injectMessage('IEN_PASS', {'idx': aiIdx}, aiIdx);
        case _AiActionType.swapAll:
          net.injectMessage('IEN_SWAP3', {'idx': aiIdx}, aiIdx);
        case _AiActionType.swap1:
          net.injectMessage('IEN_SWAP1', {
            'idx': aiIdx,
            'handIdx': hIdx,
            'centerIdx': cIdx,
          }, aiIdx);
      }
    });
  }

  /// Returns (action, handIdx, centerIdx). handIdx/centerIdx only used for swap1.
  (_AiActionType, int, int) _decide(
    List<Map<String, int>> hand,
    List<Map<String, int>> center,
    double currentScore,
    bool canKnock,
    bool humanEliminated,
  ) {
    // Knock thresholds by difficulty
    final knockThreshold = switch (difficulty) {
      SoloDifficulty.easy   => 25.0,
      SoloDifficulty.medium => 27.0,
      SoloDifficulty.hard   => 29.0,
    };

    // Evaluate all single swaps (3 hand x 3 center = 9 options)
    double bestSwap1Score = currentScore;
    int bestHandIdx = 0;
    int bestCenterIdx = 0;

    for (int h = 0; h < 3; h++) {
      for (int c = 0; c < 3; c++) {
        // Simulate swap
        final simHand = List<Map<String, int>>.from(hand);
        simHand[h] = center[c];
        final score = _calcScore(simHand);
        if (score > bestSwap1Score) {
          bestSwap1Score = score;
          bestHandIdx = h;
          bestCenterIdx = c;
        }
      }
    }

    // Evaluate swap-all
    final swapAllScore = _calcScore(center);

    // Easy: add some randomness — occasionally make suboptimal choices
    if (difficulty == SoloDifficulty.easy && rng.nextDouble() < 0.3) {
      final r = rng.nextInt(3);
      if (r == 0 && canKnock && currentScore >= 20) {
        return (_AiActionType.knock, 0, 0);
      } else if (r == 1) {
        return (_AiActionType.swapAll, 0, 0);
      } else {
        return (_AiActionType.swap1, rng.nextInt(3), rng.nextInt(3));
      }
    }

    // If we got 31, no need to do anything special — the game detects it
    if (bestSwap1Score >= 31) {
      return (_AiActionType.swap1, bestHandIdx, bestCenterIdx);
    }

    // If swap-all is significantly better than current and best single swap
    if (swapAllScore > currentScore + 5 && swapAllScore > bestSwap1Score) {
      return (_AiActionType.swapAll, 0, 0);
    }

    // If a single swap improves the score
    if (bestSwap1Score > currentScore) {
      return (_AiActionType.swap1, bestHandIdx, bestCenterIdx);
    }

    // No improvement — knock if score is above threshold
    if (canKnock && currentScore >= knockThreshold) {
      return (_AiActionType.knock, 0, 0);
    }

    // Force knock if stuck for too many turns AND no human players left
    // (prevents infinite CPU-only swapping loops)
    if (canKnock && _turnsWithoutImprovement >= 3 && humanEliminated) {
      return (_AiActionType.knock, 0, 0);
    }

    // No improvement possible — pass (keep hand as-is) if someone already knocked
    if (!canKnock) {
      // Someone already knocked — swap-all only if it's clearly better
      if (swapAllScore > currentScore + 3) {
        return (_AiActionType.swapAll, 0, 0);
      }
      return (_AiActionType.pass, 0, 0);
    }

    // Nobody knocked yet and we can't improve — do the least-harmful swap
    if (swapAllScore > currentScore) {
      return (_AiActionType.swapAll, 0, 0);
    }
    double leastLoss = double.infinity;
    int lhIdx = 0, lcIdx = 0;
    for (int h = 0; h < 3; h++) {
      for (int c = 0; c < 3; c++) {
        final simHand = List<Map<String, int>>.from(hand);
        simHand[h] = center[c];
        final loss = currentScore - _calcScore(simHand);
        if (loss < leastLoss) {
          leastLoss = loss;
          lhIdx = h;
          lcIdx = c;
        }
      }
    }
    return (_AiActionType.swap1, lhIdx, lcIdx);
  }

  static double _calcScore(List<Map<String, int>> hand) {
    // Check 3 of a kind
    if (hand[0]['rank'] == hand[1]['rank'] && hand[1]['rank'] == hand[2]['rank']) {
      return 30.5;
    }
    double best = 0;
    for (int s = 0; s < 4; s++) {
      double sum = 0;
      for (final c in hand) {
        if (c['suit'] == s) sum += _cardValue(c['rank']!);
      }
      if (sum > best) best = sum;
    }
    return best;
  }

  static int _cardValue(int rank) => rank == 1 ? 11 : rank >= 10 ? 10 : rank;
}

enum _AiActionType { knock, pass, swapAll, swap1 }
