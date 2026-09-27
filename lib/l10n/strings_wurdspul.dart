import 'app_localizations.dart';

class StringsWurdspul {
  final String gameName;
  final String gameDesc;
  final String scrambleLabel;
  final String tapLetters;
  final String correct;
  final String wrong;
  final String skip;
  final String scoreLabel;
  final String roundLabel;
  final String timeUp;
  final String soloTitle;
  final String soloDesc;
  final String personalBest;
  final String newBest;
  final String wrongWaiting;
  final String otherFirst;
  final String rules;

  const StringsWurdspul({
    required this.gameName,
    required this.gameDesc,
    required this.scrambleLabel,
    required this.tapLetters,
    required this.correct,
    required this.wrong,
    required this.skip,
    required this.scoreLabel,
    required this.roundLabel,
    required this.timeUp,
    required this.soloTitle,
    required this.soloDesc,
    required this.personalBest,
    required this.newBest,
    required this.wrongWaiting,
    required this.otherFirst,
    required this.rules,
  });

  factory StringsWurdspul.of(AppLang l) => switch (l) {
    AppLang.fy => StringsWurdspul.fy(),
    AppLang.nl => StringsWurdspul.nl(),
    AppLang.en => StringsWurdspul.en(),
  };

  factory StringsWurdspul.fy() => const StringsWurdspul(
    gameName:      'Wurdspul',
    gameDesc:      'Set de letters op oarder',
    scrambleLabel: 'Hokker wurd is dit?',
    tapLetters:    'Tapje de letters yn de goede folchoarder',
    correct:       'Goed! 🎉',
    wrong:         'Ferkeard — it wie: {word}',
    skip:          'Oerslaan',
    scoreLabel:    'Punten: {score}',
    roundLabel:    'Wurd {n} fan {total}',
    timeUp:        'Tiid is om!',
    soloTitle:     'Wurdspul Solo',
    soloDesc:      'Hoe folle wurden kinst ûntwarje?',
    personalBest:  'Bêste: {score}',
    newBest:       '🌟 Nij rekôr!',
    wrongWaiting:  'Ferkeard! Wachtsje op {player}…',
    otherFirst:    '{player} hie it earst! It wie: {word}',
    rules:         'In wurd wurdt trochinoar husele. Tapje de letters yn de goede folchoarder. Krijst in punt foar elk goed wurd. Yn duöspul: earste mei de measte punten nei 10 wurden wint!',
  );

  factory StringsWurdspul.nl() => const StringsWurdspul(
    gameName:      'Woordspel',
    gameDesc:      'Zet de letters op volgorde',
    scrambleLabel: 'Welk woord is dit?',
    tapLetters:    'Tik de letters in de goede volgorde',
    correct:       'Goed! 🎉',
    wrong:         'Fout — het was: {word}',
    skip:          'Overslaan',
    scoreLabel:    'Punten: {score}',
    roundLabel:    'Woord {n} van {total}',
    timeUp:        'Tijd is om!',
    soloTitle:     'Woordspel Solo',
    soloDesc:      'Hoeveel woorden kun jij ontwarren?',
    personalBest:  'Beste: {score}',
    newBest:       '🌟 Nieuw record!',
    wrongWaiting:  'Fout! Wachten op {player}…',
    otherFirst:    '{player} was eerst! Het was: {word}',
    rules:         'Een woord wordt door elkaar gehusseld. Tik de letters in de juiste volgorde. Je krijgt een punt voor elk goed woord. In duomodus: eerste met de meeste punten na 10 woorden wint!',
  );

  factory StringsWurdspul.en() => const StringsWurdspul(
    gameName:      'Word Scramble',
    gameDesc:      'Unscramble the letters',
    scrambleLabel: 'What word is this?',
    tapLetters:    'Tap the letters in the right order',
    correct:       'Correct! 🎉',
    wrong:         'Wrong — it was: {word}',
    skip:          'Skip',
    scoreLabel:    'Score: {score}',
    roundLabel:    'Word {n} of {total}',
    timeUp:        'Time\'s up!',
    soloTitle:     'Word Scramble Solo',
    soloDesc:      'How many words can you unscramble?',
    personalBest:  'Best: {score}',
    newBest:       '🌟 New record!',
    wrongWaiting:  'Wrong! Waiting for {player}…',
    otherFirst:    '{player} got it first! It was: {word}',
    rules:         'A word is scrambled up. Tap the letters in the correct order. You earn a point for each correct word. Versus: first player with the most points after 10 words wins!',
  );
}
