import 'app_localizations.dart';

class StringsIenEnTritich {
  final String gameName;
  final String gameDesc;
  final String rules;
  final String knock;
  final String swapAll;
  final String swimming;
  final String lives;
  final String pot;
  final String roundOver;
  final String youLoseLife;
  final String eliminated;
  final String roundWinner;
  final String thirtyOne;
  final String yourTurn;
  final String waitingFor;
  final String knocked;
  final String lastTurn;
  final String selectCard;
  final String score;
  final String pass;

  const StringsIenEnTritich({
    required this.gameName,
    required this.gameDesc,
    required this.rules,
    required this.knock,
    required this.swapAll,
    required this.swimming,
    required this.lives,
    required this.pot,
    required this.roundOver,
    required this.youLoseLife,
    required this.eliminated,
    required this.roundWinner,
    required this.thirtyOne,
    required this.yourTurn,
    required this.waitingFor,
    required this.knocked,
    required this.lastTurn,
    required this.selectCard,
    required this.score,
    required this.pass,
  });

  factory StringsIenEnTritich.of(AppLang l) => switch (l) {
    AppLang.fy => StringsIenEnTritich.fy(),
    AppLang.nl => StringsIenEnTritich.nl(),
    AppLang.en => StringsIenEnTritich.en(),
  };

  factory StringsIenEnTritich.fy() => const StringsIenEnTritich(
    gameName:    'Ien-en-tritich',
    gameDesc:    'Krij 31 punten yn ien kleur',
    rules:       'Elkenien begjint mei 3 munten. Foar elke ronde leit elkenien 1 munt yn de pot. '
                 'Elkenien krijt 3 kaarten en 3 kaarten lizze iepen yn it midden. '
                 'Op dyn beurt: wikselje 1 kaart mei it midden, wikselje alle 3, of klop. '
                 'As immen klopt, hat elkenien noch 1 beurt. '
                 'As immen 31 hat, einiget de ronde fuortendaliks. '
                 'De heechste skoare wint de pot! De leechste skoare ferliest in munt. '
                 'Telpunten: Aas=11, Kening/Frou/Boer=10, oaren=gesichtswearde. '
                 'Allinnich kaarten fan deselde kleur telle op. '
                 '3 deselde = 30,5 punten. Gjin munten mear = ôfallen!',
    knock:       'Klopje',
    swapAll:     'Alle 3 wikselje',
    swimming:    'Swimme',
    lives:       'Munten',
    pot:         'Pot',
    roundOver:   'Ronde foarby',
    youLoseLife: 'Do ferlieze in munt!',
    eliminated:  'Ofallen',
    roundWinner: '{player} wint de pot!',
    thirtyOne:   'Ien-en-tritich!',
    yourTurn:    'Dyn beurt',
    waitingFor:  '{player} is oan bar',
    knocked:     '{player} hat klopt!',
    lastTurn:    'Leste beurt!',
    selectCard:  'Kies in kaart',
    score:       'Skoare',
    pass:        'Passe',
  );

  factory StringsIenEnTritich.nl() => const StringsIenEnTritich(
    gameName:    'Eenendertig',
    gameDesc:    'Krijg 31 punten in \u00e9\u00e9n kleur',
    rules:       'Iedereen begint met 3 munten. Voor elke ronde legt iedereen 1 munt in de pot. '
                 'Iedereen krijgt 3 kaarten en 3 kaarten liggen open in het midden. '
                 'Op je beurt: wissel 1 kaart met het midden, wissel alle 3, of klop. '
                 'Als iemand klopt, heeft iedereen nog 1 beurt. '
                 'Als iemand 31 heeft, eindigt de ronde meteen. '
                 'De hoogste score wint de pot! De laagste score verliest een munt. '
                 'Puntentelling: Aas=11, Koning/Vrouw/Boer=10, overige=gezichtswaarde. '
                 'Alleen kaarten van dezelfde kleur tellen op. '
                 '3 dezelfde = 30,5 punten. Geen munten meer = afgevallen!',
    knock:       'Kloppen',
    swapAll:     'Alle 3 wisselen',
    swimming:    'Zwemmen',
    lives:       'Munten',
    pot:         'Pot',
    roundOver:   'Ronde voorbij',
    youLoseLife: 'Je verliest een munt!',
    eliminated:  'Afgevallen',
    roundWinner: '{player} wint de pot!',
    thirtyOne:   'Eenendertig!',
    yourTurn:    'Jouw beurt',
    waitingFor:  '{player} is aan de beurt',
    knocked:     '{player} heeft geklopt!',
    lastTurn:    'Laatste beurt!',
    selectCard:  'Kies een kaart',
    score:       'Score',
    pass:        'Passen',
  );

  factory StringsIenEnTritich.en() => const StringsIenEnTritich(
    gameName:    'Thirty-One',
    gameDesc:    'Get 31 points in one suit',
    rules:       'Everyone starts with 3 coins. Before each round, everyone puts 1 coin in the pot. '
                 'Everyone gets 3 cards and 3 cards are placed face-up in the center. '
                 'On your turn: swap 1 card with the center, swap all 3, or knock. '
                 'If someone knocks, everyone else gets exactly 1 more turn. '
                 'If someone gets 31, the round ends immediately. '
                 'Highest score wins the pot! Lowest score loses a coin. '
                 'Scoring: Ace=11, K/Q/J=10, others=face value. '
                 'Only cards of the same suit add up. '
                 '3 of a kind = 30.5 points. No coins left = eliminated!',
    knock:       'Knock',
    swapAll:     'Swap all 3',
    swimming:    'Swimming',
    lives:       'Coins',
    pot:         'Pot',
    roundOver:   'Round over',
    youLoseLife: 'You lose a coin!',
    eliminated:  'Eliminated',
    roundWinner: '{player} wins the pot!',
    thirtyOne:   'Thirty-one!',
    yourTurn:    'Your turn',
    waitingFor:  '{player}\'s turn',
    knocked:     '{player} knocked!',
    lastTurn:    'Last turn!',
    selectCard:  'Select a card',
    score:       'Score',
    pass:        'Pass',
  );
}
