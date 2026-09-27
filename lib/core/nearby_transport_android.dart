import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/scheduler.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'transport.dart';

const _kServiceId   = 'dev.heitis.gamesuite';
const _kMaxPlayers  = 4;

/// Nearby Connections transport (P2P_STAR strategy).
/// Host advertises; joiners discover → request connection → exchange JSON payloads.
///
/// Player index semantics mirror WifiTransport:
///   host = 0, joiners = 1..3 (lowest free index, assigned on HELLO — an
///   endpoint is not a player until it has sent HELLO).
class NearbyTransport implements ITransport, IHostIndexing {
  // ── ITransport state ──────────────────────────────────────────────────────
  @override bool isHost = false;
  @override int  myIdx  = 0;

  @override void Function(Map<String, dynamic>, int)? onMessageFrom;
  @override void Function()? onConnected;
  @override void Function()? onHandshakeComplete;
  @override void Function()? onDisconnected;
  @override void Function(int)? onPlayerCountChanged;

  // ── Private ───────────────────────────────────────────────────────────────
  final _nearby = Nearby();

  final _endpointIdx = <String, int>{};     // endpointId → playerIdx  (host, HELLO'd)
  final _idxEndpoint = <int, String>{};     // playerIdx  → endpointId (host, for sendTo)
  final _idxPlayerId = <int, String>{};     // playerIdx  → player id from HELLO (host)
  final _pending     = <String>{};          // connected endpoints without HELLO (host)

  String? _hostEndpointId;                  // joiner only

  bool _disconnectPending = false;

  String _playerName = 'Player';            // set by lobby before connecting
  void setPlayerName(String name) => _playerName = name;

  // ── Reset ─────────────────────────────────────────────────────────────────
  @override Future<void> softReset() async {
    if (!Platform.isAndroid) return;
    try { await _nearby.stopAllEndpoints(); } catch (_) {}
    try { await _nearby.stopAdvertising(); } catch (_) {}
    try { await _nearby.stopDiscovery(); } catch (_) {}
    _endpointIdx.clear();
    _idxEndpoint.clear();
    _idxPlayerId.clear();
    _pending.clear();
    _hostEndpointId = null;
    _disconnectPending = false;
  }

  @override Future<void> reset() async {
    await softReset();
    isHost               = false;
    myIdx                = 0;
    onMessageFrom        = null;
    onConnected          = null;
    onHandshakeComplete  = null;
    onDisconnected       = null;
    onPlayerCountChanged = null;
  }

  // ── Host ──────────────────────────────────────────────────────────────────
  @override Future<void> startHost() async {
    if (!Platform.isAndroid) return;
    isHost = true;
    myIdx  = 0;
    await _nearby.startAdvertising(
      _playerName,
      Strategy.P2P_STAR,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult:    _onConnectionResult,
      onDisconnected:        _onEndpointDisconnected,
      serviceId: _kServiceId,
    );
  }

  // ── Discovery ─────────────────────────────────────────────────────────────
  @override Future<void> startDiscovery(void Function(String id) onFound) async {
    if (!Platform.isAndroid) return;
    await _nearby.startDiscovery(
      _playerName,
      Strategy.P2P_STAR,
      onEndpointFound: (id, name, serviceId) {
        if (serviceId == _kServiceId) onFound(id);
      },
      onEndpointLost: (_) {},
      serviceId: _kServiceId,
    );
  }

  @override void stopDiscovery() {
    try { _nearby.stopDiscovery(); } catch (_) {}
  }

  @override Future<void> connectTo(String endpointId) async {
    if (!Platform.isAndroid) return;
    _hostEndpointId = endpointId;
    await _nearby.requestConnection(
      _playerName,
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult:    _onConnectionResult,
      onDisconnected:        _onEndpointDisconnected,
    );
  }

