import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:nearby_service/nearby_service.dart';
import 'transport.dart';

/// Player index semantics mirror WifiTransport: host = 0, joiners = 1..3
/// (lowest free index, assigned on HELLO — a peer is not a player until it
/// has sent HELLO).
class NearbyServiceTransport implements ITransport, IHostIndexing {
  @override bool isHost = false;
  @override int  myIdx  = 0;

  @override void Function(Map<String, dynamic>, int)? onMessageFrom;
  @override void Function()? onConnected;
  @override void Function()? onHandshakeComplete;
  @override void Function()? onDisconnected;
  @override void Function(int)? onPlayerCountChanged;

  final _service = kDebugMode
      ? NearbyService.getInstance(logLevel: NearbyServiceLogLevel.debug)
      : NearbyService.getInstance();

  final _deviceIdx        = <String, int>{};   // HELLO'd peers (host)
  final _idxDevice        = <int, String>{};
  final _idxPlayerId      = <int, String>{};   // playerIdx → player id from HELLO (host)
  final _connectedDevices = <String, NearbyDevice>{};
  final _channelOpened    = <String>{};        // peers whose channel setup ran

  String? _hostDeviceId;
  String? _pendingConnectId;
  bool _disconnectPending = false;
  String _playerName      = 'Player';

  StreamSubscription? _peersSub;
  final _connectedDeviceSubs = <String, StreamSubscription>{};
  final _channelStateSubs    = <String, void Function()>{};

  void setPlayerName(String name) => _playerName = name;

  // ── Reset ─────────────────────────────────────────────────────────────────
  @override Future<void> softReset() async {
    await _peersSub?.cancel(); _peersSub = null;
    for (final s in _connectedDeviceSubs.values) await s.cancel();
    _connectedDeviceSubs.clear();
    for (final cleanup in _channelStateSubs.values) cleanup();
    _channelStateSubs.clear();
    try { await _service.stopDiscovery(); } catch (_) {}
    for (final d in List.of(_connectedDevices.values)) {
      try { await _service.disconnectById(d.info.id); } catch (_) {}
    }
    _deviceIdx.clear();
    _idxDevice.clear();
    _idxPlayerId.clear();
    _connectedDevices.clear();
    _channelOpened.clear();
    _hostDeviceId     = null;
    _pendingConnectId = null;
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
    isHost = true; myIdx = 0;
    await _service.initialize(
      data: NearbyInitializeData(darwinDeviceName: _playerName),
    );
    if (Platform.isIOS || Platform.isMacOS) {
      _service.darwin?.setIsBrowser(value: false);
    }
    await _service.discover();
    _listenPeers();
  }

  // ── Joiner ────────────────────────────────────────────────────────────────
  @override Future<void> startDiscovery(void Function(String id) onFound) async {
    isHost = false;
    await _service.initialize(
      data: NearbyInitializeData(darwinDeviceName: _playerName),
    );
    if (Platform.isIOS || Platform.isMacOS) {
      _service.darwin?.setIsBrowser(value: true);
    }
    await _service.discover();
    _listenPeers(onFound: onFound);
  }

  @override void stopDiscovery() {
    try { _service.stopDiscovery(); } catch (_) {}
    _peersSub?.cancel(); _peersSub = null;
  }

  @override Future<void> connectTo(String deviceId) async {
    _pendingConnectId = deviceId;
    _hostDeviceId     = deviceId;
  }

  // ── Peer discovery stream — only used to find & connect ──────────────────
  void _listenPeers({void Function(String id)? onFound}) {
    _peersSub?.cancel();
    _peersSub = _service.getPeersStream().listen((peers) async {
      for (final peer in peers) {
        final id = peer.info.id;

        // Report discovered (not yet connected) peers to joiner UI
        if (!isHost && !peer.status.isConnected &&
            !_connectedDevices.containsKey(id)) {
          onFound?.call(id);
        }

        // Joiner: connect to the chosen peer
        if (!isHost && _pendingConnectId == id &&
            !peer.status.isConnected &&
            !_connectedDevices.containsKey(id)) {
          _pendingConnectId = null;
          try { await _service.connectById(peer.info.id); } catch (_) {}
        }

        // Both sides: when peer first appears as connected, start monitoring it
        if (peer.status.isConnected && !_connectedDevices.containsKey(id)) {
          // Only handle peers we care about:
          // host handles all connecting peers; joiner only handles the host
          if (isHost || id == _hostDeviceId) {
            _startMonitoringPeer(peer);
          }
        }
      }
    });
  }

