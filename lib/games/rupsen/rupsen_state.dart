import '../../l10n/app_localizations.dart';
import 'dart:math';
import '../../core/player.dart';

// ── Tiles ─────────────────────────────────────────────────────────────────────
// Tiles 21–36. Each tile shows its value and a rups-count (score).
// 21-24 → 1 rups, 25-28 → 2 rupsen, 29-32 → 3 rupsen, 33-36 → 4 rupsen

int rupsForTile(int value) => ((value - 21) ~/ 4) + 1;

class RupsenTile {
  final int value;
  bool faceDown; // removed from pool, face-down back in center
  RupsenTile(this.value) : faceDown = false;
  int get rupsen => rupsForTile(value);
}

// ── Die face: 1–5 are pips, 6 is a rups (worth 5 points) ────────────────────
const kRupsFace = 6; // die face value for "rups" (faces 1-5 = pips, 6 = rups)
int faceScore(int face) => face == kRupsFace ? 5 : face;

// ── Player state ──────────────────────────────────────────────────────────────
class RupsenPlayer {
  final Player player;
  final List<RupsenTile> stack = []; // top of stack = last element
  RupsenPlayer(this.player);

  int get topValue => stack.isEmpty ? 0 : stack.last.value;
  int get totalRupsen => stack.fold(0, (s, t) => s + t.rupsen);
}

// ── Turn phase ────────────────────────────────────────────────────────────────
enum RupsenPhase { rolling, busted, claimed }

// ── Main game state ───────────────────────────────────────────────────────────
class RupsenState {
  final List<Player> players;

  // Center pool: 21-36, some may be face-down
  late List<RupsenTile> pool;

  // Player stacks
  late List<RupsenPlayer> rupsenPlayers;

  // Turn state
  int activeIdx = 0;
  List<int> dice = []; // 8 dice, current roll (face 1-6)
  List<bool> held = List.filled(8, false); // which dice are set aside
  // Faces already set aside this turn (only one of each face value allowed)
  Set<int> usedFaces = {};
  // Current accumulated score this turn
  int turnScore = 0;
  bool hasRups = false; // has a rups die been set aside this turn
  bool needsSetAside   = false; // must set aside before rolling again
  bool pickedThisRoll  = false; // already picked a group this roll, must roll before picking again
  RupsenPhase phase = RupsenPhase.rolling;
  String message = '';
  bool gameOver = false;

  RupsenState(this.players) {
    pool = List.generate(16, (i) => RupsenTile(21 + i));
    rupsenPlayers = players.map((p) => RupsenPlayer(p)).toList();
    dice = List.filled(8, 1);
  }

  RupsenPlayer get activePlayer => rupsenPlayers[activeIdx];
  int get freeDiceCount => held.where((h) => !h).length;

  // Which faces can still be set aside from this roll?
  List<int> get availableFaces {
    final result = <int>{};
    for (int i = 0; i < 8; i++) {
      if (!held[i] && !usedFaces.contains(dice[i])) result.add(dice[i]);
    }
    return result.toList();
  }

  // Roll all non-held dice
  void roll() {
    final r = Random();
    for (int i = 0; i < 8; i++) {
      if (!held[i]) dice[i] = r.nextInt(6) + 1; // faces 1-5 pips, 6 = rups
    }
    needsSetAside  = true;
    pickedThisRoll = false;
    message = '';
  }

  // Check if the player is busted (no new face available to set aside)
  bool isBusted() => availableFaces.isEmpty;

  // Set aside all dice of a given face value
  // Returns true if successful
  bool setAside(int face) {
    if (usedFaces.contains(face)) return false;
    if (!availableFaces.contains(face)) return false;

    usedFaces.add(face);
    needsSetAside  = false;
    pickedThisRoll = true;
    final score = faceScore(face);
    int count = 0;
    for (int i = 0; i < 8; i++) {
      if (!held[i] && dice[i] == face) {
        held[i] = true;
        turnScore += score;
        count++;
      }
    }
    if (face == kRupsFace) hasRups = true;
    message = L.rupsen.setAsideMsg.fmt({'count': count, 'face': face == kRupsFace ? '🐛' : '$face', 'pts': score * count});
    return true;
  }