  // ── Connection lifecycle ──────────────────────────────────────────────────
  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved:       _onPayloadReceived,
      onPayloadTransferUpdate: (_, __) {},
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    // Status is an enum { CONNECTED, REJECTED, ERROR } in nearby_connections 4.3.0.
    if (status != Status.CONNECTED) {
      if (!isHost && endpointId == _hostEndpointId) {
        _hostEndpointId = null;
        _fireDisconnect(); // lets the lobby / reconnect dialog retry
      }
      return;
    }
    if (isHost) {
      // Only cap the pre-HELLO backlog: a full session must still accept a
      // player reconnecting before we noticed the drop (HELLO then reuses
      // their index; a real newcomer is refused at HELLO).
      if (_pending.length >= _kMaxPlayers - 1) {
        _nearby.disconnectFromEndpoint(endpointId);
        return;
      }
      // Not a player until it sends HELLO (see _handleHelloFromClient)
      _pending.add(endpointId);
    }
    // Fire onConnected for both host AND joiner; for the joiner Network sends
    // HELLO from this callback. onHandshakeComplete fires later on HELLO_ACK.
    onConnected?.call();
  }

  void _onEndpointDisconnected(String endpointId) {
    if (isHost) {
      // Endpoints that never sent HELLO (or were replaced by a reconnect of
      // the same player) disappear silently — no PLAYER_LEFT.
      if (_pending.remove(endpointId)) return;
      final idx = _endpointIdx.remove(endpointId);
      if (idx == null) return;
      _idxEndpoint.remove(idx);
      _idxPlayerId.remove(idx);
      onPlayerCountChanged?.call(_endpointIdx.length + 1);
      // Synthesise PLAYER_LEFT so game_mixin / waiting_screen handles it identically to WiFi
      final leftMsg = <String, dynamic>{'type': 'PLAYER_LEFT', 'idx': idx};
      _fireMessage({...leftMsg, '_from': idx}, idx);
    } else {
      _hostEndpointId = null;
      _fireDisconnect();
    }
  }

  // ── Payload receive ───────────────────────────────────────────────────────
  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES) return;
    final bytes = payload.bytes;
    if (bytes == null) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      // Host: handle HELLO
      if (isHost && json['type'] == 'HELLO') {
        _handleHelloFromClient(endpointId, json);
        return;
      }
      // Host: ignore endpoints that have not sent HELLO yet
      final int fromIdx;
      if (isHost) {
        final idx = _endpointIdx[endpointId];
        if (idx == null) return;
        fromIdx = idx;
      } else {
        fromIdx = 0;
      }
      // Host: relay chat messages
      if (isHost && (json['type'] == 'CHAT' ||
                     json['type'] == 'CHAT_TYPING' ||
                     json['type'] == 'CHAT_READ')) {
        _broadcastExcept(json, endpointId);
      }
      // Joiner: handle HELLO_ACK
      if (!isHost && json['type'] == 'HELLO_ACK') {
        final idx = json['idx'] as int? ?? 1;
        if (idx >= 1 && idx <= _kMaxPlayers - 1) myIdx = idx;
        // onConnected already fired in _onConnectionResult — only signal handshake done
        onHandshakeComplete?.call();
      }
      // Joiner: host renumbered us (Network updates its own myIdx too)
      if (!isHost && json['type'] == 'REINDEX') {
        final idx = json['idx'] as int? ?? myIdx;
        if (idx >= 1 && idx <= _kMaxPlayers - 1) myIdx = idx;
      }
      _fireMessage({...json, '_from': fromIdx}, fromIdx);
    } catch (_) {}
  }

  void _handleHelloFromClient(String endpointId, Map<String, dynamic> msg) {
    final playerId = msg['id'] as String?;
    int? idx = _endpointIdx[endpointId];
    if (idx == null) {
      if (!_pending.contains(endpointId)) return; // unknown endpoint — ignore
      idx = _claimIdx(playerId);
      if (idx == null) { // session full
        _pending.remove(endpointId);
        try { _nearby.disconnectFromEndpoint(endpointId); } catch (_) {}
        return;
      }
      _pending.remove(endpointId);
      _endpointIdx[endpointId] = idx;
      _idxEndpoint[idx] = endpointId;
      onPlayerCountChanged?.call(_endpointIdx.length + 1);
    }
    if (playerId != null) _idxPlayerId[idx] = playerId;
    // Send HELLO_ACK with the assigned player index, then let Network update
    // the roster / screens.
    _sendToEndpoint(endpointId, {'type': 'HELLO_ACK', 'idx': idx});
    _fireMessage({...msg, '_from': idx}, idx);
  }

  /// Old index if a live endpoint already carries [playerId] (that stale
  /// endpoint is dropped silently), else the lowest free index 1..3.
  int? _claimIdx(String? playerId) {
    if (playerId != null) {
      for (final e in _idxPlayerId.entries.toList()) {
        if (e.value != playerId) continue;
        final oldEp = _idxEndpoint.remove(e.key);
        _idxPlayerId.remove(e.key);
        if (oldEp != null) {
          _endpointIdx.remove(oldEp);
          try { _nearby.disconnectFromEndpoint(oldEp); } catch (_) {}
        }
        return e.key;
      }
    }
    for (int i = 1; i < _kMaxPlayers; i++) {
      if (!_idxEndpoint.containsKey(i)) return i;
    }
    return null;
  }

  // ── IHostIndexing ─────────────────────────────────────────────────────────
  @override Set<int> get connectedIndices => _idxEndpoint.keys.toSet();

  @override void remapIndices(Map<int, int> oldToNew) {
    final eps = Map<int, String>.of(_idxEndpoint);
    final ids = Map<int, String>.of(_idxPlayerId);
    _idxEndpoint.clear();
    _idxPlayerId.clear();
    _endpointIdx.clear();
    eps.forEach((oldIdx, ep) {
      final n = oldToNew[oldIdx] ?? oldIdx;
      _idxEndpoint[n] = ep;
      _endpointIdx[ep] = n;
      final pid = ids[oldIdx];
      if (pid != null) _idxPlayerId[n] = pid;
    });
  }

  // ── Send ──────────────────────────────────────────────────────────────────
  @override void send(String type, [Map<String, dynamic>? payload]) {
    final msg = {'type': type, ...?payload};
    if (isHost) {
      _broadcastAll(msg);
    } else {
      _sendToHost(msg);
    }
  }

  @override Future<void> sendAndFlush(String type, [Map<String, dynamic>? payload]) async {
    send(type, payload);
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override void sendTo(int playerIdx, String type, [Map<String, dynamic>? payload]) {
    final endpointId = _idxEndpoint[playerIdx];
    if (endpointId == null) return;
    _sendToEndpoint(endpointId, {'type': type, ...?payload});
  }

  void _sendToHost(Map<String, dynamic> msg) {
    final id = _hostEndpointId;
    if (id == null) return;
    _sendToEndpoint(id, msg);
  }

  void _broadcastAll(Map<String, dynamic> msg) {
    final bytes = _encode(msg);
    for (final id in List.of(_endpointIdx.keys)) {
      try { _nearby.sendBytesPayload(id, bytes); } catch (_) {}
    }
  }

  void _broadcastExcept(Map<String, dynamic> msg, String exceptId) {
    final bytes = _encode(msg);
    for (final id in List.of(_endpointIdx.keys)) {
      if (id == exceptId) continue;
      try { _nearby.sendBytesPayload(id, bytes); } catch (_) {}
    }
  }

  void _sendToEndpoint(String id, Map<String, dynamic> msg) {
    try { _nearby.sendBytesPayload(id, _encode(msg)); } catch (_) {}
  }

  Uint8List _encode(Map<String, dynamic> msg) =>
      Uint8List.fromList(utf8.encode(jsonEncode(msg)));

  @override int get playerCount => isHost ? _endpointIdx.length + 1 : 1;

  // ── Internal helpers ──────────────────────────────────────────────────────
  void _fireMessage(Map<String, dynamic> msg, int fromIdx) {
    try { onMessageFrom?.call(msg, fromIdx); } catch (_) {}
  }

  void _fireDisconnect() {
    if (_disconnectPending) return;
    _disconnectPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _disconnectPending = false;
      try { onDisconnected?.call(); } catch (_) {}
    });
  }

  @override Future<void> probeHotspot(void Function(String) onFound) async {}
}
