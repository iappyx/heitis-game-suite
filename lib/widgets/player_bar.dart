import 'package:flutter/material.dart';
import '../core/player.dart';
import '../core/theme.dart';

/// Unified horizontal player bar shown at the top of every game screen.
/// Highlights the active player with a glowing border.
/// Optionally shows a [score] per player.
class PlayerBar extends StatelessWidget {
  final List<Player> players;
  final int activeIdx;           // index of active/current player (-1 = none)
  final List<int>? scores;       // optional score per player (same length as players)
  final String? scoreLabel;      // e.g. '🐛', 'pts', '' — shown after score

  const PlayerBar({
    super.key,
    required this.players,
    required this.activeIdx,
    this.scores,
    this.scoreLabel,
  });

  @override Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: players.asMap().entries.map((e) {
            final active = e.key == activeIdx;
            final p      = e.value;
            final score  = scores != null && e.key < scores!.length
                ? scores![e.key] : null;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active ? p.color.withValues(alpha:.2) : Colors.white.withValues(alpha:.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? p.color : Colors.transparent,
                  width: 2),
                boxShadow: active ? [
                  BoxShadow(color: p.color.withValues(alpha:.3), blurRadius: 8),
                ] : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(p.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: active ? kText : kMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                ),
                if (score != null) ...[
                  const SizedBox(width: 5),
                  Text('$score${scoreLabel ?? ''}',
                    style: TextStyle(fontSize: 11,
                      color: active ? kText : kMuted)),
                ],
              ]),
            );
          }).toList(),
        ),
      ),
    );
  }
}
