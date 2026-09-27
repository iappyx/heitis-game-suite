import 'app_localizations.dart';

class StringsFluchTekenje {
  final String gameName;
  final String gameDesc;
  final String rules;
  final String drawing;
  final String timeLeft;       // "{n} seconds left"
  final String voteNow;
  final String cantVoteOwn;
  final String roundWinner;    // "{player} wins this round!"
  final String noVotes;
  final String round;          // "Round {n} of {total}"
  final String waitingDrawings;
  final String votedFor;       // "You voted for {player}"
  final String clearCanvas;
  final String soloComplete;   // "You drew {n} prompts!"
  final String judgeNow;       // "Did {player} draw "{prompt}"?" (2 players)
  final String judgeWaiting;
  final String judgeYes;
  final String judgeNo;
  final String judgePoint;     // "{player} gets a point!"
  final String judgeBoth;
  final String judgeNone;
  final List<String> prompts;

  const StringsFluchTekenje({
    required this.gameName,
    required this.gameDesc,
    required this.rules,
    required this.drawing,
    required this.timeLeft,
    required this.voteNow,
    required this.cantVoteOwn,
    required this.roundWinner,
    required this.noVotes,
    required this.round,
    required this.waitingDrawings,
    required this.votedFor,
    required this.clearCanvas,
    required this.soloComplete,
    required this.judgeNow,
    required this.judgeWaiting,
    required this.judgeYes,
    required this.judgeNo,
    required this.judgePoint,
    required this.judgeBoth,
    required this.judgeNone,
    required this.prompts,
  });

  factory StringsFluchTekenje.of(AppLang l) => switch (l) {
    AppLang.fy => StringsFluchTekenje.fy(),
    AppLang.nl => StringsFluchTekenje.nl(),
    AppLang.en => StringsFluchTekenje.en(),
  };

  factory StringsFluchTekenje.fy() => const StringsFluchTekenje(
    gameName:        'Fluch Tekenje',
    gameDesc:        'Teken itselde, stimme op de bêste!',
    rules:           'Elkenien tekenet itselde wurd yn 15 sekonden. Dêrnei stimme jimme op de bêste tekening. De measte stimmen = 1 punt. Earst 5 rondes winne wint! Mei 2 spilers beoardielje jimme elkoars tekening: tomme omheech = 1 punt.',
    drawing:         'Teken!',
    timeLeft:        '{n} sekonden oer',
    voteNow:         'Stimme op de bêste tekening!',
    cantVoteOwn:     'Do kinst net op dysels stimme',
    roundWinner:     '{player} wint dizze ronde!',
    noVotes:         'Gjin stimmen — it is lykspul!',
    round:           'Ronde {n} fan {total}',
    waitingDrawings: 'Wachtsje op tekeningen...',
    votedFor:        'Do hast stimd op {player}',
    clearCanvas:     'Wisje',
    soloComplete:    'Do hast {n} wurden tekene!',
    judgeNow:        'Hat {player} "{prompt}" tekene?',
    judgeWaiting:    'Wachtsje op de oare spiler...',
    judgeYes:        'Ja!',
    judgeNo:         'Nee',
    judgePoint:      '{player} krijt in punt!',
    judgeBoth:       'Jimme hawwe it allebeide goed tekene!',
    judgeNone:       'Gjin punten dizze ronde',
    prompts: [
      'hus', 'beam', 'kat', 'hun', 'sinne', 'auto', 'fisk', 'blom',
      'oaljefant', 'pinguyn', 'spin', 'dinosaurus', 'walfisk',
      'boat', 'flinter', 'stjer', 'moan', 'drager', 'kastiel', 'robot',
      'pizza', 'iisko', 'taart', 'banaan', 'apel',
      'gitaar', 'trommel', 'flearmoes', 'ienhoarn', 'raket',
      'trein', 'helikopter', 'kat op in skateboard', 'robot dy\'t pizza yt',
      'pinguyn mei in hoed', 'hus op de moan', 'fisk mei sinnebril',
      'spin yn in web', 'draak dy\'t fjoer spuit', 'ienhoarn op in reinbôge',
      'slang', 'skiep', 'ko', 'froask', 'krokodil',
      'paraplu', 'fiets', 'snjieman', 'kaktus', 'flamingo',
    ],
  );

