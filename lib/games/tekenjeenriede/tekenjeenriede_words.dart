// Trilingual word list for Tekenje & Riede
// Each entry: [frisian, dutch, english]
// Words are grouped by difficulty: easy (concrete, visual), medium, hard

const List<List<String>> kTekenjeEnRiedeWords = [
  // ── Easy ──────────────────────────────────────────────────────────────────
  ['hûs',     'huis',       'house'],
  ['kat',     'kat',        'cat'],
  ['hûn',     'hond',       'dog'],
  ['fisk',    'vis',        'fish'],
  ['beam',    'boom',       'tree'],
  ['auto',    'auto',       'car'],
  ['fûgel',   'vogel',      'bird'],
  ['boat',    'boot',       'boat'],
  ['snie',    'sneeuw',     'snow'],
  ['rein',    'regen',      'rain'],
  ['sinne',   'zon',        'sun'],
  ['moanne',  'maan',       'moon'],
  ['stjer',   'ster',       'star'],
  ['blom',    'bloem',      'flower'],
  ['apel',    'appel',      'apple'],
  ['ky',      'koe',        'cow'],
  ['hynder',  'paard',      'horse'],
  ['skiep',   'schaap',     'sheep'],
  ['foks',    'vos',        'fox'],
  ['earn',    'adelaar',    'eagle'],
  ['slange',  'slang',      'snake'],
  ['pianist', 'piano',      'piano'],
  ['gitaar',  'gitaar',     'guitar'],
  ['trein',   'trein',      'train'],
  ['fleantúch','vliegtuig', 'airplane'],
  ['fyts',    'fiets',      'bicycle'],
  ['brêge',   'brug',       'bridge'],
  ['tsjerke', 'kerk',       'church'],
  ['swurd',   'zwaard',     'sword'],
  ['hoeke',   'hoek',       'corner'],
  ['bril',    'bril',       'glasses'],
  ['hoed',    'hoed',       'hat'],
  ['reade',   'rood',       'red'],
  ['blau',    'blauw',      'blue'],
  ['grien',   'groen',      'green'],
  ['giel',    'geel',       'yellow'],
  ['swart',   'zwart',      'black'],
  ['wyt',     'wit',        'white'],
  ['ballon',  'ballon',     'balloon'],
  ['boek',    'boek',       'book'],
  ['stoel',   'stoel',      'chair'],
  ['tafel',   'tafel',      'table'],
  ['sliep',   'slapen',     'sleep'],
  ['iten',    'eten',       'eat'],
  ['swimme',  'zwemmen',    'swim'],
  ['rinne',   'rennen',     'run'],
  ['springe', 'springen',   'jump'],
  ['dûnsje',  'dansen',     'dance'],
  ['sjonge',  'zingen',     'sing'],
  ['skriuwe', 'schrijven',  'write'],

  // ── Medium ────────────────────────────────────────────────────────────────
  ['regnbôge', 'regenboog', 'rainbow'],
  ['ko\'ek',   'koekje',    'cookie'],
  ['pizza',    'pizza',     'pizza'],
  ['raket',    'raket',     'rocket'],
  ['vuurtoren','vuurtoren', 'lighthouse'],
  ['kastiel',  'kasteel',   'castle'],
  ['drache',   'draak',     'dragon'],
  ['toverstêf','toverstaf', 'magic wand'],
  ['kroone',   'kroon',     'crown'],
  ['skatkaart','schatkaart','treasure map'],
  ['oansweter','trui',      'sweater'],
  ['oerwâld',  'jungle',    'jungle'],
  ['woestyn',  'woestijn',  'desert'],
  ['iisberch', 'ijsberg',   'iceberg'],
  ['fjoertoer','vuurwerk',  'fireworks'],
  ['akwaarium','aquarium',  'aquarium'],
  ['koalfiske','duiken',    'diving'],
  ['reuzen',   'reus',      'giant'],
  ['skelet',   'skelet',    'skeleton'],
  ['komeet',   'komeet',    'comet'],
  ['submarine','onderzeeër','submarine'],
  ['trolley',  'tram',      'tram'],
  ['koekoe',   'koekoek',   'cuckoo'],
  ['pinguïn',  'pinguïn',   'penguin'],
  ['koala',    'koala',     'koala'],
  ['zebra',    'zebra',     'zebra'],
  ['giraf',    'giraf',     'giraffe'],
  ['oaljefant','olifant',   'elephant'],
  ['krokodil', 'krokodil',  'crocodile'],
  ['papegaai', 'papegaai',  'parrot'],

  // ── Hard ─────────────────────────────────────────────────────────────────
  ['freonskip', 'vriendschap','friendship'],
  ['aventoer',  'avontuur',  'adventure'],
  ['dreame',    'dromen',    'dream'],
  ['muzyk',     'muziek',    'music'],
  ['magy',      'magie',     'magic'],
  ['famylje',   'familie',   'family'],
  ['bliidskip', 'blijdschap','joy'],
  ['mooglikheid','kans',     'opportunity'],
  ['aventûr',   'ontdekking','discovery'],
  ['yntelliginsje','intelligentie','intelligence'],
];

/// Get a random word matching the given language code, not in usedWords.
String kPickWord(String langCode, List<List<String>> usedWords) {
  final unused = kTekenjeEnRiedeWords
      .where((w) => !usedWords.contains(w))
      .toList();
  if (unused.isEmpty) return kTekenjeEnRiedeWords.first[_langIdx(langCode)];
  final idx = DateTime.now().millisecondsSinceEpoch % unused.length;
  return unused[idx][_langIdx(langCode)];
}

int _langIdx(String code) => switch (code) {
  'fy' => 0,
  'nl' => 1,
  _    => 2,
};

/// Pick 3 word choices for the drawer to select from.
List<String> kPickWordChoices(String langCode, List<List<String>> usedWords) {
  final unused = [...kTekenjeEnRiedeWords]
      .where((w) => !usedWords.contains(w))
      .toList()
    ..shuffle();
  final picks = unused.take(3).toList();
  if (picks.length < 3) picks.addAll(kTekenjeEnRiedeWords.take(3 - picks.length));
  final lIdx = _langIdx(langCode);
  return picks.map((w) => w[lIdx]).toList();
}
