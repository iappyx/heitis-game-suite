import 'app_localizations.dart';

class StringsSudokuDuel {
  final String gameName;
  final String gameDesc;
  final String modeCoopTitle;
  final String modeCoopDesc;
  final String modeRaceTitle;
  final String modeRaceDesc;
  final String modeTerritoryTitle;
  final String modeTerritoryDesc;
  final String chooseMode;
  final String yourTurn;
  final String cellTaken;
  final String wrong;
  final String solved;
  final String cells;
  final String rules;

  const StringsSudokuDuel({
    required this.gameName,
    required this.gameDesc,
    required this.modeCoopTitle,
    required this.modeCoopDesc,
    required this.modeRaceTitle,
    required this.modeRaceDesc,
    required this.modeTerritoryTitle,
    required this.modeTerritoryDesc,
    required this.chooseMode,
    required this.yourTurn,
    required this.cellTaken,
    required this.wrong,
    required this.solved,
    required this.cells,
    required this.rules,
  });

  factory StringsSudokuDuel.of(AppLang l) => switch (l) {
    AppLang.fy => StringsSudokuDuel.fy(),
    AppLang.nl => StringsSudokuDuel.nl(),
    AppLang.en => StringsSudokuDuel.en(),
  };

  factory StringsSudokuDuel.fy() => const StringsSudokuDuel(
    gameName:          'Sudoku Duel',
    gameDesc:          'Trije manieren om te spyljen',
    modeCoopTitle:     'Gearwurking',
    modeCoopDesc:      'Lôs it Sudoku tegearre op',
    modeRaceTitle:     'Race',
    modeRaceDesc:      'Measte korrekte sellen wint',
    modeTerritoryTitle:'Territoarium',
    modeTerritoryDesc: 'Measte sellen yn dyn kleur wint',
    chooseMode:        'Kies in modus',
    yourTurn:          'Dyn beurt',
    cellTaken:         'Al ynfolt',
    wrong:             'Net goed',
    solved:            'Oplost!',
    cells:             'sellen',
    rules:             'Folje it 9×9 roaster yn sadat elk rij, kolom en 3×3 blok de sifers 1–9 ien kear befettet. Solo: lôs it roaster op. Gearwurking: meitsje it tegearre. Race: meast korrekte sellen wint.',
  );
  factory StringsSudokuDuel.nl() => const StringsSudokuDuel(
    gameName:          'Sudoku Duel',
    gameDesc:          'Drie manieren om te spelen',
    modeCoopTitle:     'Samenwerking',
    modeCoopDesc:      'Los de Sudoku samen op',
    modeRaceTitle:     'Race',
    modeRaceDesc:      'Meeste correcte cellen wint',
    modeTerritoryTitle:'Territorium',
    modeTerritoryDesc: 'Meeste cellen in jouw kleur wint',
    chooseMode:        'Kies een modus',
    yourTurn:          'Jouw beurt',
    cellTaken:         'Al ingevuld',
    wrong:             'Niet goed',
    solved:            'Opgelost!',
    cells:             'cellen',
    rules:             'Vul het 9×9 raster in zodat elke rij, kolom en 3×3 blok de cijfers 1–9 eenmaal bevat. Solo: los het raster op. Samenwerking: maak het samen. Race: meeste correcte cellen wint.',
  );
  factory StringsSudokuDuel.en() => const StringsSudokuDuel(
    gameName:          'Sudoku Duel',
    gameDesc:          'Three ways to play',
    modeCoopTitle:     'Co-op',
    modeCoopDesc:      'Solve the Sudoku together',
    modeRaceTitle:     'Race',
    modeRaceDesc:      'Most correct cells wins',
    modeTerritoryTitle:'Territory',
    modeTerritoryDesc: 'Most cells in your colour wins',
    chooseMode:        'Choose a mode',
    yourTurn:          'Your turn',
    cellTaken:         'Already filled',
    wrong:             'Not correct',
    solved:            'Solved!',
    cells:             'cells',
    rules:             'Fill the 9×9 grid so every row, column and 3×3 block contains the digits 1–9 once. Solo: solve the grid. Co-op: complete it together. Race: most correct cells wins.',
  );
}
