import 'app_localizations.dart';

class StringsTekenjeEnRiede {
  final String gameName;
  final String gameDesc;
  final String youDraw;
  final String youGuess;
  final String drawingLabel;
  final String guessPlaceholder;
  final String correct;        // '{player} guessed correctly' — shown to spectators
  final String youGuessedIt;   // shown only to the player who guessed correctly
  final String timeUp;
  final String roundLabel;
  final String scoreLabel;
  final String waitingForDrawer;
  final String chooseWord;
  final String sketchHint;
  final String clearCanvas;
  final String chooseLang;
  final String chooseLangHint;
  final String startGame;
  final String rules;
  final String modeTyping;      // "Type to guess"
  final String modeVerbal;      // "Guess out loud"
  final String chooseMode;      // "How do you want to guess?"
  final String gotIt;           // "Got it!" button in verbal mode
  final String verbalHint;      // "Say the word out loud!"
  final String skip;            // "Skip"
  final String waitingForGuesser; // "Waiting for guesser..."
  final String drawerConfirmed;   // "Drawer confirmed!"
  final String guesserConfirmed;  // "Guesser confirmed!"

  const StringsTekenjeEnRiede({
    required this.gameName,
    required this.gameDesc,
    required this.youDraw,
    required this.youGuess,
    required this.drawingLabel,
    required this.guessPlaceholder,
    required this.correct,
    required this.youGuessedIt,
    required this.timeUp,
    required this.roundLabel,
    required this.scoreLabel,
    required this.waitingForDrawer,
    required this.chooseWord,
    required this.sketchHint,
    required this.clearCanvas,
    required this.chooseLang,
    required this.chooseLangHint,
    required this.startGame,
    required this.rules,
    required this.modeTyping,
    required this.modeVerbal,
    required this.chooseMode,
    required this.gotIt,
    required this.verbalHint,
    required this.skip,
    required this.waitingForGuesser,
    required this.drawerConfirmed,
    required this.guesserConfirmed,
  });

  factory StringsTekenjeEnRiede.of(AppLang l) => switch (l) {
    AppLang.fy => StringsTekenjeEnRiede.fy(),
    AppLang.nl => StringsTekenjeEnRiede.nl(),
    AppLang.en => StringsTekenjeEnRiede.en(),
  };

  factory StringsTekenjeEnRiede.fy() => const StringsTekenjeEnRiede(
    gameName:          'Tekenje & Riede',
    gameDesc:          'Teken it wurd, raad it earst!',
    youDraw:           'Do tekenjest!',
    youGuess:          'Wat tekenet {player}?',
    drawingLabel:      '{player} is oan it tekenjen...',
    guessPlaceholder:  'Typ dyn antwurd...',
    correct:           '{player} hat it rieden!',
    youGuessedIt:      'Do hast it rieden!',
    timeUp:            'Tiid is om! It wie: {word}',
    roundLabel:        'Ronte {n} fan {total}',
    scoreLabel:        'Punten',
    waitingForDrawer:  'Wachtsje op de tekenaar...',
    chooseWord:        'Kies in wurd om te tekenjen:',
    sketchHint:        'Teken hjir!',
    clearCanvas:       'Wisje',
    chooseLang:        'Taalkar',
    chooseLangHint:    'Yn hokker taal moatte de wurden weze?',
    startGame:         'Begjinne',
    rules:             'De tekenaar krijt in geheim wurd en tekenet it sunder letters te skriuwen. De oaren besykje it wurd te rieden. Wat earst goed riedt, krijt punten en de tekenaar ek! Nei elke runte wikselje de rollen.',
    modeTyping:        'Typ it antwurd',
    modeVerbal:        'Rop it antwurd',
    chooseMode:        'Hoe wolle jimme riede?',
    gotIt:             'Rieden!',
    verbalHint:        'Rop it wurd hardop!',
    skip:              'Oerslaan',
    waitingForGuesser: 'Wachtsje op de rieder...',
    drawerConfirmed:   'De tekenaar seit: goed!',
    guesserConfirmed:  'De rieder seit: rieden!',
  );

  factory StringsTekenjeEnRiede.nl() => const StringsTekenjeEnRiede(
    gameName:          'Tekenen & Raden',
    gameDesc:          'Teken het woord, raad het eerst!',
    youDraw:           'Jij tekent!',
    youGuess:          'Wat tekent {player}?',
    drawingLabel:      '{player} is aan het tekenen...',
    guessPlaceholder:  'Typ je antwoord...',
    correct:           '{player} raadt het!',
    youGuessedIt:      'Jij hebt het geraden!',
    timeUp:            'Tijd is om! Het was: {word}',
    roundLabel:        'Ronde {n} van {total}',
    scoreLabel:        'Punten',
    waitingForDrawer:  'Wachten op de tekenaar...',
    chooseWord:        'Kies een woord om te tekenen:',
    sketchHint:        'Teken hier!',
    clearCanvas:       'Wissen',
    chooseLang:        'Taal kiezen',
    chooseLangHint:    'In welke taal moeten de woorden zijn?',
    startGame:         'Beginnen',
    rules:             'De tekenaar krijgt een geheim woord en tekent het zonder letters te schrijven. De anderen proberen het woord te raden. Wie het eerst goed raadt krijgt punten en de tekenaar ook! Na elke ronde wisselen de rollen.',
    modeTyping:        'Typ het antwoord',
    modeVerbal:        'Roep het antwoord',
    chooseMode:        'Hoe willen jullie raden?',
    gotIt:             'Geraden!',
    verbalHint:        'Roep het woord hardop!',
    skip:              'Overslaan',
    waitingForGuesser: 'Wachten op de rader...',
    drawerConfirmed:   'De tekenaar zegt: goed!',
    guesserConfirmed:  'De rader zegt: geraden!',
  );

  factory StringsTekenjeEnRiede.en() => const StringsTekenjeEnRiede(
    gameName:          'Draw & Guess',
    gameDesc:          'Draw the word, guess it first!',
    youDraw:           'You draw!',
    youGuess:          'What is {player} drawing?',
    drawingLabel:      '{player} is drawing...',
    guessPlaceholder:  'Type your guess...',
    correct:           '{player} guessed it!',
    youGuessedIt:      'You got it!',
    timeUp:            'Time\'s up! It was: {word}',
    roundLabel:        'Round {n} of {total}',
    scoreLabel:        'Score',
    waitingForDrawer:  'Waiting for the drawer...',
    chooseWord:        'Choose a word to draw:',
    sketchHint:        'Draw here!',
    clearCanvas:       'Clear',
    chooseLang:        'Choose language',
    chooseLangHint:    'Which language should the words be in?',
    startGame:         'Start',
    rules:             'The drawer gets a secret word and draws it without writing letters. Others try to guess the word. The first correct guesser earns points and the drawer too! Roles rotate each round.',
    modeTyping:        'Type the answer',
    modeVerbal:        'Say it out loud',
    chooseMode:        'How do you want to guess?',
    gotIt:             'Got it!',
    verbalHint:        'Say the word out loud!',
    skip:              'Skip',
    waitingForGuesser: 'Waiting for guesser...',
    drawerConfirmed:   'Drawer says correct!',
    guesserConfirmed:  'Guesser says got it!',
  );
}
