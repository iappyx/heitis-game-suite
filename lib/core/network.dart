import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'transport.dart';
import 'nearby_transport.dart';
import 'nearby_service_transport.dart';
import 'player.dart';
import 'session.dart';
import 'theme.dart';
import 'web_host.dart';

const _udpPort       = 45678;
const _tcpPort       = 45679;
/// Hosted mode: browsers load the web client and connect (WebSocket /ws) here.
const kWebPort       = 45680;
const _multicastAddr = '239.255.42.99';
const _beaconMsg     = 'HEITIS_GAMESUITE_HOST';
const _maxPlayers    = 4;

const _pingInterval  = Duration(seconds: 4);
// Generous timeout — Android can suspend Dart for 30-60s on screen sleep.
const _pingTimeout   = Duration(seconds: 90);
// A browser player whose phone went dark keeps its seat this long mid-game.
const _awayGrace     = Duration(minutes: 2);
// A connection that has not sent HELLO within this window is dropped.
const _helloTimeout  = Duration(seconds: 20);

typedef MsgHandler     = void Function(Map<String, dynamic> msg);
typedef VoidCb         = void Function();
typedef MsgFromHandler = void Function(Map<String, dynamic> msg, int fromIdx);

/// One connection to a joiner: a TCP socket (app) or a WebSocket (browser).
/// Both carry the same JSON messages.
abstract class _Conn {
  void write(String json);
  Future<void> flush();
  void destroy();
}

class _TcpConn implements _Conn {
  final Socket socket;
  _TcpConn(this.socket) {
    try { socket.setOption(SocketOption.tcpNoDelay, true); } catch (_) {}
  }
  @override void write(String json) => socket.write('$json\n');
  @override Future<void> flush() => socket.flush();
  @override void destroy() => socket.destroy();
}

class _WsConn implements _Conn {
  final WebSocket ws;
  _WsConn(this.ws);
  @override void write(String json) => ws.add(json);
  @override Future<void> flush() async {}
  @override void destroy() { ws.close(); }
}

class _Client {
  final _Conn conn;
  int idx;             // -1 until HELLO (pending — not a player yet)
  String? playerId;    // id from HELLO — used to recognise a reconnecting player
  final buf = StringBuffer();
  StreamSubscription? sub;
  Timer? watchdog;
  Timer? awayTimer;   // browser player gone mid-game: seat held until this fires
  DateTime lastPing = DateTime(0);
  _Client(this.conn, this.idx);
}

class Network with WidgetsBindingObserver {
  static final Network _i = Network._();
  factory Network() => _i;
  Network._() {
    WidgetsBinding.instance.addObserver(this);
  }

  // ── Public state ──────────────────────────────────────────────────────────
  bool isHost = false;
  int  myIdx  = 0;

  // ── Solo / AI mode ────────────────────────────────────────────────────────
  /// When true, the app is in single-player mode. send() is a no-op (AI reads
  /// game state directly) and injectMessage() pushes fake incoming messages.
  bool isSolo = false;

  // ── Tournament mode ───────────────────────────────────────────────────────
  /// When true, the current game was launched from TournamentScreen.
  /// GameOverActions shows "Record Result" (host) / "Waiting…" (client).
  bool isTournament = false;

  /// Push a message as if it came from the AI opponent (playerIdx 1).
  void injectMessage(String type, [Map<String, dynamic>? payload, int fromIdx = 1]) {
    final msg = {'type': type, ...?payload};
    try {
      _dispatch(msg, fromIdx);
      _legacyHandler?.call(msg, fromIdx);
    } catch (e, st) {
      // ignore: avoid_print
      print('[Network] injectMessage error ($type): $e\n$st');
    }
  }

  // Set while a game is running (WaitingScreen launch); cleared when the host
  // returns to WaitingScreen. Used for the Hero icon in GameScaffold.
  Map<String, dynamic>? currentGameInfo; // {'game':..,'first':..,'players':..,'cfg':..}

  // ── Transport selection ───────────────────────────────────────────────────
  /// Set to true before calling startHost/startDiscovery to use Bluetooth
  /// (Nearby Connections) instead of WiFi TCP/UDP.
  bool useNearby = false;

  /// Set to true to use nearby_service (Nearby Connections on Android,
  /// Multipeer Connectivity on iOS).
  bool useNearbyService = false;

  // Created on first use: the browser version (Hosted mode) never uses them,
  // and NearbyService checks dart:io Platform, which throws on the web.
  late final _nearby = NearbyTransport();
  late final _nearbyService = NearbyServiceTransport();

  // Written as if/return: both transports also implement IHostIndexing, so a
  // ?: expression would have no single upper bound (compiles to Object).
  ITransport get _activeTransport {
    if (useNearbyService) return _nearbyService;
    return _nearby;
  }

  /// Sets the player name used for Nearby Connections discovery/advertising.
  /// Call this before startHost() or startDiscovery() when useNearby is true.
  void setNearbyPlayerName(String name) {
    _nearby.setPlayerName(name);
    _nearbyService.setPlayerName(name);
  }

