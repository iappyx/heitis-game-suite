import 'package:flutter/material.dart';
import '../core/network.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../core/wake_lock.dart';
import '../screens/waiting_screen.dart';
import '../screens/solo_setup_screen.dart';
import '../core/player.dart';

/// Unified "Play Again / Game Select" bar shown at game-over across all games.
/// Host controls Play Again — broadcasts GAME_RESET; clients receive and call onReset.
/// Set [sendReset] to false if the onReset callback already sends GAME_RESET with its own payload.
///
/// In tournament mode (Network().isTournament == true):
///   Host  → "Record Result" button that pops back to TournamentScreen
///   Client → "Waiting for host…" label (TournamentScreen handles navigation via TOURNEY_RESULT)
class GameOverActions extends StatelessWidget {
  final List<Player> players;
  final VoidCallback onReset;   // called on BOTH host and joiner to reset state
  final bool sendReset;         // if true (default), sends bare GAME_RESET before onReset

  const GameOverActions({super.key, required this.players, required this.onReset, this.sendReset = true});

  // ── Last registered reset callback (used by REMATCH_REQ handling) ─────────
  // Only one game screen is active at a time, so a static is safe.
  // Accessed by GameMixin.handleCommonMessages for REMATCH_REQ.
  static VoidCallback? activeOnReset;
  static bool activeSendReset = true;

  static void handleMessage(Map<String, dynamic> msg, VoidCallback onReset) {
    final type = msg['type'] as String? ?? '';
    if (type == 'GAME_RESET') onReset();
    if (type == 'REMATCH_REQ' && Network().isHost) {
      if (activeSendReset) Network().send('GAME_RESET');
      onReset();
    }
  }

  @override Widget build(BuildContext context) {
    final net = Network();

    // ── Tournament mode ───────────────────────────────────────────────────────
    if (net.isTournament) {
      return Container(
        color: Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (net.isHost)
            ElevatedButton.icon(
              onPressed: () {
                WakeLock.release();
                Navigator.pop(context); // pops back to TournamentScreen; .then() fires result dialog
              },
              icon: const Text('🏆', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 16)),
              label: Text(L.common.recordResult),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
            )
          else
            Text(L.common.waitingForHostResult,
              style: const TextStyle(color: kMuted, fontStyle: FontStyle.italic, fontSize: 13)),
        ]),
      );
    }

    // ── Normal / Solo mode ────────────────────────────────────────────────────
    // Register the reset callback so REMATCH_REQ can trigger it from the mixin.
    activeOnReset = onReset;
    activeSendReset = sendReset;

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Both host and joiner see "Play Again" for quick rematch
        ElevatedButton.icon(
          onPressed: () {
            if (net.isHost) {
              if (sendReset) net.send('GAME_RESET');
              onReset();
            } else {
              // Joiner requests rematch — host will broadcast GAME_RESET
              net.send('REMATCH_REQ');
            }
          },
          icon: const Text('🔄', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 16)),
          label: Text(L.common.playAgain),
          style: ElevatedButton.styleFrom(
            backgroundColor: kPurple2, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: () async {
            WakeLock.release();
            net.currentGameInfo = null;
            if (net.isSolo) {
              // Solo: go back to game picker, keeping same human player
              final human = players[0];
              await net.reset();
              if (context.mounted) Navigator.pushAndRemoveUntil(context,
                fadeScaleRoute(SoloSetupScreen(humanPlayer: human)),
                (_) => false);
            } else {
              // Multiplayer: broadcast and go to WaitingScreen
              await net.sendAndFlush('BACK_TO_SELECT');
              await Future.delayed(const Duration(milliseconds: 100));
              if (context.mounted) Navigator.pushAndRemoveUntil(context,
                fadeScaleRoute(
                  WaitingScreen(players: players, isHost: net.isHost)),
                (_) => false);
            }
          },
          icon: const Text('🎮', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 14)),
          label: Text(L.common.gameSelect),
          style: OutlinedButton.styleFrom(
            foregroundColor: kText,
            side: const BorderSide(color: kBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
        ),
      ]),
    );
  }
}
