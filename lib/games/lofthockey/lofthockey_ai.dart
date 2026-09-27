import 'dart:math' as math;
import '../../core/solo_ai.dart';

/// AI plays the TOP mallet (y=0 side, goal at top).
///
/// Strategy — pyramid defense with active striking:
/// • **Defend**: position on the line between puck and goal centre,
///   adapting Y depth based on puck distance. Predicts wall bounces.
/// • **Strike**: when puck is slow in AI's half, approach from behind
///   and push toward opponent's goal at an angle.
/// • **Retreat**: when puck is in opponent's half, drift to centre-back
///   ready to react.
class LofthockeyAI extends SoloAI {
  LofthockeyAI(super.difficulty);

  double _reactionTimer = 0;
  double _targetX = 0.5;
  double _targetY = 0.15;
  bool _striking = false;
  bool _behindPuck = false; // positioning behind puck before striking

  ({double x, double y}) computeMallet(
    double puckX, double puckY,
    double puckVX, double puckVY,
    double malletX, double malletY,
    double dt,
  ) {
    final speed = switch (difficulty) {
      SoloDifficulty.easy   => 0.30,
      SoloDifficulty.medium => 0.55,
      SoloDifficulty.hard   => 1.2,
    };

    final reactionDelay = switch (difficulty) {
      SoloDifficulty.easy   => 0.35,
      SoloDifficulty.medium => 0.15,
      SoloDifficulty.hard   => 0.06,
    };

    final inaccuracy = switch (difficulty) {
      SoloDifficulty.easy   => 0.16,
      SoloDifficulty.medium => 0.05,
      SoloDifficulty.hard   => 0.01,
    };

    final missChance = switch (difficulty) {
      SoloDifficulty.easy   => 0.35,
      SoloDifficulty.medium => 0.08,
      SoloDifficulty.hard   => 0.01,
    };

    // Dynamic defense depth range per difficulty
    final defenseNear = switch (difficulty) {
      SoloDifficulty.easy   => 0.10,
      SoloDifficulty.medium => 0.08,
      SoloDifficulty.hard   => 0.06,
    };
    final defenseFar = switch (difficulty) {
      SoloDifficulty.easy   => 0.25,
      SoloDifficulty.medium => 0.35,
      SoloDifficulty.hard   => 0.40,
    };

    final useWallPrediction = difficulty != SoloDifficulty.easy;
    final strikeChance = switch (difficulty) {
      SoloDifficulty.easy   => 0.15,
      SoloDifficulty.medium => 0.50,
      SoloDifficulty.hard   => 0.85,
    };

    _reactionTimer -= dt;

    if (_reactionTimer <= 0) {
      _reactionTimer = reactionDelay;

      final puckSpeed = math.sqrt(puckVX * puckVX + puckVY * puckVY);
      final puckApproaching = puckVY < -0.05;
      final puckInMyHalf = puckY < 0.5;
      final puckSlow = puckSpeed < 0.15;

      if (rng.nextDouble() < missChance) {
        // Intentional miss — drift to centre
        _targetX = 0.5;
        _targetY = defenseNear + 0.04;
        _striking = false;
        _behindPuck = false;
      } else if (puckApproaching && puckInMyHalf) {
        // ── DEFEND: pyramid defense ──
        // Position on the line between puck and goal centre (0.5, 0.0)
        // Y adapts: closer to goal when puck is far, further out when close
        final depth = puckY < 0.3
            ? defenseFar  // puck is close — step out to meet it
            : defenseNear + (defenseFar - defenseNear) * (1.0 - puckY / 0.5);
        _targetY = depth;

        // Predict where puck will cross our defense Y, including wall bounces
        double interceptX;
        if (useWallPrediction) {
          interceptX = _predictX(puckX, puckY, puckVX, puckVY, depth);
        } else {
          final timeToLine = (puckY - depth).abs() / (puckVY.abs() + 0.01);
          interceptX = puckX + puckVX * timeToLine;
        }

        // Pyramid: bias toward goal centre line
        final pyramidX = interceptX * 0.7 + 0.5 * 0.3;
        _targetX = (pyramidX + (rng.nextDouble() - 0.5) * inaccuracy)
            .clamp(0.08, 0.92);
        _striking = false;
        _behindPuck = false;
      } else if (puckInMyHalf && puckSlow && rng.nextDouble() < strikeChance) {
        // ── STRIKE: puck is slow — push it away ──
        if (!_striking && !_behindPuck) {
          // Step 1: get behind the puck (between puck and own goal)
          _targetX = puckX + (rng.nextDouble() - 0.5) * 0.06;
          _targetY = (puckY - 0.10).clamp(0.05, 0.40);
          _behindPuck = true;
          _striking = false;
        } else if (_behindPuck && (malletY < puckY - 0.04 || (malletY - puckY).abs() < 0.03)) {
          // Step 2: behind the puck — now strike through it at an angle
          final angleOffset = (rng.nextDouble() - 0.5) * 0.15;
          _targetX = (puckX + angleOffset).clamp(0.08, 0.92);
          _targetY = (puckY + 0.20).clamp(0.10, 0.45);
          _striking = true;
          _behindPuck = false;
        }
      } else if (puckInMyHalf) {
        // Puck in my half but moving sideways or away — track it
        final interceptX = useWallPrediction
            ? _predictX(puckX, puckY, puckVX, puckVY, defenseNear + 0.05)
            : puckX;
        _targetX = (interceptX + (rng.nextDouble() - 0.5) * inaccuracy)
            .clamp(0.08, 0.92);
        _targetY = defenseNear + 0.05;
        _striking = false;
        _behindPuck = false;
      } else {
        // ── RETREAT: puck in opponent's half — drift to centre-back ──
        _targetX = 0.5 + (rng.nextDouble() - 0.5) * 0.10; // slight wobble
        _targetY = defenseNear + 0.02;
        _striking = false;
        _behindPuck = false;
      }
    }

    // Move toward target
    final dx = _targetX - malletX;
    final dy = _targetY - malletY;
    final dist = math.sqrt(dx * dx + dy * dy);
    final moveSpeed = _striking ? speed * 1.5 : speed;
    final maxStep = moveSpeed * dt;

    double newX, newY;
    if (dist <= maxStep) {
      newX = _targetX;
      newY = _targetY;
      if (_striking) _striking = false;
    } else {
      newX = malletX + dx / dist * maxStep;
      newY = malletY + dy / dist * maxStep;
    }

    return (
      x: newX.clamp(0.05, 0.95),
      y: newY.clamp(0.05, 0.45),
    );
  }

  /// Predict where puck will be at [targetY], accounting for wall bounces.
  double _predictX(double px, double py, double pvx, double pvy, double targetY) {
    if (pvy.abs() < 0.01) return px;
    final t = (targetY - py) / pvy;
    if (t < 0) return px; // puck moving away
    var futureX = px + pvx * t;
    // Reflect off side walls (0..1 range)
    while (futureX < 0 || futureX > 1) {
      if (futureX < 0) futureX = -futureX;
      if (futureX > 1) futureX = 2.0 - futureX;
    }
    return futureX.clamp(0.08, 0.92);
  }
}
