import 'app_localizations.dart';

class StringsBoppeslach {
  final String gameName;
  final String gameDesc;
  final String sectionHdrUpper;
  final String sectionHdrLower;
  final String rollsLeft;
  final String rollBtn;
  final String rollLeft;
  final String bonus;
  final String total;
  final String topScore;
  final String zeroFor;
  final String plusFor;
  final String mustRollFirst;
  final String yourTurn;
  final String catOnes;
  final String catTwos;
  final String catThrees;
  final String catFours;
  final String catFives;
  final String catSixes;
  final String catThreeOfKind;
  final String catFourOfKind;
  final String catFullHouse;
  final String catSmStraight;
  final String catLgStraight;
  final String catChance;
  final String catTopScore;
  final String tapToHold;
  final String waitingOpponent;
  final String chooseCategory;
  final String rollBtnShort;
  final String ptsUnit;
  final String rules;

  const StringsBoppeslach({
    required this.gameName,
    required this.gameDesc,
    required this.sectionHdrUpper,
    required this.sectionHdrLower,
    required this.rollsLeft,
    required this.rollBtn,
    required this.rollLeft,
    required this.bonus,
    required this.total,
    required this.topScore,
    required this.zeroFor,
    required this.plusFor,
    required this.mustRollFirst,
    required this.yourTurn,
    required this.catOnes,
    required this.catTwos,
    required this.catThrees,
    required this.catFours,
    required this.catFives,
    required this.catSixes,
    required this.catThreeOfKind,
    required this.catFourOfKind,
    required this.catFullHouse,
    required this.catSmStraight,
    required this.catLgStraight,
    required this.catChance,
    required this.catTopScore,
    required this.tapToHold,
    required this.waitingOpponent,
    required this.chooseCategory,
    required this.rollBtnShort,
    required this.ptsUnit,
    required this.rules,
  });

  factory StringsBoppeslach.of(AppLang l) => switch (l) {
    AppLang.fy => StringsBoppeslach.fy(),
    AppLang.nl => StringsBoppeslach.nl(),
    AppLang.en => StringsBoppeslach.en(),
  };

  factory StringsBoppeslach.fy() => const StringsBoppeslach(
    gameName:        'Boppeslach',
    gameDesc:        '5-stiften skoardzjen',
    sectionHdrUpper: 'BOPPESTE',
    sectionHdrLower: 'ÛNDERSTE',
    rollsLeft:       '{n} worp(en) oer',
    rollBtn:         'Goaie!',
    rollLeft:        '{n} goaibeurten oer',
    bonus:           'Bonus (+35)',
    total:           'TOTAAL',
    topScore:        'Topskoare! {n} punten!',
    zeroFor:         '0 punten foar {cat}',
    plusFor:         '+{n} foar {cat}!',
    mustRollFirst:   'Earst goaie!',
    yourTurn:        'Beurt fan {player}',
    catOnes:         'Ientsjes',
    catTwos:         'Twatsjes',
    catThrees:       'Trijes',
    catFours:        'Fjouwers',
    catFives:        'Fiven',
    catSixes:        'Sessen',
    catThreeOfKind:  '3 fan in soart',
    catFourOfKind:   '4 fan in soart',
    catFullHouse:    'Full House',
    catSmStraight:   'Lytse Rige',
    catLgStraight:   'Grutte Rige',
    catChance:       'Kâns',
    catTopScore:     'Top Score',
    tapToHold:       'Tikje op dobbels om te bewarjen',
    waitingOpponent: 'Wachtsje op tsjinstanner…',
    chooseCategory:  'Kies in kategory om te skoardzjen!',
    rollBtnShort:    'Goaie!',
    ptsUnit:         'ptn',
    rules:             'Goai de dobbelstiennen en skriuw de skoar yn dyn fjilden yn. Elts fjild kin mar ien kear ynfolt wurde. Heechste totaal wint!',
  );

  factory StringsBoppeslach.nl() => const StringsBoppeslach(
    gameName:        'Dobbelstenen',
    gameDesc:        '5-dobbelstenen scoren',
    sectionHdrUpper: 'BOVEN',
    sectionHdrLower: 'ONDER',
    rollsLeft:       '{n} worp(en) over',
    rollBtn:         'Gooi!',
    rollLeft:        '{n} worpen over',
    bonus:           'Bonus (+35)',
    total:           'TOTAAL',
    topScore:        'Topschore! {n} punten!',
    zeroFor:         '0 punten voor {cat}',
    plusFor:         '+{n} voor {cat}!',
    mustRollFirst:   'Eerst gooien!',
    yourTurn:        'Beurt van {player}',
    catOnes:         'Enen',
    catTwos:         'Tweeën',
    catThrees:       'Drieën',
    catFours:        'Vieren',
    catFives:        'Vijven',
    catSixes:        'Zessen',
    catThreeOfKind:  '3 van een soort',
    catFourOfKind:   '4 van een soort',
    catFullHouse:    'Full House',
    catSmStraight:   'Kleine Straat',
    catLgStraight:   'Grote Straat',
    catChance:       'Kans',
    catTopScore:     'Top Score',
    tapToHold:       'Tik op dobbelstenen om te bewaren',
    waitingOpponent: 'Wachten op tegenstander…',
    chooseCategory:  'Kies een categorie om te scoren!',
    rollBtnShort:    'Gooien!',
    ptsUnit:         'ptn',
    rules:             'Gooi de dobbelstenen en schrijf de score in je vakjes. Elk vakje kan maar één keer worden ingevuld. Hoogste totaal wint!',
  );

  factory StringsBoppeslach.en() => const StringsBoppeslach(
    gameName:        'Dice',
    gameDesc:        '5-dice scoring',
    sectionHdrUpper: 'UPPER',
    sectionHdrLower: 'LOWER',
    rollsLeft:       '{n} rolls left',
    rollBtn:         'Roll!',
    rollLeft:        '{n} rolls left',
    bonus:           'Bonus (+35)',
    total:           'TOTAL',
    topScore:        'Top Score! {n} points!',
    zeroFor:         '0 points for {cat}',
    plusFor:         '+{n} for {cat}!',
    mustRollFirst:   'Roll first!',
    yourTurn:        "{player}\'s turn",
    catOnes:         'Ones',
    catTwos:         'Twos',
    catThrees:       'Threes',
    catFours:        'Fours',
    catFives:        'Fives',
    catSixes:        'Sixes',
    catThreeOfKind:  '3 of a Kind',
    catFourOfKind:   '4 of a Kind',
    catFullHouse:    'Full House',
    catSmStraight:   'Sm. Straight',
    catLgStraight:   'Lg. Straight',
    catChance:       'Chance',
    catTopScore:     'Top Score',
    tapToHold:       'Tap dice to hold',
    waitingOpponent: 'Waiting for opponent…',
    chooseCategory:  'Choose a category to score!',
    rollBtnShort:    'Roll!',
    ptsUnit:         'pts',
    rules:             'Roll the dice and fill in your score boxes. Each box can only be filled once. Highest total wins!',
  );
}
