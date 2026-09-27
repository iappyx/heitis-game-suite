import 'app_localizations.dart';

class StringsLudo {
  final String gameName;
  final String gameDesc;
  final String rollDice;
  final String yourTurn;   // "{player}'s turn"
  final String noMoves;    // "No moves — next turn"

  final String yourTurnRoll;   // 'Your turn — roll!'
  final String opponentTurn;    // '{player}\'s turn…'
  final String rolled;          // rolled, now pick a token
  final String rolledN;         // 'Rolled {n} — pick a token'
  final String pass;           // 'Pass'
  final String rules;
  const StringsLudo({
    required this.gameName,
    required this.gameDesc,
    required this.rollDice,
    required this.yourTurn,
    required this.noMoves,
    required this.yourTurnRoll,
    required this.opponentTurn,
    required this.rolled,
    required this.rolledN,
    required this.pass,
    required this.rules,
  });

  factory StringsLudo.of(AppLang l) => switch (l) {
    AppLang.fy => StringsLudo.fy(),
    AppLang.nl => StringsLudo.nl(),
    AppLang.en => StringsLudo.en(),
  };

  factory StringsLudo.fy() => const StringsLudo(
    gameName: 'Ludo',
    gameDesc:     'Race nei de finish',
    rollDice: 'Goaie!',
    yourTurn: 'Beurt fan {player}',
    noMoves:  'Gjin setten — folgjende beurt',
    yourTurnRoll: 'Dyn beurt — goaie!',
    opponentTurn: '{player} is oan bar…',
    rolled:       'Dyn beurt — set in stik!',
    rolledN:      'Goaid {n} — set in stik',
    pass:         'Passe',
    rules:             'Goai de dobbelsteen en ferpleats dyn stikken oer it boerd. Goa in tsjinstanner om dy werom nei it nêst te stjoeren. Kom earst mei al dyn fjouwer stikken thús om te winnen!',
  );
  factory StringsLudo.nl() => const StringsLudo(
    gameName: 'Ludo',
    gameDesc:     'Race naar de finish',
    rollDice: 'Gooi dobbelsteen',
    yourTurn: 'Beurt van {player}',
    noMoves:  'Geen zetten — volgende beurt',
    yourTurnRoll: 'Jouw beurt — gooi!',
    opponentTurn: '{player} is aan de beurt…',
    rolled:       'Jouw beurt — zet een stuk!',
    rolledN:      'Gegooid {n} — zet een stuk',
    pass:         'Passen',
    rules:             'Gooi de dobbelsteen en beweeg je stukken over het bord. Land op een tegenstander om hem terug naar zijn nest te sturen. Kom als eerste met al je vier stukken thuis om te winnen!',
  );
  factory StringsLudo.en() => const StringsLudo(
    gameName: 'Ludo',
    gameDesc:     'Race to finish',
    rollDice: 'Roll Dice',
    yourTurn: '{player}\'s turn',
    noMoves:  'No moves — next turn',
    yourTurnRoll: 'Your turn — roll!',
    opponentTurn: '{player}\'s turn…',
    rolled:       'Your turn — move a piece!',
    rolledN:      'Rolled {n} — move a piece',
    pass:         'Pass',
    rules:             'Roll the die and move your pieces around the board. Land on an opponent to send them back to their nest. Get all four of your pieces home first to win!',
  );
}
