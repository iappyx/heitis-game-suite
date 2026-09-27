/// Abstract transport interface.
/// Both WifiTransport (existing TCP/UDP) and NearbyTransport implement this.
///
/// Player index semantics stay the same as before:
///   host  = idx 0
///   joiners = idx 1..3 (lowest free index on HELLO; compacted by the host
///   via Network.compactRoster() while nobody is in a game)
///
/// The host is always authoritative and relays messages between players.
abstract class ITransport {
  // ── State ─────────────────────────────────────────────────────────────────
  bool get isHost;
  int  get myIdx;

  // ── Callbacks — set by consumer before calling start* ────────────────────
  /// A message arrived from another player.
  /// [fromIdx] is the sender's player index (0 = host when joiner receives).
  void Function(Map<String, dynamic> msg, int fromIdx)? onMessageFrom;

  /// A TCP/Nearby connection was established (before HELLO handshake).
  void Function()? onConnected;

  /// HELLO_ACK received — handshake complete, we're fully in the session.
  void Function()? onHandshakeComplete;

  /// We were disconnected (socket closed / endpoint lost).
  void Function()? onDisconnected;

  /// Number of connected clients changed (host only).
  void Function(int count)? onPlayerCountChanged;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  Future<void> startHost();
  Future<void> startDiscovery(void Function(String id) onFound);
  Future<void> connectTo(String id);
  void stopDiscovery();

  /// Clears sockets/connections but keeps callbacks.
  Future<void> softReset();

  /// Full reset — clears sockets AND callbacks.
  Future<void> reset();

  // ── Messaging ─────────────────────────────────────────────────────────────
  void send(String type, [Map<String, dynamic>? payload]);
  Future<void> sendAndFlush(String type, [Map<String, dynamic>? payload]);
  void sendTo(int playerIdx, String type, [Map<String, dynamic>? payload]);

  int get playerCount;

  // Hotspot-specific (only relevant for WifiTransport)
  Future<void> probeHotspot(void Function(String id) onFound) async {}
}

/// Host-side player-index management, implemented by transports that can
/// re-key their connections (kept separate from [ITransport] so the web stub
/// does not need to implement it).
///
/// Index rules shared by every transport:
///  - A connection is NOT a player until it has sent HELLO. Connections that
///    close before HELLO never produce PLAYER_LEFT.
///  - On HELLO the joiner gets the lowest free index in 1..3. If a live
///    connection already carries the same player id (a reconnect the host has
///    not noticed yet), the old connection is dropped silently and the new one
///    takes over its index.
abstract class IHostIndexing {
  /// Indices (≥ 1) of joiners that are connected AND have sent HELLO.
  Set<int> get connectedIndices;

  /// Re-key connections: every key of [oldToNew] moves to its value.
  /// The mapping must be injective; unmapped connections keep their index.
  void remapIndices(Map<int, int> oldToNew);
}
