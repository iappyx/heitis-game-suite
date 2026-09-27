import 'app_localizations.dart';

class StringsPaddelduel {
  final String gameName;
  final String gameDesc;
  final String yourTurnExcl;
  final String opponentTurn;
  final String rules;

  const StringsPaddelduel({
    required this.gameName,
    required this.gameDesc,
    required this.yourTurnExcl,
    required this.opponentTurn,
    required this.rules,
  });

  factory StringsPaddelduel.of(AppLang l) => switch (l) {
    AppLang.fy => StringsPaddelduel.fy(),
    AppLang.nl => StringsPaddelduel.nl(),
    AppLang.en => StringsPaddelduel.en(),
  };

  factory StringsPaddelduel.fy() => const StringsPaddelduel(
    gameName:     'Paddelduel',
    gameDesc:     'Earste op 5 punten wint',
    yourTurnExcl: 'Dyn batje!',
    opponentTurn: 'Batje fan {player}',
    rules:             'Beweech dyn peddel om de bal te kearen. Lit de bal net foarby dyn peddel komme, want dêrmei skoart de tsjinstanner. Earste mei 5 punten wint!',
  );
  factory StringsPaddelduel.nl() => const StringsPaddelduel(
    gameName:     'Paddelduel',
    gameDesc:     'Eerste op 5 punten wint',
    yourTurnExcl: 'Jouw batje!',
    opponentTurn: 'Batje van {player}',
    rules:             'Beweeg je peddel om de bal te keren. Laat de bal niet langs je peddel komen, want daarmee scoort de tegenstander. Eerste met 5 punten wint!',
  );
  factory StringsPaddelduel.en() => const StringsPaddelduel(
    gameName:     'Paddle Duel',
    gameDesc:     'First to 5 points wins',
    yourTurnExcl: 'Your paddle!',
    opponentTurn: '{player}\'s paddle',
    rules:             'Move your paddle to deflect the ball. Don\'t let the ball pass your paddle or your opponent scores. First to 5 points wins!',
  );
}
