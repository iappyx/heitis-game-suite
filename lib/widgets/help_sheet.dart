import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

/// Shows a bottom sheet with game rules.
/// Call [HelpSheet.show] from any game screen.
class HelpSheet {
  HelpSheet._();

  static void show(BuildContext context, {
    required String gameName,
    required String rules,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kBg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => _HelpSheetContent(gameName: gameName, rules: rules),
    );
  }
}

class _HelpSheetContent extends StatelessWidget {
  final String gameName;
  final String rules;
  const _HelpSheetContent({required this.gameName, required this.rules});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            // Title row
            Row(children: [
              Icon(Icons.menu_book_rounded, color: kPurple, size: 22),
              const SizedBox(width: 10),
              Text(L.common.helpTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(gameName,
                style: TextStyle(color: kMuted, fontSize: 13)),
            ]),
            const SizedBox(height: 16),
            Container(height: 1, color: kBorder),
            const SizedBox(height: 16),
            // Rules text
            Text(rules,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.55)),
            const SizedBox(height: 24),
            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPurple2,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
                child: Text(L.common.helpClose),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
