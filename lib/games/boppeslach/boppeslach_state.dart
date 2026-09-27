import 'dart:math';
import '../../l10n/app_localizations.dart';
import '../../core/player.dart';

// ── Scoring categories ────────────────────────────────────────────────────────

enum BoppeslachCategory {
  ones, twos, threes, fours, fives, sixes,
  threeOfAKind, fourOfAKind, fullHouse,
  smallStraight, largeStraight,
  topScore, chance,
}

Map<BoppeslachCategory, String> get kCategoryNames => {
  BoppeslachCategory.ones:          L.boppeslach.catOnes,
  BoppeslachCategory.twos:          L.boppeslach.catTwos,
  BoppeslachCategory.threes:        L.boppeslach.catThrees,
  BoppeslachCategory.fours:         L.boppeslach.catFours,
  BoppeslachCategory.fives:         L.boppeslach.catFives,
  BoppeslachCategory.sixes:         L.boppeslach.catSixes,
  BoppeslachCategory.threeOfAKind:  L.boppeslach.catThreeOfKind,
  BoppeslachCategory.fourOfAKind:   L.boppeslach.catFourOfKind,
  BoppeslachCategory.fullHouse:     L.boppeslach.catFullHouse,
  BoppeslachCategory.smallStraight: L.boppeslach.catSmStraight,
  BoppeslachCategory.largeStraight: L.boppeslach.catLgStraight,
  BoppeslachCategory.topScore:      L.boppeslach.catTopScore,
  BoppeslachCategory.chance:        L.boppeslach.catChance,
};

const kUpperCategories = [
  BoppeslachCategory.ones, BoppeslachCategory.twos, BoppeslachCategory.threes,
  BoppeslachCategory.fours, BoppeslachCategory.fives, BoppeslachCategory.sixes,
];
const kLowerCategories = [
  BoppeslachCategory.threeOfAKind, BoppeslachCategory.fourOfAKind, BoppeslachCategory.fullHouse,
  BoppeslachCategory.smallStraight, BoppeslachCategory.largeStraight,
  BoppeslachCategory.topScore, BoppeslachCategory.chance,
];

// ── Score calculation ─────────────────────────────────────────────────────────

int calcScore(BoppeslachCategory cat, List<int> dice) {
  final counts = List.filled(7, 0);
  for (final d in dice) counts[d]++;
  final sum = dice.fold(0, (a, b) => a + b);
  switch (cat) {
    case BoppeslachCategory.ones:   return counts[1] * 1;
    case BoppeslachCategory.twos:   return counts[2] * 2;
    case BoppeslachCategory.threes: return counts[3] * 3;
    case BoppeslachCategory.fours:  return counts[4] * 4;
    case BoppeslachCategory.fives:  return counts[5] * 5;
    case BoppeslachCategory.sixes:  return counts[6] * 6;
    case BoppeslachCategory.threeOfAKind:
      return counts.any((c) => c >= 3) ? sum : 0;
    case BoppeslachCategory.fourOfAKind:
      return counts.any((c) => c >= 4) ? sum : 0;
    case BoppeslachCategory.fullHouse:
      return (counts.any((c) => c == 3) && counts.any((c) => c == 2)) ? 25 : 0;
    case BoppeslachCategory.smallStraight:
      // Need any 4 consecutive values among the 5 dice
      final sv = dice.toSet();
      final hasSmall = sv.containsAll({1,2,3,4}) || sv.containsAll({2,3,4,5}) || sv.containsAll({3,4,5,6});
      return hasSmall ? 30 : 0;
    case BoppeslachCategory.largeStraight:
      // Need all 5 dice to be consecutive (no duplicates, span of 4)
      final lv = dice.toSet().toList()..sort();
      bool isLarge = lv.length == 5;
      if (isLarge) {
        for (int i = 1; i < lv.length; i++) {
          if (lv[i] != lv[i-1] + 1) { isLarge = false; break; }
        }
      }
      return isLarge ? 40 : 0;
    case BoppeslachCategory.topScore:
      return counts.any((c) => c == 5) ? 50 : 0;
    case BoppeslachCategory.chance:
      return sum;
  }
}

// ── Player scorecard ──────────────────────────────────────────────────────────

class BoppeslachScorecard {
  final String playerId;
  final Map<BoppeslachCategory, int> scores = {};

  BoppeslachScorecard(this.playerId);

