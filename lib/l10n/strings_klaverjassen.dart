import 'app_localizations.dart';

class StringsKlaverjassen {
  final String gameName;
  final String gameDesc;
  final String yourTurn;
  final String opponentTurn;
  final String trump;         // "Trump: {suit}"
  final String chooseTrump;   // "Choose trump suit"
  final String pass;          // "Pass"
  final String play;          // "Play"
  final String nat;           // "NAT! {team} gets 0"
  final String pit;           // "PIT! +100 bonus!"
  final String roem;          // "Roem: {n} pts"
  final String roundResult;   // "Round result"
  final String teamUs;        // "Us"
  final String teamThem;      // "Them"
  final String suitHearts;
  final String suitDiamonds;
  final String suitClubs;
  final String suitSpades;
  final String trick;         // "Trick {n}/8"
  final String yourTeam;      // "Your team"
  final String passing;       // "{player} passes"
  final String playing;       // "{player} plays with {suit}"
  final String toWin;         // "Target: {n}+"
  final String mustPlay;      // "Must play — no one else went"
  final String matchOver;
  final String boompje;       // "16-round match"
  final String rules;
  final String cpuPlayer;     // "CPU {n}"
  final String lastTrick;     // "Last trick"

  const StringsKlaverjassen({
    required this.gameName, required this.gameDesc,
    required this.yourTurn, required this.opponentTurn,
    required this.trump, required this.chooseTrump, required this.pass, required this.play,
    required this.nat, required this.pit, required this.roem, required this.roundResult,
    required this.teamUs, required this.teamThem,
    required this.suitHearts, required this.suitDiamonds,
    required this.suitClubs, required this.suitSpades,
    required this.trick, required this.yourTeam,
    required this.passing, required this.playing, required this.toWin,
    required this.mustPlay, required this.matchOver, required this.boompje,
    required this.rules, required this.cpuPlayer, required this.lastTrick,
  });

  factory StringsKlaverjassen.of(AppLang l) => switch (l) {
    AppLang.fy => StringsKlaverjassen.fy(),
    AppLang.nl => StringsKlaverjassen.nl(),
    AppLang.en => StringsKlaverjassen.en(),
  };

  factory StringsKlaverjassen.fy() => const StringsKlaverjassen(
    gameName: 'Klaverjassen',
    gameDesc: '4-spiler kaartspul — 2 tsjin 2',
    yourTurn: 'Dyn beurt',
    opponentTurn: '{player} is oan bar',
    trump: 'Troef: {suit}',
    chooseTrump: 'Kies troefkleur',
    pass: 'Pas',
    play: 'Spylje',
    nat: 'NAT! {team} krijt 0 punten',
    pit: 'PIT! +100 bonus!',
    roem: 'Roem: {n} pts',
    roundResult: 'Rûnte útslach',
    teamUs: 'Wy',
    teamThem: 'Sy',
    suitHearts: 'Harten',
    suitDiamonds: 'Ruten',
    suitClubs: 'Klaveren',
    suitSpades: 'Skoppen',
    trick: 'Slag {n}/8',
    yourTeam: 'Dyn team',
    passing: '{player} past',
    playing: '{player} spilet mei {suit}',
    toWin: 'Doel: {n}+',
    mustPlay: 'Moat spylje — nimmen oars gie',
    matchOver: 'Wedstriid oer!',
    boompje: '16-rûnte wedstriid',
    rules: '4 spilers yn 2 teams. 8 tegels elk. 8 slagen per rûnte. Troefkaarten hawwe in aparte rangoarder (B, 9, A, 10, K, V, 8, 7). Beamkje = 16 rondes.',
    cpuPlayer: 'CPU {n}',
    lastTrick: 'Lêste slach',
  );

  factory StringsKlaverjassen.nl() => const StringsKlaverjassen(
    gameName: 'Klaverjassen',
    gameDesc: '4-speler kaartspel — 2 tegen 2',
    yourTurn: 'Jouw beurt',
    opponentTurn: '{player} is aan de beurt',
    trump: 'Troef: {suit}',
    chooseTrump: 'Kies troefkleur',
    pass: 'Pas',
    play: 'Speel',
    nat: 'NAT! {team} krijgt 0 punten',
    pit: 'PIT! +100 bonus!',
    roem: 'Roem: {n} pts',
    roundResult: 'Ronde uitslag',
    teamUs: 'Wij',
    teamThem: 'Zij',
    suitHearts: 'Harten',
    suitDiamonds: 'Ruiten',
    suitClubs: 'Klaveren',
    suitSpades: 'Schoppen',
    trick: 'Slag {n}/8',
    yourTeam: 'Jouw team',
    passing: '{player} past',
    playing: '{player} speelt met {suit}',
    toWin: 'Doel: {n}+',
    mustPlay: 'Moet spelen — niemand anders ging',
    matchOver: 'Wedstrijd afgelopen!',
    boompje: '16-ronde wedstrijd',
    rules: '4 spelers in 2 teams. 8 kaarten per speler. 8 slagen per ronde. Troefkaarten hebben eigen rangorde (B, 9, A, 10, K, V, 8, 7). Boompje = 16 rondes.',
    cpuPlayer: 'CPU {n}',
    lastTrick: 'Laatste slag',
  );

  factory StringsKlaverjassen.en() => const StringsKlaverjassen(
    gameName: 'Klaverjassen',
    gameDesc: '4-player card game — 2 vs 2',
    yourTurn: 'Your turn',
    opponentTurn: "{player}'s turn",
    trump: 'Trump: {suit}',
    chooseTrump: 'Choose trump suit',
    pass: 'Pass',
    play: 'Play',
    nat: 'NAT! {team} gets 0 points',
    pit: 'PIT! +100 bonus!',
    roem: 'Roem: {n} pts',
    roundResult: 'Round result',
    teamUs: 'Us',
    teamThem: 'Them',
    suitHearts: 'Hearts',
    suitDiamonds: 'Diamonds',
    suitClubs: 'Clubs',
    suitSpades: 'Spades',
    trick: 'Trick {n}/8',
    yourTeam: 'Your team',
    passing: '{player} passes',
    playing: '{player} plays with {suit}',
    toWin: 'Target: {n}+',
    mustPlay: 'Must play — no one else went',
    matchOver: 'Match over!',
    boompje: '16-round match',
    rules: '4 players in 2 teams (opposite seats). 8 cards each. 8 tricks per round. Trump cards have special rank order (J, 9, A, 10, K, Q, 8, 7). Full match = 16 rounds.',
    cpuPlayer: 'CPU {n}',
    lastTrick: 'Last trick',
  );
}
