import 'dart:async';
import '../../core/solo_ai.dart';

class UnthaldspultsjeAI extends SoloAI {
  /// Cards the AI has "seen" and remembers: index → symbol
  final _memory = <int, String>{};

  UnthaldspultsjeAI(super.difficulty);

  /// Called when a card is revealed (by either player) so AI can memorise it.
  void observe(int idx, String symbol) {
    final forgetRate = switch (difficulty) {
      SoloDifficulty.easy   => 0.80,
      SoloDifficulty.medium => 0.40,
      SoloDifficulty.hard   => 0.0,
    };
    if (rng.nextDouble() >= forgetRate) {
      _memory[idx] = symbol;
    }
  }

  /// Called when it's AI's turn to flip a card.
  /// [symbols]  full symbol list (only visible after reveal in game, but AI tracks via observe)
  /// [matched]  which cards are already matched
  /// [flipped]  currently flipped (first card if AI is on second pick)
  /// [firstIdx] the index of the first flipped card (-1 if AI picks first card)
  ///
  /// Returns the index to flip, or -1 if no valid move.
  int pickCard({
    required List<String> symbols,
    required List<bool> matched,
    required List<bool> flipped,
    required int firstIdx,
  }) {
    final available = [
      for (int i = 0; i < symbols.length; i++)
        if (!matched[i] && !flipped[i]) i
    ];
    if (available.isEmpty) return -1;

    if (firstIdx == -1) {
      // Picking first card: look for a known match pair
      for (final i in available) {
        if (!_memory.containsKey(i)) continue;
        final sym = _memory[i]!;
        // Is there another card with the same symbol in pairs?
        final partner = available.firstWhere(
          (j) => j != i && _memory[j] == sym,
          orElse: () => -1,
        );
        if (partner != -1) return i; // Found a known pair — play it
      }
      // No known pair, pick randomly
      return available[rng.nextInt(available.length)];
    } else {
      // Picking second card: try to match firstIdx
      final target = symbols[firstIdx];
      // Check pairs for a partner
      final knownMatch = available.firstWhere(
        (i) => _memory[i] == target,
        orElse: () => -1,
      );
      if (knownMatch != -1) return knownMatch;
      // No known match — pick randomly from unflipped, excluding first
      final rest = available.where((i) => i != firstIdx).toList();
      return rest.isEmpty ? -1 : rest[rng.nextInt(rest.length)];
    }
  }

  /// Forget everything (call on game reset)
  void reset() => _memory.clear();

  /// Schedule the AI's two-card turn with natural delays.
  /// Calls [onFirstPick] then [onSecondPick] with chosen indices.
  void takeTurn({
    required List<String> symbols,
    required List<bool> matched,
    required List<bool> flipped,
    required void Function(int idx) onFirstPick,
    required void Function(int idx) onSecondPick,
  }) {
    final first = pickCard(
      symbols: symbols, matched: matched, flipped: flipped, firstIdx: -1);
    if (first == -1) return;

    final delay = thinkDelay;
    Future.delayed(delay, () {
      onFirstPick(first);
      // Second pick after a brief pause
      Future.delayed(const Duration(milliseconds: 700), () {
        final second = pickCard(
          symbols: symbols, matched: matched,
          flipped: [...flipped]..[first] = true,
          firstIdx: first);
        if (second == -1) return;
        onSecondPick(second);
      });
    });
  }
}
