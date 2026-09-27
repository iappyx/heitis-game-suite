import 'app_localizations.dart';

class StringsDomino {
  final String gameName;
  final String gameDesc;
  final String yourTurn;
  final String opponentTurn;
  final String draw;        // "Draw tile"
  final String pass;        // "Pass"
  final String cannotPlay;  // "Cannot play — drawing tile…"
  final String passed;      // "{player} passed"
  final String drew;        // "{player} drew a tile"
  final String blocked;     // "Game blocked — no moves possible"
  final String roundOver;   // "Round over!"
  final String matchOver;   // "Match over!"
  final String tilesLeft;   // "{n} tiles left"
  final String yourScore;
  final String rules;
  final String leftSide;     // "◀ Left"
  final String rightSide;    // "Right ▶"

  const StringsDomino({
    required this.gameName, required this.gameDesc,
    required this.yourTurn, required this.opponentTurn,
    required this.draw, required this.pass,
    required this.cannotPlay, required this.passed, required this.drew,
    required this.blocked, required this.roundOver, required this.matchOver,
    required this.tilesLeft, required this.yourScore, required this.rules,
    required this.leftSide, required this.rightSide,
  });

  factory StringsDomino.of(AppLang l) => switch (l) {
    AppLang.fy => StringsDomino.fy(),
    AppLang.nl => StringsDomino.nl(),
    AppLang.en => StringsDomino.en(),
  };

  factory StringsDomino.fy() => const StringsDomino(
    gameName: 'Domino',
    gameDesc: 'Leit al dyn tegels neer!',
    yourTurn: 'Dyn beurt',
    opponentTurn: '{player} is oan bar',
    draw: 'Tegeltsje pakke',
    pass: 'Pas',
    cannotPlay: 'Kinst net spylje — tegeltsje pakken…',
    passed: '{player} past',
    drew: '{player} pakt in tegeltsje',
    blocked: 'Spul blokkeare — gjin setten mooglik',
    roundOver: 'Rûnte oer!',
    matchOver: 'Spul oer!',
    tilesLeft: '{n} tegels oer',
    yourScore: 'Dyn punten',
    rules: 'Elke spiler kriget 7 tegels. Set in tegeltsje del dat past by in iepen ein. Kinst net, pak dan in tegeltsje. Wa earst gjin tegels mear hat wint de rûnte. Punten = wearde fan oerbleaune tegels fan de tsjinstanner.',
    leftSide: '◀ Links',
    rightSide: 'Rjochts ▶',
  );

  factory StringsDomino.nl() => const StringsDomino(
    gameName: 'Domino',
    gameDesc: 'Leg al je stenen neer!',
    yourTurn: 'Jouw beurt',
    opponentTurn: '{player} is aan de beurt',
    draw: 'Steen trekken',
    pass: 'Pas',
    cannotPlay: 'Kan niet spelen — steen trekken…',
    passed: '{player} past',
    drew: '{player} trekt een steen',
    blocked: 'Spel geblokkeerd — geen zetten mogelijk',
    roundOver: 'Ronde afgelopen!',
    matchOver: 'Spel afgelopen!',
    tilesLeft: '{n} stenen over',
    yourScore: 'Jouw punten',
    rules: 'Elke speler krijgt 7 stenen. Leg een steen die aansluit op een open einde. Kun je niet, trek dan een steen. Wie als eerste geen stenen meer heeft wint de ronde. Punten = waarde van overgebleven stenen van de tegenstander.',
    leftSide: '◀ Links',
    rightSide: 'Rechts ▶',
  );

  factory StringsDomino.en() => const StringsDomino(
    gameName: 'Dominoes',
    gameDesc: 'Play all your tiles!',
    yourTurn: 'Your turn',
    opponentTurn: "{player}'s turn",
    draw: 'Draw tile',
    pass: 'Pass',
    cannotPlay: "Can't play — drawing tile…",
    passed: '{player} passed',
    drew: '{player} drew a tile',
    blocked: 'Game blocked — no moves possible',
    roundOver: 'Round over!',
    matchOver: 'Game over!',
    tilesLeft: '{n} tiles left',
    yourScore: 'Your score',
    rules: 'Each player gets 7 tiles. Place a tile matching an open end. If you cannot, draw from the boneyard. First to empty their hand wins the round. Points = value of opponent\'s remaining tiles.',
    leftSide: '◀ Left',
    rightSide: 'Right ▶',
  );
}
