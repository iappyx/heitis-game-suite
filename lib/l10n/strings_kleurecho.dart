import 'app_localizations.dart';

class StringsKleurEcho {
  final String gameName;
  final String gameDesc;
  final String watch;
  final String yourTurn;
  final String race;
  final String wrong;
  final String roundLabel;
  final String rules;

  const StringsKleurEcho({
    required this.gameName,
    required this.gameDesc,
    required this.watch,
    required this.yourTurn,
    required this.race,
    required this.wrong,
    required this.roundLabel,
    required this.rules,
  });

  factory StringsKleurEcho.of(AppLang l) => switch (l) {
    AppLang.fy => StringsKleurEcho.fy(),
    AppLang.nl => StringsKleurEcho.nl(),
    AppLang.en => StringsKleurEcho.en(),
  };

  factory StringsKleurEcho.fy() => const StringsKleurEcho(
    gameName:   'Kleur-echo',
    gameDesc:   'Snelste ûnthâld wint',
    watch:      'Sjoch goed!',
    yourTurn:   'Dyn beurt — tik it patroan!',
    race:       'Race! Earste korrekte rige wint',
    wrong:      'Ferkeard! {player} skoart in punt',
    roundLabel: 'Rûnte {n}',
    rules:             'Sjoch it kleurpatroan en tik it dan werom yn deselde folchoarder. Elke rûnte wurdt de rige langer. Solo: hoe fier kinst komme? Tsjin elkoar: earste dy\'t it ferkeard docht, jout de tsjinstanner in punt.',
  );
  factory StringsKleurEcho.nl() => const StringsKleurEcho(
    gameName:   'Kleurecho',
    gameDesc:   'Snelste geheugen wint',
    watch:      'Kijk goed!',
    yourTurn:   'Jouw beurt — tik het patroon!',
    race:       'Race! Eerste correcte reeks wint',
    wrong:      'Fout! {player} scoort een punt',
    roundLabel: 'Ronde {n}',
    rules:             'Kijk het kleurenpatroon en tik het dan terug in dezelfde volgorde. Elke ronde wordt de reeks langer. Solo: hoe ver kom jij? Tegen elkaar: eerste die het fout doet, geeft de tegenstander een punt.',
  );
  factory StringsKleurEcho.en() => const StringsKleurEcho(
    gameName:   'Color Echo',
    gameDesc:   'Fastest memory wins',
    watch:      'Watch carefully!',
    yourTurn:   'Your turn — tap the pattern!',
    race:       'Race! First correct sequence wins',
    wrong:      'Wrong! {player} scores a point',
    roundLabel: 'Round {n}',
    rules:             'Watch the colour pattern, then tap it back in the same order. Each round the sequence gets longer. Solo: how far can you go? Versus: first to make a mistake gives the opponent a point.',
  );
}
