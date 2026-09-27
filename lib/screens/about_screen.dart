import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

const _kAppName   = "Heiti's Game Suite";
const _kLegalese  = '© 2026 iappyx — MIT License';

// ── Licenses ─────────────────────────────────────────────────────────────────

const _kMitLicense = '''MIT License

Copyright (c) 2026 iappyx

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';

const _kKenneyLicense = '''Sound effects from Kenney (https://kenney.nl):
Interface Sounds, Digital Audio and Casino Audio.

License: Creative Commons Zero (CC0 1.0) — public domain.
Attribution is not required; credited with thanks.''';

/// Adds our own license and the bundled assets (font, sounds) to Flutter's
/// license registry, next to the package licenses Flutter collects itself.
/// Call once at startup.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks([_kAppName], _kMitLicense);
    yield LicenseEntryWithLineBreaks(['Noto Color Emoji'],
        await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield const LicenseEntryWithLineBreaks(['Kenney sound effects'], _kKenneyLicense);
    yield LicenseEntryWithLineBreaks(['Roboto'],
        await rootBundle.loadString('assets/fonts/roboto/LICENSE.txt'));
  });
}

// ── About dialog ─────────────────────────────────────────────────────────────

class AboutAppDialog extends StatelessWidget {
  const AboutAppDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const AboutAppDialog());

  @override
  Widget build(BuildContext context) {
    final c = L.common;
    return AlertDialog(
      backgroundColor: kBg2,
      title: const Row(children: [
        Text('🎮', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 28)),
        SizedBox(width: 10),
        Expanded(child: Text(_kAppName,
          style: TextStyle(color: kText, fontWeight: FontWeight.w900))),
      ]),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (_, snap) => Text(
              snap.hasData ? 'v${snap.data!.version} · build ${snap.data!.buildNumber}' : '',
              style: const TextStyle(color: kMuted, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          Text(c.aboutMadeBy,
            style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
          const Text('iappyx.github.io',
            style: TextStyle(color: kPurple, fontSize: 13)),
          const SizedBox(height: 4),
          const Text(_kLegalese, style: TextStyle(color: kMuted, fontSize: 13)),
          Text(c.aboutLicense, style: const TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 16),
          Text(c.aboutCredits,
            style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _credit(c.aboutFont),
          _credit(c.aboutSounds),
          _credit(c.aboutPackages),
        ],
      )),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: _kAppName,
            applicationLegalese: _kLegalese,
          ),
          child: Text(c.aboutAllLicenses, style: const TextStyle(color: kPurple))),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(backgroundColor: kPurple2),
          child: Text(c.aboutClose, style: const TextStyle(color: Colors.white))),
      ],
    );
  }

  Widget _credit(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('•  ', style: TextStyle(color: kMuted, fontSize: 13)),
      Expanded(child: Text(text, style: const TextStyle(color: kMuted, fontSize: 13))),
    ]),
  );
}
