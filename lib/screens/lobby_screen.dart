import '../core/platform_info.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network.dart';
import '../core/session.dart';
import '../core/wake_lock.dart';
import '../core/player.dart';
import '../core/theme.dart';
import '../core/bt_permissions.dart';
import '../l10n/app_localizations.dart';
import 'waiting_screen.dart';
import 'solo_setup_screen.dart';
import '../widgets/app_version.dart';
import 'about_screen.dart';
import '../widgets/connection_help.dart';
import '../widgets/web_invite.dart';
import '../core/stats_store.dart';
import '../core/profile_store.dart';
import '../core/sound_player.dart';

enum _LobbyMode { idle, hosting, joining, connecting }
// Which transport the user has selected
enum _Transport { wifi, bluetooth, nearbyService }

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription<(Map<String, dynamic>, int)>? _msgSub;
  final _nameCtrl  = TextEditingController();
  // Browser guest (Hosted mode): join code from the QR address, or typed in
  final _codeCtrl  = TextEditingController(
      text: isWebClient ? (Uri.base.queryParameters['code'] ?? '') : '');
  bool _codeWrong  = false;
  Color _color     = kPlayerColors[0];
  String? _status;
  _LobbyMode _mode = _LobbyMode.idle;
  // Bluetooth (Google Nearby Connections) is Android-only; macOS defaults to WiFi
  _Transport _transport = isAndroidApp ? _Transport.bluetooth
      : isIOSApp ? _Transport.nearbyService : _Transport.wifi;
  final _found     = <String>[];
  final _net       = Network();
  String? _avatarPath;
  bool _hotspot    = false;
  bool _lastWasHost = true; // remembered host/join preference
  Timer? _discoveryTimer;
  // Live list of connected players — the roster kept by Network/SessionState
  // (host decides, broadcast to joiners as ROSTER). Host always index 0.
  List<Player> get _lobbyPlayers => SessionState().roster;
  bool get _hostReady => _lobbyPlayers.length > 1; // at least 1 joiner connected
  bool _leaving = false; // navigation to WaitingScreen started

  @override void initState() {
    super.initState();
    _net.reset();
    SessionState().reset();   // resets game state, chat history is preserved
    SessionState().loadChat(); // load persisted chat history
    WakeLock.release();
    _loadPrefs();
    StatsStore().load();
    ProfileStore().load().then((_) => _syncFromActiveProfile());
    SessionState().rosterRevision.addListener(_onRosterChanged);
  }

  void _onRosterChanged() {
    if (!mounted) return;
    setState(() {
      // Joiner: adopt the (possibly de-duplicated) colour the host gave us
      if (!_net.isHost) {
        final me = SessionState().rosterByIdx[_net.myIdx];
        if (me != null && _net.myIdx > 0) _color = me.color;
      }
    });
  }

  /// Sync lobby fields from the active profile (called after ProfileStore loads).
  void _syncFromActiveProfile() {
    final profile = ProfileStore().active;
    if (profile == null || !mounted) return;
    setState(() {
      _nameCtrl.text = profile.name;
      _color         = profile.color;
      _avatarPath    = profile.avatarPath;
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = prefs.getString('player_name') ?? '';
      final cv = prefs.getInt('player_color');
      if (cv != null) _color = Color(cv);
      _avatarPath = prefs.getString('avatar_path');
      // Restore last connection settings
      final ti = prefs.getInt('lobby_transport');
      if (ti != null && ti >= 0 && ti < _Transport.values.length &&
          (isAndroidApp || _Transport.values[ti] != _Transport.bluetooth)) {
        _transport = _Transport.values[ti];
      }
      _lastWasHost = prefs.getBool('lobby_was_host') ?? true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final name  = _nameCtrl.text.trim();
    await prefs.setString('player_name', name);
    await prefs.setInt('player_color', _color.value);
    if (_avatarPath != null) await prefs.setString('avatar_path', _avatarPath!);
    else await prefs.remove('avatar_path');
    // Persist connection settings
    await prefs.setInt('lobby_transport', _transport.index);
    await prefs.setBool('lobby_was_host', _lastWasHost);

    // Also persist to ProfileStore
    final store  = ProfileStore();
    final active = store.active;
    if (active != null) {
      await store.updateProfile(active.copyWith(
        name:       name.isEmpty ? active.name : name,
        colorValue: _color.value,
        avatarPath: _avatarPath,
      ));
    } else if (name.isNotEmpty) {
      await store.createProfile(
          name: name, colorValue: _color.value, avatarPath: _avatarPath);
    }
  }

  @override void dispose() {
    SessionState().rosterRevision.removeListener(_onRosterChanged);
    _discoveryTimer?.cancel();
    _msgSub?.cancel();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    // Only tear down network resources in idle mode (user navigated back without
    // connecting). In all other modes the TCP/UDP sockets are actively needed by
    // the screen we're navigating TO, so we must not destroy them here.
    if (_mode == _LobbyMode.idle) {
      _net.softReset();
    } else {
      // Don't leave closures of this disposed screen on the singleton
      _net.onConnected = null;
      _net.onPlayerCountChanged = null;
    }
    super.dispose();
  }

  bool get _busy => _mode != _LobbyMode.idle;

  // Random per app run. Part of our player id so two tablets with the same
  // profile id (Android Auto Backup restores SharedPreferences on a new
  // device) never claim each other's index.
  // In the browser the profile (and its id) lives in this browser's storage
  // only, so it is unique and must stay the same across a page reload — a
  // reloaded page then gets its held seat back (Hosted mode).
  static final String _runTag = isWebClient ? 'web' : List.generate(6,
      (_) => Random().nextInt(36).toRadixString(36)).join();

  /// Player id sent as HELLO: stable per profile for the whole app run, so a
  /// player who goes back to the lobby and rejoins (same or new LobbyScreen)
  /// is recognised by the host and takes over their old index instead of
  /// appearing twice next to a ghost. _savePrefs() creates a profile before
  /// host/join; 'p-' is only a fallback if ProfileStore failed.
  Player _buildMe() {
    return Player(
      id: '${ProfileStore().active?.id ?? 'p'}-$_runTag',
      name: _nameCtrl.text.trim().isEmpty ? L.common.defaultPlayer : _nameCtrl.text.trim(),
      color: _color, avatarPath: _avatarPath,
    );
  }

  Future<void> _cancel() async {
    _discoveryTimer?.cancel();
    await _net.leaveSession(); // host: tells joiners that already joined
    await WakeLock.release();
    if (mounted) setState(() {
      _mode = _LobbyMode.idle; _status = null;
      _found.clear(); _hotspot = false;
    });
  }

  // ── SOLO ──────────────────────────────────────────────────────────────────
  bool _soloNav = false;
  Future<void> _goSolo() async {
    if (_soloNav) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _status = L.common.yourName);
      return;
    }
    _soloNav = true;
    await _savePrefs();
    final me = Player(id: 'solo-human', name: name, color: _color, avatarPath: _avatarPath);
    if (!mounted) return;
    Navigator.push(context, fadeScaleRoute(
      SoloSetupScreen(humanPlayer: me))).then((_) => _soloNav = false);
  }

  // ── HOST ──────────────────────────────────────────────────────────────────
  Future<void> _host() async {
    if (_busy) return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _status = L.common.yourName);
      return;
    }
    if (_transport == _Transport.bluetooth ||
        _transport == _Transport.nearbyService) {
      final granted = await requestBluetoothPermissions(context);
      if (!granted || !mounted) return;
    }
    _lastWasHost = true;
    setState(() { _mode = _LobbyMode.hosting; _status = null; _found.clear(); });
    await _savePrefs();
    await _net.reset();
    _net.useNearby        = (_transport == _Transport.bluetooth);
    _net.useNearbyService = (_transport == _Transport.nearbyService);
    if (_net.useNearby || _net.useNearbyService) _net.setNearbyPlayerName(_buildMe().name);
    final me = _buildMe();
    // Network keeps the roster: joiners are added on HELLO, removed on
    // PLAYER_LEFT, and broadcast to everyone as ROSTER.
    _net.initHostRoster(me);

    _msgSub?.cancel();
    _msgSub = _net.listen(_onHostMsg);
    _net.onConnected = () {
      if (mounted) setState(() {});
    };
    _net.onPlayerCountChanged = (count) {
      if (mounted) setState(() {});
    };
    _net.onDisconnected = () {
      if (mounted) setState(() {});
    };

    // Hosted mode: on WiFi, browsers can join too (QR code in the lobby)
    _net.hostWeb = _transport == _Transport.wifi;
    try {
      await _net.startHost();
      if (mounted) setState(() {});
    } catch (e) {
      await _net.reset();
      if (mounted) setState(() { _mode = _LobbyMode.idle; _status = L.common.connectionFailed; });
    }
  }

  // ── Host message handler ──────────────────────────────────────────────────
  // Roster bookkeeping (HELLO → add, PLAYER_LEFT → remove, ROSTER broadcast)
  // is done by Network before the message arrives here.
  void _onHostMsg(Map<String, dynamic> msg, int fromIdx) {
    switch (msg['type'] as String?) {
      case 'HELLO':
        if (mounted) setState(() {});
        break;
      case 'PLAYER_LEFT':
        // Nobody is in a game yet — renumber joiners to 1..n-1 right away
        _net.compactRoster();
        if (mounted) setState(() {});
        break;
    }
  }

  // ── Joiner message handler ────────────────────────────────────────────────
  void _onJoinMsg(Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
      case 'JOIN_REJECTED':
        // Browser guest sent a wrong join code — show the code field again
        _codeWrong = true;
        if (mounted) setState(() { _mode = _LobbyMode.idle; _status = L.common.webCodeWrong; });
        break;
      case 'LOBBY_START':
      case 'BACK_TO_SELECT':
        // LOBBY_START: host started the session. BACK_TO_SELECT: we (re)joined
        // a host that is already on the game-select screen.
        final roster = SessionState().roster;
        final fallback = (msg['players'] as List?)
          ?.map((j) => Player.fromJson(Map<String, dynamic>.from(j as Map))).toList();
        _goToWaiting(roster.length > 1 ? roster : (fallback ?? roster), isHost: false);
        break;
    }
  }

  void _startLobby() {
    if (!_hostReady || _leaving) return;
    _net.compactRoster();
    final list = _lobbyPlayers.map((p) => p.toJson()).toList();
    _net.send('LOBBY_START', {'players': list});
    _goToWaiting(_lobbyPlayers, isHost: true);
  }

  // ── JOIN ──────────────────────────────────────────────────────────────────
  Future<void> _join() async {
    if (_busy) return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _status = L.common.yourName);
      return;
    }
    if (_transport == _Transport.bluetooth ||
        _transport == _Transport.nearbyService) {
      final granted = await requestBluetoothPermissions(context);
      if (!granted || !mounted) return;
    }
    _lastWasHost = false;
    final searchMsg = (_transport == _Transport.bluetooth || _transport == _Transport.nearbyService)
        ? L.common.btSearching : L.common.searchingForHost;
    setState(() { _mode = _LobbyMode.joining; _status = searchMsg; _found.clear(); });
    await _savePrefs();
    await _net.reset();
    _net.useNearby        = (_transport == _Transport.bluetooth);
    _net.useNearbyService = (_transport == _Transport.nearbyService);
    if (_net.useNearby || _net.useNearbyService) _net.setNearbyPlayerName(_buildMe().name);

    _msgSub?.cancel();
    _msgSub = _net.listen((msg, _) => _onJoinMsg(msg));
    _net.helloFromLobby = true;
    // Network sends this profile as HELLO once per connection (join and
    // reconnect) — never send HELLO from here.
    _net.setHello(_buildMe().toJson());
    _net.onConnected = () {
      if (mounted) setState(() { _mode = _LobbyMode.connecting; _status = L.common.connectedWaiting; });
    };
    _net.onDisconnected = () {
      SessionState().clearRoster();
      if (_codeWrong) return; // keep the "wrong code" message
      if (mounted) setState(() { _mode = _LobbyMode.idle; _status = L.common.hostDisconnected; });
    };

    if (isWebClient) {
      // Browser guest: the host is the server this page came from
      _codeWrong = false;
      _net.joinCode = _codeCtrl.text.trim();
      await _connectTo(Uri.base.host);
      if (mounted && _mode == _LobbyMode.joining) {
        setState(() => _mode = _LobbyMode.idle);
      }
      return;
    }

    try {
      await _net.startDiscovery((ip) {
        _discoveryTimer?.cancel();
        if (!_found.contains(ip)) {
          if (mounted) setState(() { _found.add(ip); _status = null; });
        }
      });
      if (mounted) setState(() { _mode = _LobbyMode.joining; });
      // Show hint after 30s if no hosts found
      _discoveryTimer?.cancel();
      _discoveryTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && _mode == _LobbyMode.joining && _found.isEmpty) {
          setState(() => _status = L.common.noHostsFound);
        }
      });
    } catch (e) {
      await _net.reset();
      if (mounted) setState(() { _mode = _LobbyMode.idle; _status = L.common.connectionFailed; });
    }
  }

  Future<void> _connectTo(String ip) async {
    if (_mode == _LobbyMode.connecting) return;
    setState(() { _mode = _LobbyMode.connecting; _status = L.common.connecting; });
    try {
      await _net.connectTo(ip);
    } catch (e) {
      if (mounted) setState(() { _mode = _LobbyMode.joining; _status = L.common.connectionFailed; });
    }
  }

  void _toggleHotspot(bool val) {
    setState(() => _hotspot = val);
    if (!val) {
      // Switch back to UDP discovery
      _net.startDiscovery((ip) {
        if (!_found.contains(ip)) {
          if (mounted) setState(() { _found.add(ip); _status = null; });
        }
      });
    } else {
      // Switch to hotspot probe
      _net.probeHotspot((ip) {
        if (!_found.contains(ip)) {
          if (mounted) setState(() { _found.add(ip); _status = null; });
        }
      });
    }
  }

  /// Always-visible one-liner under the transport tabs.
  String get _transportSubtitle => switch (_transport) {
    _Transport.wifi          => L.common.tabSubWifi,
    _Transport.bluetooth     => L.common.tabSubBluetooth,
    _Transport.nearbyService => isAndroidApp
        ? L.common.tabSubNearbyAndroid : L.common.tabSubNearbyApple,
  };

  /// Returns a transport-specific hint string for the active transport.
  String get _transportHint => switch (_transport) {
    _Transport.wifi          => L.common.wifiHint,
    _Transport.bluetooth     => L.common.bluetoothHint,
    _Transport.nearbyService => L.common.nearbyHint,
  };

  void _goToWaiting(List<Player> players, {required bool isHost}) {
    if (!mounted || _leaving) return;
    _leaving = true;
    _msgSub?.cancel(); _msgSub = null;
    SessionState()
      ..reset()
      ..myAvatarPath = _avatarPath
      ..preloadAvatar();
    Navigator.pushAndRemoveUntil(context,
      fadeScaleRoute(WaitingScreen(players: players, isHost: isHost)),
      (_) => false);
  }

  // ── Profile switcher ──────────────────────────────────────────────────────
  Future<void> _createNewProfile() async {
    // Pick a color not already taken
    final usedColors = ProfileStore().profiles.map((p) => p.colorValue).toSet();
    final nextColor  = kPlayerColors.firstWhere(
      (c) => !usedColors.contains(c.value),
      orElse: () => kPlayerColors[ProfileStore().profiles.length % kPlayerColors.length],
    );
    final profile = await ProfileStore().createProfile(
      name:       '',
      colorValue: nextColor.value,
    );
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = '';
      _color         = profile.color;
      _avatarPath    = null;
    });
    // Focus name field so user can type immediately
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  // ── Profile edit sheet ────────────────────────────────────────────────────
  Future<void> _editProfile(GameProfile profile) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: kBg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ProfileEditSheet(
        profile: profile,
        onSaved: (name, colorValue, avatarPath, lang) async {
          // Update ProfileStore
          await ProfileStore().updateProfile(profile.copyWith(
            name: name, colorValue: colorValue, avatarPath: avatarPath));
          // Update live lobby state
          if (mounted) setState(() {
            _nameCtrl.text = name;
            _color         = Color(colorValue);
            _avatarPath    = avatarPath;
          });
          // Persist prefs
          await _savePrefs();
        },
        onDelete: ProfileStore().profiles.length > 1 ? () async {
          await ProfileStore().deleteProfile(profile.id);
          if (!mounted) return;
          _syncFromActiveProfile();
          setState(() {});
        } : null,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addProfile() async {
    await _createNewProfile();
    if (!mounted) return;
    final profile = ProfileStore().active;
    if (profile != null) await _editProfile(profile);
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override Widget build(BuildContext ctx) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment.topCenter, radius: 1.2,
          colors: [Color(0xFF2D1060), kBg])),
      child: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(children: [
            // Top bar: about + mute button
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(
                icon: const Icon(Icons.info_outline, color: kMuted),
                tooltip: L.common.about,
                onPressed: () => AboutAppDialog.show(context),
              ),
              StatefulBuilder(builder: (ctx, setSt) => IconButton(
                icon: Icon(SoundPlayer.i.muted ? Icons.volume_off : Icons.volume_up,
                  color: kMuted),
                onPressed: () async {
                  await SoundPlayer.i.toggleMute();
                  setSt(() {});
                },
              )),
            ]),

            // Title
            const Text('🎮', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 56)),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFFE0C3FC), kPurple, Color(0xFFE0C3FC)]).createShader(b),
              child: const Text("Heiti's Game Suite",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                  color: Colors.white, height: 1.1)),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: kPurple.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kPurple.withValues(alpha: .3))),
              child: Text(L.common.appTagline,
                style: const TextStyle(color: kMuted, fontSize: 12)),
            ),
            const SizedBox(height: 4),
            const AppVersionLabel(),
            const SizedBox(height: 28),

            // ── Profile bubbles ──────────────────────────────────────────────
            _buildProfileBubbles(),
            const SizedBox(height: 28),

            // ── Connection card ──────────────────────────────────────────────
            Container(
              decoration: cardDecoration(),
              padding: const EdgeInsets.all(16),
              child: Column(children: [

                // Transport toggle + "which connection?" help
                if (_mode == _LobbyMode.idle && !isWebClient) Row(children: [
                  Expanded(child: _TransportToggle(
                    value: _transport,
                    onChanged: (t) => setState(() => _transport = t),
                  )),
                  IconButton(
                    icon: const Icon(Icons.help_outline, color: kMuted),
                    tooltip: L.common.connHelpTitle,
                    onPressed: () => ConnectionHelpSheet.show(context),
                  ),
                ]),
                if (_mode == _LobbyMode.idle && !isWebClient) Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  child: Text(_transportSubtitle, textAlign: TextAlign.center,
                    style: const TextStyle(color: kMuted, fontSize: 12)),
                ),

                // Browser guest (Hosted mode): can only join the host that served it
                if (_mode == _LobbyMode.idle && isWebClient &&
                    (_codeWrong || Uri.base.queryParameters['code'] == null)) Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kText, fontSize: 22,
                      fontWeight: FontWeight.w900, letterSpacing: 6),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: L.common.webCodeHint,
                      hintStyle: const TextStyle(color: kMuted, fontSize: 14,
                        letterSpacing: 0, fontWeight: FontWeight.normal)),
                  )),
                if (_mode == _LobbyMode.idle && isWebClient) SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: _join, style: primaryButton(),
                    child: Text(L.common.joinBtn))),

                // Host / Join — last-used action is highlighted
                if (_mode == _LobbyMode.idle && !isWebClient) Row(children: [
                  Expanded(child: _lastWasHost
                    ? ElevatedButton(onPressed: _host, style: primaryButton(),
                        child: Text(L.common.hostBtn))
                    : OutlinedButton(onPressed: _host, style: secondaryButton(),
                        child: Text(L.common.hostBtn))),
                  const SizedBox(width: 12),
                  Expanded(child: _lastWasHost
                    ? OutlinedButton(onPressed: _join, style: secondaryButton(),
                        child: Text(L.common.joinBtn))
                    : ElevatedButton(onPressed: _join, style: primaryButton(),
                        child: Text(L.common.joinBtn))),
                ]),
                if (_mode == _LobbyMode.idle) const SizedBox(height: 8),

                // Solo
                if (_mode == _LobbyMode.idle) SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _goSolo,
                    icon: const Icon(Icons.person, size: 16),
                    label: Text(L.common.soloBtn),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kMuted,
                      side: const BorderSide(color: kBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                  )),

                // HOSTING
                if (_mode == _LobbyMode.hosting) ...[
                  _LobbyPlayerList(players: _lobbyPlayers,
                    subtitle: _transport == _Transport.nearbyService
                        ? L.common.waitingForPlayers1
                        : L.common.waitingForPlayers),
                  WebInviteCard(urls: _net.webUrls),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: ElevatedButton(
                      onPressed: _hostReady ? _startLobby : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPurple2, foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text(_hostReady
                        ? L.common.startN.fmt({'n': _lobbyPlayers.length})
                        : (_transport == _Transport.nearbyService
                            ? L.common.waitingForPlayers1
                            : L.common.waitingForPlayers)))),
                    const SizedBox(width: 8),
                    TextButton(onPressed: _cancel,
                      child: const Text('✕', style: TextStyle(
                        fontFamilyFallback: ['NotoColorEmoji'], color: kMuted))),
                  ]),
                ],

                // JOINING
                if (_mode == _LobbyMode.joining || _mode == _LobbyMode.connecting) ...[
                  if (_mode == _LobbyMode.joining && _found.isEmpty) ...[
                    const CircularProgressIndicator(color: kPurple),
                    const SizedBox(height: 10),
                    Text(_status ?? L.common.searchingForHost,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kMuted, fontSize: 13)),
                    if (_status == L.common.noHostsFound ||
                        _status == L.common.connectionFailed) ...[
                      const SizedBox(height: 6),
                      Text(_transportHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kMuted, fontSize: 11)),
                    ],
                    const SizedBox(height: 12),
                    if (_transport == _Transport.wifi)
                      HotspotToggle(value: _hotspot, onChanged: _toggleHotspot),
                  ] else if (_mode == _LobbyMode.joining) ...[
                    Text((_transport == _Transport.bluetooth ||
                          _transport == _Transport.nearbyService)
                        ? L.common.btFoundHost : L.common.foundHost,
                      style: const TextStyle(color: kMuted, fontSize: 13)),
                    const SizedBox(height: 8),
                    ..._found.map((id) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ElevatedButton(
                        onPressed: () => _connectTo(id), style: primaryButton(),
                        child: Text((_transport == _Transport.bluetooth ||
                                     _transport == _Transport.nearbyService)
                            ? L.common.btConnectTo.fmt({'name': id})
                            : L.common.connectTo.fmt({'ip': id})))))
                  ] else ...[
                    if (_lobbyPlayers.isNotEmpty)
                      _LobbyPlayerList(players: _lobbyPlayers,
                        subtitle: L.common.waitingForHost)
                    else ...[
                      const CircularProgressIndicator(color: kPurple),
                      const SizedBox(height: 10),
                      Text(_status ?? L.common.connectedWaiting,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kMuted, fontSize: 13)),
                    ],
                  ],
                  const SizedBox(height: 10),
                  TextButton(onPressed: _cancel,
                    child: Text(L.common.cancelBtn,
                      style: const TextStyle(color: kMuted))),
                ],

                if (_mode == _LobbyMode.idle && _status != null) ...[
                  const SizedBox(height: 10),
                  Text(_status!, textAlign: TextAlign.center,
                    style: const TextStyle(color: kMuted, fontSize: 13)),
                  if (_status == L.common.connectionFailed ||
                      _status == L.common.hostDisconnected) ...[
                    const SizedBox(height: 6),
                    Text(_transportHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kMuted, fontSize: 11)),
                  ],
                ],
              ]),
            ),
          ]),
        ),
      ))),
    ),
  );

  // ── Profile bubble row ───────────────────────────────────────────────────
  Widget _buildProfileBubbles() {
    final profiles  = ProfileStore().profiles;
    final activeId  = ProfileStore().active?.id;
    final canAdd    = profiles.length < ProfileStore.kMaxProfiles;

    return Row(mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...profiles.map((p) {
          final isActive = p.id == activeId;
          return GestureDetector(
            onTap: () async {
              HapticFeedback.selectionClick();
              if (isActive) {
                // Tap own bubble → edit
                await _editProfile(p);
              } else {
                // Tap other bubble → switch
                await ProfileStore().setActive(p.id);
                if (mounted) _syncFromActiveProfile();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: isActive ? 84 : 64,
              height: isActive ? 84 : 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.color.withValues(alpha: .25),
                border: Border.all(
                  color: isActive ? p.color : p.color.withValues(alpha: .4),
                  width: isActive ? 3 : 1.5),
                boxShadow: isActive ? [
                  BoxShadow(color: p.color.withValues(alpha: .45),
                    blurRadius: 18, spreadRadius: 2),
                ] : null,
                image: (p.avatarPath != null && File(p.avatarPath!).existsSync())
                  ? DecorationImage(
                      image: FileImage(File(p.avatarPath!)),
                      fit: BoxFit.cover)
                  : null,
              ),
              child: (p.avatarPath == null || !File(p.avatarPath!).existsSync())
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.person,
                      color: p.color,
                      size: isActive ? 32 : 24),
                    const SizedBox(height: 2),
                    Text(
                      p.name.isEmpty ? '?' : p.name.split(' ').first,
                      style: TextStyle(
                        color: isActive ? Colors.white : kMuted,
                        fontSize: isActive ? 11 : 9,
                        fontWeight: isActive
                          ? FontWeight.bold : FontWeight.normal),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ])
                : null,
            ),
          );
        }),

        // "+" bubble
        if (canAdd && !_busy)
          GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); _addProfile(); },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .04),
                border: Border.all(color: kBorder, width: 1.5)),
              child: const Icon(Icons.add, color: kMuted, size: 28),
            ),
          ),
      ],
    );
  }
}


