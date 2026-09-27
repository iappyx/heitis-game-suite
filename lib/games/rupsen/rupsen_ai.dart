import '../../core/solo_ai.dart';
import 'rupsen_state.dart';

/// AI for Rupsen. Each call to [act] performs exactly ONE action then returns.
/// The screen calls [act] after every state broadcast when it's the AI's turn.
class RupsenAI extends SoloAI {
  RupsenAI(super.difficulty);

  int get _threshold => switch (difficulty) {
    SoloDifficulty.easy   => 14,
    SoloDifficulty.medium => 20,
    SoloDifficulty.hard   => 26,
  };

  void act(RupsenState state) {
    scheduleMove(() => _oneAction(state));
  }

  void _oneAction(RupsenState state) {
    final from = playerIdx;

    // Turn is over — inject RUP_NEXT to advance to next player
    if (state.phase == RupsenPhase.busted || state.phase == RupsenPhase.claimed) {
      net.injectMessage('RUP_NEXT', {}, from);
      return;
    }

    // needsSetAside=false → roll
    if (!state.needsSetAside) {
      net.injectMessage('RUP_ROLL', {}, from);
      return;
    }

    // Busted (no faces to set aside)
    if (state.isBusted()) return; // _executeRoll already set phase=busted; next act() injects RUP_NEXT

    // Set aside best face
    if (state.availableFaces.isNotEmpty) {
      final face = _chooseFace(state);
      net.injectMessage('RUP_ASIDE', {'face': face}, from);
      return;
    }
  }

  /// Called by screen after RUP_ASIDE is processed. Decides: claim or roll?
  void decideAfterAside(RupsenState state) {
    scheduleMove(() {
      if (state.phase != RupsenPhase.rolling) return;
      final from = playerIdx;
      final canRoll = state.freeDiceCount > 0 &&
                      state.usedFaces.length < 6 &&
                      !state.needsSetAside;
      if (canRoll && !(state.canClaim && state.turnScore >= _threshold)) {
        net.injectMessage('RUP_ROLL', {}, from);
      } else {
        // Claim (a stuck turn without a claim was already auto-busted by the host)
        net.injectMessage('RUP_CLAIM', {}, from);
      }
    });
  }

  int _chooseFace(RupsenState state) {
    final faces = state.availableFaces;
    if (faces.contains(kRupsFace) && !state.hasRups) return kRupsFace;
    if (faces.contains(kRupsFace) && state.turnScore > _threshold ~/ 2) return kRupsFace;
    return faces.reduce((a, b) =>
      _faceScore(state, a) >= _faceScore(state, b) ? a : b);
  }

  int _faceScore(RupsenState state, int face) {
    int count = 0;
    for (int i = 0; i < 8; i++) {
      if (!state.held[i] && state.dice[i] == face) count++;
    }
    return count * faceScore(face);
  }
}
