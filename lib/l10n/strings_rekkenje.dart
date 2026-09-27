import 'app_localizations.dart';

class StringsRekkenje {
  final String gameName;
  final String gameDesc;
  final String setupTitle;       // "Math Quest Setup"
  final String setupSubtitle;    // "Host configures the game for everyone"
  final String cancelBtn;
  final String startBtn;         // "Start!"
  final String playerLabel;      // "Player" (column header)
  final String roundOf;          // "Round {cur} of {total}"
  final String roundShort;       // "Round {cur}/{total}"  (compact)
  final String questionShort;    // "Q {n}/{total}"
  final String secondsLeft;      // "{n}s"
  final String waitingRoundEnd;  // "Waiting for round to end…"
  final String waitingNextRound; // "Waiting for host to start next round…"
  final String roundDone;        // "Round {n} Done!"
  final String nextRound;        // "Round {n}!"
  final String answeredOf;       // "{done}/{total}" — answers label
  final String range;            // "0–{max}"
  // Operation labels (shown in config/game header)
  final String opAddition;
  final String opSubtraction;
  final String opMultiplication;
  final String opDivision;
  final String opMixed;
  // Config section headers
  final String sectionOperation;
  final String sectionMax;
  final String sectionRounds;
  final String sectionQuestions;
  final String sectionTime;

  final String correct;          // "Correct! ✅"
  final String incorrect;        // "Incorrect \n({ans})"
  final String thisRound;        // "This round"
  final String totalLabel;       // "Total"
  final String accuracy;         // "Accuracy"
  final String pointsLabel;      // "Points"
  final String sectionNumberRange;
  final String summaryRounds;      // "{n} rounds"
  final String summaryQuestions;   // "{n} questions"
  final String summarySecondsPerRound; // "{n}s/round"
  final String goBtn;              // "GO!" // "Number Range"
  final String playersLabel;       // "PLAYERS" section header
  final String rules;
  const StringsRekkenje({
    required this.gameName,
    required this.gameDesc,
    required this.setupTitle,
    required this.setupSubtitle,
    required this.cancelBtn,
    required this.startBtn,
    required this.playerLabel,
    required this.roundOf,
    required this.roundShort,
    required this.questionShort,
    required this.secondsLeft,
    required this.waitingRoundEnd,
    required this.waitingNextRound,
    required this.roundDone,
    required this.nextRound,
    required this.answeredOf,
    required this.range,
    required this.opAddition,
    required this.opSubtraction,
    required this.opMultiplication,
    required this.opDivision,
    required this.opMixed,
    required this.sectionOperation,
    required this.sectionMax,
    required this.sectionRounds,
    required this.sectionQuestions,
    required this.sectionTime,
    required this.correct,
    required this.incorrect,
    required this.thisRound,
    required this.totalLabel,
    required this.accuracy,
    required this.pointsLabel,
    required this.sectionNumberRange,
    required this.summaryRounds,
    required this.summaryQuestions,
    required this.summarySecondsPerRound,
    required this.goBtn,
    required this.playersLabel,
    required this.rules,
  });

  factory StringsRekkenje.of(AppLang l) => switch (l) {
    AppLang.fy => StringsRekkenje.fy(),
    AppLang.nl => StringsRekkenje.nl(),
    AppLang.en => StringsRekkenje.en(),
  };

  factory StringsRekkenje.fy() => const StringsRekkenje(
    gameName:         'Rekkenje',
    gameDesc:     'Race om te antwurdzjen!',
    setupTitle:       'Rekkenje Ynstelle',
    setupSubtitle:    'Host stelt it spultsje yn foar elkenien',
    cancelBtn:        'Ôfbrekke',
    startBtn:         'Begjin!',
    playerLabel:      'Spiler',
    roundOf:          'Rûnte {cur} fan {total}',
    roundShort:       'Rûnte {cur}/{total}',
    questionShort:    'Fr {n}/{total}',
    secondsLeft:      '{n}s',
    waitingRoundEnd:  'Wachtsje op ein fan de rûnte…',
    waitingNextRound: 'Wachtsje op host foar de folgjende rûnte…',
    roundDone:        'Rûnte {n} klear!',
    nextRound:        'Rûnte {n}!',
    answeredOf:       '{done}/{total}',
    range:            '0–{max}',
    opAddition:       'Optelle',
    opSubtraction:    'Ôflûke',
    opMultiplication: 'Fermannichfâldigje',
    opDivision:       'Diele',
    opMixed:          'Gemengd',
    sectionOperation: 'Operaasje',
    sectionMax:       'Maksimum wearde',
    sectionRounds:    'Rûnten',
    sectionQuestions: 'Fragen per rûnte',
    sectionTime:      'Sekonden per rûnte',
    correct:          'Goed! ✅',
    incorrect:        'Ferkeard \n({ans})',
    thisRound:        'Dizze rûnte',
    totalLabel:       'Totaal',
    accuracy:         'Krektens',
    pointsLabel:      'Punten',
    sectionNumberRange: 'Getal berik',
    summaryRounds:    '{n} rûnten',
    summaryQuestions: '{n} fragen',
    summarySecondsPerRound: '{n}s/rûnte',
    goBtn:            'LOS!',
    playersLabel:     'SPILERS',
    rules:             'Beäntwurdzje wiskundefragen sa gau en korrekt mooglik. Elke korrekte antwurd leveret punten op. De spiler mei de heechste skoare nei alle rûnten wint!',
  );

