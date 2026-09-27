import 'app_localizations.dart';

class StringsPuntenEnFakjes {
  final String gameName;
  final String gameDesc;
  final String yourTurn;   // "{player}'s turn"
  final String score;      // "Score"

  final String yourTurnExcl;
  final String opponentTurn;  // '{player}\'s turn…'
  final String draw;
  final String rules;
  const StringsPuntenEnFakjes({
    required this.gameName,
    required this.gameDesc,
    required this.yourTurn,
    required this.score,
    required this.yourTurnExcl,
    required this.opponentTurn,
    required this.draw,
    required this.rules,
  });

  factory StringsPuntenEnFakjes.of(AppLang l) => switch (l) {
    AppLang.fy => StringsPuntenEnFakjes.fy(),
    AppLang.nl => StringsPuntenEnFakjes.nl(),
    AppLang.en => StringsPuntenEnFakjes.en(),
  };

  factory StringsPuntenEnFakjes.fy() => const StringsPuntenEnFakjes(
    gameName: 'Punten & Fakjes',
    gameDesc:     'Fjirken foltôgje',
    yourTurn: 'Beurt fan {player}',
    score:    'Punten',
    yourTurnExcl: 'Dyn beurt!',
    opponentTurn: '{player} is oan bar…',
    draw:         'Lykspul!',
    rules:             'Teken om bar in line tusken twa stippen. Meist do de fierde line fan in fak sette, krijst dat fak en in ekstra beurt. Measte fakjes oan it ein wint!',
  );
  factory StringsPuntenEnFakjes.nl() => const StringsPuntenEnFakjes(
    gameName: 'Dots & Vakjes',
    gameDesc:     'Vierkantjes voltooien',
    yourTurn: 'Beurt van {player}',
    score:    'Punten',
    yourTurnExcl: 'Jouw beurt!',
    opponentTurn: '{player} is aan de beurt…',
    draw:         'Gelijkspel!',
    rules:             'Teken om de beurt een lijn tussen twee stippen. Als jij de vierde lijn van een vakje plaatst, krijg je dat vakje en een extra beurt. Meeste vakjes aan het einde wint!',
  );
  factory StringsPuntenEnFakjes.en() => const StringsPuntenEnFakjes(
    gameName: 'Dots & Boxes',
    gameDesc:     'Complete squares',
    yourTurn: '{player}\'s turn',
    score:    'Score',
    yourTurnExcl: 'Your turn!',
    opponentTurn: '{player}\'s turn…',
    draw:         'Draw!',
    rules:             'Take turns drawing a line between two dots. If you complete the fourth side of a box, you claim it and take another turn. Most boxes at the end wins!',
  );
}
