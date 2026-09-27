import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ── Data model ─────────────────────────────────────────────────────────────────

class GameStat {
  int wins;
  int losses;
  int draws;

  GameStat({this.wins = 0, this.losses = 0, this.draws = 0});

  int get played => wins + losses + draws;

  Map<String, dynamic> toJson() => {'w': wins, 'l': losses, 'd': draws};

  factory GameStat.fromJson(Map<String, dynamic> j) => GameStat(
        wins: (j['w'] as int? ?? 0),
        losses: (j['l'] as int? ?? 0),
        draws: (j['d'] as int? ?? 0),
      );
}

// ── Singleton ─────────────────────────────────────────────────────────────────

class StatsStore {
  static final StatsStore _instance = StatsStore._();
  factory StatsStore() => _instance;
  StatsStore._();

  static const _kPrefKey = 'game_stats_v1';

  // Outer key = playerName, inner key = gameId
  final Map<String, Map<String, GameStat>> _data = {};

  bool _loaded = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Must be called once at app start (LobbyScreen.initState).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefKey);
      if (raw != null) {
        final outer = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in outer.entries) {
          final inner = entry.value as Map<String, dynamic>;
          _data[entry.key] = inner.map(
            (gameId, v) => MapEntry(gameId, GameStat.fromJson(v as Map<String, dynamic>)),
          );
        }
      }
      _loaded = true;
    } catch (_) {}
  }

  /// Record a game result.
  ///   [profileId] — stable profile ID (falls back to playerName for legacy data)
  ///   [gameId]    — game id string (e.g. 'buterbreaengrienetsiis')
  ///   [result]    — 'win' | 'loss' | 'draw'
  void record(String profileId, String gameId, String result) {
    final byGame = _data.putIfAbsent(profileId, () => {});
    final stat   = byGame.putIfAbsent(gameId, () => GameStat());
    switch (result) {
      case 'win':  stat.wins++;   break;
      case 'loss': stat.losses++; break;
      case 'draw': stat.draws++;  break;
    }
    // Save right away (no debounce) so a result recorded just before the app
    // is closed isn't lost. Results are rare, so the write cost is negligible.
    unawaited(_persist());
  }

  /// Get stats for a player across all games, sorted by most played.
  List<({String gameId, GameStat stat})> statsFor(String playerName) {
    final byGame = _data[playerName] ?? {};
    final entries = byGame.entries
        .map((e) => (gameId: e.key, stat: e.value))
        .toList();
    entries.sort((a, b) => b.stat.played.compareTo(a.stat.played));
    return entries;
  }

  /// All player names that have any stats.
  List<String> get players => _data.keys.toList()..sort();

  /// Clear all stats (used in tests / settings).
  Future<void> clearAll() async {
    _data.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }

  /// Clear the stats of one game for every profile (superuser screen).
  Future<void> clearGame(String gameId) async {
    for (final byGame in _data.values) {
      byGame.remove(gameId);
    }
    _data.removeWhere((_, byGame) => byGame.isEmpty);
    await _persist();
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final outer = _data.map(
        (player, byGame) => MapEntry(
          player,
          byGame.map((gameId, stat) => MapEntry(gameId, stat.toJson())),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefKey, jsonEncode(outer));
    } catch (_) {}
  }
}
