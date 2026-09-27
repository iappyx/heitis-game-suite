import 'app_localizations.dart';

class StringsSkofpuzzel {
  final String gameName;
  final String gameDesc;
  final String solved;
  final String yourTime;
  final String opponentSolving;
  final String youWon;
  final String personalBest;
  final String newBest;
  final String movesLabel;
  final String usePhoto;
  final String useNumbers;
  final String chooseMode;
  final String startGame;
  final String pickPhoto;
  final String rules;

  const StringsSkofpuzzel({
    required this.gameName,
    required this.gameDesc,
    required this.solved,
    required this.yourTime,
    required this.opponentSolving,
    required this.youWon,
    required this.personalBest,
    required this.newBest,
    required this.movesLabel,
    required this.usePhoto,
    required this.useNumbers,
    required this.chooseMode,
    required this.startGame,
    required this.pickPhoto,
    required this.rules,
  });

  factory StringsSkofpuzzel.of(AppLang l) => switch (l) {
    AppLang.fy => StringsSkofpuzzel.fy(),
    AppLang.nl => StringsSkofpuzzel.nl(),
    AppLang.en => StringsSkofpuzzel.en(),
  };

  factory StringsSkofpuzzel.fy() => const StringsSkofpuzzel(
    gameName:        'Skofpuzzel',
    gameDesc:        'Skow de tegels op oarder',
    solved:          'Oplost! 🎉',
    yourTime:        'Dyn tiid: {time}s',
    opponentSolving: '{player} is oan it oplossen…',
    youWon:          'Do hast wûn! 🏆',
    personalBest:    'Bêste: {time}s',
    newBest:         '🌟 Nij rekôr!',
    movesLabel:      '{n} set',
    usePhoto:        'Foto brûke',
    useNumbers:      'Sifers brûke',
    chooseMode:      'Kies de modus',
    startGame:       'Begjinne',
    pickPhoto:       'Kies in foto',
    rules:           'Skow de tegels om de ôfbylding (of nûmers 1–15) op oarder te krijen. De lege tegel brûkst om te skuorren. Yn duöspul: earste dy\'t it oplost wint!',
  );

  factory StringsSkofpuzzel.nl() => const StringsSkofpuzzel(
    gameName:        'Schuifpuzzel',
    gameDesc:        'Schuif de tegels op volgorde',
    solved:          'Opgelost! 🎉',
    yourTime:        'Jouw tijd: {time}s',
    opponentSolving: '{player} is aan het oplossen…',
    youWon:          'Jij wint! 🏆',
    personalBest:    'Beste: {time}s',
    newBest:         '🌟 Nieuw record!',
    movesLabel:      '{n} zet',
    usePhoto:        'Foto gebruiken',
    useNumbers:      'Cijfers gebruiken',
    chooseMode:      'Kies de modus',
    startGame:       'Beginnen',
    pickPhoto:       'Kies een foto',
    rules:           'Schuif de tegels om de afbeelding (of nummers 1–15) op volgorde te krijgen. Het lege vakje gebruik je om te schuiven. In duo-modus: eerste die oplost wint!',
  );

  factory StringsSkofpuzzel.en() => const StringsSkofpuzzel(
    gameName:        'Sliding Puzzle',
    gameDesc:        'Slide the tiles into order',
    solved:          'Solved! 🎉',
    yourTime:        'Your time: {time}s',
    opponentSolving: '{player} is solving…',
    youWon:          'You win! 🏆',
    personalBest:    'Best: {time}s',
    newBest:         '🌟 New record!',
    movesLabel:      '{n} moves',
    usePhoto:        'Use photo',
    useNumbers:      'Use numbers',
    chooseMode:      'Choose mode',
    startGame:       'Start',
    pickPhoto:       'Pick a photo',
    rules:           'Slide the tiles to arrange the image (or numbers 1–15) in order. Use the empty space to slide tiles. Versus: first to solve wins!',
  );
}