  factory StringsRekkenje.nl() => const StringsRekkenje(
    gameName:         'Rekenen',
    gameDesc:     'Race om te antwoorden!',
    setupTitle:       'Rekenspel instellen',
    setupSubtitle:    'Host stelt het spel in voor iedereen',
    cancelBtn:        'Annuleren',
    startBtn:         'Start!',
    playerLabel:      'Speler',
    roundOf:          'Ronde {cur} van {total}',
    roundShort:       'Ronde {cur}/{total}',
    questionShort:    'Vr {n}/{total}',
    secondsLeft:      '{n}s',
    waitingRoundEnd:  'Wachten op einde van de ronde…',
    waitingNextRound: 'Wachten op host voor de volgende ronde…',
    roundDone:        'Ronde {n} klaar!',
    nextRound:        'Ronde {n}!',
    answeredOf:       '{done}/{total}',
    range:            '0–{max}',
    opAddition:       'Optellen',
    opSubtraction:    'Aftrekken',
    opMultiplication: 'Vermenigvuldigen',
    opDivision:       'Delen',
    opMixed:          'Gemengd',
    sectionOperation: 'Bewerking',
    sectionMax:       'Maximale waarde',
    sectionRounds:    'Rondes',
    sectionQuestions: 'Vragen per ronde',
    sectionTime:      'Seconden per ronde',
    correct:          'Goed! ✅',
    incorrect:        'Fout \n({ans})',
    thisRound:        'Deze ronde',
    totalLabel:       'Totaal',
    accuracy:         'Nauwkeurigheid',
    pointsLabel:      'Punten',
    sectionNumberRange: 'Getalsbereik',
    summaryRounds:    '{n} rondes',
    summaryQuestions: '{n} vragen',
    summarySecondsPerRound: '{n}s/ronde',
    goBtn:            'START!',
    playersLabel:     'SPELERS',
    rules:             'Beantwoord rekenvragen zo snel en correct mogelijk. Elk correct antwoord levert punten op. De speler met de hoogste score na alle rondes wint!',
  );

  factory StringsRekkenje.en() => const StringsRekkenje(
    gameName:         'Math Quest',
    gameDesc:     'Race to answer!',
    setupTitle:       'Math Quest Setup',
    setupSubtitle:    'Host configures the game for everyone',
    cancelBtn:        'Cancel',
    startBtn:         'Start!',
    playerLabel:      'Player',
    roundOf:          'Round {cur} of {total}',
    roundShort:       'Round {cur}/{total}',
    questionShort:    'Q {n}/{total}',
    secondsLeft:      '{n}s',
    waitingRoundEnd:  'Waiting for round to end…',
    waitingNextRound: 'Waiting for host to start next round…',
    roundDone:        'Round {n} Done!',
    nextRound:        'Round {n}!',
    answeredOf:       '{done}/{total}',
    range:            '0–{max}',
    opAddition:       'Addition',
    opSubtraction:    'Subtraction',
    opMultiplication: 'Multiplication',
    opDivision:       'Division',
    opMixed:          'Mixed',
    sectionOperation: 'Operation',
    sectionMax:       'Max value',
    sectionRounds:    'Rounds',
    sectionQuestions: 'Questions per round',
    sectionTime:      'Seconds per round',
    correct:          'Correct! ✅',
    incorrect:        'Incorrect \n({ans})',
    thisRound:        'This round',
    totalLabel:       'Total',
    accuracy:         'Accuracy',
    pointsLabel:      'Points',
    sectionNumberRange: 'Number Range',
    summaryRounds:    '{n} rounds',
    summaryQuestions: '{n} questions',
    summarySecondsPerRound: '{n}s/round',
    goBtn:            'GO!',
    playersLabel:     'PLAYERS',
    rules:             'Answer maths questions as quickly and correctly as possible. Each correct answer earns points. The player with the highest score after all rounds wins!',
  );
}
