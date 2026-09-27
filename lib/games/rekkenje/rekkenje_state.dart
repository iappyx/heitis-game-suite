import '../../l10n/app_localizations.dart';
import 'dart:math';

// ── Config ────────────────────────────────────────────────────────────────────
enum RekkenjeOp { addition, subtraction, multiplication, division }

Map<RekkenjeOp, String> get kOpLabel => {
  RekkenjeOp.addition:       '${L.rekkenje.opAddition} +',
  RekkenjeOp.subtraction:    '${L.rekkenje.opSubtraction} -',
  RekkenjeOp.multiplication: '${L.rekkenje.opMultiplication} x',
  RekkenjeOp.division:       '${L.rekkenje.opDivision} ÷',
};

const kOpSymbol = {
  RekkenjeOp.addition:       '+',
  RekkenjeOp.subtraction:    '−',
  RekkenjeOp.multiplication: '×',
  RekkenjeOp.division:       '÷',
};

const kRanges = [10, 20, 40, 60, 80, 100, 200];

class RekkenjeConfig {
  final RekkenjeOp op;
  final int maxVal;        // e.g. 20 means 0–20
  final int rounds;        // total rounds
  final int questionsPerRound;
  final int secondsPerRound;

  const RekkenjeConfig({
    required this.op,
    required this.maxVal,
    required this.rounds,
    required this.questionsPerRound,
    required this.secondsPerRound,
  });

  Map<String, dynamic> toJson() => {
    'op':    op.index,
    'max':   maxVal,
    'rounds': rounds,
    'qpr':   questionsPerRound,
    'spr':   secondsPerRound,
  };

  factory RekkenjeConfig.fromJson(Map<String, dynamic> j) => RekkenjeConfig(
    op:                 RekkenjeOp.values[j['op'] as int],
    maxVal:             j['max'] as int,
    rounds:             j['rounds'] as int,
    questionsPerRound:  j['qpr'] as int,
    secondsPerRound:    j['spr'] as int,
  );
}

// ── Question ──────────────────────────────────────────────────────────────────
class RekkenjeQuestion {
  final int a, b;
  final RekkenjeOp op;
  final int answer;

  RekkenjeQuestion({required this.a, required this.b, required this.op})
      : answer = _compute(a, b, op);

  static int _compute(int a, int b, RekkenjeOp op) {
    switch (op) {
      case RekkenjeOp.addition:       return a + b;
      case RekkenjeOp.subtraction:    return a - b;
      case RekkenjeOp.multiplication: return a * b;
      case RekkenjeOp.division:       return a ~/ b;
    }
  }

  String get questionText {
    final sym = kOpSymbol[op]!;
    return '$a $sym $b = ?';
  }
}

List<RekkenjeQuestion> generateQuestions(RekkenjeConfig cfg, int count) {
  final r = Random();
  final questions = <RekkenjeQuestion>[];
  final max = cfg.maxVal;

  for (int i = 0; i < count; i++) {
    int a, b;
    switch (cfg.op) {
      case RekkenjeOp.addition:
        // a + b ≤ max
        a = r.nextInt(max + 1);
        b = r.nextInt(max - a + 1);
        break;
      case RekkenjeOp.subtraction:
        // a - b ≥ 0, a ≤ max
        a = r.nextInt(max + 1);
        b = r.nextInt(a + 1);
        break;
      case RekkenjeOp.multiplication:
        // a * b ≤ max, avoid 0×0 triviality
        do {
          a = r.nextInt(max ~/ 2 + 1).clamp(1, max);
          final maxB = (max ~/ a).clamp(1, max);
          b = r.nextInt(maxB) + 1;
        } while (a * b > max || (a == 1 && b == 1));
        break;
      case RekkenjeOp.division:
        // b * a ≤ max, b ≠ 0, result is integer
        b = r.nextInt(max ~/ 2).clamp(2, max);
        final maxQ = max ~/ b;
        if (maxQ < 1) { a = b; } // fallback: a = b, answer = 1
        else          { a = b * (r.nextInt(maxQ) + 1); }
        break;
    }
    questions.add(RekkenjeQuestion(a: a, b: b, op: cfg.op));
  }
  return questions;
}

// ── Per-player answer record ──────────────────────────────────────────────────
class PlayerAnswer {
  final int questionIdx;
  final int given;
  final bool correct;
  final int secondsLeft; // seconds remaining when answered (for speed bonus)

  PlayerAnswer({
    required this.questionIdx,
    required this.given,
    required this.correct,
    required this.secondsLeft,
  });

  int get points => correct ? (5 + secondsLeft) : 0;
}

// ── Per-player round stats ────────────────────────────────────────────────────
class PlayerRoundStats {
  int correct = 0;
  int total   = 0;
  int points  = 0;

  void add(PlayerAnswer a) {
    total++;
    if (a.correct) { correct++; points += a.points; }
  }

  String get accuracyStr => total == 0 ? '—' : '${(correct * 100 ~/ total)}%';
}

// ── Game-wide accumulated stats ───────────────────────────────────────────────
class PlayerTotalStats {
  int correct = 0;
  int total   = 0;
  int points  = 0;

  void addRound(PlayerRoundStats rs) {
    correct += rs.correct;
    total   += rs.total;
    points  += rs.points;
  }

  String get accuracyStr => total == 0 ? '—' : '${(correct * 100 ~/ total)}%';
}
