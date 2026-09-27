import '../../core/solo_ai.dart';

class PaddelduelAI extends SoloAI {
  PaddelduelAI(super.difficulty);

  /// Tuning below is expressed per fixed step of [_stepDt] seconds (60 Hz), so
  /// the AI behaves identically on 60/90/120 Hz displays.
  static const double _stepDt = 1 / 60;
  double _acc = 0;

  /// Called every physics tick by host. Returns the Y position the AI paddle
  /// should move toward (0..1 normalised).
  /// [ballY]   current ball Y (0..1)
  /// [ballVx]  ball horizontal velocity (positive = moving toward AI)
  /// [rpy]     current right-paddle Y (0..1)  — AI controls right paddle
  /// [dt]      elapsed time since the previous call, in seconds
  /// [minY]/[maxY] paddle-centre limits (same as the human paddle)
  double computePaddleY(double ballY, double ballVx, double rpy, double dt,
      {double minY = 0.10, double maxY = 0.90}) {
    _acc += dt;
    // Advance in fixed 60 Hz steps (max 6 per call to avoid spiral after stalls)
    int steps = 0;
    while (_acc >= _stepDt && steps < 6) {
      _acc -= _stepDt;
      steps++;
      rpy = _step(ballY, ballVx, rpy, minY, maxY);
    }
    if (steps == 6) _acc = 0;
    return rpy;
  }

  double _step(double ballY, double ballVx, double rpy, double minY, double maxY) {
    final ballApproaching = ballVx > 0;

    // Miss rate: probability per 60 Hz step of ignoring the ball
    final missRate = switch (difficulty) {
      SoloDifficulty.easy   => ballApproaching ? 0.55 : 0.85,
      SoloDifficulty.medium => ballApproaching ? 0.25 : 0.70,
      SoloDifficulty.hard   => ballApproaching ? 0.06 : 0.35,
    };

    if (rng.nextDouble() < missRate) {
      // Drift slowly toward centre instead of tracking ball
      return (rpy + (0.5 - rpy) * 0.012).clamp(minY, maxY).toDouble();
    }

    // Max speed the AI paddle can move per 60 Hz step
    final speed = switch (difficulty) {
      SoloDifficulty.easy   => 0.007,
      SoloDifficulty.medium => 0.013,
      SoloDifficulty.hard   => 0.025,
    };

    // Tracking inaccuracy — aim slightly off from ball position
    final offset = switch (difficulty) {
      SoloDifficulty.easy   => (rng.nextDouble() - 0.5) * 0.12,
      SoloDifficulty.medium => (rng.nextDouble() - 0.5) * 0.05,
      SoloDifficulty.hard   => (rng.nextDouble() - 0.5) * 0.02,
    };

    final target = ballY + offset;
    final diff = target - rpy;
    final step = diff.abs() < speed ? diff : (diff > 0 ? speed : -speed);
    return (rpy + step).clamp(minY, maxY).toDouble();
  }
}