  /// True if the current turnScore can actually claim something:
  /// - must have a rups face set aside
  /// - score must be >= 21
  /// - score must EXACTLY match an opponent's top tile, OR a face-up pool tile exists <= score
  bool get canClaim {
    if (!hasRups || turnScore < 21) return false;
    final v = turnScore;
    for (int i = 0; i < rupsenPlayers.length; i++) {
      if (i == activeIdx) continue;
      if (rupsenPlayers[i].topValue == v) return true;
    }
    // Pool path: can only take a pool tile whose value < v, OR == v if not own top
    return pool.any((t) => !t.faceDown && t.value <= v);
  }

  /// Returns the tile value that would actually be claimed (for UI preview).
  /// Returns 0 if nothing claimable.
  int get peekClaimValue {
    if (!canClaim) return 0;
    final v = turnScore;
    for (int i = 0; i < rupsenPlayers.length; i++) {
      if (i == activeIdx) continue;
      if (rupsenPlayers[i].topValue == v) return v; // steal exact match
    }
    final available = pool.where((t) => !t.faceDown && t.value <= v).toList();
    if (available.isEmpty) return 0;
    available.sort((a, b) => b.value.compareTo(a.value));
    return available.first.value;
  }

  // Attempt to claim a tile with current turnScore
  // Returns outcome message
  String claim() {
    if (!hasRups) {
      return bustTurn(L.rupsen.noWormBust);
    }
    final v = turnScore;

    // Check if another player's top tile matches exactly → steal it
    for (int i = 0; i < rupsenPlayers.length; i++) {
      if (i == activeIdx) continue;
      if (rupsenPlayers[i].topValue == v) {
        final tile = rupsenPlayers[i].stack.removeLast();
        rupsenPlayers[activeIdx].stack.add(tile);
        phase = RupsenPhase.claimed;
        return L.rupsen.steals.fmt({'player': activePlayer.player.name, 'n': '$v', 'other': rupsenPlayers[i].player.name});
      }
    }

    // Find highest available tile in pool ≤ v
    final available = pool.where((t) => !t.faceDown && t.value <= v).toList();
    if (available.isEmpty) {
      return bustTurn(L.rupsen.noTileBust.fmt({'n': '$v'}));
    }
    available.sort((a, b) => b.value.compareTo(a.value));
    final tile = available.first;
    pool.firstWhere((t) => t.value == tile.value).faceDown = true; // remove from pool
    rupsenPlayers[activeIdx].stack.add(tile);
    phase = RupsenPhase.claimed;
    return L.rupsen.claims.fmt({'player': activePlayer.player.name, 'n': '${tile.value}', 'worms': '🐛' * tile.rupsen});
  }

  String bustTurn(String reason) {
    phase = RupsenPhase.busted;
    if (rupsenPlayers[activeIdx].stack.isNotEmpty) {
      // Step 1: Return top tile to pool face-UP
      final lost = rupsenPlayers[activeIdx].stack.removeLast();
      final poolTile = pool.firstWhere((t) => t.value == lost.value,
          orElse: () => lost);
      poolTile.faceDown = false; // face-up = back in play

      // Step 2: Flip the highest remaining face-up pool tile face-down,
      // UNLESS the returned tile is itself the highest (it was just added back,
      // so it would be the one flipped — which would cancel the return, so skip).
      final openAfterReturn = pool.where((t) => !t.faceDown).toList();
      if (openAfterReturn.isNotEmpty) {
        openAfterReturn.sort((a, b) => b.value.compareTo(a.value));
        final highest = openAfterReturn.first;
        // Only flip if the highest is NOT the tile we just returned
        if (highest.value != lost.value) {
          highest.faceDown = true;
        }
      }
    } else {
      // Player had no tile to return → just flip highest face-up tile face-down
      final highestOpen = pool.where((t) => !t.faceDown).toList();
      if (highestOpen.isNotEmpty) {
        highestOpen.sort((a, b) => b.value.compareTo(a.value));
        highestOpen.first.faceDown = true;
      }
    }
    return reason;
  }