  void _wireNearbyCallbacks() {
    final t = _activeTransport;
    t.onMessageFrom        = (msg, fromIdx) => _receive(msg, fromIdx);
    t.onConnected          = () {
      // Joiner: exactly one HELLO per established connection (lobby join and
      // reconnect alike). Screens must NOT send HELLO themselves.
      if (!isHost && _hello != null) t.send('HELLO', _hello);
      onConnected?.call();
    };
    t.onHandshakeComplete  = () {
      myIdx = t.myIdx;
      onHandshakeComplete?.call();
    };
    t.onDisconnected       = () => onDisconnected?.call();
    t.onPlayerCountChanged = (n) => onPlayerCountChanged?.call(n);
  }

  // ── Message stream (replaces single onMessageFrom callback) ──────────────
  // Any number of screens can listen simultaneously. Subscriptions are
  // cancelled automatically when the subscriber calls sub.cancel() in dispose().
  final _msgController = StreamController<(Map<String, dynamic>, int)>.broadcast();
  Stream<(Map<String, dynamic>, int)> get messages => _msgController.stream;

  /// Subscribe to incoming messages. Store the returned subscription and
  /// cancel it in your dispose().
  StreamSubscription<(Map<String, dynamic>, int)> listen(
      void Function(Map<String, dynamic> msg, int fromIdx) handler) {
    return _msgController.stream.listen((e) {
      try {
        handler(e.$1, e.$2);
      } catch (err, st) {
        // Malformed or unexpected network message — log and discard.
        // ignore: avoid_print
        print('[Network] message handler error: $err\n$st');
      }
    });
  }

  /// Fire a message to all current listeners.
  void _dispatch(Map<String, dynamic> msg, int fromIdx) {
    if (!_msgController.isClosed) _msgController.add((msg, fromIdx));
    netLog.add(_NetLogEntry(msg, fromIdx, outgoing: false));
    if (netLog.length > 200) netLog.removeAt(0);
  }

  // ── Debug network log (persists across superuser screen open/close) ─────────
  static final List<_NetLogEntry> netLog = [];

  // Legacy compat — kept so solo_ai.dart and any remaining direct callers
  // still compile. Prefer listen() for new code.
  @Deprecated('Use Network().listen() instead')
  MsgFromHandler? get onMessageFrom => _legacyHandler;
  @Deprecated('Use Network().listen() instead')
  set onMessageFrom(MsgFromHandler? h) => _legacyHandler = h;
  MsgFromHandler? _legacyHandler;

  set onMessage(MsgHandler? h) =>
      _legacyHandler = h == null ? null : (msg, _) => h(msg);
  MsgHandler? get onMessage =>
      _legacyHandler == null ? null : (msg) => _legacyHandler!(msg, 0);

  VoidCb? onConnected;
  VoidCb? onHandshakeComplete;
  VoidCb? onDisconnected;
  /// App-level (set once in main.dart, NOT cleared by reset): the host left
  /// the session on purpose — go to the start screen, don't try to reconnect.
  VoidCb? onHostLeft;
  void Function(int count)? onPlayerCountChanged;

  // ── Private ───────────────────────────────────────────────────────────────
  ServerSocket?       _server;
  Socket?             _socket;
  // Browser joiner (web client): WebSocket to the host instead of TCP
  WebSocketChannel?   _wsChan;
  StreamSubscription? _wsSub;
  // Host: serves the web client + WebSocket endpoint for browser players
  WebClientServer?    _web;
  /// Host: also accept browser players (Hosted mode). WiFi only.
  bool hostWeb = false;
  /// Host: addresses browsers can open (empty until the web server runs).
  /// Each carries the join code, so scanning the QR code needs no typing.
  List<String> get webUrls =>
      [for (final u in _web?.urls ?? const <String>[]) '$u/?code=$webCode'];
  /// Host: 4-digit code browser players must send with HELLO (new per session,
  /// shown on the host's screen and included in the QR code).
  String webCode = '';
  /// Browser guest: the code to send with HELLO (from the URL or typed in).
  String joinCode = '';
  /// True when the current connection was started from the start screen
  /// (not from an in-game reconnect) — tells the host to route a returning
  /// browser player back into the running game.
  bool helloFromLobby = false;
  final _clients    = <int, _Client>{};   // registered players (sent HELLO)
  final _pending    = <_Client>{};        // connected, no HELLO yet

  RawDatagramSocket?  _udp;
  Timer?              _beaconTimer;
  Timer?              _pingTimer;
  Timer?              _watchdog;
  StreamSubscription? _tcpSub;
  final _buf        = StringBuffer();
  bool _appPaused   = false;
  bool _disconnectPending = false;
  DateTime _lastSendTime = DateTime.now(); // used to skip redundant PINGs

