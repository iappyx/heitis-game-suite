import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/theme.dart';
import '../core/debug.dart';
import '../screens/superuser_screen.dart';

/// Small version label — call once from a StatefulWidget that has a
/// long lifetime (LobbyScreen / WaitingScreen).
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key});
  @override State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  String _version = '';
  int _tapCount = 0;
  DateTime _lastTap = DateTime(0);

  @override void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version} · build ${info.buildNumber}');
    });
  }

  void _onTap() {
    if (!kDebugSuperuser) return;
    final now = DateTime.now();
    if (now.difference(_lastTap) > const Duration(seconds: 2)) _tapCount = 0;
    _lastTap = now;
    _tapCount++;
    if (_tapCount >= 5) {
      _tapCount = 0;
      gSuperuserUnlocked = true;
      SuperuserScreen.show(context);
    }
  }

  @override Widget build(BuildContext context) {
    if (_version.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _onTap,
      child: Text(_version,
        style: const TextStyle(color: kMuted, fontSize: 10,
          fontFeatures: [FontFeature.tabularFigures()])),
    );
  }
}
