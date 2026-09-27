import '../core/platform_info.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

/// "Which connection?" sheet: when WiFi, Bluetooth and Nearby (P2P) work.
/// Platform-aware: Bluetooth (Google Nearby Connections) only exists on
/// Android; on Apple devices Nearby only reaches other Apple devices.
class ConnectionHelpSheet extends StatelessWidget {
  const ConnectionHelpSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: kBg2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const ConnectionHelpSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final c = L.common;
    final android = isAndroidApp;
    return SafeArea(child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(c.connHelpTitle,
                style: const TextStyle(color: kText, fontSize: 20,
                  fontWeight: FontWeight.w900))),
              IconButton(
                icon: const Icon(Icons.close, color: kMuted),
                onPressed: () => Navigator.pop(context)),
            ]),
            Text(c.connSameForAll,
              style: const TextStyle(color: kMuted, fontSize: 13)),
            const SizedBox(height: 14),

            _card(Icons.wifi, c.transportWifi,
              c.connWifiNeeds, c.connWifiWorks, c.connWifiFails),
            if (android) _card(Icons.bluetooth, c.transportBluetooth,
              c.connBtNeeds, c.connBtWorks, c.connBtFails),
            _card(Icons.devices, c.transportNearby,
              c.connNearbyNeeds, c.connNearbyWorks, c.connNearbyFails),
            // Hosted mode: players without the app join a WiFi host in their browser
            _card(Icons.language, c.connWebTitle,
              c.connWebNeeds, c.connWebWorks, c.connWebFails),
            if (!android) _note(c.connAppleNoBt),

            const SizedBox(height: 6),
            Text(c.connGuideTitle,
              style: const TextStyle(color: kText, fontSize: 15,
                fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _bullet('🏠', c.connGuideHome),
            if (android) _bullet('🚗', c.connGuideRoad),
            _bullet('💻', c.connGuideMixed),
            if (!android) _bullet('🍏', c.connGuideApple),
            _bullet('🌐', c.connGuideFriends),
          ]),
        )),
      ),
    ));
  }

  Widget _card(IconData icon, String title, String needs, String works,
      String fails) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kBorder)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: kPurple, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: kText, fontSize: 15,
          fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 6),
      _line(L.common.connNeeds, needs),
      _line(L.common.connWorksWith, works),
      _line(L.common.connFailsWhen, fails),
    ]),
  );

  Widget _line(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text.rich(TextSpan(children: [
      TextSpan(text: '$label: ',
        style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
      TextSpan(text: text),
    ]), style: const TextStyle(color: kMuted, fontSize: 13)),
  );

  Widget _note(String text) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: kPurple.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: const TextStyle(color: kText, fontSize: 13)),
  );

  Widget _bullet(String emoji, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(
        fontFamilyFallback: ['NotoColorEmoji'], fontSize: 14)),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
        style: const TextStyle(color: kMuted, fontSize: 13))),
    ]),
  );
}
