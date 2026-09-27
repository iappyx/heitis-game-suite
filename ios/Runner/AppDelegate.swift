import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Wake lock channel — keeps screen on during games
    let controller = window?.rootViewController as! FlutterViewController
    let wakeLockChannel = FlutterMethodChannel(
      name: "com.iappyx.heitisgames/wakelock",
      binaryMessenger: controller.binaryMessenger)
    wakeLockChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "acquire":
        UIApplication.shared.isIdleTimerDisabled = true
        result(nil)
      case "release":
        UIApplication.shared.isIdleTimerDisabled = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