  factory StringsFluchTekenje.nl() => const StringsFluchTekenje(
    gameName:        'Snel Tekenen',
    gameDesc:        'Teken hetzelfde, stem op de beste!',
    rules:           'Iedereen tekent hetzelfde woord in 15 seconden. Daarna stemmen jullie op de beste tekening. De meeste stemmen = 1 punt. Eerste met 5 rondes wint! Met 2 spelers beoordelen jullie elkaars tekening: duim omhoog = 1 punt.',
    drawing:         'Teken!',
    timeLeft:        '{n} seconden over',
    voteNow:         'Stem op de beste tekening!',
    cantVoteOwn:     'Je kunt niet op jezelf stemmen',
    roundWinner:     '{player} wint deze ronde!',
    noVotes:         'Geen stemmen — het is gelijk!',
    round:           'Ronde {n} van {total}',
    waitingDrawings: 'Wachten op tekeningen...',
    votedFor:        'Je hebt gestemd op {player}',
    clearCanvas:     'Wissen',
    soloComplete:    'Je hebt {n} woorden getekend!',
    judgeNow:        'Heeft {player} "{prompt}" getekend?',
    judgeWaiting:    'Wachten op de andere speler...',
    judgeYes:        'Ja!',
    judgeNo:         'Nee',
    judgePoint:      '{player} krijgt een punt!',
    judgeBoth:       'Jullie hebben het allebei goed getekend!',
    judgeNone:       'Geen punten deze ronde',
    prompts: [
      'huis', 'boom', 'kat', 'hond', 'zon', 'auto', 'vis', 'bloem',
      'olifant', 'pinguin', 'spin', 'dinosaurus', 'walvis',
      'boot', 'vlinder', 'ster', 'maan', 'draak', 'kasteel', 'robot',
      'pizza', 'ijsje', 'taart', 'banaan', 'appel',
      'gitaar', 'trommel', 'vleermuis', 'eenhoorn', 'raket',
      'trein', 'helikopter', 'kat op een skateboard', 'robot die pizza eet',
      'pinguin met een hoed', 'huis op de maan', 'vis met zonnebril',
      'spin in een web', 'draak die vuur spuwt', 'eenhoorn op een regenboog',
      'slang', 'schaap', 'koe', 'kikker', 'krokodil',
      'paraplu', 'fiets', 'sneeuwpop', 'cactus', 'flamingo',
    ],
  );

  factory StringsFluchTekenje.en() => const StringsFluchTekenje(
    gameName:        'Quick Draw',
    gameDesc:        'Draw the same prompt, vote on the best!',
    rules:           'Everyone draws the same word in 15 seconds. Then you vote on the best drawing. Most votes = 1 point. First to win 5 rounds wins! With 2 players you judge each other\'s drawing: thumbs up = 1 point.',
    drawing:         'Draw!',
    timeLeft:        '{n} seconds left',
    voteNow:         'Vote for the best drawing!',
    cantVoteOwn:     'You can\'t vote for your own drawing',
    roundWinner:     '{player} wins this round!',
    noVotes:         'No votes — it\'s a tie!',
    round:           'Round {n} of {total}',
    waitingDrawings: 'Waiting for drawings...',
    votedFor:        'You voted for {player}',
    clearCanvas:     'Clear',
    soloComplete:    'You drew {n} prompts!',
    judgeNow:        'Did {player} draw "{prompt}"?',
    judgeWaiting:    'Waiting for the other player...',
    judgeYes:        'Yes!',
    judgeNo:         'No',
    judgePoint:      '{player} gets a point!',
    judgeBoth:       'You both drew it!',
    judgeNone:       'No points this round',
    prompts: [
      'house', 'tree', 'cat', 'dog', 'sun', 'car', 'fish', 'flower',
      'elephant', 'penguin', 'spider', 'dinosaur', 'whale',
      'boat', 'butterfly', 'star', 'moon', 'dragon', 'castle', 'robot',
      'pizza', 'ice cream', 'cake', 'banana', 'apple',
      'guitar', 'drum', 'bat', 'unicorn', 'rocket',
      'train', 'helicopter', 'a cat on a skateboard', 'a robot eating pizza',
      'a penguin in a hat', 'a house on the moon', 'a fish with sunglasses',
      'a spider in a web', 'a dragon breathing fire', 'a unicorn on a rainbow',
      'snake', 'sheep', 'cow', 'frog', 'crocodile',
      'umbrella', 'bicycle', 'snowman', 'cactus', 'flamingo',
    ],
  );
}
