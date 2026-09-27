import 'package:flutter/material.dart';
import '../core/player.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

/// Unified winner/result banner shown above GameOverActions at game end.
/// Pass [winnerIdx] = index into [players], or -1 for a draw.
/// Optionally pass [scores] as a list of (label, value) pairs shown below the winner.
/// Pass [onFirstRender] to trigger confetti exactly once when the banner appears.
class GameResultBanner extends StatefulWidget {
  final List<Player> players;
  final int winnerIdx;       // -1 = draw
  final List<({String label, String value})>? scores;
  final VoidCallback? onFirstRender;

  const GameResultBanner({
    super.key,
    required this.players,
    required this.winnerIdx,
    this.scores,
    this.onFirstRender,
  });

  @override State<GameResultBanner> createState() => _GameResultBannerState();
}

class _GameResultBannerState extends State<GameResultBanner> {
  @override void initState() {
    super.initState();
    if (widget.onFirstRender != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFirstRender!();
      });
    }
  }

  @override Widget build(BuildContext context) {
    final isDraw   = widget.winnerIdx < 0;
    final winner   = isDraw ? null : widget.players[widget.winnerIdx];
    final color    = isDraw ? kMuted : winner!.color;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha:.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha:.4), width: 1.5),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Trophy / draw icon
        Text(isDraw ? '🤝' : '🏆', style: const TextStyle(fontSize: 32, fontFamilyFallback: ['NotoColorEmoji'])),
        const SizedBox(height: 6),
        Text(
          isDraw ? L.common.itsADraw : L.common.wins.fmt({'player': winner!.name}),
          style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w900,
            color: color,
            shadows: [Shadow(color: color.withValues(alpha:.4), blurRadius: 8)]),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (widget.scores != null && widget.scores!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 16, runSpacing: 4,
            alignment: WrapAlignment.center,
            children: widget.scores!.map((s) => Text(
              '${s.label}: ${s.value}',
              style: const TextStyle(color: kMuted, fontSize: 12),
            )).toList(),
          ),
        ],
      ]),
    );
  }
}

