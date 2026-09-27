import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

const kBg      = Color(0xFF0D0621);
const kBg2     = Color(0xFF1A0A2E);
const kPurple  = Color(0xFFA855F7);
const kPurple2 = Color(0xFF7C3AED);
const kText    = Color(0xFFF0E6FF);
const kMuted   = Color(0x73F0E6FF);
const kCard    = Color(0x0FF0E6FF);
const kBorder  = Color(0x4DA855F7);
const kGreen   = Color(0xFF6EE7A0);

const kPlayerColors = [
  Color(0xFFE74C3C),
  Color(0xFF3498DB),
  Color(0xFF2ECC71),
  Color(0xFFF39C12),
  Color(0xFF9B59B6),
  Color(0xFF1ABC9C),
];

ThemeData buildTheme() => ThemeData(
  // Browser (Hosted mode): bundled fonts only — offline, no Google Fonts CDN
  fontFamily: kIsWeb ? 'RobotoWeb' : null,
  fontFamilyFallback: kIsWeb ? const ['NotoColorEmoji'] : null,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kBg,
  colorScheme: const ColorScheme.dark(primary: kPurple, surface: kBg2),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: kText),
    bodySmall:  TextStyle(color: kMuted, fontSize: 12),
  ),
);

// Shared decoration for cards
BoxDecoration cardDecoration() => BoxDecoration(
  color: kCard,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: kBorder),
);

// Gradient button style
ButtonStyle primaryButton() => ElevatedButton.styleFrom(
  backgroundColor: kPurple2,
  foregroundColor: Colors.white,
  minimumSize: const Size(double.infinity, 52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
);

ButtonStyle secondaryButton() => OutlinedButton.styleFrom(
  foregroundColor: kText,
  minimumSize: const Size(double.infinity, 52),
  side: const BorderSide(color: kBorder),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
);

// ─────────────────────────────────────────────────────────────────────────────
// Shared fade + scale route transition
// ─────────────────────────────────────────────────────────────────────────────
Route<T> fadeScaleRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, __, ___) => page,
  transitionDuration: const Duration(milliseconds: 300),
  reverseTransitionDuration: const Duration(milliseconds: 250),
  transitionsBuilder: (_, animation, __, child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
        child: child,
      ),
    );
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Shared hotspot toggle used in lobby and reconnect dialog
// ─────────────────────────────────────────────────────────────────────────────
class HotspotToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const HotspotToggle({super.key, required this.value, required this.onChanged});

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: value ? kPurple.withValues(alpha: .12) : Colors.white.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: value ? kPurple.withValues(alpha: .4) : kBorder)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('📡', style: TextStyle(fontSize: 16, fontFamilyFallback: ['NotoColorEmoji'])),
      const SizedBox(width: 8),
      Flexible(child: Text(L.common.usingHotspot,
        style: TextStyle(color: kText, fontSize: 13))),
      const SizedBox(width: 8),
      Switch(value: value, onChanged: onChanged,
        activeColor: kPurple, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ]),
  );
}

// ── Language selector toggle ──────────────────────────────────────────────────
class LangToggle extends StatelessWidget {
  final void Function(AppLang) onChanged;
  const LangToggle({super.key, required this.onChanged});

  @override Widget build(BuildContext context) {
    final current = L.lang;
    return Row(mainAxisSize: MainAxisSize.min, children: AppLang.values.map((lang) {
      final selected = lang == current;
      return GestureDetector(
        onTap: () => onChanged(lang),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? kPurple2 : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? kPurple : kBorder,
              width: selected ? 1.5 : 1)),
          child: Text(lang.label,
            style: TextStyle(
              color: selected ? Colors.white : kMuted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ),
      );
    }).toList());
  }
}

// ── Emoji-safe text widget ────────────────────────────────────────────────────
// Uses NotoColorEmoji as fallback so emoji render correctly on iOS.
class EmojiText extends StatelessWidget {
  final String text;
  final double? fontSize;
  final Color? color;
  const EmojiText(this.text, {super.key, this.fontSize, this.color});

  @override Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: fontSize,
      color: color,
      fontFamilyFallback: ['NotoColorEmoji'],
    ),
  );
}
