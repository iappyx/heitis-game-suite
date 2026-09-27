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
    whitesTurn:  'White\'s turn',
    blacksTurn:  'Black\'s turn',
    yourMove:    'Your move',
    waiting:     'Waiting…',
    rules:             'Classic chess. Move your pieces according to standard chess rules. Checkmate your opponent\'s king to win.',
  );
}