// Live player list shown in lobby while waiting
// ─────────────────────────────────────────────────────────────────────────────
// WiFi / Bluetooth transport selector
// ─────────────────────────────────────────────────────────────────────────────
class _TransportToggle extends StatelessWidget {
  final _Transport value;
  final ValueChanged<_Transport> onChanged;
  const _TransportToggle({required this.value, required this.onChanged});

  @override Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: [
        _Tab(
          icon: Icons.wifi,
          label: L.common.transportWifi,
          selected: value == _Transport.wifi,
          onTap: () => onChanged(_Transport.wifi),
        ),
        if (isAndroidApp) // Nearby Connections only exists on Android
          _Tab(
            icon: Icons.bluetooth,
            label: L.common.transportBluetooth,
            selected: value == _Transport.bluetooth,
            onTap: () => onChanged(_Transport.bluetooth),
          ),
        _Tab(
          icon: Icons.devices,
          label: L.common.transportNearby,
          selected: value == _Transport.nearbyService,
          onTap: () => onChanged(_Transport.nearbyService),
        ),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({required this.icon, required this.label,
    required this.selected, required this.onTap});

  @override Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: selected ? kPurple2 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14,
            color: selected ? Colors.white : kMuted),
          const SizedBox(width: 5),
          Flexible(child: Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : kMuted),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Live player list shown in lobby while waiting
// ─────────────────────────────────────────────────────────────────────────────
class _LobbyPlayerList extends StatelessWidget {
  final List<Player> players;
  final String subtitle;
  const _LobbyPlayerList({required this.players, required this.subtitle});

