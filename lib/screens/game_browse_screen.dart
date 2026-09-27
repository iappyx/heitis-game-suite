import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/games_registry.dart';
import '../core/network.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

// ── Category definitions ──────────────────────────────────────────────────────

enum GameCategory { strategy, word, arcade, puzzle, classic }

Map<GameCategory, ({String icon, String label})> _categoryMeta() => {
  GameCategory.strategy: (icon: '♟',  label: L.common.catStrategy),
  GameCategory.word:     (icon: '🔤', label: L.common.catWord),
  GameCategory.arcade:   (icon: '🕹', label: L.common.catArcade),
  GameCategory.puzzle:   (icon: '🧩', label: L.common.catPuzzle),
  GameCategory.classic:  (icon: '🎲', label: L.common.catClassic),
};

const _kGameCategories = <String, GameCategory>{
  'skaken':        GameCategory.strategy,
  'damjen':     GameCategory.strategy,
  'fjouweropinrige':   GameCategory.strategy,
  'buterbreaengrienetsiis':    GameCategory.strategy,
  'puntenenfakjes': GameCategory.strategy,
  'suderseeslach':   GameCategory.strategy,
  'wurdspul':    GameCategory.word,
  'tekenjeenriede':   GameCategory.word,
  'wurdsikerij':   GameCategory.word,
  'slange':        GameCategory.arcade,
  'paddelduel':         GameCategory.arcade,
  'kleurecho':        GameCategory.arcade,
  'rekkenje':    GameCategory.arcade,
  'lofthockey':    GameCategory.arcade,
  'fluchtekenje':    GameCategory.arcade,
  'tikrazernij':    GameCategory.arcade,
  'unthaldspultsje':       GameCategory.puzzle,
  'sudokuduel':       GameCategory.puzzle,
  'skofpuzzel':GameCategory.puzzle,
  'kruske':       GameCategory.puzzle,
  'boppeslach':         GameCategory.classic,
  'ludo':         GameCategory.classic,
  'rupsen':       GameCategory.classic,
  'patience':    GameCategory.classic,
  'ienentritich':  GameCategory.classic,
};

GameCategory categoryOf(String gameId) =>
    _kGameCategories[gameId] ?? GameCategory.classic;

// ── Full-screen game browser ──────────────────────────────────────────────────

/// Full-screen game browser shown instead of the inline grid.
/// [selectedId] is the currently selected game. [playerCount] filters unavailable games.
/// [onSelect] fires when the host taps a game.
/// [isHost] controls whether tapping is allowed.
class GameBrowseScreen extends StatefulWidget {
  final String selectedId;
  final int playerCount;
  final bool isHost;
  final ValueChanged<String>? onSelect;

  const GameBrowseScreen({
    super.key,
    required this.selectedId,
    required this.playerCount,
    required this.isHost,
    this.onSelect,
  });

  @override State<GameBrowseScreen> createState() => _GameBrowseState();
}

class _GameBrowseState extends State<GameBrowseScreen> {
  GameCategory? _filterCat; // null = show all
  VoidCallback? _prevDisconnect;
  VoidCallback? _myDisconnect; // the handler this screen installed

  @override
  void initState() {
    super.initState();
    // Detect disconnect while browsing games — pop back to waiting screen
    _prevDisconnect = Network().onDisconnected;
    _myDisconnect = () {
      if (mounted) Navigator.pop(context);
      _prevDisconnect?.call();
    };
    Network().onDisconnected = _myDisconnect;
  }

  @override
  void dispose() {
    // Only restore if nobody replaced our handler meanwhile (e.g. the
    // ReconnectDialog opened by _prevDisconnect installs its own).
    if (identical(Network().onDisconnected, _myDisconnect)) {
      Network().onDisconnected = _prevDisconnect;
    }
    super.dispose();
  }

  bool _available(GameInfo g) =>
      g.maxPlayers == null || widget.playerCount <= g.maxPlayers!;

  List<GameInfo> get _filtered {
    if (_filterCat == null) return kGames;
    return kGames.where((g) => categoryOf(g.id) == _filterCat).toList();
  }

  @override Widget build(BuildContext context) {
    final games = _filtered;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(child: Column(children: [
        // Header
        Container(
          color: kBg,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(children: [
            Semantics(
              label: 'Back',
              child: GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); Navigator.pop(context); },
                child: Container(width: 48, height: 48,
                  decoration: BoxDecoration(color: Colors.black54,
                    borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                  child: const Icon(Icons.arrow_back, color: kText, size: 20)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: Colors.black54,
                borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
              child: Text(L.common.chooseGame,
                style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            )),
            const SizedBox(width: 44), // balance back button
          ]),
        ),

        // Category filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            _CategoryChip(
              label: L.common.allFilter,
              icon: '🎮',
              selected: _filterCat == null,
              onTap: () => setState(() => _filterCat = null),
            ),
            ...GameCategory.values.map((cat) {
              final meta = _categoryMeta()[cat]!;
              return _CategoryChip(
                label: meta.label,
                icon: meta.icon,
                selected: _filterCat == cat,
                onTap: () => setState(() => _filterCat = _filterCat == cat ? null : cat),
              );
            }),
          ]),
        ),

