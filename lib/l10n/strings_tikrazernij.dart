import 'app_localizations.dart';

class StringsTikRazernij {
  final String gameName;
  final String gameDesc;
  final String rules;
  final String round;       // "Round {n} of 3"
  final String getReady;
  final String go;
  final String timeLeft;    // "{n}s"
  final String roundOver;
  final String yourScore;   // "Score: {n}"
  final String tapYourColor;
  final String wrongColor;  // "Wrong color! -1"

  const StringsTikRazernij({
    required this.gameName,
    required this.gameDesc,
    required this.rules,
    required this.round,
    required this.getReady,
    required this.go,
    required this.timeLeft,
    required this.roundOver,
    required this.yourScore,
    required this.tapYourColor,
    required this.wrongColor,
  });

  factory StringsTikRazernij.of(AppLang l) => switch (l) {
    AppLang.fy => StringsTikRazernij.fy(),
    AppLang.nl => StringsTikRazernij.nl(),
    AppLang.en => StringsTikRazernij.en(),
  };

  factory StringsTikRazernij.fy() => const StringsTikRazernij(
    gameName:     'Tik Razernij',
    gameDesc:     'Tik op de doelen foardat se ferdwine!',
    rules:        'Kleurde doelen ferskine op it skerm. Tik op doelen yn dyn kleur foar +1 punt. Tikst op in doel fan de tsjinstanner? Dan -1 punt! Elke ronde duorret 30 sekonden. Bêste fan 3 rondes wint!',
    round:        'Ronde {n} fan 3',
    getReady:     'Klear meitsje!',
    go:           'GO!',
    timeLeft:     '{n}s',
    roundOver:    'Ronde oer!',
    yourScore:    'Skoare: {n}',
    tapYourColor: 'Tik op dyn kleur!',
    wrongColor:   'Ferkearde kleur! -1',
  );

  factory StringsTikRazernij.nl() => const StringsTikRazernij(
    gameName:     'Tikkerij',
    gameDesc:     'Tik op de doelen voordat ze verdwijnen!',
    rules:        'Gekleurde doelen verschijnen op het scherm. Tik op doelen in jouw kleur voor +1 punt. Tik je op een doel van de tegenstander? Dan -1 punt! Elke ronde duurt 30 seconden. Beste van 3 rondes wint!',
    round:        'Ronde {n} van 3',
    getReady:     'Maak je klaar!',
    go:           'GO!',
    timeLeft:     '{n}s',
    roundOver:    'Ronde voorbij!',
    yourScore:    'Score: {n}',
    tapYourColor: 'Tik op jouw kleur!',
    wrongColor:   'Verkeerde kleur! -1',
  );

  factory StringsTikRazernij.en() => const StringsTikRazernij(
    gameName:     'Tap Frenzy',
    gameDesc:     'Tap the targets before they disappear!',
    rules:        'Colored targets appear on screen. Tap targets in your color for +1 point. Tap an opponent\'s target and you lose 1 point! Each round lasts 30 seconds. Best of 3 rounds wins!',
    round:        'Round {n} of 3',
    getReady:     'Get ready!',
    go:           'GO!',
    timeLeft:     '{n}s',
    roundOver:    'Round over!',
    yourScore:    'Score: {n}',
    tapYourColor: 'Tap your color!',
    wrongColor:   'Wrong color! -1',
  );
}