  // ── Lifecycle — pause watchdog on screen sleep ────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _appPaused = true;
      // Cancel watchdogs so screen sleep doesn't trigger false disconnect
      _watchdog?.cancel();
      for (final c in _clients.values) c.watchdog?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _appPaused = false;
      // After screen wake, probe immediately rather than giving a fresh 90s window.
      // A silently dead socket will be detected within one ping interval (~4s).
      if (isHost) {
        // Host: send PING to all clients and give them a short window to respond
        _broadcastAll({'type': 'PING'});
        for (final cl in _clients.values) {
          cl.watchdog?.cancel();
          cl.watchdog = Timer(const Duration(seconds: 12), () => _clientDisconnected(cl));
        }
      } else if (_joinerConnected) {
        // Joiner: send PING to host, short window to see PONG
        _sendRaw({'type': 'PING'});
        _watchdog?.cancel();
        _watchdog = Timer(const Duration(seconds: 12), _handleDisconnect);
      }
    }
  }

  // ── Safe disconnect — deferred post-frame so Flutter is never mid-build ──
  void _fireDisconnect() {
    if (_disconnectPending) return;
    _disconnectPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _disconnectPending = false;
      try { onDisconnected?.call(); } catch (_) {}
    });
  }

  // ── Reset — clears sockets, preserves callbacks ───────────────────────────
  Future<void> softReset() async {
    if (useNearby || useNearbyService) {
      await _activeTransport.softReset();
      return;
    }
    _beaconTimer?.cancel();  _beaconTimer = null;
    _pingTimer?.cancel();    _pingTimer   = null;
    _watchdog?.cancel();     _watchdog    = null;
    for (final c in [..._clients.values, ..._pending]) {
      c.watchdog?.cancel();
      c.awayTimer?.cancel();
      try { c.sub?.cancel(); } catch (_) {}
      try { c.conn.destroy(); } catch (_) {}
    }
    _clients.clear();
    _pending.clear();
    try { await _wsSub?.cancel(); } catch (_) {}
    _wsSub = null;
    try { await _wsChan?.sink.close(); } catch (_) {}
    _wsChan = null;
    try { await _web?.stop(); } catch (_) {}
    _web = null;
    try { await _tcpSub?.cancel(); } catch (_) {}
    _tcpSub = null;
    try { _socket?.destroy(); } catch (_) {}
    _socket = null;
    try { await _server?.close(); } catch (_) {}
    _server = null;
    _udp?.close(); _udp = null;
    _buf.clear();
    _disconnectPending = false;
  }

  /// Leave the session on purpose (back to the start screen). The host first
  /// tells the joiners (HOST_LEFT) so they return to the start screen instead
  /// of trying to reconnect. Joiners just disconnect (host sees PLAYER_LEFT).
  Future<void> leaveSession() async {
    if (isHost && !isSolo) {
      try {
        await sendAndFlush('HOST_LEFT');
        await Future.delayed(const Duration(milliseconds: 300)); // let it arrive
      } catch (_) {}
    }
    await reset();
  }

  Future<void> reset() async {
    if (useNearby || useNearbyService) {
      await _activeTransport.reset();
      isHost               = false;
      myIdx                = 0;
      isSolo               = false;
      isTournament         = false;
      onMessageFrom        = null;
      onConnected          = null;
      onHandshakeComplete  = null;
      onDisconnected       = null;
      onPlayerCountChanged = null;
      currentGameInfo      = null;
      useNearby            = false;
      useNearbyService     = false;
      hostWeb              = false;
      _hello               = null;
      SessionState().clearRoster();
      return;
    }
    await softReset();
    isHost               = false;
    myIdx                = 0;
    isSolo               = false;
    isTournament         = false;
    onMessageFrom        = null;
    onConnected          = null;
    onHandshakeComplete  = null;
    onDisconnected       = null;
    onPlayerCountChanged = null;
    _hello               = null;
    hostWeb              = false;
    currentGameInfo      = null;
    SessionState().clearRoster();
  }

  // ── HOST ──────────────────────────────────────────────────────────────────
  Future<void> startHost() async {
    if (useNearby || useNearbyService) {
      isHost = true; myIdx = 0;
      _wireNearbyCallbacks();
      await _activeTransport.startHost();
      return;
    }
    isHost = true;
    myIdx  = 0;
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        _server = await ServerSocket.bind(
            InternetAddress.anyIPv4, _tcpPort, shared: false);
        break;
      } catch (_) {
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    if (_server == null) throw Exception('Cannot bind port $_tcpPort');
    _acceptLoop();
    if (hostWeb) {
      // Hosted mode: failing to start (port busy, no web client packaged)
      // must not break normal hosting — browsers just can't join then.
      try {
        webCode = (1000 + Random.secure().nextInt(9000)).toString();
        _web = await WebClientServer.start(port: kWebPort, onSocket: _acceptWebSocket);
      } catch (e) {
        debugPrint('[Network] web client server not started: $e');
      }
    }
    _startBeacon();
    _startHostPings();
  }

  void _acceptLoop() {
    _server?.listen((sock) {
      // A connection only becomes a player once it sends HELLO (see
      // _handleFromClient). Until then it is "pending": it gets no index, no
      // broadcasts, and closing it never produces PLAYER_LEFT — so hotspot
      // probes and half-open connections can't create ghost players.
      if (_pending.length >= _maxPlayers) { sock.destroy(); return; }
      final client = _Client(_TcpConn(sock), -1);
      _pending.add(client);
      _wireClient(client, sock);
    }, onError: (_) {});
  }

  /// Hosted mode: a browser opened the web client and connected to /ws.
  /// Same rules as a TCP connection: pending until it sends HELLO.
  void _acceptWebSocket(WebSocket ws) {
    if (_pending.length >= _maxPlayers) { ws.close(); return; }
    final c = _Client(_WsConn(ws), -1);
    _pending.add(c);
    c.sub = ws.listen(
      (data) {
        if (!_appPaused) _resetClientWatchdog(c);
        if (data is! String || data.length > 1 << 20) return;
        for (final line in data.split('\n')) {
          if (line.trim().isEmpty) continue;
          try { _handleFromClient(jsonDecode(line) as Map<String, dynamic>, c); } catch (_) {}
        }
      },
      onDone:  () => _clientDisconnected(c),
      onError: (_) => _clientDisconnected(c),
      cancelOnError: false,
    );
    _resetClientWatchdog(c);
  }

  void _wireClient(_Client c, Socket socket) {
    c.sub = socket
        .transform(StreamTransformer<Uint8List, String>.fromHandlers(
          handleData: (data, sink) =>
              sink.add(utf8.decode(data, allowMalformed: true))))
        .listen(
      (chunk) {
        if (!_appPaused) _resetClientWatchdog(c);
        c.buf.write(chunk);
        if (c.buf.length > 1 << 20) { _clientDisconnected(c); return; }
        final s = c.buf.toString();
        final lines = s.split('\n');
        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          try { _handleFromClient(jsonDecode(line) as Map<String, dynamic>, c); } catch (_) {}
        }
        c.buf.clear();
        c.buf.write(lines.last);
      },
      onDone:  () => _clientDisconnected(c),
      onError: (_) => _clientDisconnected(c),
      cancelOnError: false,
    );
    _resetClientWatchdog(c);
  }

  void _resetClientWatchdog(_Client c) {
    if (_appPaused) return;
    c.watchdog?.cancel();
    c.watchdog = Timer(c.idx < 0 ? _helloTimeout : _pingTimeout,
        () => _clientDisconnected(c));
  }

  /// Picks the index for a joiner that just sent HELLO: its old index if a
  /// live connection already carries the same player id (that stale
  /// connection is dropped silently — no PLAYER_LEFT), else the lowest free
  /// index 1..3. Returns null when the session is full.
  int? _claimIdx(_Client c, String? playerId) {
    if (playerId != null) {
      for (final old in _clients.values.toList()) {
        if (old != c && old.playerId == playerId) {
          _clients.remove(old.idx);
          _dropSilently(old);
          return old.idx;
        }
      }
    }
    for (int i = 1; i < _maxPlayers; i++) {
      if (!_clients.containsKey(i)) return i;
    }
    return null;
  }

  void _dropSilently(_Client c) {
    c.watchdog?.cancel();
    c.awayTimer?.cancel();
    c.awayTimer = null;
    try { c.sub?.cancel(); } catch (_) {}
    try { c.conn.destroy(); } catch (_) {}
    _pending.remove(c);
  }

  void _handleFromClient(Map<String, dynamic> msg, _Client c) {
    switch (msg['type'] as String?) {
      case 'PONG': break;
      case 'PING':
        final now = DateTime.now();
        if (now.difference(c.lastPing).inSeconds >= 1) {
          c.lastPing = now;
          _sendToClient(c, {'type': 'PONG'});
        }
        break;
      case 'HELLO':
        final playerId = msg['id'] as String?;
        // Browser players need the join code from the host's screen / QR code
        if (c.conn is _WsConn && msg['code'] != webCode) {
          _sendToClient(c, {'type': 'JOIN_REJECTED', 'reason': 'code'});
          Future.delayed(const Duration(milliseconds: 300), () => _dropSilently(c));
          return;
        }
        // A browser player coming back to its held seat (see _clientDisconnected)
        final wasAway = playerId != null && _clients.values.any(
            (o) => o != c && o.playerId == playerId && o.awayTimer != null);
        if (c.idx < 0) {
          final idx = _claimIdx(c, playerId);
          if (idx == null) { _dropSilently(c); return; } // session full
          _pending.remove(c);
          c.idx = idx;
          _clients[idx] = c;
          _resetClientWatchdog(c);
        }
        c.playerId = playerId;
        _sendToClient(c, {'type': 'HELLO_ACK', 'idx': c.idx});
        _receive({...msg, '_from': c.idx}, c.idx);
        onConnected?.call();
        onPlayerCountChanged?.call(_clients.length + 1);
        if (wasAway) {
          final back = {'type': 'PLAYER_BACK', 'idx': c.idx,
              'name': SessionState().rosterByIdx[c.idx]?.name};
          try { _broadcastExcept(back, c.idx); } catch (_) {}
          _receive(back, c.idx);
          // Page was reloaded (joined from its start screen, not the in-game
          // reconnect dialog): send it to game select; its WaitingScreen then
          // asks for the running game (WAITING_SYNC_REQ → START_GAME).
          if (msg['lobby'] == true && currentGameInfo != null) {
            _sendToClient(c, {'type': 'BACK_TO_SELECT'});
          }
        }
        break;
      default:
        if (c.idx < 0) break; // not a player until HELLO
        // Relay CHAT, CHAT_TYPING, CHAT_READ from one client to all others
        // so 3+ player chat works correctly.
        if (msg['type'] == 'CHAT' ||
            msg['type'] == 'CHAT_TYPING' ||
            msg['type'] == 'CHAT_READ') {
          try { _broadcastExcept(msg, c.idx); } catch (_) {}
        }
        _receive({...msg, '_from': c.idx}, c.idx);
    }
  }

  void _clientDisconnected(_Client c) {
    // Browser player in a running game (phone went dark, app switch): hold the
    // seat so it can reconnect with the same player id and carry on. Only
    // after the grace period does it count as having left.
    if (c.conn is _WsConn && c.idx >= 0 && identical(_clients[c.idx], c) &&
        currentGameInfo != null && c.awayTimer == null) {
      c.watchdog?.cancel();
      try { c.sub?.cancel(); } catch (_) {}
      try { c.conn.destroy(); } catch (_) {}
      final away = {'type': 'PLAYER_AWAY', 'idx': c.idx,
          'name': SessionState().rosterByIdx[c.idx]?.name};
      try { _broadcastExcept(away, c.idx); } catch (_) {}
      _receive(away, c.idx);
      c.awayTimer = Timer(_awayGrace, () {
        c.awayTimer = null;
        _clientDisconnected(c);
      });
      return;
    }
    _dropSilently(c);
    // Only a registered player (HELLO sent, still the live connection for its
    // index) produces PLAYER_LEFT. Pending connections (e.g. a hotspot probe)
    // and connections already replaced by a reconnect vanish silently.
    if (c.idx < 0 || !identical(_clients[c.idx], c)) return;
    _clients.remove(c.idx);
    final leftMsg = _playerLeftMsg(c.idx);
    try { _broadcastExcept(leftMsg, -1); } catch (_) {}
    onPlayerCountChanged?.call(_clients.length + 1);
    // Restart beacon so the disconnected player can rediscover the host
    if (_beaconTimer == null && _server != null) _startBeacon();
    // Also deliver PLAYER_LEFT to the host's own message handler
    // so game screens can react (redirect everyone to game select etc.)
    _receive(leftMsg, c.idx);
  }

  void _startBeacon() async {
    if (_beaconTimer != null) return; // already running or being started
    // Set a sentinel so concurrent calls don't start a second beacon
    _beaconTimer = Timer(Duration.zero, () {});
    try {
      _udp?.close();
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udp!.broadcastEnabled = true;
      final data      = utf8.encode(_beaconMsg);
      final multicast = InternetAddress(_multicastAddr);
      final broadcast = InternetAddress('255.255.255.255');
      void sendBeacon() {
        try { _udp?.send(data, multicast, _udpPort); } catch (_) {}
        try { _udp?.send(data, broadcast, _udpPort); } catch (_) {}
      }
      sendBeacon();
      _beaconTimer?.cancel();
      _beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) => sendBeacon());
    } catch (_) {
      _beaconTimer?.cancel();
      _beaconTimer = null;
    }
  }

  /// Host on WiFi: make sure the UDP beacon runs (it is stopped when a game
  /// starts) so players can (re)join while everyone is on game select.
  void ensureDiscoverable() {
    if (isHost && !isSolo && !useNearby && !useNearbyService && _server != null) {
      _startBeacon();
    }
  }

  void _startHostPings() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_appPaused) return;
      // Skip ping if a real message was sent within the last ping interval —
      // the remote side already knows we're alive.
      if (DateTime.now().difference(_lastSendTime) < _pingInterval) return;
      _broadcastAll({'type': 'PING'});
    });
  }

  // ── JOINER ────────────────────────────────────────────────────────────────
  Future<void> startDiscovery(void Function(String ip) onFound) async {
    if (useNearby || useNearbyService) {
      isHost = false;
      _wireNearbyCallbacks();
      await _activeTransport.startDiscovery(onFound);
      return;
    }
    isHost = false;
    _udp?.close(); _udp = null;
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpPort,
        reuseAddress: true, reusePort: true);
    try { _udp?.joinMulticast(InternetAddress(_multicastAddr)); } catch (_) {}
    final udp = _udp;
    if (udp == null) return;
    udp.broadcastEnabled = true;
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _udp?.receive();
      if (dg == null) return;
      final text = utf8.decode(dg.data, allowMalformed: true).trim();
      if (text == _beaconMsg) onFound(dg.address.address);
    });
  }

  void stopDiscovery() { _udp?.close(); _udp = null; }

  static const _hotspotIPs = ['192.168.43.1', '192.168.49.1'];

  /// Joiner: finds a host on a phone hotspot by opening (and closing) a TCP
  /// connection to the game port. Harmless for the host: a connection is not
  /// a player until it sends HELLO, so the probe never shows up in the lobby.
  Future<void> probeHotspot(void Function(String ip) onFound) async {
    stopDiscovery();
    bool found = false;
    for (final ip in _hotspotIPs) {
      Socket.connect(ip, _tcpPort, timeout: const Duration(seconds: 3)).then((sock) {
        sock.destroy();
        if (!found) { found = true; onFound(ip); }
      }).catchError((_) {});
    }
  }

  Future<void> connectTo(String ip) async {
    if (useNearby || useNearbyService) {
      await _activeTransport.connectTo(ip);
      return;
    }
    stopDiscovery();
    if (kIsWeb) {
      // Browser guest (Hosted mode): WebSocket to the host that served us
      final chan = WebSocketChannel.connect(
          Uri(scheme: 'ws', host: ip, port: kWebPort, path: '/ws'));
      await chan.ready.timeout(const Duration(seconds: 8));
      _wsChan = chan;
      _wsSub = chan.stream.listen(
        (data) {
          if (!_appPaused) _resetWatchdog();
          if (data is! String) return;
          for (final line in data.split('\n')) {
            if (line.trim().isEmpty) continue;
            try { _handleIncoming(jsonDecode(line) as Map<String, dynamic>); } catch (_) {}
          }
        },
        onDone:  () => _handleDisconnect(),
        onError: (_) => _handleDisconnect(),
        cancelOnError: false,
      );
    } else {
      _socket = await Socket.connect(ip, _tcpPort,
          timeout: const Duration(seconds: 8));
      _wireSocket(_socket!);
    }
    _resetWatchdog();
    _startJoinerPings();
    // Exactly one HELLO per connection — screens never send HELLO themselves.
    if (_hello != null) {
      _sendRaw({'type': 'HELLO', ..._hello!,
        if (kIsWeb) 'code': joinCode, if (helloFromLobby) 'lobby': true});
    }
    onConnected?.call();
  }

  void _startJoinerPings() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_appPaused) return;
      if (DateTime.now().difference(_lastSendTime) < _pingInterval) return;
      _sendRaw({'type': 'PING'});
    });
  }

  void _resetWatchdog() {
    if (_appPaused) return;
    _watchdog?.cancel();
    _watchdog = Timer(_pingTimeout, _handleDisconnect);
  }

  void _wireSocket(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _buf.clear();
    _tcpSub = socket
        .transform(StreamTransformer<Uint8List, String>.fromHandlers(
          handleData: (data, sink) =>
              sink.add(utf8.decode(data, allowMalformed: true))))
        .listen(
      (chunk) {
        if (!_appPaused) _resetWatchdog();
        _buf.write(chunk);
        if (_buf.length > 1 << 20) { _handleDisconnect(); return; }
        final s = _buf.toString();
        final lines = s.split('\n');
        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          try { _handleIncoming(jsonDecode(line) as Map<String, dynamic>); } catch (_) {}
        }
        _buf.clear();
        _buf.write(lines.last);
      },
      onDone:  () => _handleDisconnect(),
      onError: (_) => _handleDisconnect(),
      cancelOnError: false,
    );
  }

  void _handleIncoming(Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
      case 'PING':
        _sendRaw({'type': 'PONG'});
        break;
      case 'PONG': break;
      case 'HELLO_ACK':
        final idx = msg['idx'] as int? ?? 1;
        if (idx >= 0 && idx <= _maxPlayers - 1) myIdx = idx;
        try { onHandshakeComplete?.call(); } catch (_) {}
        break;
      default:
        _receive(msg, 0);
    }
  }

  // ── Incoming pipeline (all transports) ────────────────────────────────────
  /// Every message from a remote player passes through here: session-level
  /// messages (HELLO / PLAYER_LEFT on the host, ROSTER / REINDEX on joiners)
  /// update the roster first, then the message goes to the screens.
  void _receive(Map<String, dynamic> msg, int fromIdx) {
    try {
      final type = msg['type'] as String?;
      if (isHost) {
        if (type == 'HELLO') {
          _rosterOnHello(fromIdx, msg);
        } else if (type == 'PLAYER_LEFT') {
          final idx = msg['idx'] as int? ?? fromIdx;
          // Nearby transports synthesise a bare PLAYER_LEFT — add name/id and
          // tell the other joiners (the WiFi path already did both).
          if (msg['id'] == null) {
            final p = SessionState().rosterByIdx[idx];
            if (p != null) msg = {...msg, 'name': p.name, 'id': p.id};
            if (useNearby || useNearbyService) {
              final out = Map<String, dynamic>.from(msg)..remove('_from');
              out.remove('type');
              _activeTransport.send('PLAYER_LEFT', out);
            }
          }
          if (SessionState().rosterRemove(idx) != null) _broadcastRoster();
        }
      } else {
        if (type == 'HOST_LEFT') {
          // Host went back to the start screen: the coming disconnect is
          // intentional, so no reconnect dialog.
          onDisconnected      = null;
          onHandshakeComplete = null;
          final cb = onHostLeft;
          if (cb != null) Future.microtask(cb);
          return;
        } else if (type == 'ROSTER') {
          SessionState().applyRosterJson(msg['players'] as List? ?? const []);
        } else if (type == 'REINDEX') {
          final idx = msg['idx'] as int?;
          if (idx != null && idx >= 1 && idx <= _maxPlayers - 1) myIdx = idx;
        }
      }
    } catch (_) {}
    try { _dispatch(msg, fromIdx); _legacyHandler?.call(msg, fromIdx); } catch (_) {}
  }

  // ── Roster (host-authoritative list of connected HUMAN players) ───────────
  /// Host: start a fresh roster with ourselves at index 0.
  void initHostRoster(Player me) => SessionState().setRoster({0: me});

  Map<String, dynamic> _playerLeftMsg(int idx) {
    final p = SessionState().rosterByIdx[idx];
    return {
      'type': 'PLAYER_LEFT', 'idx': idx,
      if (p != null) 'name': p.name,
      if (p != null) 'id': p.id,
    };
  }

  void _rosterOnHello(int idx, Map<String, dynamic> msg) {
    if (idx < 1) return;
    final session = SessionState();
    final others = session.rosterByIdx.entries.where((e) => e.key != idx);
    final used = others.map((e) => e.value.color.value).toSet();
    var color = Color(msg['color'] as int? ?? kPlayerColors[idx % kPlayerColors.length].value);
    if (used.contains(color.value)) {
      color = kPlayerColors.firstWhere((c) => !used.contains(c.value),
          orElse: () => kPlayerColors[idx % kPlayerColors.length]);
    }
    final id = msg['id'] as String? ?? 'p-$idx';
    // A player can only be in the roster once
    for (final e in others.toList()) {
      if (e.value.id == id) session.rosterRemove(e.key);
    }
    session.rosterPut(idx, Player(
      id: id, name: msg['name'] as String? ?? 'Player', color: color));
    _broadcastRoster();
  }

  void _broadcastRoster() {
    if (!isHost || isSolo) return;
    send('ROSTER', {'players': SessionState().rosterToJson()});
  }

  Set<int> get _connectedJoinerIndices {
    if (useNearby || useNearbyService) {
      final Object t = _activeTransport;
      return t is IHostIndexing ? t.connectedIndices : <int>{};
    }
    return _clients.keys.toSet();
  }

  /// Host, only while nobody is in a game (LobbyScreen / WaitingScreen):
  /// drops roster entries without a live connection and renumbers joiners to
  /// 1..n-1 in their current order. Moved joiners get REINDEX {'idx': new};
  /// everyone gets the new ROSTER. Returns true if anything changed.
  bool compactRoster() {
    if (!isHost || isSolo) return false;
    final session   = SessionState();
    final byIdx     = session.rosterByIdx;
    final connected = _connectedJoinerIndices;
    final keys      = byIdx.keys.where((k) => k == 0 || connected.contains(k)).toList()..sort();
    bool changed    = keys.length != byIdx.length;
    // Renumber every live connection (normally identical to the roster's
    // joiners) so the transport's index map stays collision-free.
    final order     = {...keys.where((k) => k != 0), ...connected}.toList()..sort();
    final mapping   = <int, int>{};
    int next = 1;
    for (final k in order) {
      if (k != next) mapping[k] = next;
      next++;
    }
    if (mapping.isNotEmpty) {
      changed = true;
      if (useNearby || useNearbyService) {
        final Object t = _activeTransport;
        if (t is IHostIndexing) t.remapIndices(mapping);
      } else {
        final moved = <int, _Client>{};
        for (final c in _clients.values) {
          c.idx = mapping[c.idx] ?? c.idx;
          moved[c.idx] = c;
        }
        _clients..clear()..addAll(moved);
      }
    }
    if (changed) {
      session.setRoster({for (final k in keys) mapping[k] ?? k: byIdx[k]!});
      for (final newIdx in mapping.values) {
        sendTo(newIdx, 'REINDEX', {'idx': newIdx});
      }
      _broadcastRoster();
    }
    return changed;
  }

  // ── Send helpers (WiFi only — Nearby delegates via sendTo above) ──────────
  void _sendToClient(_Client c, Map<String, dynamic> msg) {
    try { c.conn.write(jsonEncode(msg)); } catch (_) {}
  }

  void _broadcastAll(Map<String, dynamic> msg) {
    _lastSendTime = DateTime.now();
    final json = jsonEncode(msg);
    for (final c in _clients.values) {
      try { c.conn.write(json); } catch (_) {}
    }
  }

  void _broadcastExcept(Map<String, dynamic> msg, int exceptIdx) {
    _lastSendTime = DateTime.now();
    final json = jsonEncode(msg);
    for (final c in _clients.values) {
      if (c.idx == exceptIdx) continue;
      try { c.conn.write(json); } catch (_) {}
    }
  }

  bool get _joinerConnected => _socket != null || _wsChan != null;

  void _sendRaw(Map<String, dynamic> payload) {
    if (!_joinerConnected) return;
    _lastSendTime = DateTime.now();
    try {
      if (_wsChan != null) {
        _wsChan!.sink.add(jsonEncode(payload));
      } else {
        _socket!.write('${jsonEncode(payload)}\n');
      }
    } catch (_) {}
  }

  // Joiner's HELLO payload (Player.toJson()). Sent by Network itself exactly
  // once per established connection — on first join and on every reconnect.
  Map<String, dynamic>? _hello;

  /// Joiner: set the profile sent as HELLO on every (re)connection.
  /// Call before connecting; screens must not send HELLO themselves.
  void setHello(Map<String, dynamic> player) {
    _hello = Map<String, dynamic>.from(player)..remove('type');
  }

  void send(String type, [Map<String, dynamic>? payload]) {
    if (isSolo) return; // AI reads state directly — no messages needed
    final msg = {'type': type, ...?payload};
    netLog.add(_NetLogEntry(msg, -1, outgoing: true));
    if (netLog.length > 200) netLog.removeAt(0);
    if (type == 'HELLO') {
      // Legacy callers: remember the profile. Network already sends HELLO on
      // connect, so don't send a second one on a live connection.
      setHello(msg);
      return;
    }
    if (useNearby || useNearbyService) { _activeTransport.send(type, payload); return; }
    if (isHost) {
      // Stop beacon once the game actually starts — all players are already connected.
      // The beacon serves no purpose during gameplay and wastes WiFi radio cycles.
      if (type == 'START_GAME') { _beaconTimer?.cancel(); _beaconTimer = null; }
      _broadcastAll(msg);
    } else {
      _sendRaw(msg);
    }
  }

  Future<void> sendAndFlush(String type, [Map<String, dynamic>? payload]) async {
    if (useNearby || useNearbyService) { await _activeTransport.sendAndFlush(type, payload); return; }
    send(type, payload);
    try {
      if (isHost) {
        final clients = _clients.values.toList();
        await Future.wait(clients.map((c) => c.conn.flush()));
      } else if (_socket != null) {
        await _socket!.flush();
      }
    } catch (_) {}
  }

  int get playerCount => (useNearby || useNearbyService)
      ? _activeTransport.playerCount
      : (isHost ? _clients.length + 1 : 1);

  void sendTo(int playerIdx, String type, [Map<String, dynamic>? payload]) {
    if (useNearby || useNearbyService) { _activeTransport.sendTo(playerIdx, type, payload); return; }
    final client = _clients[playerIdx];
    if (client == null) return;
    _sendToClient(client, {'type': type, ...?payload});
  }

  // ── Disconnect ────────────────────────────────────────────────────────────
  void _handleDisconnect() {
    _watchdog?.cancel();    _watchdog    = null;
    _pingTimer?.cancel();   _pingTimer   = null;
    _beaconTimer?.cancel(); _beaconTimer = null;
    for (final c in [..._clients.values, ..._pending]) {
      c.watchdog?.cancel();
      c.awayTimer?.cancel();
      try { c.sub?.cancel(); } catch (_) {}
      try { c.conn.destroy(); } catch (_) {}
    }
    _clients.clear();
    _pending.clear();
    try { _wsSub?.cancel(); } catch (_) {}
    _wsSub = null;
    try { _wsChan?.sink.close(); } catch (_) {}
    _wsChan = null;
    try { _web?.stop(); } catch (_) {}
    _web = null;
    try { _tcpSub?.cancel(); } catch (_) {}
    _tcpSub = null;
    try { _socket?.destroy(); } catch (_) {}
    _socket = null;
    try { _server?.close(); } catch (_) {}
    _server = null;
    _udp?.close(); _udp = null;
    _buf.clear();
    _fireDisconnect();
  }
}

// ── Network log entry (used by SuperuserScreen) ───────────────────────────────
class _NetLogEntry {
  final String time;
  final String type;
  final int fromIdx;
  final bool outgoing;
  final String raw;

  _NetLogEntry(Map<String, dynamic> msg, int from, {required this.outgoing})
      : time = _fmtTime(),
        type = msg['type'] as String? ?? '?',
        fromIdx = from,
        raw = _shortJson(msg);

  static String _fmtTime() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2,'0')}:'
        '${n.minute.toString().padLeft(2,'0')}:'
        '${n.second.toString().padLeft(2,'0')}';
  }

  static String _shortJson(Map<String, dynamic> msg) {
    final copy = Map<String, dynamic>.from(msg)..remove('type');
    if (copy.isEmpty) return '';
    try {
      final s = copy.toString();
      return s.length > 80 ? '${s.substring(0, 80)}…' : s;
    } catch (_) { return ''; }
  }
}

// Public alias so SuperuserScreen can reference it
typedef NetLogEntry = _NetLogEntry;