  @override Widget build(BuildContext ctx) => Column(children: [
    Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 12),
      textAlign: TextAlign.center),
    const SizedBox(height: 10),
    Wrap(spacing: 10, runSpacing: 8,
      children: players.map((p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: p.color.withValues(alpha: .15), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.color.withValues(alpha: .5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
          Text(p.name, style: const TextStyle(color: kText, fontSize: 12)),
        ]),
      )).toList()),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar crop/zoom dialog
// ─────────────────────────────────────────────────────────────────────────────
class _AvatarCropDialog extends StatefulWidget {
  final String imagePath;
  final Color color;
  const _AvatarCropDialog({required this.imagePath, required this.color});
  @override State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  double _scale = 1.0, _startScale = 1.0;
  Offset _offset = Offset.zero, _startOffset = Offset.zero;
  final _repaintKey = GlobalKey();
  bool _saving = false;

  @override Widget build(BuildContext ctx) {
    const previewSize = 220.0;
    return AlertDialog(
      backgroundColor: kBg2,
      title: Text(L.common.cropPhoto, style: const TextStyle(color: kText, fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(L.common.dragPinch, style: const TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 12),
        ClipOval(child: SizedBox(
          width: previewSize, height: previewSize,
          child: GestureDetector(
            onScaleStart: (d) {
              _startScale = _scale;
              _startOffset = d.focalPoint - _offset;
            },
            onScaleUpdate: (d) => setState(() {
              _scale = (_startScale * d.scale).clamp(0.5, 5.0);
              _offset = d.focalPoint - _startOffset;
            }),
            child: RepaintBoundary(
              key: _repaintKey,
              child: ClipOval(child: SizedBox(
                width: previewSize, height: previewSize,
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(_offset.dx, _offset.dy)
                    ..scale(_scale),
                  child: Image.file(File(widget.imagePath), fit: BoxFit.cover,
                    width: previewSize, height: previewSize),
                ),
              )),
            ),
          ),
        )),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.zoom_out, color: kMuted, size: 16),
          Expanded(child: Slider(
            value: _scale, min: 0.5, max: 5.0, activeColor: kPurple,
            onChanged: (v) => setState(() => _scale = v),
          )),
          const Icon(Icons.zoom_in, color: kMuted, size: 16),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text(L.common.cancelBtn, style: const TextStyle(color: kMuted))),
        ElevatedButton(
          onPressed: _saving ? null : () async {
            setState(() => _saving = true);
            try {
              final boundary = _repaintKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2.0);
              final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
              if (byteData == null) { if (ctx.mounted) Navigator.pop(ctx); return; }
              final dir = Directory('${File(widget.imagePath).parent.path}/avatars');
              await dir.create(recursive: true);
              final path = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
              await File(path).writeAsBytes(byteData.buffer.asUint8List());
              if (ctx.mounted) Navigator.pop(ctx, path);
            } catch (_) {
              if (ctx.mounted) Navigator.pop(ctx);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: kPurple2, foregroundColor: Colors.white),
          child: _saving
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(L.common.useThis),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom color picker dialog
// ─────────────────────────────────────────────────────────────────────────────
class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _ColorPickerDialog({required this.initial});
  @override State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  @override void initState() { super.initState(); _hsv = HSVColor.fromColor(widget.initial); }

  @override Widget build(BuildContext ctx) {
    final color = _hsv.toColor();
    return AlertDialog(
      backgroundColor: kBg2,
      title: Text(L.common.pickColour, style: const TextStyle(color: kText, fontSize: 16)),
      content: SizedBox(width: 280, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(L.common.hue, style: const TextStyle(color: kMuted, fontSize: 11)),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _HueSlider(hue: _hsv.hue,
              onChanged: (h) => setState(() => _hsv = _hsv.withHue(h))))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(L.common.sat, style: const TextStyle(color: kMuted, fontSize: 11)),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SliderTheme(
              data: SliderTheme.of(ctx).copyWith(trackHeight: 10, thumbColor: Colors.white,
                activeTrackColor: _hsv.withSaturation(1).withValue(1).toColor(),
                inactiveTrackColor: Colors.white24),
              child: Slider(value: _hsv.saturation,
                onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)))))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(L.common.bri, style: const TextStyle(color: kMuted, fontSize: 11)),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SliderTheme(
              data: SliderTheme.of(ctx).copyWith(trackHeight: 10, thumbColor: Colors.white,
                activeTrackColor: color, inactiveTrackColor: Colors.white24),
              child: Slider(value: _hsv.value,
                onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)))))),
        ]),
        const SizedBox(height: 16),
        Container(height: 44, width: double.infinity,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text(L.common.cancelBtn, style: const TextStyle(color: kMuted))),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, color),
          style: ElevatedButton.styleFrom(backgroundColor: color,
            foregroundColor: color.computeLuminance() > 0.4 ? Colors.black : Colors.white),
          child: Text(L.common.useThis)),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueSlider({required this.hue, required this.onChanged});
  @override Widget build(BuildContext ctx) => GestureDetector(
    onHorizontalDragUpdate: (d) {
      final box = ctx.findRenderObject() as RenderBox;
      onChanged(((d.localPosition.dx / box.size.width).clamp(0.0, 1.0)) * 360);
    },
    onTapDown: (d) {
      final box = ctx.findRenderObject() as RenderBox;
      onChanged(((d.localPosition.dx / box.size.width).clamp(0.0, 1.0)) * 360);
    },
    child: CustomPaint(size: const Size(double.infinity, 22), painter: _HuePainter(hue: hue)),
  );
}

