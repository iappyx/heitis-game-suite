import 'dart:async';
import 'dart:math' as math;
import 'network.dart';
import '../screens/solo_setup_screen.dart';

export '../screens/solo_setup_screen.dart' show SoloDifficulty;

/// Base class for all AI opponents.
/// Call [scheduleMove] after any state change where it becomes the AI's turn.
/// The AI calls [net.injectMessage] to deliver its chosen move.
abstract class SoloAI {
  final Network net = Network();
  final SoloDifficulty difficulty;
  final math.Random rng = math.Random();
  bool _pending = false;
  int _generation = 0; // bumped by cancel() — stale delayed moves are dropped
  int playerIdx = 1; // set by the screen after construction

  SoloAI(this.difficulty);

  /// Delay before the AI "thinks" — feels more natural.
  Duration get thinkDelay {
    final ms = 500 + rng.nextInt(400); // 500–900ms
    return Duration(milliseconds: ms);
  }

  /// Call this whenever it becomes the AI's turn.
  /// Guards against double-scheduling.
  /// Accepts both synchronous and asynchronous compute functions.
  void scheduleMove(FutureOr<void> Function() computeAndInject) {
    if (_pending) return;
    _pending = true;
    final gen = _generation;
    Future.delayed(thinkDelay, () async {
      if (gen != _generation) return; // cancelled while waiting
      _pending = false;
      try {
        await computeAndInject();
      } catch (e, st) {
        // ignore — AI move failed silently; game remains playable
        // ignore: avoid_print
        print('[SoloAI] scheduleMove error: $e\n$st');
      }
    });
  }

  /// Drops any pending move so it never fires (call on dispose/reset).
  void cancel() {
    _pending = false;
    _generation++;
  }
}
