import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/network.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

/// Hosted mode: QR code + address that friends without the app scan to play
/// in their browser (same WiFi or the host's hotspot).
class WebInviteCard extends StatelessWidget {
  final List<String> urls;
  const WebInviteCard({super.key, required this.urls});

  /// Dialog version (e.g. from the game select screen).
  static Future<void> show(BuildContext context) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: kBg2,
      content: WebInviteCard(urls: Network().webUrls),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text(L.common.aboutClose, style: const TextStyle(color: kPurple))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(8)),
          child: QrImageView(data: urls.first, size: 120,
            backgroundColor: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L.common.webInviteTitle, style: const TextStyle(
              color: kText, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(L.common.webInviteHint,
              style: const TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 6),
            SelectableText(urls.first.split('/?').first, style: const TextStyle(
              color: kPurple, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            // Join code: in the QR code, and shown for people who type the address
            Text('${L.common.webCodeLabel}: ${Network().webCode}',
              style: const TextStyle(color: kText, fontSize: 22,
                fontWeight: FontWeight.w900, letterSpacing: 4)),
          ],
        )),
      ]),
    );
  }
}