class _HuePainter extends CustomPainter {
  final double hue;
  const _HuePainter({required this.hue});
  @override void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 6, size.width, 10);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..shader = LinearGradient(colors: List.generate(7,
        (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor())).createShader(rect));
    final tx = (hue / 360) * size.width;
    canvas.drawCircle(Offset(tx, 11), 10, Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor());
    canvas.drawCircle(Offset(tx, 11), 10,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override bool shouldRepaint(_HuePainter o) => o.hue != hue;
}

// ── Profile edit bottom sheet ─────────────────────────────────────────────────
class _ProfileEditSheet extends StatefulWidget {
  final GameProfile profile;
  final Future<void> Function(String name, int colorValue, String? avatarPath, AppLang lang) onSaved;
  final VoidCallback? onDelete;
  const _ProfileEditSheet({required this.profile, required this.onSaved, this.onDelete});
  @override State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  late final TextEditingController _nameCtrl;
  late Color _color;
  String? _avatarPath;
  late AppLang _lang;
  bool _saving = false;

  @override void initState() {
    super.initState();
    _nameCtrl   = TextEditingController(text: widget.profile.name);
    _color      = widget.profile.color;
    _avatarPath = widget.profile.avatarPath;
    _lang       = AppLocalizations().lang;
  }

  @override void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: kBg2,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text(L.common.choosePhoto, style: const TextStyle(
          color: kText, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.camera_alt, color: kPurple),
          title: Text(L.common.takeSelfie, style: const TextStyle(color: kText)),
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library, color: kPurple),
          title: Text(L.common.chooseFromGallery, style: const TextStyle(color: kText)),
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
        const SizedBox(height: 8),
      ])),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final xfile  = await picker.pickImage(
      source: source, imageQuality: 85,
      preferredCameraDevice: CameraDevice.front);
    if (xfile == null || !mounted) return;
    final cropped = await showDialog<String>(
      context: context, barrierDismissible: false,
      builder: (_) => _AvatarCropDialog(imagePath: xfile.path, color: _color));
    if (cropped != null && mounted) setState(() => _avatarPath = cropped);
  }

  Future<void> _pickCustomColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(initial: _color));
    if (picked != null && mounted) setState(() => _color = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final name = _nameCtrl.text.trim();
    await widget.onSaved(
      name.isEmpty ? widget.profile.name : name,
      _color.value,
      _avatarPath,
      _lang,
    );
    if (mounted) Navigator.pop(context);
  }

  @override Widget build(BuildContext context) {
    final hasAvatar = _avatarPath != null && File(_avatarPath!).existsSync();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(child: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: kBorder,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),

          // Large avatar
          GestureDetector(
            onTap: isWebClient ? null : _pickAvatar,
            child: Stack(alignment: Alignment.bottomRight, children: [
              Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _color.withValues(alpha: .25),
                  border: Border.all(color: _color, width: 3),
                  boxShadow: [BoxShadow(
                    color: _color.withValues(alpha: .4),
                    blurRadius: 20, spreadRadius: 2)],
                  image: hasAvatar
                    ? DecorationImage(
                        image: FileImage(File(_avatarPath!)),
                        fit: BoxFit.cover)
                    : null,
                ),
                child: !hasAvatar
                  ? Icon(Icons.person, color: _color, size: 44) : null,
              ),
              // No photo picking in the browser (Hosted mode)
              if (!isWebClient) Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: kPurple2, shape: BoxShape.circle,
                  border: Border.all(color: kBg2, width: 2)),
                child: const Icon(Icons.camera_alt,
                  color: Colors.white, size: 14)),
            ]),
          ),
          const SizedBox(height: 20),

          // Name field
          TextField(
            controller: _nameCtrl,
            maxLength: 16,
            style: const TextStyle(color: kText),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: L.common.yourName,
              hintStyle: const TextStyle(color: kMuted),
              filled: true, fillColor: Colors.white10,
              counterStyle: const TextStyle(color: kMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _color, width: 2)),
            ),
          ),
          const SizedBox(height: 16),

          // Color swatches
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ...kPlayerColors.map((c) => GestureDetector(
              onTap: () => setState(() => _color = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: c, shape: BoxShape.circle,
                  border: Border.all(
                    color: _color.value == c.value
                      ? Colors.white : Colors.transparent,
                    width: 3)),
              ),
            )),
            GestureDetector(
              onTap: _pickCustomColor,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(colors: [
                    Colors.red, Colors.yellow, Colors.green,
                    Colors.cyan, Colors.blue, Colors.purple, Colors.red]),
                  border: Border.all(
                    color: kPlayerColors.every((c) => _color.value != c.value)
                      ? Colors.white : Colors.transparent,
                    width: 3)),
                child: const Icon(Icons.add, color: Colors.white, size: 16)),
            ),
          ]),
          const SizedBox(height: 16),

          // Language toggle
          LangToggle(onChanged: (lang) async {
            await AppLocalizations().load(lang);
            if (mounted) setState(() => _lang = lang);
          }),
          const SizedBox(height: 24),

          // Save button
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _color,
                foregroundColor: _color.computeLuminance() > 0.4
                  ? Colors.black : Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
              child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                : Text(L.common.useThis,
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            )),

          // Delete button
          if (widget.onDelete != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                widget.onDelete!();
              },
              icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 16),
              label: const Text('Delete profile',
                style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 8),
        ]),
      ))),
    );
  }
}
