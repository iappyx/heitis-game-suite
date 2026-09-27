import 'app_localizations.dart';

class StringsFjouwerOpInRige {
  final String gameName;
  final String gameDesc;
  final String yourTurn;    // "{player}'s turn"
  final String winsCount;   // "{player} wins"

  final String yourTurnExcl;  // 'Your turn!'
  final String opponentTurn;   // '{player}\'s turn…'
  final String draw;
  final String rules;
  const StringsFjouwerOpInRige({
    required this.gameName,
    required this.gameDesc,
    required this.yourTurn,
    required this.winsCount,
    required this.yourTurnExcl,
    required this.opponentTurn,
    required this.draw,
    required this.rules,
  });

  factory StringsFjouwerOpInRige.of(AppLang l) => switch (l) {
    AppLang.fy => StringsFjouwerOpInRige.fy(),
    AppLang.nl => StringsFjouwerOpInRige.nl(),
    AppLang.en => StringsFjouwerOpInRige.en(),
  };

  factory StringsFjouwerOpInRige.fy() => const StringsFjouwerOpInRige(
    gameName:  'Fjouwer op in Rige',
    gameDesc:     'Fjouwer yn in rige',
    yourTurn:  'Beurt fan {player}',
    winsCount: '{player} wint',
    yourTurnExcl: 'Dyn beurt!',
    opponentTurn: '{player} is oan bar…',
    draw:         'Lykspul!',
    rules:             'Lit om bar in skijf falle yn in kolom fan it 6×7 boerd. Earste mei fjouwer skiven op in rige (horizontaal, fertikaal of diagoanaal) wint!',
  );
  factory StringsFjouwerOpInRige.nl() => const StringsFjouwerOpInRige(
    gameName:  'Rij van Vier',
    gameDesc:     'Vier op een lijn',
    yourTurn:  'Beurt van {player}',
    winsCount: '{player} wint',
    yourTurnExcl: 'Jouw beurt!',
    opponentTurn: '{player} is aan de beurt…',
    draw:         'Gelijkspel!',
    rules:             'Laat om de beurt een schijf vallen in een kolom van het 6×7 bord. Eerste met vier schijven op een rij (horizontaal, verticaal of diagonaal) wint!',
  );
  factory StringsFjouwerOpInRige.en() => const StringsFjouwerOpInRige(
    gameName:  'Four in a Row',
    gameDesc:     'Line up four',
    yourTurn:  '{player}\'s turn',
    winsCount: '{player} wins',
    yourTurnExcl: 'Your turn!',
    opponentTurn: '{player}\'s turn…',
    draw:         'Draw!',
    rules:             'Take turns dropping a disc into a column on the 6×7 board. First with four in a row (horizontal, vertical or diagonal) wins!',
  );
}