        const Divider(color: kBorder, height: 1),

        // Game grid
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisExtent: 100,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: games.length,
          itemBuilder: (_, i) {
            final g = games[i];
            final avail = _available(g);
            final selected = g.id == widget.selectedId;
            return _GameTile(
              game: g,
              available: avail,
              selected: selected,
              isHost: widget.isHost,
              onTap: (widget.isHost && avail)
                ? () {
                    widget.onSelect?.call(g.id);
                    Navigator.pop(context);
                  }
                : null,
            );
          },
        )),
      ])),
    );
  }
}

// ── Compact inline picker (used in waiting_screen card) ──────────────────────

/// Compact horizontal strip showing the selected game + a browse button.
/// Used inside the waiting_screen card instead of the full grid.
class GamePickerStrip extends StatelessWidget {
  final String selectedId;
  final int playerCount;
  final bool isHost;
  final ValueChanged<String>? onSelect;

  const GamePickerStrip({
    super.key,
    required this.selectedId,
    required this.playerCount,
    required this.isHost,
    this.onSelect,
  });

  @override Widget build(BuildContext context) {
    final g = kGames.firstWhere((g) => g.id == selectedId, orElse: () => kGames[0]);

    return GestureDetector(
      onTap: isHost ? () => _openBrowser(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kPurple.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kPurple.withValues(alpha: .4))),
        child: Row(children: [
          Text(g.icon, style: const TextStyle(fontSize: 26,
            fontFamilyFallback: ['NotoColorEmoji'])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.name, style: const TextStyle(color: kText, fontSize: 15,
              fontWeight: FontWeight.bold)),
            Text(g.desc, style: const TextStyle(color: kMuted, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (isHost) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: kPurple2.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPurple2.withValues(alpha: .6))),
              child: Text(L.common.browseTitle, style: const TextStyle(color: kPurple, fontSize: 12,
                fontWeight: FontWeight.bold))),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                shape: BoxShape.circle),
              child: const SizedBox(width: 10, height: 10,
                child: CircularProgressIndicator(strokeWidth: 2, color: kPurple))),
          ],
        ]),
      ),
    );
  }

  void _openBrowser(BuildContext context) {
    Navigator.push(context, fadeScaleRoute(GameBrowseScreen(
      selectedId:  selectedId,
      playerCount: playerCount,
      isHost:      isHost,
      onSelect:    onSelect,
    )));
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label, icon;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.icon,
    required this.selected, required this.onTap});

  @override Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? kPurple2.withValues(alpha: .25) : Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? kPurple2 : kBorder, width: selected ? 2 : 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 14, fontFamilyFallback: ['NotoColorEmoji'])),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
          color: selected ? kText : kMuted,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12)),
      ]),
    ),
  );
}

class _GameTile extends StatelessWidget {
  final GameInfo game;
  final bool available, selected, isHost;
  final VoidCallback? onTap;
  const _GameTile({required this.game, required this.available, required this.selected,
    required this.isHost, this.onTap});

  @override Widget build(BuildContext context) {
    final cat  = categoryOf(game.id);
    final meta = _categoryMeta()[cat]!;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: available ? 1.0 : 0.38,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? kPurple.withValues(alpha: .2)
                : Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kPurple : (available ? kBorder : kBorder.withValues(alpha: .4)),
              width: selected ? 2 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(game.icon, style: const TextStyle(fontSize: 22,
                fontFamilyFallback: ['NotoColorEmoji'])),
              const Spacer(),
              // Category badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(meta.icon, style: const TextStyle(fontSize: 10,
                  fontFamilyFallback: ['NotoColorEmoji']))),
            ]),
            const SizedBox(height: 6),
            Text(game.name, style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13,
              color: available ? kText : kMuted)),
            const SizedBox(height: 2),
            Expanded(child: Text(
              available ? game.desc : (game.maxPlayers == 1 ? L.common.singlePlayerOnly : L.common.twoPlayersOnly),
              style: TextStyle(
                color: available ? kMuted : Colors.white24, fontSize: 10,
                fontStyle: available ? FontStyle.normal : FontStyle.italic),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}
