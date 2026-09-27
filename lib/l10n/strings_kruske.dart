import 'app_localizations.dart';

class StringsKruske {
  final String gameName;
  final String gameDesc;
  final String rollBtn;
  final String penaltyBtn;        // "✗ Penalty"
  final String penaltiesUsed;     // "{n}/4 used"
  final String passBtn;           // "Pass"
  final String confirmBtn;        // "✓ OK"
  final String waitingOthers;     // "Waiting for others…"
  final String rowLocked;         // "{row} LOCKED"
  final String youSuffix;         // "(you)"  — appended to own name
  final String scoreLabel;        // "Score:"
  final String penLabel;          // "Pen:"
  final String ptsUnit;           // "pts"
  final String gameOver;          // "Game Over!"
  final String yourTurn;          // "{player}'s turn"
  final String sumLabel;          // "Sum: {n}"
  // Row names (row colours)
  final String rowOrange;
  final String rowPink;
  final String rowTeal;
  final String rowLilac;

  final String chooseOrPass;      // 'Choose or Pass' (non-active during choosing)
  final String yourTurnRoll;      // "Your turn — tap Roll!"
  final String isRolling;         // "{player} is rolling…"
  final String chooseCells;       // "Choose cells, then ✓ OK"
  final String waitingSubmit;     // "Waiting for others…" (already have waitingOthers, this is submit-specific)
  final String diceLabel;         // "DICE" section header
  final String rules;
  const StringsKruske({
    required this.gameName,
    required this.gameDesc,
    required this.rollBtn,
    required this.penaltyBtn,
    required this.penaltiesUsed,
    required this.passBtn,
    required this.confirmBtn,
    required this.waitingOthers,
    required this.rowLocked,
    required this.youSuffix,
    required this.scoreLabel,
    required this.penLabel,
    required this.ptsUnit,
    required this.gameOver,
    required this.yourTurn,
    required this.sumLabel,
    required this.rowOrange,
    required this.rowPink,
    required this.rowTeal,
    required this.rowLilac,
    required this.chooseOrPass,
    required this.yourTurnRoll,
    required this.isRolling,
    required this.chooseCells,
    required this.waitingSubmit,
    required this.diceLabel,
    required this.rules,
  });

  factory StringsKruske.of(AppLang l) => switch (l) {
    AppLang.fy => StringsKruske.fy(),
    AppLang.nl => StringsKruske.nl(),
    AppLang.en => StringsKruske.en(),
  };

  factory StringsKruske.fy() => const StringsKruske(
    gameName:      'Krúske',
    gameDesc:     'Streekje & skoardzje',
    rollBtn:       'Goaie!',
    penaltyBtn:    '✗ Boete',
    penaltiesUsed: '{n}/4 brûkt',
    passBtn:       'Passe',
    confirmBtn:    '✓ OK',
    waitingOthers: 'Wachtsje op oaren…',
    rowLocked:     '{row} GRINDZELE',
    youSuffix:     '(do)',
    scoreLabel:    'Punten:',
    penLabel:      'Boete:',
    ptsUnit:       'ptn',
    gameOver:      'Spultsje oer!',
    yourTurn:      'Beurt fan {player}',
    sumLabel:      'Som: {n}',
    rowOrange:     'Oranje',
    rowPink:       'Rôze',
    rowTeal:       'Turkoaze',
    rowLilac:      'Lila',
    chooseOrPass:  'Kies of Pas',
    yourTurnRoll:  'Dyn beurt — tikje Goaie!',
    isRolling:     '{player} is oan it goaien…',
    chooseCells:   'Kies fakjes, dan ✓ OK',
    waitingSubmit: 'Wachtsje op oaren…',
    diceLabel:     'DOBBELS',
    rules:             'Krúske is in dobbelsjenspultsje wêr\'t elke spiler in eigen skoarekaart hat. Goai de dobbelstiennen en set in krúske yn in rige. As alle fiif fjilden yn in rige fol binne, kinst de rige ôfslute foar in bonus. Heechste skoare wint.',
  );

  factory StringsKruske.nl() => const StringsKruske(
    gameName:      'Krúske',
    gameDesc:     'Doorstrepen & scoren',
    rollBtn:       'Gooi!',
    penaltyBtn:    '✗ Straf',
    penaltiesUsed: '{n}/4 gebruikt',
    passBtn:       'Passen',
    confirmBtn:    '✓ OK',
    waitingOthers: 'Wachten op anderen…',
    rowLocked:     '{row} VERGRENDELD',
    youSuffix:     '(jij)',
    scoreLabel:    'Score:',
    penLabel:      'Straf:',
    ptsUnit:       'ptn',
    gameOver:      'Spel voorbij!',
    yourTurn:      'Beurt van {player}',
    sumLabel:      'Som: {n}',
    rowOrange:     'Oranje',
    rowPink:       'Roze',
    rowTeal:       'Turquoise',
    rowLilac:      'Lila',
    chooseOrPass:  'Kies of Pas',
    yourTurnRoll:  'Jouw beurt — tik Gooi!',
    isRolling:     '{player} is aan het gooien…',
    chooseCells:   'Kies vakjes, dan ✓ OK',
    waitingSubmit: 'Wachten op anderen…',
    diceLabel:     'DOBBELSTENEN',
    rules:             'Krúske is een dobbelspel waarbij elke speler een eigen scorekaart heeft. Gooi de dobbelstenen en zet kruisjes in een rij. Als alle vijf vakjes in een rij vol zijn, kun je de rij afsluiten voor een bonus. Hoogste score wint.',
  );

  factory StringsKruske.en() => const StringsKruske(
    gameName:      'Krúske',
    gameDesc:     'Cross off & score',
    rollBtn:       'Roll!',
    penaltyBtn:    '✗ Penalty',
    penaltiesUsed: '{n}/4 used',
    passBtn:       'Pass',
    confirmBtn:    '✓ OK',
    waitingOthers: 'Waiting for others…',
    rowLocked:     '{row} LOCKED',
    youSuffix:     '(you)',
    scoreLabel:    'Score:',
    penLabel:      'Pen:',
    ptsUnit:       'pts',
    gameOver:      'Game Over!',
    yourTurn:      '{player}\'s turn',
    sumLabel:      'Sum: {n}',
    rowOrange:     'Orange',
    rowPink:       'Pink',
    rowTeal:       'Teal',
    rowLilac:      'Lilac',
    chooseOrPass:  'Choose or Pass',
    yourTurnRoll:  'Your turn — tap Roll!',
    isRolling:     '{player} is rolling…',
    chooseCells:   'Choose cells, then ✓ OK',
    waitingSubmit: 'Waiting for others…',
    diceLabel:     'DICE',
    rules:             'Krúske is a dice game where each player has their own score card. Roll the dice and mark a cross in a row. When all five boxes in a row are filled, you can close the row for a bonus. Highest score wins.',
  );
}
