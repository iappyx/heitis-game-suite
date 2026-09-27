import 'app_localizations.dart';

class StringsLofthockey {
  final String gameName;
  final String gameDesc;
  final String rules;
  final String goal;
  final String firstTo7;

  const StringsLofthockey({
    required this.gameName,
    required this.gameDesc,
    required this.rules,
    required this.goal,
    required this.firstTo7,
  });

  factory StringsLofthockey.of(AppLang l) => switch (l) {
    AppLang.fy => StringsLofthockey.fy(),
    AppLang.nl => StringsLofthockey.nl(),
    AppLang.en => StringsLofthockey.en(),
  };

  factory StringsLofthockey.fy() => const StringsLofthockey(
    gameName:  'Lofthockey',
    gameDesc:  'Skoar doelpunten!',
    rules:     'Sleep dyn mallet oer it fjild om de puck yn it doel fan dyn tsjinstanner te slaan. '
               'Elke spiler kin allinnich op syn eigen helte bewege. '
               'De earste mei 7 doelpunten wint!',
    goal:      'Doelpunt!',
    firstTo7:  'Earste mei 7 wint',
  );

  factory StringsLofthockey.nl() => const StringsLofthockey(
    gameName:  'Airhockey',
    gameDesc:  'Scoor doelpunten!',
    rules:     'Sleep je mallet over het veld om de puck in het doel van je tegenstander te slaan. '
               'Elke speler kan alleen op zijn eigen helft bewegen. '
               'De eerste met 7 doelpunten wint!',
    goal:      'Doelpunt!',
    firstTo7:  'Eerste met 7 wint',
  );

  factory StringsLofthockey.en() => const StringsLofthockey(
    gameName:  'Air Hockey',
    gameDesc:  'Score goals!',
    rules:     'Drag your mallet across the field to hit the puck into your opponent\'s goal. '
               'Each player can only move on their own half. '
               'First to 7 goals wins!',
    goal:      'Goal!',
    firstTo7:  'First to 7 wins',
  );
}