  // ── Per-peer connected device stream (step 7 from docs) ──────────────────
  void _startMonitoringPeer(NearbyDevice peer) {
    final id = peer.info.id;
    // Register the peer immediately so we don't double-add
    _connectedDevices[id] = peer;

    _connectedDeviceSubs[id]?.cancel();
    _connectedDeviceSubs[id] = _service.getConnectedDeviceStreamById(peer.info.id).listen(
      (event) async {
        if (event == null) {
          // Peer disconnected — clean up subscriptions safely
          try { _connectedDeviceSubs[id]?.cancel(); } catch (_) {}
          _connectedDeviceSubs.remove(id);
          try { _channelStateSubs[id]?.call(); } catch (_) {}
          _channelStateSubs.remove(id);
          _connectedDevices.remove(id);
          _channelOpened.remove(id);
          if (isHost) {
            _onPeerDisconnected(id);
          } else {
            _fireDisconnect();
          }
          return;
        }
        // Update stored device info
        _connectedDevices[id] = event;

        final nowConnected = event.status.isConnected;
        // Only proceed with channel setup once per connection. The host does
        // NOT assign an index here — the peer becomes a player on HELLO.
        if (nowConnected && !_channelOpened.contains(id)) {
          // (A full session is refused at HELLO, so a player reconnecting
          // before we noticed the drop can still take over their index.)
          _channelOpened.add(id);
          await _openChannelAndNotify(event);
        }
      },
    );
  }

  // ── Open channel and wait for it to be ready, then fire onConnected ───────
  Future<void> _openChannelAndNotify(NearbyDevice peer) async {
    final id = peer.info.id;

    await _service.startCommunicationChannel(
      NearbyCommunicationChannelData(
        id,
        messagesListener: NearbyServiceMessagesListener(
          onData: (msg) => _onMessage(msg, peerId: id),
        ),
      ),
    );

    // Wait for channel state to reach 'connected'
    if (_service.communicationChannelStateValue != CommunicationChannelState.connected) {
      final completer = Completer<void>();
      final sub = _service.getCommunicationChannelStateStream().listen((state) {
        if (state == CommunicationChannelState.connected && !completer.isCompleted) {
          completer.complete();
        }
      });
      // Track so softReset can clean up
      _channelStateSubs[id] = () { try { sub.cancel(); } catch (_) {} };
      // Timeout after 5s in case state never fires
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
      try { sub.cancel(); } catch (_) {}
      _channelStateSubs.remove(id);
    }

    // Joiner: Network sends HELLO from onConnected (once per connection).
    onConnected?.call();
    // Stop scanning — we're connected, no need to keep the radio busy
    try { await _service.stopDiscovery(); } catch (_) {}
  }

  void _onPeerDisconnected(String id) {
    _connectedDevices.remove(id);
    // Peers that never sent HELLO (or were replaced by a reconnect of the
    // same player) disappear silently — no PLAYER_LEFT.
    final idx = _deviceIdx.remove(id);
    if (idx == null) return;
    _idxDevice.remove(idx);
    _idxPlayerId.remove(idx);
    onPlayerCountChanged?.call(_deviceIdx.length + 1);
    final leftMsg = <String, dynamic>{'type': 'PLAYER_LEFT', 'idx': idx};
    try { onMessageFrom?.call({...leftMsg, '_from': idx}, idx); } catch (_) {}
  }

  // ── Message receive ───────────────────────────────────────────────────────
  void _onMessage(ReceivedNearbyMessage msg, {required String peerId}) {
    final content = msg.content;
    if (content is! NearbyMessageTextRequest) return;
    try {
      final json    = jsonDecode(content.value) as Map<String, dynamic>;
      if (isHost && json['type'] == 'HELLO') {
        _handleHello(peerId, json);
        return;
      }

      // Ignore messages from unknown peers (not yet HELLO'd)
      final fromIdx = isHost ? (_deviceIdx[peerId] ?? -1) : 0;
      if (isHost && fromIdx < 0) return;

      if (isHost && (json['type'] == 'CHAT' ||
                     json['type'] == 'CHAT_TYPING' ||
                     json['type'] == 'CHAT_READ')) {
        _broadcastExcept(json, peerId);
      }
      if (!isHost && json['type'] == 'HELLO_ACK') {
        final idx = json['idx'] as int? ?? 1;
        if (idx >= 1 && idx <= 3) myIdx = idx;
        onHandshakeComplete?.call();
      }
      // Joiner: host renumbered us (Network updates its own myIdx too)
      if (!isHost && json['type'] == 'REINDEX') {
        final idx = json['idx'] as int? ?? myIdx;
        if (idx >= 1 && idx <= 3) myIdx = idx;
      }
      try { onMessageFrom?.call({...json, '_from': fromIdx}, fromIdx); } catch (_) {}
    } catch (_) {}
  }

