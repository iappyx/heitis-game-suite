import 'app_localizations.dart';

class StringsDamjen {
  final String gameName;
  final String gameDesc;
  final String yourTurn;     // "{player}'s turn"
  final String mustJump;     // "Must jump!"
  final String drawNoProgress; // draw: 40 moves each without capture or man move

  final String yourMove;
  final String opponentTurn;  // '{player}\'s turn…'
  final String rules;
  const StringsDamjen({
    required this.gameName,
    required this.gameDesc,
    required this.yourTurn,
    required this.mustJump,
    required this.drawNoProgress,
    required this.yourMove,
    required this.opponentTurn,
    required this.rules,
  });

  factory StringsDamjen.of(AppLang l) => switch (l) {
    AppLang.fy => StringsDamjen.fy(),
    AppLang.nl => StringsDamjen.nl(),
    AppLang.en => StringsDamjen.en(),
  };

  factory StringsDamjen.fy() => const StringsDamjen(
    gameName:  'Damjen',
    gameDesc:     'Springe & slaan',
    yourTurn:  'Beurt fan {player}',
    mustJump:  'Moat slaan!',
    drawNoProgress: '40 setten elk sûnder slaan of skiifset — lykspul!',
    yourMove:  'Dyn beurt',
    opponentTurn: '{player} is oan bar…',
    rules:             'Ferpleats dyn skiven diagoanaal oer it boerd. Springe oer tsjinstanners om se te slaan. De spiler dy\'t alle stikken fan de tsjinstanner slaan hat, wint!',
  );
  factory StringsDamjen.nl() => const StringsDamjen(
    gameName:  'Dammen',
    gameDesc:     'Springen & slaan',
    yourTurn:  'Beurt van {player}',
    mustJump:  'Verplicht slaan!',
    drawNoProgress: '40 zetten elk zonder slaan of schijfzet — gelijkspel!',
    yourMove:  'Jouw beurt',
    opponentTurn: '{player} is aan de beurt…',
    rules:             'Beweeg je schijven diagonaal over het bord. Spring over tegenstanders om ze te slaan. De speler die alle stukken van de tegenstander heeft geslagen, wint!',
  );
  factory StringsDamjen.en() => const StringsDamjen(
    gameName:  'Checkers',
    gameDesc:     'Jump & capture',
    yourTurn:  '{player}\'s turn',
    mustJump:  'Must jump!',
    drawNoProgress: '40 moves each without a capture or man move — draw!',
    yourMove:  'Your move',
    opponentTurn: '{player}\'s turn…',
    rules:             'Move your pieces diagonally across the board. Jump over opponents to capture them. The player who captures all opponent\'s pieces wins!',
  );
}
