import 'app_localizations.dart';

class StringsWaBistDo {
  final String gameName;
  final String gameDesc;
  final String yourTurn;
  final String opponentTurn;
  final String askQuestion;  // "Ask a question"
  final String guess;        // "Make a guess!"
  final String guessBtn;
  final String correct;      // "Correct! {player} wins!"
  final String wrong;        // "Wrong guess — {player} loses!"
  final String yes;
  final String no;
  final String whoIsIt;      // "Who is it?"
  final String eliminated;   // "{n} characters eliminated"
  final String remaining;    // "{n} remaining"
  final String yourCharacter; // "Your character: {name}"
  final String opponentGuessed; // "{player} is guessing…"
  final String rules;
  final String chooseCharacter; // "Choose your character"
  final String waitingChoice;   // "Waiting for {player} to choose…"
  final String questionPrompt;  // "Ask yes/no about your opponent's character"

  const StringsWaBistDo({
    required this.gameName, required this.gameDesc,
    required this.yourTurn, required this.opponentTurn,
    required this.askQuestion, required this.guess, required this.guessBtn,
    required this.correct, required this.wrong,
    required this.yes, required this.no,
    required this.whoIsIt, required this.eliminated, required this.remaining,
    required this.yourCharacter, required this.opponentGuessed,
    required this.rules, required this.chooseCharacter,
    required this.waitingChoice, required this.questionPrompt,
  });

  factory StringsWaBistDo.of(AppLang l) => switch (l) {
    AppLang.fy => StringsWaBistDo.fy(),
    AppLang.nl => StringsWaBistDo.nl(),
    AppLang.en => StringsWaBistDo.en(),
  };

  factory StringsWaBistDo.fy() => const StringsWaBistDo(
    gameName: 'Wa Bist Do?',
    gameDesc: 'Ried it personaazje fan dyn tsjinstanner!',
    yourTurn: 'Dyn beurt — stel in fraach',
    opponentTurn: '{player} stelt in fraach…',
    askQuestion: 'Stel fraach',
    guess: 'Rieden!',
    guessBtn: 'Ik wit it!',
    correct: 'Goed! {player} wint!',
    wrong: 'Ferkeard! {player} ferliest!',
    yes: 'Ja',
    no: 'Nee',
    whoIsIt: 'Wa is it?',
    eliminated: '{n} personaazjes útsletten',
    remaining: '{n} oer',
    yourCharacter: 'Dyn personaazje: {name}',
    opponentGuessed: '{player} riedt…',
    rules: 'Kies in personaazje. Freegje inoar om bar ja/nee-fragen yn it echt. Tik in gesicht om it om te draaien (útslute). Dinkst dat do witst wa it is? Kies Rieden en tik it gesicht oan.',
    chooseCharacter: 'Kies dyn personaazje',
    waitingChoice: 'Wachtsje op {player}…',
    questionPrompt: 'Freegje in fraach yn it echt — tik om út te sluten',
  );

  factory StringsWaBistDo.nl() => const StringsWaBistDo(
    gameName: 'Wie Ben Je?',
    gameDesc: 'Raad het personage van je tegenstander!',
    yourTurn: 'Jouw beurt — stel een vraag',
    opponentTurn: '{player} stelt een vraag…',
    askQuestion: 'Vraag stellen',
    guess: 'Raden!',
    guessBtn: 'Ik weet het!',
    correct: 'Goed! {player} wint!',
    wrong: 'Fout! {player} verliest!',
    yes: 'Ja',
    no: 'Nee',
    whoIsIt: 'Wie is jouw persoon?',
    eliminated: '{n} personages uitgeschakeld',
    remaining: '{n} over',
    yourCharacter: 'Jouw personage: {name}',
    opponentGuessed: '{player} raadt…',
    rules: 'Kies een personage. Stel elkaar om beurten ja/nee-vragen in het echt. Tik een gezicht om het om te klappen (elimineren). Denk je te weten wie het is? Kies Raden en tik het gezicht aan.',
    chooseCharacter: 'Kies jouw personage',
    waitingChoice: 'Wachten op {player}…',
    questionPrompt: 'Stel een vraag in het echt — tik om te elimineren',
  );

  factory StringsWaBistDo.en() => const StringsWaBistDo(
    gameName: 'Who Are You?',
    gameDesc: "Guess your opponent's character!",
    yourTurn: 'Your turn — ask a question',
    opponentTurn: '{player} is asking…',
    askQuestion: 'Ask question',
    guess: 'Guess!',
    guessBtn: "I know it!",
    correct: 'Correct! {player} wins!',
    wrong: 'Wrong! {player} loses!',
    yes: 'Yes',
    no: 'No',
    whoIsIt: 'Who is it?',
    eliminated: '{n} characters eliminated',
    remaining: '{n} remaining',
    yourCharacter: 'Your character: {name}',
    opponentGuessed: '{player} is guessing…',
    rules: 'Choose a character. Ask each other yes/no questions out loud in real life. Tap a face to flip it down (eliminate). Think you know who it is? Switch to Guess mode and tap the face.',
    chooseCharacter: 'Choose your character',
    waitingChoice: 'Waiting for {player}…',
    questionPrompt: "Ask a question out loud — tap faces to eliminate",
  );
}