  void _handleHello(String peerId, Map<String, dynamic> msg) {
    if (!_connectedDevices.containsKey(peerId)) return;
    final playerId = msg['id'] as String?;
    int? idx = _deviceIdx[peerId];
    if (idx == null) {
      idx = _claimIdx(playerId);
      if (idx == null) { // session full
        try { _service.disconnectById(peerId); } catch (_) {}
        return;
      }
      _deviceIdx[peerId] = idx;
      _idxDevice[idx]    = peerId;
      onPlayerCountChanged?.call(_deviceIdx.length + 1);
    }
    if (playerId != null) _idxPlayerId[idx] = playerId;
    _sendToId(peerId, {'type': 'HELLO_ACK', 'idx': idx});
    try { onMessageFrom?.call({...msg, '_from': idx}, idx); } catch (_) {}
  }

  /// Old index if a live peer already carries [playerId] (that stale peer is
  /// dropped silently), else the lowest free index 1..3.
  int? _claimIdx(String? playerId) {
    if (playerId != null) {
      for (final e in _idxPlayerId.entries.toList()) {
        if (e.value != playerId) continue;
        final oldId = _idxDevice.remove(e.key);
        _idxPlayerId.remove(e.key);
        if (oldId != null) {
          _deviceIdx.remove(oldId);
          try { _service.disconnectById(oldId); } catch (_) {}
        }
        return e.key;
      }
    }
    for (int i = 1; i <= 3; i++) {
      if (!_idxDevice.containsKey(i)) return i;
    }
    return null;
  }

  // ── IHostIndexing ─────────────────────────────────────────────────────────
  @override Set<int> get connectedIndices => _idxDevice.keys.toSet();

  @override void remapIndices(Map<int, int> oldToNew) {
    final devs = Map<int, String>.of(_idxDevice);
    final ids  = Map<int, String>.of(_idxPlayerId);
    _idxDevice.clear();
    _idxPlayerId.clear();
    _deviceIdx.clear();
    devs.forEach((oldIdx, dev) {
      final n = oldToNew[oldIdx] ?? oldIdx;
      _idxDevice[n]   = dev;
      _deviceIdx[dev] = n;
      final pid = ids[oldIdx];
      if (pid != null) _idxPlayerId[n] = pid;
    });
  }

  // ── Send ──────────────────────────────────────────────────────────────────
  @override void send(String type, [Map<String, dynamic>? payload]) {
    final msg = {'type': type, ...?payload};
    if (isHost) _broadcastAll(msg);
    else if (_hostDeviceId != null) _sendToId(_hostDeviceId!, msg);
  }

  @override Future<void> sendAndFlush(String type, [Map<String, dynamic>? payload]) async {
    send(type, payload);
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override void sendTo(int playerIdx, String type, [Map<String, dynamic>? payload]) {
    final id = _idxDevice[playerIdx];
    if (id == null) return;
    _sendToId(id, {'type': type, ...?payload});
  }

  // Host: only peers that have sent HELLO are players
  void _broadcastAll(Map<String, dynamic> msg) {
    for (final id in List.of(_deviceIdx.keys)) _sendToId(id, msg);
  }

  void _broadcastExcept(Map<String, dynamic> msg, String exceptId) {
    for (final id in List.of(_deviceIdx.keys)) {
      if (id != exceptId) _sendToId(id, msg);
    }
  }

  void _sendToId(String id, Map<String, dynamic> msg) {
    final device = _connectedDevices[id];
    if (device == null) return;
    try {
      _service.send(OutgoingNearbyMessage(
        content: NearbyMessageTextRequest.create(value: jsonEncode(msg)),
        receiver: device.info,
      ));
    } catch (_) {}
  }

  @override int get playerCount => isHost ? _deviceIdx.length + 1 : 1;
  @override Future<void> probeHotspot(void Function(String) onFound) async {}

  void _fireDisconnect() {
    if (_disconnectPending) return;
    _disconnectPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _disconnectPending = false;
      try { onDisconnected?.call(); } catch (_) {}
    });
  }
}