  bool hasScored(BoppeslachCategory cat) => scores.containsKey(cat);
  int get upperTotal => kUpperCategories.fold(0, (s, c) => s + (scores[c] ?? 0));
  int get bonus      => upperTotal >= 63 ? 35 : 0;
  int get lowerTotal => kLowerCategories.fold(0, (s, c) => s + (scores[c] ?? 0));
  int get total      => upperTotal + bonus + lowerTotal;
  bool get complete  => scores.length == BoppeslachCategory.values.length;

  void reset() => scores.clear();

  Map<String, dynamic> toJson() => {
    'pid': playerId,
    'scores': scores.map((k, v) => MapEntry(k.index.toString(), v)),
  };

  void applyJson(Map<String, dynamic> j) {
    scores.clear();
    final m = j['scores'] as Map<String, dynamic>;
    m.forEach((k, v) {
      scores[BoppeslachCategory.values[int.parse(k)]] = v as int;
    });
  }
}

// ── Main game state ───────────────────────────────────────────────────────────

class BoppeslachState {
  final List<Player> players;
  final List<BoppeslachScorecard> scorecards;

  List<int>  dice           = [1, 1, 1, 1, 1];
  List<bool> held           = [false, false, false, false, false];
  int rollsLeft             = 3;
  int currentPlayerIdx      = 0;
  bool gameOver             = false;
  String message            = '';

  BoppeslachState(this.players)
      : scorecards = players.map((p) => BoppeslachScorecard(p.id)).toList();

  Player get currentPlayer => players[currentPlayerIdx];
  BoppeslachScorecard get currentCard => scorecards[currentPlayerIdx];

  void roll() {
    if (rollsLeft <= 0) return;
    final r = Random();
    for (int i = 0; i < 5; i++) {
      if (!held[i]) dice[i] = r.nextInt(6) + 1;
    }
    rollsLeft--;
    message = rollsLeft == 0
        ? L.boppeslach.chooseCategory
        : L.boppeslach.rollsLeft.fmt({'n': rollsLeft});
  }

  void toggleHold(int i) {
    if (rollsLeft == 3) return;
    held[i] = !held[i];
  }

  void scoreCategory(BoppeslachCategory cat) {
    if (currentCard.hasScored(cat) || rollsLeft == 3) return;
    final points = calcScore(cat, dice);
    currentCard.scores[cat] = points;
    if (cat == BoppeslachCategory.topScore && points == 50) {
      message = L.boppeslach.topScore.fmt({'n': '$points'});
    } else if (points == 0) {
      message = L.boppeslach.zeroFor.fmt({'cat': kCategoryNames[cat]!});
    } else {
      message = L.boppeslach.plusFor.fmt({'n': '$points', 'cat': kCategoryNames[cat]!});
    }
    _nextTurn();
  }

  void _nextTurn() {
    if (scorecards.every((s) => s.complete)) { gameOver = true; return; }
    currentPlayerIdx = (currentPlayerIdx + 1) % players.length;
    int safety = 0;
    while (currentCard.complete && safety++ < players.length) {
      currentPlayerIdx = (currentPlayerIdx + 1) % players.length;
    }
    dice      = [1, 1, 1, 1, 1];
    held      = [false, false, false, false, false];
    rollsLeft = 3;
  }

  /// 0-based winner index, or -1 for a draw (tie for the highest total).
  int get winnerIdx {
    int best = -1; int w = -1; bool tie = false;
    for (int i = 0; i < players.length; i++) {
      final t = scorecards[i].total;
      if (t > best) { best = t; w = i; tie = false; }
      else if (t == best) { tie = true; }
    }
    return tie ? -1 : w;
  }

  Map<String, dynamic> toSyncJson() => {
    'dice':       dice,
    'held':       held,
    'rollsLeft':  rollsLeft,
    'currentIdx': currentPlayerIdx,
    'gameOver':   gameOver,
    'message':    message,
    'scorecards': scorecards.map((s) => s.toJson()).toList(),
  };

  void applySyncJson(Map<String, dynamic> j) {
    dice             = List<int>.from(j['dice'] as List);
    held             = List<bool>.from(j['held'] as List);
    rollsLeft        = j['rollsLeft'] as int;
    currentPlayerIdx = j['currentIdx'] as int;
    gameOver         = j['gameOver'] as bool;
    message          = j['message'] as String? ?? '';
    final cards      = j['scorecards'] as List;
    for (int i = 0; i < scorecards.length && i < cards.length; i++) {
      scorecards[i].applyJson(cards[i] as Map<String, dynamic>);
    }
  }
}
