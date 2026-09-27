import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Unified status bar shown between PlayerBar and game content.
/// Displays turn indicators, phase info, and action descriptions.
/// Collapses to zero height when [text] is null or empty.
class GameStatusBar extends StatelessWidget {
  final String? text;
  final Color? textColor;
  final Widget? action;

  const GameStatusBar({super.key, this.text, this.textColor, this.action});

  @override
  Widget build(BuildContext context) {
    final show = text != null && text!.isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: show
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      text!,
                      key: ValueKey(text),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor ?? kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 8),
                  action!,
                ],
              ]),
            )
          : const SizedBox.shrink(),
    );
  }
}
