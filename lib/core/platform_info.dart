import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

// Platform checks that are safe in the browser: dart:io's Platform throws on
// the web, where the app runs as a guest client (Hosted mode).
bool get isAndroidApp => !kIsWeb && Platform.isAndroid;
bool get isIOSApp     => !kIsWeb && Platform.isIOS;
bool get isWebClient  => kIsWeb;
