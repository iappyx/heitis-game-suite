import 'app_localizations.dart';

class StringsButerBreaEnGrieneTsiis {
  final String gameName;
  final String gameDesc;
  final String yourTurn;       // "{player}'s turn"
  final String xTurn;          // "X's turn"
  final String oTurn;          // "O's turn"
  final String winsCount;      // "{player} wins"
  final String draws;
  final String drawCount;      // "Draw! ({n} draws)"
  final String yourTurnExcl;   // "Your turn!"
  final String opponentTurn;   // "{player}'s turn…"
  final String rules;

  const StringsButerBreaEnGrieneTsiis({
    required this.gameName,
    required this.gameDesc,
    required this.yourTurn,
    required this.xTurn,
    required this.oTurn,
    required this.winsCount,
    required this.draws,
    required this.drawCount,
    required this.yourTurnExcl,
    required this.opponentTurn,
    required this.rules,
  });

  factory StringsButerBreaEnGrieneTsiis.of(AppLang l) => switch (l) {
    AppLang.fy => StringsButerBreaEnGrieneTsiis.fy(),
    AppLang.nl => StringsButerBreaEnGrieneTsiis.nl(),
    AppLang.en => StringsButerBreaEnGrieneTsiis.en(),
  };

  factory StringsButerBreaEnGrieneTsiis.fy() => const StringsButerBreaEnGrieneTsiis(
    gameName:     'Bûter, brea en griene tsiis',
    gameDesc:     '3 op in rige',
    yourTurn:     'Beurt fan {player}',
    xTurn:        'X is oan bar',
    oTurn:        'O is oan bar',
    winsCount:    '{player} wint',
    draws:        'Lykspul',
    drawCount:    'Lykspul! ({n}×)',
    yourTurnExcl: 'Dyn beurt!',
    opponentTurn: '{player} is oan bar…',
    rules:             'Spilers sette om bar in X of O op it 3×3 boerd. Earste mei trije op in rige (horizontaal, fertikaal of diagoanaal) wint!',
  );
  factory StringsButerBreaEnGrieneTsiis.nl() => const StringsButerBreaEnGrieneTsiis(
    gameName:     'Tic-Tac-Toe',
    gameDesc:     '3 op een rij',
    yourTurn:     'Beurt van {player}',
    xTurn:        'X is aan de beurt',
    oTurn:        'O is aan de beurt',
    winsCount:    '{player} wint',
    draws:        'Gelijkspel',
    drawCount:    'Gelijkspel! ({n}×)',
    yourTurnExcl: 'Jouw beurt!',
    opponentTurn: '{player} is aan de beurt…',
    rules:             'Spelers zetten om de beurt een X of O op het 3×3 bord. Eerste met drie op een rij (horizontaal, verticaal of diagonaal) wint!',
  );
  factory StringsButerBreaEnGrieneTsiis.en() => const StringsButerBreaEnGrieneTsiis(
    gameName:     'Tic-Tac-Toe',
    gameDesc:     '3 in a row',
    yourTurn:     '{player}\'s turn',
    xTurn:        'X\'s turn',
    oTurn:        'O\'s turn',
    winsCount:    '{player} wins',
    draws:        'Draws',
    drawCount:    'Draw! ({n} draws)',
    yourTurnExcl: 'Your turn!',
    opponentTurn: '{player}\'s turn…',
    rules:             'Players take turns placing X or O on the 3×3 grid. First with three in a row (horizontal, vertical or diagonal) wins!',
  );
}
