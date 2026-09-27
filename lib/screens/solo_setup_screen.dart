import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network.dart';
import '../core/player.dart';
import '../core/theme.dart';
import '../core/wake_lock.dart';
import '../core/game_router.dart';
import '../l10n/app_localizations.dart';
import '../screens/lobby_screen.dart';
import '../games/rekkenje/rekkenje_config_dialog.dart';
import '../games/rekkenje/rekkenje_state.dart';

enum SoloDifficulty { easy, medium, hard }

/// Games that support AI solo play (must match IDs in games_registry.dart)
const _soloGames = {
  'boppeslach', 'kruske', 'rupsen', 'ludo', 'rekkenje', 'sudokuduel', 'kleurecho',
  'buterbreaengrienetsiis', 'fjouweropinrige', 'skaken', 'damjen', 'wurdspul',
  'paddelduel', 'unthaldspultsje', 'suderseeslach', 'puntenenfakjes',
  'skofpuzzel', 'slange', 'aaisykje',
  'domino', 'klaverjassen', 'wurdsikerij', 'patience',
  'lofthockey',
  'ienentritich',
  'tikrazernij',
};

class SoloSetupScreen extends StatefulWidget {
  /// The human player (name + color already set in lobby)
  final Player humanPlayer;
  const SoloSetupScreen({super.key, required this.humanPlayer});
  @override State<SoloSetupScreen> createState() => _SoloSetupState();
}

class _SoloSetupState extends State<SoloSetupScreen> {
  String? _selectedGame; // null = no selection yet
  SoloDifficulty _difficulty = SoloDifficulty.medium;

  static const _kLastSoloGame = 'last_solo_game';

  @override
  void initState() {
    super.initState();
    _loadLastGame();
  }

