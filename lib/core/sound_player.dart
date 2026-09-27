import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central sound manager for Heiti's Game Suite.
/// Use [SoundPlayer.i] to access the singleton.
///
/// Mute state is persisted via SharedPreferences (key: 'sound_muted').
/// Call [SoundPlayer.i.init()] once at app startup (in main.dart).
class SoundPlayer {
  SoundPlayer._();
  static final SoundPlayer i = SoundPlayer._();

  static const String _prefKey = 'sound_muted';

  bool _muted = false;
  bool get muted => _muted;

  final _rng = Random();

  // Pool of players to allow overlapping sounds
  final List<AudioPlayer> _pool = [];
  static const int _poolSize = 6;

  Future<void> init() async {
    for (var i = 0; i < _poolSize; i++) {
      _pool.add(AudioPlayer());
    }
    final prefs = await SharedPreferences.getInstance();
    _muted = prefs.getBool(_prefKey) ?? false;
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, _muted);
  }

  // Pick a free player from the pool (round-robin)
  int _nextPlayer = 0;
  AudioPlayer _getPlayer() {
    final p = _pool[_nextPlayer % _poolSize];
    _nextPlayer++;
    return p;
  }

  Future<void> _play(String filename) async {
    if (_muted) return;
    try {
      final player = _getPlayer();
      await player.play(AssetSource('sounds/$filename'));
    } catch (_) {}
  }

  Future<void> _playOne(List<String> files) async {
    if (files.isEmpty) return;
    await _play(files[_rng.nextInt(files.length)]);
  }

  // ─── Global / UI ────────────────────────────────────────────────────────────

  Future<void> uiClick()        => _play('click_003.ogg');
  Future<void> uiConfirm()      => _play('confirmation_002.ogg');
  Future<void> uiBack()         => _play('back_002.ogg');
  Future<void> uiOpen()         => _play('open_002.ogg');
  Future<void> uiSelect()       => _play('select_004.ogg');
  Future<void> gameWin()        => _play('powerUp7.ogg');
  Future<void> gameDraw()       => _play('twoTone1.ogg');
  Future<void> gameLoss()       => _play('lowDown.ogg');
  Future<void> newBest()        => _play('powerUp11.ogg');

  // ─── Dice roll (shared by Boppeslach, Krúske, Rupsen, Ludo, Rekkenje) ───────

  Future<void> diceRoll() => _playOne([
    'dice-throw-1.ogg','dice-throw-2.ogg','dice-throw-3.ogg',
    'die-throw-1.ogg','die-throw-2.ogg','die-throw-3.ogg','die-throw-4.ogg',
  ]);

  Future<void> singleDieRoll() => _playOne([
    'die-throw-1.ogg','die-throw-2.ogg','die-throw-3.ogg','die-throw-4.ogg',
  ]);

  // ─── Boppeslach ─────────────────────────────────────────────────────────────

  Future<void> boppeslachScoreFill()   => _play('chip-lay-2.ogg');
  Future<void> boppeslachRowLocked()   => _play('close_002.ogg');
  Future<void> boppeslachRoundDone()   => _play('confirmation_001.ogg');

  // ─── Krúske ─────────────────────────────────────────────────────────────────

  Future<void> kruskeCross()     => _play('select_003.ogg');
  Future<void> kruskeBonus()     => _play('phaseJump1.ogg');

  // ─── Rupsen ─────────────────────────────────────────────────────────────────

  Future<void> rupsenSetAside()  => _play('chip-lay-1.ogg');
  Future<void> rupsenClaim()     => _play('confirmation_002.ogg');
  Future<void> rupsenBust()      => _play('error_003.ogg');

  // ─── Ludo ───────────────────────────────────────────────────────────────────

  Future<void> ludoMove()        => _play('select_002.ogg');
  Future<void> ludoCapture()     => _play('chips-collide-2.ogg');
  Future<void> ludoExitNest()    => _play('phaserUp1.ogg');
  Future<void> ludoReachHome()   => _play('phaseJump2.ogg');

  // ─── Rekkenje ───────────────────────────────────────────────────────────────

  Future<void> rekkenjeQuestion()    => _play('question_002.ogg');
  Future<void> rekkenjeCorrect()     => _play('confirmation_002.ogg');
  Future<void> rekkenjeWrong()       => _play('error_002.ogg');
  Future<void> rekkenjeRoundEnd()    => _play('phaseJump1.ogg');
  Future<void> rekkenjeTick()        => _play('tick_001.ogg');

  // ─── Bûter, brea en griene tsiis ────────────────────────────────────────────

  Future<void> buterBreaEnGrieneTsiisPlaceX()       => _play('switch_004.ogg');
  Future<void> buterBreaEnGrieneTsiisPlaceO()       => _play('switch_005.ogg');
  Future<void> buterBreaEnGrieneTsiisWinLine()      => _play('powerUp8.ogg');

  // ─── Fjouwer op in Rige ─────────────────────────────────────────────────────

  Future<void> fjouwerOpInRigeDrop()        => _play('drop_002.ogg');
  Future<void> fjouwerOpInRigeLand()        => _play('chip-lay-3.ogg');
  Future<void> fjouwerOpInRigeWin()         => _play('powerUp8.ogg');

  // ─── Skaken ─────────────────────────────────────────────────────────────────

  Future<void> skakenPick()       => _play('select_005.ogg');
  Future<void> skakenPlace()      => _play('chip-lay-2.ogg');
  Future<void> skakenCapture()    => _play('chips-collide-1.ogg');
  Future<void> skakenCheck()      => _play('bong_001.ogg');
  Future<void> skakenCheckmate()  => _play('powerUp7.ogg');
  Future<void> skakenInvalid()    => _play('error_001.ogg');

  // ─── Damjen ─────────────────────────────────────────────────────────────────

  Future<void> damjenMove()    => _play('select_002.ogg');
  Future<void> damjenCapture() => _play('chips-collide-1.ogg');
  Future<void> damjenKing()    => _play('phaserUp2.ogg');

  // ─── Suderseeslach ──────────────────────────────────────────────────────────

  Future<void> suderseeslachPlace() => _play('card-shove-2.ogg');
  Future<void> suderseeslachMiss()  => _play('laser3.ogg');
  Future<void> suderseeslachHit()   => _play('laser8.ogg');
  Future<void> suderseeslachSunk()  => _play('spaceTrash1.ogg');

  // ─── Punten & Fakjes ────────────────────────────────────────────────────────

  Future<void> puntenEnFakjesLine()        => _play('pluck_001.ogg');
  Future<void> puntenEnFakjesBox()         => _play('chip-lay-1.ogg');
  Future<void> puntenEnFakjesExtraTurn()   => _play('pepSound2.ogg');

  // ─── Ûnthâldspultsje ────────────────────────────────────────────────────────

  Future<void> unthaldspultsjeFlip() => _playOne([
    'card-slide-1.ogg','card-slide-2.ogg','card-slide-3.ogg','card-slide-4.ogg',
  ]);
  Future<void> unthaldspultsjeMatch()     => _play('confirmation_003.ogg');
  Future<void> unthaldspultsjeNoMatch()   => _play('card-shove-1.ogg');
  Future<void> unthaldspultsjeAllDone()   => _play('powerUp6.ogg');

  // ─── Paddelduel ─────────────────────────────────────────────────────────────

  Future<void> paddelduelPaddle()      => _play('glass_003.ogg');
  Future<void> paddelduelWall()        => _play('glass_001.ogg');
  Future<void> paddelduelScore()       => _play('pepSound3.ogg');
  Future<void> paddelduelStart()       => _play('phaserUp3.ogg');

  // ─── Kleur-echo ─────────────────────────────────────────────────────────────
  // Uses glass_001–004: four distinct chime pitches — perfect for the 4 buttons

  Future<void> kleurEchoTone1()      => _play('glass_001.ogg');
  Future<void> kleurEchoTone2()      => _play('glass_002.ogg');
  Future<void> kleurEchoTone3()      => _play('glass_003.ogg');
  Future<void> kleurEchoTone4()      => _play('glass_004.ogg');
  Future<void> kleurEchoWrong()      => _play('error_005.ogg');

  Future<void> kleurEchoButton(int idx) {
    switch (idx % 4) {
      case 0: return kleurEchoTone1();
      case 1: return kleurEchoTone2();
      case 2: return kleurEchoTone3();
      default: return kleurEchoTone4();
    }
  }

  // ─── Sudoku Duel ────────────────────────────────────────────────────────────

  Future<void> sudokuDuelCell()      => _play('tick_001.ogg');
  Future<void> sudokuDuelCorrect()   => _play('confirmation_001.ogg');
  Future<void> sudokuDuelWrong()     => _play('error_001.ogg');
  Future<void> sudokuDuelSolved()    => _play('powerUp9.ogg');
  Future<void> sudokuDuelClaim()     => _play('chip-lay-1.ogg');

  // ─── Skofpuzzel ─────────────────────────────────────────────────────────────
  // (reuses Sudoku Duel sounds — tile slide and solve)

  // ─── Slange ─────────────────────────────────────────────────────────────────
  // (reuses rupsenClaim for eat, rupsenBust for crash, newBest for record)

  // ─── Tekenje & Riede ────────────────────────────────────────────────────────
  // (reuses rupsenClaim for correct guess, rupsenBust for wrong, sudokuDuelCell for draw stroke)

  // ─── Aaisykje ───────────────────────────────────────────────────────────────
  Future<void> aaisykjePickup()      => _play('confirmation_002.ogg'); // collect normal egg
  Future<void> aaisykjeTimeEgg()     => _play('phaserUp1.ogg');        // time egg collected
  Future<void> aaisykjeDecoy()       => _play('error_003.ogg');        // decoy egg (penalty)
  Future<void> aaisykjePowerup()     => _play('powerUp5.ogg');         // surprise/powerup egg
  Future<void> aaisykjeKievit()      => _play('select_006.ogg');       // lapwing call / kievit
  Future<void> aaisykjeMoo()         => _play('error_005.ogg');        // cow blocks player
  Future<void> aaisykjeBoswachter()  => _play('zap1.ogg');             // guard hits player
  Future<void> aaisykjeLevelDone()   => _play('powerUp9.ogg');         // stage complete
  Future<void> aaisykjeShield()      => _play('toggle_001.ogg');       // shield powerup activate
  Future<void> aaisykjeFreeze()      => _play('phaserUp3.ogg');        // freeze powerup activate
  Future<void> aaisykjeCombo()       => _play('pepSound2.ogg');        // combo multiplier tick

  // ─── Cleanup ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    for (final p in _pool) { await p.dispose(); }
    _pool.clear();
  }
}
