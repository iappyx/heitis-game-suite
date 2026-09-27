import 'transport.dart';

/// Stub implementation of NearbyTransport for platforms where
/// nearby_connections (Google Nearby Connections API) is not available (iOS).
/// The Bluetooth tab is hidden on iOS so this should never be called.
class NearbyTransport implements ITransport {
  @override bool isHost = false;
  @override int  myIdx  = 0;

  @override void Function(Map<String, dynamic>, int)? onMessageFrom;
  @override void Function()? onConnected;
  @override void Function()? onHandshakeComplete;
  @override void Function()? onDisconnected;
  @override void Function(int)? onPlayerCountChanged;

  void setPlayerName(String name) {}

  @override Future<void> softReset() async {}
  @override Future<void> reset() async {}
  @override Future<void> startHost() async {}
  @override Future<void> startDiscovery(void Function(String) onFound) async {}
  @override void stopDiscovery() {}
  @override Future<void> connectTo(String id) async {}
  @override void send(String type, [Map<String, dynamic>? payload]) {}
  @override Future<void> sendAndFlush(String type, [Map<String, dynamic>? payload]) async {}
  @override void sendTo(int playerIdx, String type, [Map<String, dynamic>? payload]) {}
  @override int get playerCount => 1;
  @override Future<void> probeHotspot(void Function(String) onFound) async {}
}
