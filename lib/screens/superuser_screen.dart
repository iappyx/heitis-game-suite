import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/network.dart';
import '../core/session.dart';
import '../core/stats_store.dart';
import '../core/profile_store.dart';
import '../core/theme.dart';
import '../core/games_registry.dart';

// ── SuperuserScreen ───────────────────────────────────────────────────────────
class SuperuserScreen extends StatefulWidget {
  const SuperuserScreen({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SuperuserScreen(),
    );
  }

  @override State<SuperuserScreen> createState() => _SuperuserScreenState();
}

class _SuperuserScreenState extends State<SuperuserScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _net = Network();

  // Network tab
  final _typeCtrl = TextEditingController(text: 'PLAYER_LEFT');
  final _payloadCtrl = TextEditingController(text: '{}');
  final _fromCtrl = TextEditingController(text: '1');
  int _lastLogLen = 0;
  Timer? _pollTimer;
  final _logScroll = ScrollController();

  // Stats tab
  String? _clearResult;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _lastLogLen = Network.netLog.length;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final cur = Network.netLog.length;
      if (cur != _lastLogLen) {
        _lastLogLen = cur;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) {
            _logScroll.animateTo(_logScroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabs.dispose();
    _typeCtrl.dispose();
    _payloadCtrl.dispose();
    _fromCtrl.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  // ── Network tab ─────────────────────────────────────────────────────────────
  void _inject() {
    final type = _typeCtrl.text.trim().toUpperCase();
    if (type.isEmpty) return;
    Map<String, dynamic>? payload;
    try {
      final raw = _payloadCtrl.text.trim();
      if (raw.isNotEmpty && raw != '{}') {
        payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid JSON payload')));
      return;
    }
    final from = int.tryParse(_fromCtrl.text.trim()) ?? 1;
    _net.injectMessage(type, payload, from);
  }

  void _disconnect() => _net.onDisconnected?.call();

  void _clearChat() {
    // Clear locally
    SessionState().clearChat();
    // Broadcast to all connected devices
    _net.send('CLEAR_CHAT');
  }

  Widget _buildNetworkTab() {
    final netState = [
      ('isHost', _net.isHost),
      ('isSolo', _net.isSolo),
      ('isTournament', _net.isTournament),
    ];

    return ListView(padding: const EdgeInsets.all(12), children: [
      // State badges
      Wrap(spacing: 8, runSpacing: 6, children: netState.map((e) =>
        _Badge(label: e.$1, value: e.$2)
      ).toList()),
      const SizedBox(height: 16),

      // Inject message
      _SectionTitle('Inject Message'),
      Row(children: [
        Expanded(child: _Field(_typeCtrl, 'Type (e.g. PLAYER_LEFT)')),
        const SizedBox(width: 8),
        SizedBox(width: 50, child: _Field(_fromCtrl, 'From')),
      ]),
      const SizedBox(height: 6),
      _Field(_payloadCtrl, 'Payload JSON', lines: 2),
      const SizedBox(height: 8),
      Row(children: [
        _ActionBtn('⚡ Inject', onTap: _inject, color: kPurple2),
        const SizedBox(width: 10),
        _ActionBtn('🔌 Disconnect', onTap: _disconnect, color: Colors.orange.shade800),
        const SizedBox(width: 10),
        _ActionBtn('💬 Clear Chat', onTap: _clearChat, color: Colors.red.shade800),
      ]),
      const SizedBox(height: 16),

      // Quick inject buttons
      _SectionTitle('Quick Inject'),
      Wrap(spacing: 8, runSpacing: 6, children: [
        _QuickBtn('PLAYER_LEFT', () => _net.injectMessage('PLAYER_LEFT', {'idx': 1}, 1)),
        _QuickBtn('BACK_TO_SELECT', () => _net.injectMessage('BACK_TO_SELECT', null, 0)),
        _QuickBtn('GAME_RESET', () => _net.injectMessage('GAME_RESET', null, 0)),
        _QuickBtn('START_GAME', () => _net.injectMessage('START_GAME', null, 0)),
      ]),
      const SizedBox(height: 16),

      // Message log
      _SectionTitle('Message Log  (${Network.netLog.length})'),
      Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorder),
        ),
        child: Network.netLog.isEmpty
          ? const Center(child: Text('No messages yet',
              style: TextStyle(color: kMuted, fontSize: 12)))
          : ListView.builder(
              controller: _logScroll,
              padding: const EdgeInsets.all(6),
              itemCount: Network.netLog.length,
              itemBuilder: (_, i) {
                final e = Network.netLog[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: RichText(text: TextSpan(
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    children: [
                      TextSpan(text: '${e.time} ',
                          style: const TextStyle(color: kMuted)),
                      TextSpan(
                        text: e.outgoing ? '↑ ' : '↓ ',
                        style: TextStyle(
                          color: e.outgoing ? Colors.lightBlueAccent : const Color(0xFFA8F060),
                          fontWeight: FontWeight.bold)),
                      if (!e.outgoing) TextSpan(
                          text: '[${e.fromIdx}] ',
                          style: const TextStyle(color: Colors.orangeAccent)),
                      TextSpan(text: e.type,
                          style: TextStyle(
                            color: e.outgoing ? Colors.lightBlueAccent : const Color(0xFFA8F060),
                            fontWeight: FontWeight.bold)),
                      if (e.raw.isNotEmpty)
                        TextSpan(text: '  ${e.raw}',
                            style: const TextStyle(color: kMuted)),
                    ],
                  )),
                );
              },
            ),
      ),
      const SizedBox(height: 6),
      Align(alignment: Alignment.centerRight,
        child: _ActionBtn('Clear log', onTap: () => setState(() { Network.netLog.clear(); _lastLogLen = 0; }),
            color: Colors.grey.shade700, small: true)),
    ]);
  }

  // ── Stats tab ───────────────────────────────────────────────────────────────
  Widget _buildStatsTab() {
    final games = kGames;
    return ListView(padding: const EdgeInsets.all(12), children: [
      _SectionTitle('Reset Stats'),
      _ActionBtn('🗑 Reset ALL stats', onTap: () async {
        await StatsStore().clearAll();
        setState(() => _clearResult = 'All stats cleared');
      }, color: Colors.red.shade800),
      const SizedBox(height: 8),
      ...games.map((g) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text('${g.icon} ${g.name}',
              style: const TextStyle(color: kText, fontSize: 13)),
          const Spacer(),
          _ActionBtn('Reset', small: true, color: Colors.red.shade900,
            onTap: () async {
              await StatsStore().clearGame(g.id);
              setState(() => _clearResult = '${g.name} stats cleared');
            }),
        ]),
      )),
      if (_clearResult != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2A1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x4DC8F59A)),
          ),
          child: Text('✓ $_clearResult',
              style: const TextStyle(color: Color(0xFFA8F060), fontSize: 13)),
        ),
      ],
    ]);
  }

  // ── Info tab ────────────────────────────────────────────────────────────────
  Widget _buildInfoTab() {
    final profiles = ProfileStore().profiles;
    final rows = <(String, String)>[
      ('isHost', '${_net.isHost}'),
      ('isSolo', '${_net.isSolo}'),
      ('isTournament', '${_net.isTournament}'),
      ('currentGame', _net.currentGameInfo?['game']?.toString() ?? '—'),
      ('profiles', '${profiles.length}'),
      ('activeProfile', ProfileStore().active?.name ?? '—'),
    ];
    return ListView(padding: const EdgeInsets.all(12), children: [
      _SectionTitle('Network State'),
      ...rows.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(r.$1, style: const TextStyle(color: kMuted, fontSize: 12,
              fontFamily: 'monospace')),
          const Spacer(),
          Text(r.$2, style: const TextStyle(color: kText, fontSize: 12,
              fontFamily: 'monospace')),
        ]),
      )),
      const SizedBox(height: 16),
      _SectionTitle('Profiles (${profiles.length})'),
      ...profiles.map((p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(width: 12, height: 12, margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
          Text(p.name, style: const TextStyle(color: kText, fontSize: 13)),
          const SizedBox(width: 4),
          Text('(${p.id})', style: const TextStyle(color: kMuted, fontSize: 11)),
        ]),
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0B1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: kPurple2, width: 2)),
        ),
        child: Column(children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: kMuted, borderRadius: BorderRadius.circular(2)),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Text('🛠️ Superuser', style: TextStyle(
                color: kPurple, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: kMuted, size: 20)),
            ]),
          ),
          // Tabs
          TabBar(
            controller: _tabs,
            labelColor: kPurple,
            unselectedLabelColor: kMuted,
            indicatorColor: kPurple2,
            tabs: const [
              Tab(text: 'Network'),
              Tab(text: 'Stats'),
              Tab(text: 'Info'),
            ],
          ),
          // Content
          Expanded(child: TabBarView(
            controller: _tabs,
            children: [
              _buildNetworkTab(),
              _buildStatsTab(),
              _buildInfoTab(),
            ],
          )),
        ]),
      ),
    );
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(
      color: kPurple, fontSize: 12, fontWeight: FontWeight.bold,
      letterSpacing: 1.2)));
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final int lines;
  const _Field(this.ctrl, this.hint, {this.lines = 1});
  @override Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines: lines,
    style: const TextStyle(color: kText, fontSize: 12, fontFamily: 'monospace'),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kMuted, fontSize: 11),
      filled: true, fillColor: Colors.black38,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kBorder)),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool small;
  const _ActionBtn(this.label, {required this.onTap, required this.color, this.small = false});
  @override Widget build(BuildContext context) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
      backgroundColor: color, foregroundColor: Colors.white,
      padding: EdgeInsets.symmetric(
          horizontal: small ? 12 : 16, vertical: small ? 6 : 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(fontSize: small ? 11 : 13)),
    child: Text(label),
  );
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickBtn(this.label, this.onTap);
  @override Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.orangeAccent,
      side: const BorderSide(color: Colors.orangeAccent),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
    child: Text(label),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final bool value;
  const _Badge({required this.label, required this.value});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: value ? const Color(0xFF1A3A1A) : const Color(0xFF2A1A1A),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: value ? const Color(0xFF4DC88A) : Colors.red.shade900)),
    child: Text('$label: ${value ? "✓" : "✗"}',
      style: TextStyle(
        color: value ? const Color(0xFF8AF0A0) : Colors.red.shade300,
        fontSize: 11, fontFamily: 'monospace')),
  );
}
