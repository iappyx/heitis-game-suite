// Conditionally import the real Android implementation or the stub,
// depending on platform. nearby_connections is Android-only.
// The stub is used on iOS/macOS where it is not available.
// The Bluetooth tab is hidden on iOS so the stub is never called.
//
// NOTE: dart.library.io is true on ALL native platforms (Android + iOS),
// so we cannot use it to distinguish Android from iOS in a conditional export.
// Instead we export the Android file on all native platforms and guard every
// method inside it with Platform.isAndroid at runtime. The web gets the stub.
export 'nearby_transport_stub.dart'
    if (dart.library.io) 'nearby_transport_android.dart';
