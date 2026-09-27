import 'package:flutter/services.dart';

/// Acquires a CPU + WiFi wake lock via the native foreground service.
/// Call [acquire] when a game starts, [release] when returning to lobby.
class WakeLock {
  static const _ch = MethodChannel('com.iappyx.heitisgames/wakelock');

  static Future<void> acquire() async {
    try { await _ch.invokeMethod('acquire'); } catch (_) {}
  }

  static Future<void> release() async {
    try { await _ch.invokeMethod('release'); } catch (_) {}
  }
}