  Future<void> _loadLastGame() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_kLastSoloGame);
    if (mounted && last != null && _soloGames.contains(last)) {
      setState(() => _selectedGame = last);
    }
  }

  Future<void> _saveLastGame() async {
    if (_selectedGame == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSoloGame, _selectedGame!);
  }

  List<GameInfo> get _games =>
      kGames.where((g) => _soloGames.contains(g.id)).toList();

  // Games where solo = 1 player only (no AI opponent)
  static const _singlePlayerGames = {'boppeslach', 'kruske', 'rekkenje', 'sudokuduel', 'kleurecho', 'wurdspul', 'skofpuzzel', 'aaisykje', 'wurdsikerij', 'patience', 'tikrazernij'};

  // Games where the AI can fill multiple opponent slots
  static const _multiAiGames = {'ludo', 'rupsen', 'ienentritich'};

  // Number of AI opponents for multi-AI games
  int _aiCount = 1;

  void _start() async {
    final game = _selectedGame;
    if (game == null) return;
    await _saveLastGame();
    // Rekkenje needs its own config dialog
    RekkenjeConfig? rekkenjeCfg;
    if (game == 'rekkenje') {
      rekkenjeCfg = await showDialog<RekkenjeConfig>(
        context: context, builder: (_) => const RekkenjeConfigDialog());
      if (rekkenjeCfg == null || !mounted) return;
    }

    final net = Network();
    await net.reset();
    net.isSolo  = true;
    net.isHost  = true;
    net.myIdx   = 0;

    final List<Player> players;
    if (_singlePlayerGames.contains(game)) {
      // Human only — no dummy AI player shown
      players = [widget.humanPlayer];
    } else if (_multiAiGames.contains(game)) {
      final aiColors = [
        const Color(0xFF9E9E9E),
        const Color(0xFFFF7043),
        const Color(0xFF29B6F6),
      ];
      final aiNames = [
        L.common.soloComputerName,
        '${L.common.soloComputerName} 2',
        '${L.common.soloComputerName} 3',
      ];
      players = [
        widget.humanPlayer,
        ...List.generate(_aiCount, (i) => Player(
          id: 'ai-$i', name: aiNames[i], color: aiColors[i])),
      ];
    } else {
      final computer = Player(
        id: 'ai-computer', name: L.common.soloComputerName,
        color: const Color(0xFF9E9E9E));
      players = [widget.humanPlayer, computer];
    }

    await WakeLock.acquire();
    if (!mounted) return;

    final Map<String, dynamic> extra;
    if (game == 'rekkenje' && rekkenjeCfg != null) {
      extra = rekkenjeCfg.toJson(); // full config with 'op' key
    } else {
      extra = {'difficulty': _difficulty.index};
    }

    Navigator.pushReplacement(context, fadeScaleRoute(
      buildGameScreen(game, 1, players, extra),
    ));
  }

  @override Widget build(BuildContext context) {
    final games = _games;
    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment.topCenter, radius: 1.2,
            colors: [Color(0xFF2D1060), kBg])),
        child: SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(children: [
              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pushAndRemoveUntil(
                    context,
                    fadeScaleRoute(const LobbyScreen()),
                    (_) => false,
                  ),
                  child: Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kBorder)),
                    child: const Icon(Icons.arrow_back, color: kText, size: 18)),
                ),
              ),
              const SizedBox(height: 12),

              // Title
              Text(L.common.soloTitle,
                style: const TextStyle(color: kText, fontSize: 22,
                  fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),

              // Main card
              Container(
                decoration: cardDecoration(),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Game picker
                  Text(L.common.soloChooseGame,
                    style: const TextStyle(color: kMuted, fontSize: 12,
                      fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  ...games.map((g) => _GameTile(
                    game: g,
                    selected: _selectedGame == g.id,
                    onTap: () => setState(() => _selectedGame = g.id),
                  )),

                  // Difficulty
                  if (!_singlePlayerGames.contains(_selectedGame)) ...[
                    const SizedBox(height: 20),
                    Text(L.common.soloDifficulty,
                      style: const TextStyle(color: kMuted, fontSize: 12,
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Row(children: SoloDifficulty.values.map((d) {
                      final label = switch (d) {
                        SoloDifficulty.easy   => L.common.soloEasy,
                        SoloDifficulty.medium => L.common.soloMedium,
                        SoloDifficulty.hard   => L.common.soloHard,
                      };
                      final color = switch (d) {
                        SoloDifficulty.easy   => Colors.green,
                        SoloDifficulty.medium => Colors.orange,
                        SoloDifficulty.hard   => Colors.red,
                      };
                      final sel = _difficulty == d;
                      return Expanded(child: GestureDetector(
                        onTap: () => setState(() => _difficulty = d),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: sel ? color.withValues(alpha: .18) : Colors.white.withValues(alpha: .05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel ? color : kBorder, width: sel ? 2 : 1)),
                          child: Column(children: [
                            Icon(_diffIcon(d), color: sel ? color : kMuted, size: 20),
                            const SizedBox(height: 4),
                            Text(label, style: TextStyle(
                              color: sel ? color : kMuted, fontSize: 13,
                              fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                          ]),
                        ),
                      ));
                    }).toList()),
                  ],

                  // AI opponent count (ludo / rupsen)
                  if (_multiAiGames.contains(_selectedGame)) ...[
                    const SizedBox(height: 20),
                    Text(L.common.soloOpponents,
                      style: const TextStyle(color: kMuted, fontSize: 12,
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Row(children: [1, 2, 3].map((n) {
                      final sel = _aiCount == n;
                      return Expanded(child: GestureDetector(
                        onTap: () => setState(() => _aiCount = n),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: sel ? kPurple2.withValues(alpha: .20) : Colors.white.withValues(alpha: .05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: sel ? kPurple2 : kBorder,
                              width: sel ? 2 : 1)),
                          child: Center(child: Text('$n',
                            style: TextStyle(color: sel ? kText : kMuted, fontSize: 18,
                              fontWeight: sel ? FontWeight.bold : FontWeight.normal))),
                        ),
                      ));
                    }).toList()),
                  ],

                  const SizedBox(height: 24),

                  // Play button
                  SizedBox(width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedGame != null ? _start : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPurple2,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                      child: Text(L.common.soloPlay,
                        style: const TextStyle(color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.bold)),
                    )),
                ]),
              ),
            ]),
          ),
        ))),
      ),
    );
  }


  IconData _diffIcon(SoloDifficulty d) => switch (d) {
    SoloDifficulty.easy   => Icons.sentiment_satisfied,
    SoloDifficulty.medium => Icons.sentiment_neutral,
    SoloDifficulty.hard   => Icons.sentiment_very_dissatisfied,
  };
}

class _GameTile extends StatelessWidget {
  final GameInfo game;
  final bool selected;
  final VoidCallback onTap;
  const _GameTile({required this.game, required this.selected, required this.onTap});

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kPurple2.withValues(alpha: .15) : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? kPurple2 : kBorder,
            width: selected ? 2 : 1)),
        child: Row(children: [
          Text(game.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.name, style: TextStyle(
                color: selected ? kText : kMuted,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14)),
              Text(game.desc, style: const TextStyle(color: kMuted, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          if (selected)
            const Icon(Icons.check_circle, color: kPurple2, size: 20),
        ]),
      ),
    );
  }
}
