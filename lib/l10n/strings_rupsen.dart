import 'app_localizations.dart';

class StringsRupsen {
  final String gameName;
  final String gameDesc;
  final String rollBtn;          // "Roll!"
  final String rollAgainBtn;     // "Roll Again"
  final String setAsideBtn;      // "SET ASIDE"
  final String claimBtn;         // "✔ Claim {n}"
  final String tapToSetAside;    // "Tap a die to set aside"
  final String isChoosing;       // "{player} is choosing…"
  final String waitingFor;       // "Waiting for {player}…"
  final String bust;             // "Bust!"
  final String gotOne;           // "Got one!"
  final String nextTurn;         // "Next Turn ➜"
  final String scoreLabel;       // "Score: {n}"
  final String tilePool;         // "TILE POOL"
  final String noTiles;          // "no tiles"
  final String noNewFacesBust;   // "No new faces — bust!"
  final String noWormBust;       // "No 🐛 — bust!"
  final String noTileBust;       // "No tile ≤ {n} — bust!"
  final String setAsideMsg;      // "Set aside {count}× {face} (+{pts})"
  final String steals;           // "{player} steals tile {n} from {other}!"
  final String claims;           // "{player} claims tile {n} ({worms}🐛)!"
  final String tilesCount;       // "{n} tiles"

  final String usedFaces;        // "used faces"
  final String yourTurnDice;     // "Your turn"
  final String opponentTurnDice; // "{player}'s turn"
  final String stacksLabel;      // column header for player stacks
  final String rollingLabel;     // "ROLLING" section header
  final String rules;
  const StringsRupsen({
    required this.gameName,
    required this.gameDesc,
    required this.rollBtn,
    required this.rollAgainBtn,
    required this.setAsideBtn,
    required this.claimBtn,
    required this.tapToSetAside,
    required this.isChoosing,
    required this.waitingFor,
    required this.bust,
    required this.gotOne,
    required this.nextTurn,
    required this.scoreLabel,
    required this.tilePool,
    required this.noTiles,
    required this.noNewFacesBust,
    required this.noWormBust,
    required this.noTileBust,
    required this.setAsideMsg,
    required this.steals,
    required this.claims,
    required this.tilesCount,
    required this.usedFaces,
    required this.yourTurnDice,
    required this.opponentTurnDice,
    required this.stacksLabel,
    required this.rollingLabel,
    required this.rules,
  });

  factory StringsRupsen.of(AppLang l) => switch (l) {
    AppLang.fy => StringsRupsen.fy(),
    AppLang.nl => StringsRupsen.nl(),
    AppLang.en => StringsRupsen.en(),
  };

  factory StringsRupsen.fy() => const StringsRupsen(
    gameName:       'Rupsen',
    gameDesc:     'Tiles sammelje',
    rollBtn:        'Goaie!',
    rollAgainBtn:   'Nochris Goaie',
    setAsideBtn:    'OPZIJ',
    claimBtn:       '✔ Nim {n}',
    tapToSetAside:  'Tikje op in dobbel om opzij te lizzen',
    isChoosing:     '{player} is oan it kiezen…',
    waitingFor:     'Wachtsje op {player}…',
    bust:           'Bist!',
    gotOne:         'In!',
    nextTurn:       'Folgjende Beurt ➜',
    scoreLabel:     'Punten: {n}',
    tilePool:       'TEGELPOOL',
    noTiles:        'gjin tegels',
    noNewFacesBust: 'Gjin nije kanten — bist!',
    noWormBust:     'Gjin 🐛 — bist!',
    noTileBust:     'Gjin tegel ≤ {n} — bist!',
    setAsideMsg:    '{count}× {face} opzijlein (+{pts})',
    steals:         '{player} stielt tegel {n} fan {other}!',
    claims:         '{player} kriget tegel {n} ({worms}🐛)!',
    tilesCount:     '{n} tegels',
    usedFaces:      'brûkte kanten',
    yourTurnDice:   'Dyn beurt',
    opponentTurnDice: '{player} is oan bar',
    stacksLabel:    'Stapels',
    rollingLabel:   'GOAIEN',
    rules:             'Goai 8 dobbelstiennen en set weardefolle sjelpen opsy. Doch dit mear kear foar in hegere skoare. Tapje "Eis op" om de rûnte te einigjen. Goaist yn brekke, dan ferliest do alle punten fan dizze rûnte. As alle tegels op binne, wint wa\'t de measte 🐛 hat. By lykspul wint de spiler mei de heechste tegel.',
  );

