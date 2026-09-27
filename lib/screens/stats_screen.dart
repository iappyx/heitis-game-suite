import 'package:flutter/material.dart';
import '../core/stats_store.dart';
import '../core/profile_store.dart';
import '../core/theme.dart';
import '../core/games_registry.dart';
import '../l10n/app_localizations.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String? _selectedKey;

  String _displayName(String key) =>
      ProfileStore().profiles.where((p) => p.id == key).firstOrNull?.name ?? key;

  Color? _displayColor(String key) =>
      ProfileStore().profiles.where((p) => p.id == key).firstOrNull?.color;

  @override void initState() {
    super.initState();
    final players = StatsStore().players;
    if (players.isNotEmpty) _selectedKey = players.first;
  }

  @override Widget build(BuildContext context) {
    final store   = StatsStore();
    final players = store.players;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(child: Column(children: [
        Container(
          color: kBg,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: const Icon(Icons.arrow_back, color: kText, size: 18)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: Colors.black54,
                borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
              child: Text(L.common.statsTitle,
                style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            )),
            GestureDetector(
              onTap: () => _confirmClear(context),
              child: Container(width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: const Icon(Icons.delete_outline, color: kMuted, size: 18)),
            ),
          ]),
        ),

        if (players.isEmpty)
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🏆', style: TextStyle(fontSize: 48, fontFamilyFallback: ['NotoColorEmoji'])),
            const SizedBox(height: 12),
            Text(L.common.statsEmpty,
              style: const TextStyle(color: kMuted, fontSize: 14), textAlign: TextAlign.center),
          ])))
        else ...[
          if (players.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: players.map((key) {
                final sel   = key == _selectedKey;
                final name  = _displayName(key);
                final color = _displayColor(key) ?? kPurple2;
                return GestureDetector(
                  onTap: () => setState(() => _selectedKey = key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? color.withValues(alpha: .18) : Colors.white.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? color : kBorder, width: sel ? 2 : 1)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(name, style: TextStyle(
                        color: sel ? kText : kMuted,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13)),
                    ]),
                  ),
                );
              }).toList()),
            ),
          Expanded(child: _buildTable(store, _selectedKey ?? players.first)),
        ],
      ])),
    );
  }

  Widget _buildTable(StatsStore store, String key) {
    final rows = store.statsFor(key);
    if (rows.isEmpty) return Center(child: Text(L.common.statsEmpty,
        style: const TextStyle(color: kMuted, fontSize: 14)));

    final iconMap = { for (final g in kGames) g.id: g.icon };
    final nameMap = { for (final g in kGames) g.id: g.name };
    final color   = _displayColor(key) ?? kPurple2;
    final name    = _displayName(key);

    int totalW = 0, totalL = 0, totalD = 0;
    for (final r in rows) { totalW += r.stat.wins; totalL += r.stat.losses; totalD += r.stat.draws; }
    final totalPlayed = totalW + totalL + totalD;
    final winRate = totalPlayed > 0 ? (totalW / totalPlayed * 100).round() : 0;
    final fav = rows.isNotEmpty ? rows.first : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        // Profile summary card
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .2), shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: .6), width: 2)),
              child: Center(child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('$totalPlayed ${L.common.gamesPlayed}', style: const TextStyle(color: kMuted, fontSize: 12)),
            ])),
            Column(children: [
              Text('$winRate%', style: TextStyle(
                color: winRate >= 50 ? Colors.greenAccent : Colors.redAccent,
                fontSize: 22, fontWeight: FontWeight.bold)),
              Text(L.common.winRate, style: const TextStyle(color: kMuted, fontSize: 10)),
            ]),
            if (fav != null) ...[
              const SizedBox(width: 16),
              Column(children: [
                Text(iconMap[fav.gameId] ?? '🎮',
                  style: const TextStyle(fontSize: 22, fontFamilyFallback: ['NotoColorEmoji'])),
                Text(L.common.favourite, style: const TextStyle(color: kMuted, fontSize: 10)),
              ]),
            ],
          ]),
        ),

        Container(
          decoration: cardDecoration(),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Row(children: [
                Expanded(child: Text(L.common.statsGame,
                  style: const TextStyle(color: kMuted, fontSize: 11,
                    fontWeight: FontWeight.bold, letterSpacing: 1))),
                _HeaderCell(L.common.statsWin),
                _HeaderCell(L.common.statsLoss),
                _HeaderCell(L.common.statsDraw),
                _HeaderCell(L.common.statsPlayed),
                _HeaderCell('%'),
              ]),
            ),
            const Divider(color: kBorder, height: 1),
            ...rows.map((r) => _StatRow(
              icon: iconMap[r.gameId] ?? '🎮',
              name: nameMap[r.gameId] ?? r.gameId,
              stat: r.stat,
              isFav: r == fav,
            )),
            const Divider(color: kBorder, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Expanded(child: Text(L.common.statsTotal,
                  style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.bold))),
                _ValueCell('$totalW', color: Colors.greenAccent),
                _ValueCell('$totalL', color: Colors.redAccent),
                _ValueCell('$totalD', color: kMuted),
                _ValueCell('$totalPlayed', color: kText, bold: true),
                _ValueCell('$winRate%',
                  color: winRate >= 50 ? Colors.greenAccent : Colors.redAccent, bold: true),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kBg2,
      title: Text(L.common.statsClearTitle, style: const TextStyle(color: kText)),
      content: Text(L.common.statsClearBody, style: const TextStyle(color: kMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text(L.common.cancelBtn, style: const TextStyle(color: kMuted))),
        ElevatedButton(
          onPressed: () async {
            await StatsStore().clearAll();
            if (mounted) { Navigator.pop(context); setState(() {}); }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
          child: Text(L.common.statsClearConfirm, style: const TextStyle(color: Colors.white))),
      ],
    ));
  }
}

