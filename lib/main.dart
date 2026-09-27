import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/network.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/wake_lock.dart';
import 'core/sound_player.dart';
import 'l10n/app_localizations.dart';
import 'screens/lobby_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/about_screen.dart';

late final bool _onboardingDone;

// Used to leave the session from anywhere when the host quits (HOST_LEFT)
final _navKey       = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  await AppLocalizations.init();
  await SoundPlayer.i.init();
  final prefs = await SharedPreferences.getInstance();
  _onboardingDone = prefs.getBool('onboarding_done') ?? false;
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const GameSuiteApp());
}

class GameSuiteApp extends StatefulWidget {
  const GameSuiteApp({super.key});
  @override
  State<GameSuiteApp> createState() => _GameSuiteAppState();
}

class _GameSuiteAppState extends State<GameSuiteApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Network().onHostLeft = _onHostLeft;
  }

  /// Joiner: the host went back to the start screen — follow it there
  /// (from any screen or dialog) instead of showing the reconnect dialog.
  Future<void> _onHostLeft() async {
    await Network().reset();
    SessionState().reset();
    await WakeLock.release();
    _navKey.currentState?.pushAndRemoveUntil(
      fadeScaleRoute(const LobbyScreen()), (_) => false);
    _messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(L.common.hostLeft),
      backgroundColor: Colors.orange.shade800,
      duration: const Duration(seconds: 3)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-apply immersive mode whenever the app comes back to the foreground.
  /// Android resets the system UI bars on every screen lock/unlock; without
  /// this the status bar and nav bar permanently reappear over the game.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Heiti's Game Suite",
    navigatorKey: _navKey,
    scaffoldMessengerKey: _messengerKey,
    theme: buildTheme(),
    // Browser guests (Hosted mode) skip the intro and go straight to Join
    home: _onboardingDone || kIsWeb ? const LobbyScreen() : const OnboardingScreen(),
    debugShowCheckedModeBanner: false,
    // Clamp text scale so system accessibility font size doesn't break layouts
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.of(context).textScaler.clamp(
          minScaleFactor: 0.8, maxScaleFactor: 1.2)),
      child: child!,
    ),
  );
}
