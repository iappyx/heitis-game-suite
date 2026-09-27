import 'app_localizations.dart';

class StringsAaisykje {
  final String gameName;
  final String gameDesc;
  final String level;
  final String eggs;
  final String score;
  final String time;
  final String combo;
  final String lives;
  final String levelComplete;
  final String goalReached;
  final String timeBonus;
  final String gameOver;
  final String youWon;
  final String allLevels;
  final String totalScore;
  final String collect;         // 'Collect {n} eggs'
  final String hatchIn;         // 'Hatch in {n}s'
  final String guards;          // '{n} guard(s)'
  final String lapwings;        // '{n} lapwing(s)'
  final String hatched;         // 'Hatched! -{n}'
  final String decoy;           // 'Wrong egg! -{n}'
  final String bonusLife;       // '+1 life!'
  final String maxLives;        // 'Max lives: +100pts'
  final String timePlus;        // '+10s'
  final String powerGhost;
  final String powerShield;
  final String powerSpeed;
  final String powerMagnet;
  final String powerFreeze;
  final String newBest;
  final String rules;

  const StringsAaisykje({
    required this.gameName,
    required this.gameDesc,
    required this.level,
    required this.eggs,
    required this.score,
    required this.time,
    required this.combo,
    required this.lives,
    required this.levelComplete,
    required this.goalReached,
    required this.timeBonus,
    required this.gameOver,
    required this.youWon,
    required this.allLevels,
    required this.totalScore,
    required this.collect,
    required this.hatchIn,
    required this.guards,
    required this.lapwings,
    required this.hatched,
    required this.decoy,
    required this.bonusLife,
    required this.maxLives,
    required this.timePlus,
    required this.powerGhost,
    required this.powerShield,
    required this.powerSpeed,
    required this.powerMagnet,
    required this.powerFreeze,
    required this.newBest,
    required this.rules,
  });

  String collectN(int n)    => collect.replaceAll('{n}', '$n');
  String hatchInN(int n)    => hatchIn.replaceAll('{n}', '$n');
  String guardsN(int n)     => guards.replaceAll('{n}', '$n');
  String lapwingsN(int n)   => lapwings.replaceAll('{n}', '$n');
  String hatchedN(int n)    => hatched.replaceAll('{n}', '$n');
  String decoyN(int n)      => decoy.replaceAll('{n}', '$n');
  String goalReachedN(int s) => goalReached.replaceAll('{s}', '$s');

  factory StringsAaisykje.of(AppLang l) => switch (l) {
    AppLang.fy => StringsAaisykje.fy(),
    AppLang.nl => StringsAaisykje.nl(),
    AppLang.en => StringsAaisykje.en(),
  };

  factory StringsAaisykje.fy() => const StringsAaisykje(
    gameName:      'Aaisykje',
    gameDesc:      'Sykje ljipaaien foardat se útkomme!',
    level:         'Nivo {n}',
    eggs:          'Aaien: {n}/{t}',
    score:         'Punten',
    time:          'Tiid',
    combo:         'Combo',
    lives:         'Libbens',
    levelComplete: 'Nivo foltôge!',
    goalReached:   'Doel helle! +{s}s bonus!',
    timeBonus:     'TIID BONUS',
    gameOver:      'GAME OVER',
    youWon:        'WÛN!',
    allLevels:     'Alle 20 nivo\'s helle!',
    totalScore:    'Totale punten',
    collect:       '{n} aaien sammelje',
    hatchIn:       'Útkomme yn {n}s',
    guards:        '{n} boswachter(s)',
    lapwings:      '{n} ljip(en)',
    hatched:       'Útkomme! -{n}',
    decoy:         'Ferkeard aai! -{n}',
    bonusLife:     '+1 libben!',
    maxLives:      'Max libbens: +100pts',
    timePlus:      '+10s',
    powerGhost:    '👻 Geast — ûnsichtber!',
    powerShield:   '🛡️ Skyld — unberikber!',
    powerSpeed:    '⚡ Rappe — 2x flugger!',
    powerMagnet:   '🧲 Magneet — lûkt aaien!',
    powerFreeze:   '❄️ Befriest — stopje boswachters!',
    newBest:       '🌟 Nij rekôr!',
    rules:         'Fersammelje alle ljipaaien foardat se útkomme. '
                   'Mij de boswachters. '
                   'Surprise-aaien jouwe bysûndere krêften. '
                   'As alle aaien samle binne, begjint de tiidbonus!',
  );