class _StatRow extends StatelessWidget {
  final String icon, name;
  final GameStat stat;
  final bool isFav;
  const _StatRow({required this.icon, required this.name, required this.stat, this.isFav = false});

  @override Widget build(BuildContext context) {
    final played = stat.played;
    final rate = played > 0 ? (stat.wins / played * 100).round() : 0;
    return Container(
      color: isFav ? kPurple.withValues(alpha: .06) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 18, fontFamilyFallback: ['NotoColorEmoji'])),
        const SizedBox(width: 6),
        Expanded(child: Row(children: [
          Flexible(child: Text(name,
            style: const TextStyle(color: kText, fontSize: 13), overflow: TextOverflow.ellipsis)),
          if (isFav) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: kPurple.withValues(alpha: .3), borderRadius: BorderRadius.circular(4)),
              child: const Text('★', style: TextStyle(color: kPurple, fontSize: 9))),
          ],
        ])),
        _ValueCell('${stat.wins}',   color: Colors.greenAccent),
        _ValueCell('${stat.losses}', color: Colors.redAccent),
        _ValueCell('${stat.draws}',  color: kMuted),
        _ValueCell('${stat.played}', color: kText),
        _ValueCell('$rate%',
          color: rate >= 50 ? Colors.greenAccent.withValues(alpha: .7) : Colors.redAccent.withValues(alpha: .7)),
      ]),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);
  @override Widget build(BuildContext context) => SizedBox(
    width: 40,
    child: Text(text, textAlign: TextAlign.center,
      style: const TextStyle(color: kMuted, fontSize: 11,
        fontWeight: FontWeight.bold, letterSpacing: 0.5)),
  );
}

class _ValueCell extends StatelessWidget {
  final String text;
  final Color color;
  final bool bold;
  const _ValueCell(this.text, {required this.color, this.bold = false});
  @override Widget build(BuildContext context) => SizedBox(
    width: 40,
    child: Text(text, textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 13,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
  );
}