  // Advance to next player and reset turn state
  void nextTurn() {
    final allFaceDown = pool.every((t) => t.faceDown);
    if (allFaceDown) {
      gameOver = true;
      return;
    }
    activeIdx = (activeIdx + 1) % players.length;
    _resetTurn();
  }

  void _resetTurn() {
    dice = List.filled(8, 1);
    held = List.filled(8, false);
    usedFaces = {};
    turnScore = 0;
    hasRups = false;
    needsSetAside  = false;
    pickedThisRoll = false;
    phase = RupsenPhase.rolling;
    message = '';
  }

  // ── Serialisation ────────────────────────────────────────────────────────────
  Map<String, dynamic> toSyncJson() => {
    'pool':       pool.map((t) => t.faceDown ? 1 : 0).toList(),
    'stacks':     rupsenPlayers.map((wp) => wp.stack.map((t) => t.value).toList()).toList(),
    'activeIdx':  activeIdx,
    'dice':       dice,
    'held':       held,
    'usedFaces':  usedFaces.toList(),
    'turnScore':  turnScore,
    'hasRups':    hasRups,
    'needsSetAside':  needsSetAside,
    'pickedThisRoll': pickedThisRoll,
    'phase':      phase.index,
    'message':    message,
    'gameOver':   gameOver,
  };

  void applySyncJson(Map<String, dynamic> j) {
    final poolFd = List<int>.from(j['pool'] as List);
    for (int i = 0; i < pool.length && i < poolFd.length; i++) {
      pool[i].faceDown = poolFd[i] == 1;
    }
    final stacks = j['stacks'] as List;
    for (int i = 0; i < rupsenPlayers.length && i < stacks.length; i++) {
      rupsenPlayers[i].stack.clear();
      for (final v in stacks[i] as List) {
        // Find the tile in the pool (or create ghost for stolen tiles)
        final val = v as int;
        rupsenPlayers[i].stack.add(RupsenTile(val)..faceDown = false);
      }
    }
    activeIdx  = j['activeIdx'] as int;
    dice       = List<int>.from(j['dice'] as List);
    held       = List<bool>.from(j['held'] as List);
    usedFaces  = Set<int>.from((j['usedFaces'] as List).map((v) => v as int));
    turnScore  = j['turnScore'] as int;
    hasRups       = j['hasRups'] as bool;
    needsSetAside  = (j['needsSetAside']  as bool?) ?? false;
    pickedThisRoll = (j['pickedThisRoll'] as bool?) ?? false;
    phase      = RupsenPhase.values[j['phase'] as int];
    message    = j['message'] as String? ?? '';
    gameOver   = j['gameOver'] as bool;
  }

  // Reset for Play Again
  void resetGame(int firstPlayerIdx) {
    pool = List.generate(16, (i) => RupsenTile(21 + i));
    for (final wp in rupsenPlayers) wp.stack.clear();
    activeIdx = firstPlayerIdx;
    gameOver = false;
    _resetTurn();
  }

  /// 0-based winner index, or -1 for a draw.
  /// Tie rule: most worms wins; on a tie, the tied player holding the
  /// highest-numbered tile wins; if still tied (e.g. no tiles), it's a draw.
  int get winnerIdx {
    int maxWorms = 0;
    for (final wp in rupsenPlayers) {
      if (wp.totalRupsen > maxWorms) maxWorms = wp.totalRupsen;
    }
    final tied = <int>[];
    for (int i = 0; i < rupsenPlayers.length; i++) {
      if (rupsenPlayers[i].totalRupsen == maxWorms) tied.add(i);
    }
    if (tied.length == 1) return tied.first;
    int bestIdx = -1;
    int bestTile = 0;
    for (final i in tied) {
      int high = 0;
      for (final t in rupsenPlayers[i].stack) {
        if (t.value > high) high = t.value;
      }
      if (high > bestTile) {
        bestTile = high;
        bestIdx = i;
      }
    }
    return bestIdx; // -1 when no tied player holds a tile → draw
  }
}