  factory StringsAaisykje.nl() => const StringsAaisykje(
    gameName:      'Aaisykje',
    gameDesc:      'Zoek kievitseieren voor ze uitkomen!',
    level:         'Level {n}',
    eggs:          'Eieren: {n}/{t}',
    score:         'Punten',
    time:          'Tijd',
    combo:         'Combo',
    lives:         'Levens',
    levelComplete: 'Level voltooid!',
    goalReached:   'Doel gehaald! +{s}s bonus!',
    timeBonus:     'TIJDBONUS',
    gameOver:      'GAME OVER',
    youWon:        'GEWONNEN!',
    allLevels:     'Alle 20 levels gehaald!',
    totalScore:    'Totale punten',
    collect:       '{n} eieren verzamelen',
    hatchIn:       'Uitkomen in {n}s',
    guards:        '{n} boswachter(s)',
    lapwings:      '{n} kievit(en)',
    hatched:       'Uitgekomen! -{n}',
    decoy:         'Verkeerd ei! -{n}',
    bonusLife:     '+1 leven!',
    maxLives:      'Max levens: +100pts',
    timePlus:      '+10s',
    powerGhost:    '👻 Geest — onzichtbaar!',
    powerShield:   '🛡️ Schild — onaantastbaar!',
    powerSpeed:    '⚡ Snelheid — 2x sneller!',
    powerMagnet:   '🧲 Magneet — trekt eieren!',
    powerFreeze:   '❄️ Bevriest — stop boswachters!',
    newBest:       '🌟 Nieuw record!',
    rules:         'Verzamel alle kievitseieren voor ze uitkomen. '
                   'Vermijd de boswachters. '
                   'Surprise-eieren geven speciale krachten. '
                   'Als alle eieren zijn verzameld, begint de tijdbonus!',
  );

  factory StringsAaisykje.en() => const StringsAaisykje(
    gameName:      'Aaisykje',
    gameDesc:      'Collect lapwing eggs before they hatch!',
    level:         'Level {n}',
    eggs:          'Eggs: {n}/{t}',
    score:         'Score',
    time:          'Time',
    combo:         'Combo',
    lives:         'Lives',
    levelComplete: 'Level complete!',
    goalReached:   'Goal reached! +{s}s bonus!',
    timeBonus:     'TIME BONUS',
    gameOver:      'GAME OVER',
    youWon:        'YOU WIN!',
    allLevels:     'All 20 levels completed!',
    totalScore:    'Total score',
    collect:       'Collect {n} eggs',
    hatchIn:       'Hatch in {n}s',
    guards:        '{n} guard(s)',
    lapwings:      '{n} lapwing(s)',
    hatched:       'Hatched! -{n}',
    decoy:         'Wrong egg! -{n}',
    bonusLife:     '+1 life!',
    maxLives:      'Max lives: +100pts',
    timePlus:      '+10s',
    powerGhost:    '👻 Ghost — invisible!',
    powerShield:   '🛡️ Shield — invulnerable!',
    powerSpeed:    '⚡ Speed — 2x faster!',
    powerMagnet:   '🧲 Magnet — pulls eggs!',
    powerFreeze:   '❄️ Freeze — stop guards!',
    newBest:       '🌟 New record!',
    rules:         'Collect all lapwing eggs before they hatch. '
                   'Avoid the gamekeepers (boswachters). '
                   'Surprise eggs grant special powers. '
                   'Once all eggs are collected, a time bonus begins!',
  );
}
