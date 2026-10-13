import 'app_localizations.dart';

class StringsSkaken {
  final String gameName;
  final String gameDesc;
  final String yourTurn;    // "{player}'s turn"
  final String check;       // "Check!"
  final String checkmate;   // "Checkmate!"
  final String stalemate;   // "Stalemate — draw!"
  final String drawInsufficient; // draw: not enough pieces to checkmate
  final String drawFiftyMoves;   // draw: 50 moves without capture/pawn move
  final String stalemateWhy;     // result banner: what stalemate means
  final String stalemateWarnTitle; // dialog before a move that stalemates
  final String stalemateWarnBody;
  final String stalemateWarnOther; // button: pick another move
  final String stalemateWarnPlay;  // button: play it anyway
  final String whitesTurn;
  final String blacksTurn;

  final String yourMove;
  final String waiting;
  final String rules;
  const StringsSkaken({
    required this.gameName,
    required this.gameDesc,
    required this.yourTurn,
    required this.check,
    required this.checkmate,
    required this.stalemate,
    required this.drawInsufficient,
    required this.drawFiftyMoves,
    required this.stalemateWhy,
    required this.stalemateWarnTitle,
    required this.stalemateWarnBody,
    required this.stalemateWarnOther,
    required this.stalemateWarnPlay,
    required this.whitesTurn,
    required this.blacksTurn,
    required this.yourMove,
    required this.waiting,
    required this.rules,
  });

  factory StringsSkaken.of(AppLang l) => switch (l) {
    AppLang.fy => StringsSkaken.fy(),
    AppLang.nl => StringsSkaken.nl(),
    AppLang.en => StringsSkaken.en(),
  };

  factory StringsSkaken.fy() => const StringsSkaken(
    gameName:    'Skaken',
    gameDesc:     'Klassyk skaakspul',
    yourTurn:    'Beurt fan {player}',
    check:       'Skaak!',
    checkmate:   'Skaakmat!',
    stalemate:   'Pat — lykspul!',
    drawInsufficient: 'Te min stikken foar skaakmat — lykspul!',
    drawFiftyMoves:   '50 setten sûnder slaan of pionset — lykspul!',
    stalemateWhy:     'Pat: de kening stiet net skaak, mar kin nergens mear hinne. Neffens de regels is dat lykspul.',
    stalemateWarnTitle: 'Pas op: dit wurdt pat',
    stalemateWarnBody:  'Nei dizze set stiet de kening fan dyn tsjinstanner net skaak, mar kin er gjin inkelde set mear dwaan. Dat is pat, en pat is lykspul. Om te winnen moatst skaakmat jaan.',
    stalemateWarnOther: 'Oare set kieze',
    stalemateWarnPlay:  'Dochs dwaan',
    whitesTurn:  'Wyt is oan bar',
    blacksTurn:  'Swart is oan bar',
    yourMove:    'Dyn beurt',
    waiting:     'Wachtsje…',
    rules:             'Klassyk skaak. Bewege dyn stikken neffens de standert skaakregels. Sett de kening fan dyn tsjinstanner yn skaakmat om te winnen.',
  );
  factory StringsSkaken.nl() => const StringsSkaken(
    gameName:    'Schaken',
    gameDesc:     'Klassiek schaak',
    yourTurn:    'Beurt van {player}',
    check:       'Schaak!',
    checkmate:   'Schaakmat!',
    stalemate:   'Pat — gelijkspel!',
    drawInsufficient: 'Te weinig stukken voor schaakmat — gelijkspel!',
    drawFiftyMoves:   '50 zetten zonder slaan of pionzet — gelijkspel!',
    stalemateWhy:     'Pat: de koning staat niet schaak, maar kan nergens meer heen. Volgens de regels is dat gelijkspel.',
    stalemateWarnTitle: 'Let op: dit wordt pat',
    stalemateWarnBody:  'Na deze zet staat de koning van je tegenstander niet schaak, maar kan hij geen enkele zet meer doen. Dat is pat, en pat is gelijkspel. Om te winnen moet je schaakmat geven.',
    stalemateWarnOther: 'Andere zet kiezen',
    stalemateWarnPlay:  'Toch doen',
    whitesTurn:  'Wit is aan de beurt',
    blacksTurn:  'Zwart is aan de beurt',
    yourMove:    'Jouw beurt',
    waiting:     'Wachten…',
    rules:             'Klassiek schaken. Beweeg je stukken volgens de standaard schaakregels. Zet de koning van je tegenstander schaakmat om te winnen.',
  );
  factory StringsSkaken.en() => const StringsSkaken(
    gameName:    'Chess',
    gameDesc:     'Classic chess',
    yourTurn:    '{player}\'s turn',
    check:       'Check!',
    checkmate:   'Checkmate!',
    stalemate:   'Stalemate — draw!',
    drawInsufficient: 'Not enough pieces to checkmate — draw!',
    drawFiftyMoves:   '50 moves without a capture or pawn move — draw!',
    stalemateWhy:     'Stalemate: the king is not in check, but has no move left. By the rules that is a draw.',
    stalemateWarnTitle: 'Careful: this is stalemate',
    stalemateWarnBody:  'After this move your opponent\'s king is not in check, but has no legal move left. That is stalemate, and stalemate is a draw. To win, you need to give checkmate.',
    stalemateWarnOther: 'Pick another move',
    stalemateWarnPlay:  'Play it anyway',
    whitesTurn:  'White\'s turn',
    blacksTurn:  'Black\'s turn',
    yourMove:    'Your move',
    waiting:     'Waiting…',
    rules:             'Classic chess. Move your pieces according to standard chess rules. Checkmate your opponent\'s king to win.',
  );
}
