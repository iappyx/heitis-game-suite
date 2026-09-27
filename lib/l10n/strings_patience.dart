import 'app_localizations.dart';

class StringsPatience {
  final String gameName;
  final String gameDesc;
  final String rules;
  final String moves;
  final String time;
  final String youWin;
  final String newGame;
  final String stock;
  final String autoCompleting;

  const StringsPatience({
    required this.gameName,
    required this.gameDesc,
    required this.rules,
    required this.moves,
    required this.time,
    required this.youWin,
    required this.newGame,
    required this.stock,
    required this.autoCompleting,
  });

  factory StringsPatience.of(AppLang l) => switch (l) {
    AppLang.fy => StringsPatience.fy(),
    AppLang.nl => StringsPatience.nl(),
    AppLang.en => StringsPatience.en(),
  };

  factory StringsPatience.fy() => const StringsPatience(
    gameName:       'Patience',
    gameDesc:       'Klassyk kaartspul',
    rules:          'Ferpleats kaarten tusken 7 kolommen en bou 4 stapels op fan Aas oant Kening per kleur. Kolommen bouwe ôf fan Kening nei Aas yn wikselende kleuren (read/swart). Tik op de stok om in kaart te lûken. Tik op in kaart om te selektearjen, tik dan op de bestimming om te ferpleatsen.',
    moves:          'Setten',
    time:           'Tiid',
    youWin:         'Do hast wûn!',
    newGame:        'Nij spul',
    stock:          'Stok',
    autoCompleting: 'Auto-oanfolje...',
  );

  factory StringsPatience.nl() => const StringsPatience(
    gameName:       'Patience',
    gameDesc:       'Klassiek kaartspel',
    rules:          'Verplaats kaarten tussen 7 kolommen en bouw 4 stapels op van Aas tot Koning per kleur. Kolommen bouwen af van Koning naar Aas in afwisselende kleuren (rood/zwart). Tik op de stok om een kaart te trekken. Tik op een kaart om te selecteren, tik dan op de bestemming om te verplaatsen.',
    moves:          'Zetten',
    time:           'Tijd',
    youWin:         'Je hebt gewonnen!',
    newGame:        'Nieuw spel',
    stock:          'Stok',
    autoCompleting: 'Auto-aanvullen...',
  );

  factory StringsPatience.en() => const StringsPatience(
    gameName:       'Solitaire',
    gameDesc:       'Classic card game',
    rules:          'Move cards between 7 tableau columns and build 4 foundation piles from Ace to King per suit. Tableau columns build down from King to Ace in alternating colours (red/black). Tap the stock to draw a card. Tap a card to select it, then tap a destination to move it.',
    moves:          'Moves',
    time:           'Time',
    youWin:         'You win!',
    newGame:        'New game',
    stock:          'Stock',
    autoCompleting: 'Auto-completing...',
  );
}
