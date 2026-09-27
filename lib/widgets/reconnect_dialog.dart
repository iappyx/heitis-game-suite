import 'dart:async';
import 'package:flutter/material.dart';
import '../core/network.dart';
import '../core/platform_info.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

class ReconnectDialog extends StatefulWidget {
  final VoidCallback onReconnected;
  final VoidCallback onExit;
  const ReconnectDialog({super.key, required this.onReconnected, required this.onExit});
  @override State<ReconnectDialog> createState() => _ReconnectDialogState();
}

enum _RState { searching, found, failed, timedOut }

class _ReconnectDialogState extends State<ReconnectDialog> {
  final _net = Network();

  _RState _state = _RState.searching;
  String _detail = '';
  int _attemptN = 0;
  bool _hotspot = false;

  Timer? _retryTimer;
  Timer? _timeoutTimer;
  // The dialog closes itself at most once — a duplicate onConnected /
  // onHandshakeComplete must never pop the game screen underneath.
  bool _closed = false;

  static const _attemptTimeout = Duration(seconds: 20);
  static const _retryDelay     = Duration(seconds: 3);
  static const _maxAttempts    = 10;

  @override void initState() { super.initState(); _doAttempt(); }

  @override void dispose() {
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  /// Removes this dialog's own route (only if it is still there) exactly once.
  bool _closeSelf() {
    if (_closed || !mounted) return false;
    _closed = true;
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return true;
    if (route.isCurrent) {
      Navigator.pop(context);
    } else {
      Navigator.removeRoute(context, route);
    }
    return true;
  }

  void _reconnected() {
    if (_closeSelf()) widget.onReconnected();
  }

  Future<void> _doAttempt() async {
    if (!mounted || _closed) return;
    _attemptN++;
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();

    final wasHost = _net.isHost;
    setState(() {
      _state  = _RState.searching;
      _detail = wasHost ? L.common.waitingForReconnect : L.common.searchingForHost;
    });

    await _net.softReset();
    _net.isHost = wasHost;
    if (!mounted) return;

    // Per-attempt timeout
    _timeoutTimer = Timer(_attemptTimeout, () {
      if (mounted && _state == _RState.searching) {
        setState(() {
          _state  = _RState.timedOut;
          _detail = L.common.timedOut;
        });
        _scheduleRetry();
      }
    });

    if (wasHost) {
      _net.onConnected = () {
        _timeoutTimer?.cancel();
        _retryTimer?.cancel();
        if (mounted) {
          setState(() { _state = _RState.found; _detail = L.common.playerReconnected; });
          Future.delayed(const Duration(milliseconds: 500), _reconnected);
        }
      };
      _net.onDisconnected = () {
        if (mounted && _state == _RState.searching) {
          setState(() { _state = _RState.failed; _detail = L.common.playerDisconnectedAgain; });
          _scheduleRetry();
        }
      };
      try { await _net.startHost(); }
      catch (e) {
        if (mounted) { setState(() { _state = _RState.failed; _detail = L.common.connectionFailed; }); _scheduleRetry(); }
      }

    } else {
      bool connecting = false;
      // Network sends HELLO itself once the connection is up (onConnected is
      // not needed here). We wait for onHandshakeComplete (fires on HELLO_ACK)
      // so both sides are fully identified before dismissing the dialog.
      _net.onHandshakeComplete = () {
        _timeoutTimer?.cancel();
        _retryTimer?.cancel();
        if (mounted) {
          setState(() { _state = _RState.found; _detail = L.common.rejoinConnected; });
          Future.delayed(const Duration(milliseconds: 400), _reconnected);
        }
      };
      _net.onDisconnected = () {
        connecting = false;
        if (mounted && _state == _RState.searching) {
          setState(() { _state = _RState.failed; _detail = L.common.lostConnection; });
          _scheduleRetry();
        }
      };
      Future<void> onFound(String ip) async {
        if (connecting || !mounted) return;
        connecting = true;
        if (mounted) setState(() => _detail = L.common.foundHostConnecting);
        try { await _net.connectTo(ip); }
        catch (_) {
          connecting = false;
          if (mounted) { setState(() { _state = _RState.failed; _detail = L.common.connectionFailed; }); _scheduleRetry(); }
        }
      }
      // An in-game reconnect, not a fresh join from the start screen
      _net.helloFromLobby = false;
      if (isWebClient) {
        // Browser (Hosted mode): no discovery — the host served this page
        await onFound(Uri.base.host);
        return;
      }
      try {
        if (_hotspot) {
          await _net.probeHotspot(onFound);
        } else {
          await _net.startDiscovery(onFound);
        }
      } catch (e) {
        if (mounted) setState(() { _state = _RState.failed; _detail = L.common.connectionFailed; });
      }
    }
  }

  void _scheduleRetry() {
    if (_attemptN >= _maxAttempts) {
      // Give up after max attempts — show failed state briefly, then exit
      setState(() { _state = _RState.failed; _detail = L.common.connectionLostHint; });
      Future.delayed(const Duration(seconds: 2), () { if (mounted) _exit(); });
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () { if (mounted) _doAttempt(); });
  }

  /// Returns a transport-specific hint for the active transport.
  String get _transportHint {
    if (_net.useNearby || _net.useNearbyService) return L.common.bluetoothHint;
    return L.common.wifiHint;
  }

  void _manualRetry() { _retryTimer?.cancel(); _timeoutTimer?.cancel(); _doAttempt(); }

  void _exit() {
    _retryTimer?.cancel(); _timeoutTimer?.cancel();
    if (!_closeSelf()) return;
    _net.reset();
    widget.onExit();
  }

  @override Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      backgroundColor: kBg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Text('📡', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 24)),
        const SizedBox(width: 8),
        Text(L.common.reconnecting, style: const TextStyle(color: kText, fontSize: 18)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 4),
        SizedBox(height: 48, child: switch (_state) {
          _RState.searching => const CircularProgressIndicator(color: kPurple),
          _RState.found     => const Icon(Icons.check_circle, color: kGreen, size: 40),
          _RState.failed    => const Icon(Icons.wifi_off, color: Colors.orange, size: 40),
          _RState.timedOut  => const Icon(Icons.signal_wifi_statusbar_connected_no_internet_4,
                                color: Colors.redAccent, size: 40),
        }),
        const SizedBox(height: 12),
        Text(_detail, textAlign: TextAlign.center,
          style: const TextStyle(color: kMuted, fontSize: 13)),
        // Hotspot toggle — only relevant in WiFi mode
        if (!_net.useNearby && !_net.useNearbyService) ...[
          if (!_net.isHost && _state == _RState.searching) ...[
            const SizedBox(height: 10),
            HotspotToggle(
              value: _hotspot,
              onChanged: (v) {
                setState(() => _hotspot = v);
                _retryTimer?.cancel();
                _timeoutTimer?.cancel();
                _doAttempt();
              }),
          ],
        ],
        // Transport-specific hint
        const SizedBox(height: 8),
        Text(_transportHint,
          textAlign: TextAlign.center,
          style: const TextStyle(color: kMuted, fontSize: 11)),
        // Show connection-lost hint more prominently after failures
        if (_state == _RState.failed || _state == _RState.timedOut) ...[
          const SizedBox(height: 4),
          Text(L.common.connectionLostHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 11)),
        ],
        if (_attemptN > 1) ...[
          const SizedBox(height: 4),
          Text(L.common.attempt.fmt({'n': _attemptN}), textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 12)),
        ],
      ]),
      actions: [
        TextButton(
          onPressed: (_state == _RState.searching) ? null : _manualRetry,
          child: Text(L.common.retryNow, style: const TextStyle(color: kPurple))),
        TextButton(onPressed: _exit,
          child: Text(L.common.exitToLobby, style: const TextStyle(color: kMuted))),
      ],
    ),
  );
}

