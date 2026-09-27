import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import 'lobby_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  void _goToLobby() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.pushReplacement(context, fadeScaleRoute(const LobbyScreen()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = L.common;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Pages ──────────────────────────────────────────────────
            PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _WelcomePage(s),
                _HowToPlayPage(s),
                _GetStartedPage(s, onGo: _goToLobby),
              ],
            ),

            // ── Skip button (pages 0-1) ────────────────────────────────
            if (_page < 2)
              Positioned(
                top: 12,
                right: 16,
                child: TextButton(
                  onPressed: _goToLobby,
                  child: Text(s.obSkip,
                    style: const TextStyle(color: kMuted, fontSize: 14)),
                ),
              ),

            // ── Page dots ──────────────────────────────────────────────
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: _page == i ? 24 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _page == i ? kPurple : kBorder,
                    borderRadius: BorderRadius.circular(5),
                  ),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 1: Welcome ─────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final StringsCommon s;
  const _WelcomePage(this.s);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🎮',
          style: TextStyle(fontSize: 72, fontFamilyFallback: ['NotoColorEmoji'])),
        const SizedBox(height: 24),
        Text(s.obWelcome,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: kText, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Text(s.obSubtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: kMuted, fontSize: 16)),
      ],
    ),
  );
}

// ── Page 2: How to play ─────────────────────────────────────────────────────

class _HowToPlayPage extends StatelessWidget {
  final StringsCommon s;
  const _HowToPlayPage(this.s);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ModeRow(emoji: '📡', label: 'Host', desc: s.obHost),
        const SizedBox(height: 20),
        _ModeRow(emoji: '🔗', label: 'Join', desc: s.obJoin),
        const SizedBox(height: 20),
        _ModeRow(emoji: '🤖', label: 'Solo', desc: s.obSolo),
      ],
    ),
  );
}

class _ModeRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String desc;
  const _ModeRow({required this.emoji, required this.label, required this.desc});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: cardDecoration(),
    child: Row(
      children: [
        Text(emoji,
          style: const TextStyle(fontSize: 32, fontFamilyFallback: ['NotoColorEmoji'])),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                style: const TextStyle(
                  color: kText, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(desc,
                style: const TextStyle(color: kMuted, fontSize: 14),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Page 3: Get started ─────────────────────────────────────────────────────

class _GetStartedPage extends StatelessWidget {
  final StringsCommon s;
  final VoidCallback onGo;
  const _GetStartedPage(this.s, {required this.onGo});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🚀',
          style: TextStyle(fontSize: 72, fontFamilyFallback: ['NotoColorEmoji'])),
        const SizedBox(height: 24),
        Text(s.obReady,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: kText, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 32),
        SizedBox(
          width: 220,
          child: ElevatedButton(
            style: primaryButton(),
            onPressed: onGo,
            child: Text(s.obLetsGo),
          ),
        ),
      ],
    ),
  );
}
