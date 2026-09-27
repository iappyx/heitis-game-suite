import 'app_localizations.dart';

class StringsUnthaldspultsje {
  final String gameName;
  final String gameDesc;
  final String loading;
  final String yourTurn;   // "{player}'s turn"
  final String pairs;      // "pairs" label
  final String matched;    // "{player} matched!"

  final String opponentTurn;  // '{player}\'s turn…'
  final String pairsLabel;
  final String rules;
  const StringsUnthaldspultsje({
    required this.gameName,
    required this.gameDesc,
    required this.loading,
    required this.yourTurn,
    required this.pairs,
    required this.matched,
    required this.opponentTurn,
    required this.pairsLabel,
    required this.rules,
  });

  factory StringsUnthaldspultsje.of(AppLang l) => switch (l) {
    AppLang.fy => StringsUnthaldspultsje.fy(),
    AppLang.nl => StringsUnthaldspultsje.nl(),
    AppLang.en => StringsUnthaldspultsje.en(),
  };

  factory StringsUnthaldspultsje.fy() => const StringsUnthaldspultsje(
    gameName: 'Ûnthâldspultsje',
    gameDesc:     'Fyn de paren',
    loading:  'Laden…',
    yourTurn: 'Beurt fan {player}',
    pairs:    'paren',
    matched:  '{player} hat in pear!',
    opponentTurn: '{player} is oan bar…',
    pairsLabel:   'paren',
    rules:             'Kear om bar twa kaarten om. As se oerienkomme, bliuwe se omdraaid en krijst in ekstra beurt. Measte paren oan it ein wint!',
  );
  factory StringsUnthaldspultsje.nl() => const StringsUnthaldspultsje(
    gameName: 'Paren Zoeken',
    gameDesc:     'Vind de paren',
    loading:  'Laden…',
    yourTurn: 'Beurt van {player}',
    pairs:    'paren',
    matched:  '{player} heeft een paar!',
    opponentTurn: '{player} is aan de beurt…',
    pairsLabel:   'paren',
    rules:             'Draai om de beurt twee kaarten om. Als ze overeenkomen, blijven ze omgedraaid en krijg je een extra beurt. Meeste paren aan het einde wint!',
  );
  factory StringsUnthaldspultsje.en() => const StringsUnthaldspultsje(
    gameName: 'Pair Hunt',
    gameDesc:     'Find the pairs',
    loading:  'Loading…',
    yourTurn: '{player}\'s turn',
    pairs:    'pairs',
    matched:  '{player} matched!',
    opponentTurn: '{player}\'s turn…',
    pairsLabel:   'pairs',
    rules:             'Take turns flipping two cards. If they match, they stay face up and you get another turn. Most pairs at the end wins!',
  );
}