  factory StringsRupsen.nl() => const StringsRupsen(
    gameName:       'Rupsen',
    gameDesc:     'Tegels verzamelen',
    rollBtn:        'Gooi!',
    rollAgainBtn:   'Opnieuw Gooien',
    setAsideBtn:    'OPZIJ',
    claimBtn:       '✔ Neem {n}',
    tapToSetAside:  'Tik op een dobbelsteen om opzij te leggen',
    isChoosing:     '{player} kiest…',
    waitingFor:     'Wachten op {player}…',
    bust:           'Foetsie!',
    gotOne:         'Gelukt!',
    nextTurn:       'Volgende Beurt ➜',
    scoreLabel:     'Score: {n}',
    tilePool:       'TEGELPOOL',
    noTiles:        'geen tegels',
    noNewFacesBust: 'Geen nieuwe kanten — foetsie!',
    noWormBust:     'Geen 🐛 — foetsie!',
    noTileBust:     'Geen tegel ≤ {n} — foetsie!',
    setAsideMsg:    '{count}× {face} opzijgelegd (+{pts})',
    steals:         '{player} steelt tegel {n} van {other}!',
    claims:         '{player} neemt tegel {n} ({worms}🐛)!',
    tilesCount:     '{n} tegels',
    usedFaces:      'gebruikte kanten',
    yourTurnDice:   'Jouw beurt',
    opponentTurnDice: '{player} is aan de beurt',
    stacksLabel:    'Stapels',
    rollingLabel:   'GOOIEN',
    rules:             'Gooi 8 dobbelstenen en zet waardevolle zijden opzij. Doe dit meerdere keren voor een hogere score. Tik "Opeisen" om de ronde te beëindigen. Gooi je failliet, dan verlies je alle punten van deze ronde. Als alle tegels op zijn, wint wie de meeste 🐛 heeft. Bij gelijkspel wint de speler met de hoogste tegel.',
  );

  factory StringsRupsen.en() => const StringsRupsen(
    gameName:       'Rupsen',
    gameDesc:     'Push-your-luck tiles',
    rollBtn:        'Roll!',
    rollAgainBtn:   'Roll Again',
    setAsideBtn:    'SET ASIDE',
    claimBtn:       '✔ Claim {n}',
    tapToSetAside:  'Tap a die to set aside',
    isChoosing:     '{player} is choosing…',
    waitingFor:     'Waiting for {player}…',
    bust:           'Bust!',
    gotOne:         'Got one!',
    nextTurn:       'Next Turn ➜',
    scoreLabel:     'Score: {n}',
    tilePool:       'TILE POOL',
    noTiles:        'no tiles',
    noNewFacesBust: 'No new faces — bust!',
    noWormBust:     'No 🐛 — bust!',
    noTileBust:     'No tile ≤ {n} — bust!',
    setAsideMsg:    'Set aside {count}× {face} (+{pts})',
    steals:         '{player} steals tile {n} from {other}!',
    claims:         '{player} claims tile {n} ({worms}🐛)!',
    tilesCount:     '{n} tiles',
    usedFaces:      'used faces',
    yourTurnDice:   'Your turn',
    opponentTurnDice: "{player}'s turn",
    stacksLabel:    'Stacks',
    rollingLabel:   'ROLLING',
    rules:             'Roll 8 dice and set aside valuable faces. Do this multiple times for a higher score. Tap "Claim" to end your turn. If you go bust, you lose all points for this round. When all tiles are gone, the most 🐛 wins. On a tie, the player holding the highest tile wins.',
  );
}
