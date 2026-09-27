import 'app_localizations.dart';

class StringsSlange {
  final String gameName;
  final String gameDesc;
  final String scoreLabel;
  final String ready;
  final String tapToStart;
  final String paused;
  final String crashed;
  final String personalBest;
  final String newBest;
  final String rules;

  const StringsSlange({
    required this.gameName,
    required this.gameDesc,
    required this.scoreLabel,
    required this.ready,
    required this.tapToStart,
    required this.paused,
    required this.crashed,
    required this.personalBest,
    required this.newBest,
    required this.rules,
  });

  factory StringsSlange.of(AppLang l) => switch (l) {
    AppLang.fy => StringsSlange.fy(),
    AppLang.nl => StringsSlange.nl(),
    AppLang.en => StringsSlange.en(),
  };

  factory StringsSlange.fy() => const StringsSlange(
    gameName:     'Slange',
    gameDesc:     'Yt iten, net dyn eigen sturt!',
    scoreLabel:   'Punten: {score}',
    ready:        'Klear?',
    tapToStart: 'Tikje om te begjinnen',
    paused:       'Pauze',
    crashed:      'Botsing!',
    personalBest: 'Bêste: {score}',
    newBest:      '🌟 Nij rekôr!',
    rules:        'Swipe om de rjochting fan de slange te feroarjen. Yt de reade apels om te groeien. De muorren binne trochsichtich — do geist oan de iene kant út en komst oan de oare kant wer yn. Botse net tsjin dyn eigen liif. Yn duöspul: beide slangen binne op itselde fjild — botse ek net tsjin de oar!',
  );

  factory StringsSlange.nl() => const StringsSlange(
    gameName:     'Slang',
    gameDesc:     'Eet eten, niet je eigen staart!',
    scoreLabel:   'Punten: {score}',
    ready:        'Klaar?',
    tapToStart: 'Tik om te beginnen',
    paused:       'Pauze',
    crashed:      'Botsing!',
    personalBest: 'Beste: {score}',
    newBest:      '🌟 Nieuw record!',
    rules:        'Swipe om de richting van de slang te veranderen. Eet de rode appels om te groeien. De muren zijn doordringbaar — ga je aan één kant uit, dan kom je aan de andere kant weer binnen. Botst niet tegen je eigen lijf. In duo-modus: beide slangen zijn op hetzelfde veld — botst ook niet tegen de ander!',
  );

  factory StringsSlange.en() => const StringsSlange(
    gameName:     'Snake',
    gameDesc:     'Eat apples, avoid your tail!',
    scoreLabel:   'Score: {score}',
    ready:        'Ready?',
    tapToStart: 'Tap to start',
    paused:       'Paused',
    crashed:      'Crash!',
    personalBest: 'Best: {score}',
    newBest:      '🌟 New record!',
    rules:        'Swipe to change your snake\'s direction. Eat red apples to grow and score points. Walls wrap around — exit one side and re-enter from the opposite. Don\'t crash into your own body. Versus: both snakes share the same grid — don\'t crash into each other either. Last snake alive wins!',
  );
}
