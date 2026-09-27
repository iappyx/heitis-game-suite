import 'app_localizations.dart';

class StringsWurdsikerij {
  final String gameName;
  final String gameDesc;
  final String rules;
  final String wordsFound;
  final String timeLabel;
  final String allFound;
  final String youWin;
  final String youLose;
  final String tapFirst;
  final String tapLast;
  final String notAWord;

  const StringsWurdsikerij({
    required this.gameName,
    required this.gameDesc,
    required this.rules,
    required this.wordsFound,
    required this.timeLabel,
    required this.allFound,
    required this.youWin,
    required this.youLose,
    required this.tapFirst,
    required this.tapLast,
    required this.notAWord,
  });

  factory StringsWurdsikerij.of(AppLang l) => switch (l) {
    AppLang.fy => StringsWurdsikerij.fy(),
    AppLang.nl => StringsWurdsikerij.nl(),
    AppLang.en => StringsWurdsikerij.en(),
  };

  factory StringsWurdsikerij.fy() => const StringsWurdsikerij(
    gameName:   'Wurdsikerij',
    gameDesc:   'Fyn wurden yn it roaster',
    rules:      'Fyn alle ferburgen wurden yn it roaster. Tik op de earste letter en dan op de lêste letter fan in wurd. Wurden steane horizontaal, fertikaal of skean. Op \'swier\' kinne se ek efterstebek stean. De spiler dy\'t de measte wurden fynt, wint!',
    wordsFound: 'wurden fûn',
    timeLabel:  'Tiid',
    allFound:   'Alle wurden fûn!',
    youWin:     'Do hast wûn!',
    youLose:    'Do hast ferlern.',
    tapFirst:   'Tik op de earste letter',
    tapLast:    'Tik op de lêste letter',
    notAWord:   'Gjin ferstopt wurd',
  );

  factory StringsWurdsikerij.nl() => const StringsWurdsikerij(
    gameName:   'Woordzoeker',
    gameDesc:   'Vind woorden in het rooster',
    rules:      'Vind alle verborgen woorden in het rooster. Tik op de eerste letter en dan op de laatste letter van een woord. Woorden staan horizontaal, verticaal of schuin. Op \'moeilijk\' kunnen ze ook achterstevoren staan. De speler die de meeste woorden vindt, wint!',
    wordsFound: 'woorden gevonden',
    timeLabel:  'Tijd',
    allFound:   'Alle woorden gevonden!',
    youWin:     'Je hebt gewonnen!',
    youLose:    'Je hebt verloren.',
    tapFirst:   'Tik op de eerste letter',
    tapLast:    'Tik op de laatste letter',
    notAWord:   'Geen verborgen woord',
  );

  factory StringsWurdsikerij.en() => const StringsWurdsikerij(
    gameName:   'Word Search',
    gameDesc:   'Find words in the grid',
    rules:      'Find all hidden words in the grid. Tap the first letter, then tap the last letter of a word. Words run horizontally, vertically or diagonally. On \'hard\' they can also run backwards. The player who finds the most words wins!',
    wordsFound: 'words found',
    timeLabel:  'Time',
    allFound:   'All words found!',
    youWin:     'You win!',
    youLose:    'You lose.',
    tapFirst:   'Tap the first letter',
    tapLast:    'Tap the last letter',
    notAWord:   'Not a hidden word',
  );
}
