import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

// All runtime permissions needed by Nearby Connections.
//
// Android API behaviour:
//   Permission.bluetooth          → always 'restricted' on API 31+  (legacy, skip check)
//   Permission.bluetoothScan/Advertise/Connect → real runtime perms on API 31+
//   Permission.nearbyWifiDevices  → real runtime perm on API 33+;
//                                   'restricted' on API 32- (= not applicable, treat as OK)
//   Permission.locationWhenInUse  → real runtime perm on all versions
//
// We include nearbyWifiDevices in the request list so it gets prompted on API 33+.
// On older devices permission_handler returns 'restricted' for it, which we treat as OK.
final _kPermissions = [
  Permission.bluetoothScan,
  Permission.bluetoothAdvertise,
  Permission.bluetoothConnect,
  Permission.locationWhenInUse,
  Permission.nearbyWifiDevices,   // required on API 33+ — restricted (=OK) on older
];

bool _isOk(PermissionStatus s) =>
    s == PermissionStatus.granted    ||
    s == PermissionStatus.limited    ||
    s == PermissionStatus.restricted ||  // not applicable on this API level
    s == PermissionStatus.provisional;

Future<bool> requestBluetoothPermissions(BuildContext context) async {
  // Request all — OS will only show dialog for ones not yet decided
  final statuses = await _kPermissions.request();

  final denied = statuses.entries
      .where((e) => !_isOk(e.value))
      .toList();

  if (denied.isEmpty) return true;

  // Something is denied — show dialog with Settings button
  if (!context.mounted) return false;

  final goToSettings = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PermissionDialog(),
  ) ?? false;

  if (!goToSettings) return false;

  // The dialog already opened Settings and popped `true` once the app was
  // resumed. Give the OS a moment, then re-check the real statuses
  // (`.status` queries the OS, it isn't cached).
  await Future.delayed(const Duration(milliseconds: 500));
  for (final p in _kPermissions) {
    if (!_isOk(await p.status)) return false;
  }
  return true;
}

class _PermissionDialog extends StatefulWidget {
  @override State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog>
    with WidgetsBindingObserver {
  bool _waitingForSettings = false;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForSettings) {
      _waitingForSettings = false;
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override Widget build(BuildContext context) => AlertDialog(
    backgroundColor: kBg2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(L.common.btPermissionTitle,
      style: const TextStyle(color: kText, fontSize: 16,
        fontWeight: FontWeight.bold)),
    content: Text(L.common.btPermissionBody,
      style: const TextStyle(color: kMuted, fontSize: 13)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(L.common.cancelBtn,
          style: const TextStyle(color: kMuted))),
      ElevatedButton(
        onPressed: () async {
          _waitingForSettings = true;
          await openAppSettings();
          // dialog closes via didChangeAppLifecycleState on resume
        },
        style: ElevatedButton.styleFrom(backgroundColor: kPurple2),
        child: Text(L.common.btPermissionBtn,
          style: const TextStyle(color: Colors.white))),
    ],
  );
}
