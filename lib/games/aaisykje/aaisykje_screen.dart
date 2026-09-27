import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../core/wake_lock.dart';
import '../../core/sound_player.dart';
import '../../core/session.dart';
import '../../screens/lobby_screen.dart';
import '../../screens/solo_setup_screen.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../l10n/app_localizations.dart';
import 'aaisykje_data.dart';
import 'aaisykje_painter.dart';

// ── Game state machine ────────────────────────────────────────────────────────
enum _AaState { levelIntro, playing, levelComplete, gameOver, won }

class AaisykjeScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;

  const AaisykjeScreen({super.key, required this.players, required this.firstPlayer});

  @override
  State<AaisykjeScreen> createState() => _AaisykjeScreenState();
}

class _AaisykjeScreenState extends State<AaisykjeScreen>
    with SingleTickerProviderStateMixin, GameMixin {

  final _net = Network();

  // ── Ticker ─────────────────────────────────────────────────────────────────
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // ── Layout (established in first build) ───────────────────────────────────
  double W = 0, H = 0;
  double groundY = 0, horizonY = 0, ditch1 = 0, ditch2 = 0;

  // ── Game state ─────────────────────────────────────────────────────────────
  _AaState _state = _AaState.levelIntro;
  int _currentLevel = 0;
  int _totalScore = 0;
  int _totalScore2 = 0; // P2 accumulated score across levels
  int _score = 0;
  int _eggs = 0;          // eggs collected this level
  int _combo = 1;
  double _comboTimer = 0;
  double _timeLeft = 0;
  int _lives = 5;
  double _gameTime = 0;
  double _forestKeeperWarning = 0;
  double _screenShake = 0;

  // ── Time bonus ─────────────────────────────────────────────────────────────
  bool _timeBonusActive = false;
  double _timeBonusRemaining = 0;
  double _timeBonusFlash = 0;
  static const _timeBonusSpeed = 10.0; // pts/s drain rate

  // ── Time egg + surprise egg ────────────────────────────────────────────────
  double _timeEggTimer = 0;
  bool _timeEggSpawned = false;
  double _surpriseEggTimer = 0;
  bool _surpriseEggSpawned = false;

  // ── Powerup ────────────────────────────────────────────────────────────────
  AaPowerup? _activePowerup;
  double _powerupTimer = 0;

  // ── Entities ───────────────────────────────────────────────────────────────
  AaPlayer? _player;
  final List<AaKievit> _kievits = [];
  final List<AaBoswachter> _boswachters = [];
  final List<AaEgg> _eggs_ = [];      // named awkwardly to not clash with _eggs counter
  final List<AaCow> _cows = [];
  final List<AaParticle> _particles = [];
  final List<AaFloatingText> _floatingTexts = [];
  final List<AaHatchingBird> _hatchingBirds = [];
  final List<AaHeartItem> _heartItems = [];
  final List<AaCloud> _clouds = [];
  List<(double,double,double)> _trees = [];
  final List<AaFlower> _flowers = [];
  List<AaRainDrop> _rainDrops = [];
  double _rainIntensity = 0;
  bool _rainActive = false;

  // ── Horizon ────────────────────────────────────────────────────────────────
  int _horizonScene = 0;
  double _horizonOffsetX = 0;
  bool _horizonScrolling = false;
  double _horizonScrollSpeed = 0;
  bool _horizonScrollDone = false;
  int _nextHorizonScene = 0;

  // ── Input ──────────────────────────────────────────────────────────────────
  Offset _joystick = Offset.zero; // normalised -1..1 on each axis

  // ── Multiplayer ────────────────────────────────────────────────────────────
  bool get _isMulti => widget.players.length >= 2;
  // Second player state (host tracks authoritative; client receives via AAI_TICK)
  AaPlayer? _player2;
  int _score2 = 0;
  int _eggs2 = 0;
  int _combo2 = 1;
  double _comboTimer2 = 0;
  int _lives2 = 5;
  AaPowerup? _activePowerup2;
  double _powerupTimer2 = 0;
  // Remote joystick input received by host from client
  Offset _remoteJoystick = Offset.zero;
  // Client-side: lerp targets received from host — eggie glides smoothly
  double _targetX = 0, _targetY = 0;
  double _target2X = 0, _target2Y = 0;
  bool _targetSet = false, _target2Set = false;
  // Throttle: outgoing AAI_TICK (host) — client input is sent every frame (unthrottled)
  double _netTickTimer = 0;
  static const _netTickRate = 1/30.0; // 30 Hz world snapshot

  // ── RNG ────────────────────────────────────────────────────────────────────
  final _rng = math.Random();

  // ── Highscore ──────────────────────────────────────────────────────────────
  int _bestScore = 0;

  @override
  List<Player> get gamePlayers => widget.players;

  @override
  void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    _loadBest();
    _ticker = createTicker(_onTick)..start();
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          // Client requests full state from host to recover from black screen
          if (!_net.isHost) {
            _net.send('AAI_SYNC_REQ', {});
          }
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  void _onMsg(Map<String,dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    final t = msg['type'] as String? ?? '';
    switch (t) {
      case 'GAME_RESET':
        // Host pressed Play Again via GameOverActions
        setState(() => _restartGame());
        break;
      case 'AAI_START':
        // Client: host says start (or restart) this level
        if (!_net.isHost) {
          final level = msg['level'] as int? ?? _currentLevel;
          _currentLevel = level;
          _totalScore = 0; _totalScore2 = 0;
          _score = 0; _eggs = 0; _combo = 1; _comboTimer = 0; _lives = 5;
          _score2 = 0; _eggs2 = 0; _combo2 = 1; _comboTimer2 = 0; _lives2 = 5;
          _horizonScene = 0; _horizonOffsetX = 0; _horizonScrolling = false;
          _targetSet = false; _target2Set = false;
          if (W > 0 && H > 0) {
            _initLevel(level);
            setState(() => _startPlaying());
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && W > 0 && H > 0) {
                _initLevel(level);
                setState(() => _startPlaying());
              }
            });
          }
        }
        break;
      case 'AAI_INPUT':
        // Host receives remote player joystick
        if (_net.isHost) {
          _remoteJoystick = Offset(
            (msg['dx'] as num).toDouble(),
            (msg['dy'] as num).toDouble(),
          );
        }
        break;
      case 'AAI_TICK':
        // Client receives authoritative world state from host
        if (!_net.isHost) _applyTick(msg);
        break;
      case 'AAI_EGG_COLLECTED':
        // Client: an egg was collected — remove it locally and show VFX
        if (!_net.isHost) {
          final idx = msg['idx'] as int? ?? 0;
          final byP2 = msg['p2'] as bool? ?? false;
          if (idx >= 0 && idx < _eggs_.length) {
            final e = _eggs_[idx];
            _spawnParticles(e.x, e.y, const Color(0xFFFFE566), 10);
            _eggs_.removeAt(idx);
          }
          // On client: byP2==true means host's p2 = the client = "me" → update _score
          //            byP2==false means host's p1 = opponent → update _score2
          if (byP2) {
            _score = msg['score2'] as int? ?? _score;
            _eggs  = msg['eggs2']  as int? ?? _eggs;
            _combo = msg['combo2'] as int? ?? _combo;
          } else {
            _score2 = msg['score'] as int? ?? _score2;
            _eggs2  = msg['eggs']  as int? ?? _eggs2;
            _combo2 = msg['combo'] as int? ?? _combo2;
          }
        }
        break;
      case 'AAI_BONUS_START':
        // Client: time bonus phase started
        if (!_net.isHost) {
          _timeBonusActive = true;
          _timeBonusRemaining = (msg['time'] as num).toDouble();
          _timeBonusFlash = 1.0;
          _spawnParticles(W/2,H/2,const Color(0xFFFFE566),30);
          _spawnParticles(W/2,H/2,const Color(0xFF66FF99),20);
        }
        break;
      case 'AAI_GAME_OVER':
        // Client: game over from host
        if (!_net.isHost) {
          // Mirror host's final scores so both sides decide the same winner
          _score       = msg['s2']  as int? ?? _score;
          _score2      = msg['s1']  as int? ?? _score2;
          _totalScore  = msg['ts2'] as int? ?? _totalScore;
          _totalScore2 = msg['ts1'] as int? ?? _totalScore2;
          setState(() => _endGame());
        }
        break;
      case 'AAI_LEVEL_DONE':
        // Client: advance to next level
        if (!_net.isHost) {
          final nextLv = msg['next'] as int? ?? 0;
          final ts1 = msg['ts1'] as int?; // host's (opponent's) authoritative total
          final ts2 = msg['ts2'] as int?; // joiner's own authoritative total
          if (nextLv >= kAaisyLevels.length) {
            setState(() {
              if (ts1 != null && ts2 != null) {
                // Host totals already include the final level — mirror host exactly
                _totalScore = ts2; _totalScore2 = ts1;
                _score = 0; _score2 = 0;
              }
              _timeBonusActive = false;
              _state = _AaState.won;
              _saveBest(_totalScore + _score);
              SoundPlayer.i.gameWin();
              // Client win — confetti + stats (host already recorded via its own won path)
              final myIdx = _net.myIdx.clamp(0, widget.players.length - 1);
              final oppIdx = myIdx == 0 ? 1 : 0;
              final myTotal  = _totalScore + _score;
              final oppTotal = _totalScore2 + _score2;
              final winnerIdx = myTotal > oppTotal ? myIdx
                              : oppTotal > myTotal ? oppIdx : -1;
              fireConfettiOnce(winnerIdx);
              recordResult('aaisykje', winnerIdx);
            });
          } else {
            // Accumulate score before level transition clears _score —
            // prefer host's authoritative totals (include the time bonus)
            if (ts1 != null && ts2 != null) {
              _totalScore = ts2; _totalScore2 = ts1;
            } else {
              _totalScore += _score;
            }
            // Don't set _currentLevel here — _updateHorizonScroll will increment it
            setState(() => _startLevelComplete(nextLv));
          }
        }
        break;
      case 'AAI_SYNC_REQ':
        // Client reconnected and needs full game state
        if (_net.isHost) _sendSync();
        break;
      case 'AAI_SYNC':
        // Host sent full game state after reconnect
        if (!_net.isHost) _applySync(msg);
        break;
    }
  }

  /// Client-side: apply authoritative world snapshot from host AAI_TICK.
  void _applyTick(Map<String,dynamic> msg) {
    if (W == 0 || H == 0) return;
    // On the client, the *local* player is host's p2 (host moves it via _remoteJoystick).
    // The opponent (host's p1) is shown as _player2 here.
    // All positions are normalised 0..1; denormalise to local W×H.
    double dx(num v) => v.toDouble() * W;
    double dy(num v) => v.toDouble() * H;

    // p2 in tick = client's own eggie — store as lerp target, don't snap
    final p2raw = msg['p2'] as List?;
    if (p2raw != null && _player != null) {
      _targetX = dx(p2raw[0] as num);
      _targetY = dy(p2raw[1] as num);
      _targetSet = true;
      _player!.dir = p2raw[2] as int? ?? _player!.dir;
      _player!.invincible = (p2raw[3] as num? ?? 0).toDouble();
    }
    // p1 in tick = opponent eggie — store as lerp target
    final p1raw = msg['p1'] as List?;
    if (p1raw != null) {
      _target2X = dx(p1raw[0] as num);
      _target2Y = dy(p1raw[1] as num);
      _target2Set = true;
      if (_player2 == null) {
        _player2 = AaPlayer(x: _target2X, y: _target2Y);
      } else {
        _player2!.dir = p1raw[2] as int? ?? _player2!.dir;
        _player2!.invincible = (p1raw[3] as num? ?? 0).toDouble();
      }
    }
    // Kievits
    final kv = msg['kv'] as List?;
    if (kv != null && kv.length == _kievits.length) {
      for (int i=0; i<_kievits.length; i++) {
        final k = kv[i] as List;
        _kievits[i].x = dx(k[0] as num);
        _kievits[i].y = dy(k[1] as num);
        _kievits[i].dir = k[2] as int? ?? _kievits[i].dir;
        _kievits[i].wingPhase = (k[3] as num? ?? 0).toDouble();
      }
    }
    // Boswachters
    final bw = msg['bw'] as List?;
    if (bw != null && bw.length == _boswachters.length) {
      for (int i=0; i<_boswachters.length; i++) {
        final b = bw[i] as List;
        _boswachters[i].x = dx(b[0] as num);
        _boswachters[i].y = dy(b[1] as num);
        _boswachters[i].dir = b[2] as int? ?? _boswachters[i].dir;
        _boswachters[i].walkPhase = (b[3] as num? ?? 0).toDouble();
        _boswachters[i].stunned = (b[4] as num? ?? 0).toDouble();
      }
    }
    // Eggs
    final eg = msg['eg'] as List?;
    if (eg != null) {
      while (_eggs_.length > eg.length) _eggs_.removeLast();
      for (int i=0; i<eg.length; i++) {
        final e = eg[i] as List;
        if (i >= _eggs_.length) {
          _eggs_.add(AaEgg(
            x: dx(e[0] as num), y: dy(e[1] as num),
            type: EggType.values[(e[2] as int? ?? 0).clamp(0, EggType.values.length-1)],
          ));
        } else {
          _eggs_[i].x = dx(e[0] as num);
          _eggs_[i].y = dy(e[1] as num);
        }
        _eggs_[i].timer = (e[3] as num? ?? 0).toDouble();
      }
    }
    // Scores — note: s1/l1 = host player, s2/l2 = client player
    // On client, show own score as _score and host's as _score2
    _score  = msg['s2'] as int? ?? _score;   // client is p2
    _score2 = msg['s1'] as int? ?? _score2;  // host is p1 → shown as opponent
    _eggs   = msg['e2'] as int? ?? _eggs;
    _eggs2  = msg['e1'] as int? ?? _eggs2;
    _lives  = msg['l2'] as int? ?? _lives;
    _lives2 = msg['l1'] as int? ?? _lives2;
    _timeLeft = (msg['t'] as num? ?? _timeLeft).toDouble();
    // Total scores — ts2 = client's cumulative total, ts1 = host's
    _totalScore  = msg['ts2'] as int? ?? _totalScore;
    _totalScore2 = msg['ts1'] as int? ?? _totalScore2;
    // Powerups — pw2/pt2 = client's own powerup; pw1/pt1 = opponent's
    final pw2 = msg['pw2'] as int? ?? -1;
    _activePowerup  = pw2 >= 0 ? AaPowerup.values[pw2.clamp(0, AaPowerup.values.length-1)] : null;
    _powerupTimer   = (msg['pt2'] as num? ?? 0).toDouble();
    final pw1 = msg['pw1'] as int? ?? -1;
    _activePowerup2 = pw1 >= 0 ? AaPowerup.values[pw1.clamp(0, AaPowerup.values.length-1)] : null;
    _powerupTimer2  = (msg['pt1'] as num? ?? 0).toDouble();
    if (mounted) setState(() {});
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _bestScore = prefs.getInt('aaisykje_best') ?? 0; });
  }

  Future<void> _saveBest(int score) async {
    if (score <= _bestScore) return;
    _bestScore = score;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('aaisykje_best', score);
  }

  @override
  void dispose() {
    _ticker.dispose();
    msgSub?.cancel();
    WakeLock.release();
    super.dispose();
  }

  // ── Tick ───────────────────────────────────────────────────────────────────
  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return; // skip huge gaps

    if (_state == _AaState.playing) {
      _update(dt.clamp(0.0, 0.05));
      if (mounted) setState(() {});
    } else if (_horizonScrolling) {
      _updateHorizonScroll(dt);
      if (mounted) setState(() {});
    }
  }

  // ── Init level ─────────────────────────────────────────────────────────────
  void _initLevel(int lvIdx) {
    if (W == 0) return; // layout not ready yet
    if (lvIdx >= kAaisyLevels.length) return; // safety guard
    _horizonScrolling = false; // stop any in-progress scroll
    _horizonScrollDone = true;
    _horizonScene = lvIdx % kHorizonScenes.length;
    final lv = kAaisyLevels[lvIdx];

    _score = 0; _eggs = 0; _combo = 1; _comboTimer = 0;
    _timeLeft = lv.duration.toDouble();
    _forestKeeperWarning = 0;
    _timeBonusActive = false; _timeBonusFlash = 0;
    _activePowerup = null; _powerupTimer = 0;
    _timeEggTimer = 15+_rng.nextDouble()*25; _timeEggSpawned = false;
    _surpriseEggTimer = 8+_rng.nextDouble()*22; _surpriseEggSpawned = false;
    _gameTime = 0;

    _player = AaPlayer(x:W/2, y:H*0.75)..invincible=2.0;
    // Second player spawns offset from player 1
    if (_isMulti) {
      _player2 = AaPlayer(x:W/2+60, y:H*0.72)..invincible=2.0;
      _score2 = 0; _eggs2 = 0; _combo2 = 1; _comboTimer2 = 0;
      // Lives carry across levels (only reset in _restartGame)
      _activePowerup2 = null; _powerupTimer2 = 0;
      _remoteJoystick = Offset.zero;
    } else {
      _player2 = null;
    }
    _trees = buildTrees(W, H, groundY);

    // Cows
    _cows.clear();
    final numCows = 3+_rng.nextInt(5);
    for (int i=0; i<numCows; i++) {
      final pos = safePosOnGround(_rng, 80, W-80, groundY, H, _trees, [], ditch1, ditch2);
      _cows.add(AaCow(x:pos.x, y:pos.y, sz:36+_rng.nextDouble()*8)
        ..vx=(_rng.nextDouble()-0.5)*14 ..vy=(_rng.nextDouble()-0.5)*4
        ..walkPhase=_rng.nextDouble()*math.pi*2
        ..dir=_rng.nextBool()?1:-1
        ..wanderTimer=2+_rng.nextDouble()*4);
    }

    // Kievits
    _kievits.clear();
    for (int i=0; i<lv.numKievits; i++) {
      final vx = (_rng.nextBool()?1:-1)*(lv.kievitSpeed*0.8+_rng.nextDouble()*lv.kievitSpeed*0.4);
      _kievits.add(AaKievit(
        x: 80+_rng.nextDouble()*(W-160),
        y: H*0.1+_rng.nextDouble()*H*0.18,
        vx: vx, speed: lv.kievitSpeed,
        layMin: lv.layMin, layMax: lv.layMax,
        initialLayTimer: 2+i*1.5+_rng.nextDouble()*3,
      )..vy=0 ..wingPhase=_rng.nextDouble()*math.pi*2 ..dir=vx>=0?1:-1);
    }

    // Boswachters
    _boswachters.clear();
    for (int i=0; i<lv.numBoswachters; i++) {
      // Default: place in opposite corner from player start (W/2, H*0.75)
      ({double x, double y}) pos = i.isEven
          ? (x: W*0.1, y: groundY + (H-groundY)*0.3)
          : (x: W*0.9, y: groundY + (H-groundY)*0.7);
      for (int attempt=0; attempt<40; attempt++) {
        final p = safePosOnGround(_rng, 60, W-60, groundY, H, _trees, _cows, ditch1, ditch2);
        final dx=p.x-W/2, dy=p.y-H*0.75;
        if (math.sqrt(dx*dx+dy*dy)>=200) { pos=p; break; }
      }
      _boswachters.add(AaBoswachter(
        x:pos.x, y:pos.y,
        speed: lv.bwSpeed,
        targetPlayer: i.isEven || !_isMulti, // even→p1, odd→p2 (solo all→p1)
      ));
    }

    // Misc
    _eggs_.clear(); _heartItems.clear(); _hatchingBirds.clear();
    _particles.clear(); _floatingTexts.clear();

    _rainActive = _rng.nextDouble()<0.30;
    _rainIntensity = 0;
    if (_rainActive) {
      _rainDrops = List.generate(140, (_) => AaRainDrop(
        x:_rng.nextDouble()*(W+100)-50, y:_rng.nextDouble()*H,
        speed:280+_rng.nextDouble()*160, len:8+_rng.nextDouble()*10,
        alpha:0.3+_rng.nextDouble()*0.4));
    } else {
      _rainDrops = [];
    }

    _flowers.clear();
    for (int i=0; i<8; i++) {
      for (int a=0; a<20; a++) {
        final fx=30+_rng.nextDouble()*(W-60), fy=groundY+4+_rng.nextDouble()*(H-groundY-20);
        if (!_isInTreeOrCow(fx,fy) && !_isInDitch(fy)) {
          final palR = [0xFFFF6EB4,0xFFFF8C42,0xFFA78BFA,0xFFF9E547,0xFFFF4D6D];
          _flowers.add(AaFlower(x:fx, y:fy, r:3+_rng.nextDouble()*4, color:palR[_rng.nextInt(5)]));
          break;
        }
      }
    }

    _clouds.clear();
    for (int i=0; i<5; i++) {
      _clouds.add(AaCloud(x:_rng.nextDouble()*W, y:25+_rng.nextDouble()*110,
          r:26+_rng.nextDouble()*20, speed:7+_rng.nextDouble()*11, alpha:0.65+_rng.nextDouble()*0.3));
    }

    _state = _AaState.levelIntro;
    WakeLock.acquire();
  }

  void _startPlaying() {
    SoundPlayer.i.uiConfirm();
    _state = _AaState.playing;
    if (_isMulti && _net.isHost) {
      _net.send('AAI_START', {'level': _currentLevel});
    }
  }

  // ── Update loop ────────────────────────────────────────────────────────────
  void _update(double dt) {
    final lv = kAaisyLevels[_currentLevel];
    _gameTime += dt;

    // ── Client-only: visual-only updates (no game logic) ──────────────────
    if (_isMulti && !_net.isHost) {
      // Rain animation
      if (_rainActive) {
        _rainIntensity = math.min(1, _rainIntensity+dt*0.4);
        for (final d in _rainDrops) {
          d.y += d.speed*dt; d.x -= d.speed*0.18*dt;
          if (d.y > H+20) { d.y=-10; d.x=_rng.nextDouble()*(W+100)-50; }
        }
      } else {
        _rainIntensity = math.max(0, _rainIntensity-dt*0.5);
      }
      // Animate kievit wings locally (positions come from tick)
      for (final k in _kievits) k.wingPhase += dt*2.8;
      // Animate boswachter walk phase locally
      for (final b in _boswachters) b.walkPhase += dt*4;
      // Clouds, particles, texts, hatching birds
      for (final c in _clouds) { c.x += c.speed*dt; if (c.x > W+100) c.x=-100; }
      _particles.removeWhere((p) {
        p.x+=p.vx*dt; p.y+=p.vy*dt; p.vy+=80*dt; p.life-=p.decay*dt; return p.life<=0;
      });
      _floatingTexts.removeWhere((ft) { ft.y+=ft.vy*dt; ft.life-=dt; return ft.life<=0; });
      _hatchingBirds.removeWhere((b) {
        b.x+=b.vx*dt; b.y+=b.vy*dt; b.vy-=28*dt; b.wingPhase+=dt*(b.isJackdaw?14:10); b.life-=dt; return b.life<=0;
      });
      // Bob phases for both players
      if (_player != null) _player!.bobPhase += dt*8;
      if (_player2 != null) _player2!.bobPhase += dt*8;
      // Lerp player positions toward host-authoritative targets (removes 15Hz snap jitter)
      const double lerpSpeed = 25.0; // 30Hz ticks at 60fps ≈ 2 frames to converge
      final t = (lerpSpeed * dt).clamp(0.0, 1.0);
      if (_targetSet && _player != null) {
        _player!.x += (_targetX - _player!.x) * t;
        _player!.y += (_targetY - _player!.y) * t;
      }
      if (_target2Set && _player2 != null) {
        _player2!.x += (_target2X - _player2!.x) * t;
        _player2!.y += (_target2Y - _player2!.y) * t;
      }
      if (_timeBonusFlash > 0) _timeBonusFlash = (_timeBonusFlash-0.04).clamp(0,1);
      if (_screenShake > 0.3) _screenShake *= 0.78; else _screenShake = 0;
      // Send joystick to host every frame — input is tiny (2 floats) and local WiFi can handle it
      _net.send('AAI_INPUT', {'dx': _joystick.dx, 'dy': _joystick.dy});
      // Throttle only the world snapshot (host side)
      _netTickTimer = (_netTickTimer + dt).clamp(0.0, _netTickRate * 2);
      return; // ← client skips all simulation below
    }

    // ── Host (and solo) simulation ────────────────────────────────────────

    // Time management
    if (_timeBonusActive) {
      final drain = math.min(_timeBonusRemaining, _timeBonusSpeed*dt);
      _timeBonusRemaining -= drain;
      _timeLeft = _timeBonusRemaining;
      final pts = drain*10;
      if (pts >= 1) {
        _score += pts.round();
        // Both players earn the full shared time bonus (winner stays decided by eggs)
        if (_isMulti) _score2 += pts.round();
      }
      if (_timeBonusRemaining <= 0) {
        _timeBonusActive = false;
        _heartItems.clear();
        _totalScore += _score;
        if (_isMulti) _totalScore2 += _score2;
        if (_currentLevel >= kAaisyLevels.length-1) {
          _state = _AaState.won;
          // Level scores are now folded into the totals — clear them so the
          // win screen (which shows total+score) doesn't count the last level twice
          _score = 0; _score2 = 0;
          SoundPlayer.i.gameWin();
          _saveBest(_totalScore);
          if (_isMulti) {
            // Final level: tell the joiner the game is won, with authoritative totals
            if (_net.isHost) {
              _net.send('AAI_LEVEL_DONE', {
                'next': kAaisyLevels.length,
                'ts1': _totalScore, 'ts2': _totalScore2,
              });
            }
            final myIdx  = _net.myIdx.clamp(0, widget.players.length - 1);
            final oppIdx = myIdx == 0 ? 1 : 0;
            final myTotal  = _totalScore;
            final oppTotal = _totalScore2;
            final winnerIdx = myTotal > oppTotal ? myIdx
                            : oppTotal > myTotal ? oppIdx : -1;
            fireConfettiOnce(winnerIdx);
            recordResult('aaisykje', winnerIdx);
            if (_net.isHost) SessionState().advanceGame();
          } else {
            fireConfettiOnce(0); // solo win — player 0
            recordResult('aaisykje', 0);
          }
        } else {
          _startLevelComplete(_currentLevel+1);
        }
        return;
      }
    } else {
      _timeLeft -= dt;
      if (_timeLeft <= 0) { _endGame(); return; }
    }

    // Time bonus flash drain
    if (_timeBonusFlash > 0) _timeBonusFlash = (_timeBonusFlash-0.04).clamp(0,1);

    // Time egg spawn
    if (!_timeBonusActive && !_timeEggSpawned && lv.eggTarget >= 3) {
      _timeEggTimer -= dt;
      if (_timeEggTimer <= 0) {
        _timeEggSpawned = true;
        final pos = _safePos(80, W-80);
        _eggs_.add(AaEgg(x:pos.x, y:pos.y, type:EggType.timeEgg));
        _spawnParticles(pos.x, pos.y-8, const Color(0xFF44CCFF), 10);
        _addFloatingText(pos.x, pos.y-20, '+10s…', const Color(0xFF44CCFF));
      }
    }

    // Surprise egg spawn
    if (!_timeBonusActive && !_surpriseEggSpawned) {
      _surpriseEggTimer -= dt;
      if (_surpriseEggTimer <= 0) {
        _surpriseEggSpawned = true;
        const types = AaPowerup.values;
        final stype = types[_rng.nextInt(types.length)];
        final pos = _safePos(80, W-80);
        _eggs_.add(AaEgg(x:pos.x, y:pos.y, type:EggType.surprise, powerup:stype));
        _spawnParticles(pos.x, pos.y-8, _powerupColor(stype), 12);
        _addFloatingText(pos.x, pos.y-22, '✨', Colors.white);
      }
    }

    // Tick active powerup
    if (_activePowerup != null) {
      _powerupTimer -= dt;
      if (_powerupTimer <= 0) _deactivatePowerup();
    }
    if (_isMulti && _activePowerup2 != null) {
      _powerupTimer2 -= dt;
      if (_powerupTimer2 <= 0) _deactivatePowerup2();
    }

    // Rain
    if (_rainActive) {
      _rainIntensity = math.min(1, _rainIntensity+dt*0.4);
      for (final d in _rainDrops) {
        d.y += d.speed*dt; d.x -= d.speed*0.18*dt;
        if (d.y > H+20) { d.y=-10; d.x=_rng.nextDouble()*(W+100)-50; }
      }
    } else {
      _rainIntensity = math.max(0, _rainIntensity-dt*0.5);
    }

    _comboTimer -= dt;
    if (_comboTimer <= 0) _combo = 1;
    if (_isMulti) {
      _comboTimer2 -= dt;
      if (_comboTimer2 <= 0) _combo2 = 1;
    }

    // Player movement (host authoritative for both)
    if (_player != null) _updatePlayer(dt, lv);
    if (_isMulti && _player2 != null) {
      _updatePlayerWith(dt, lv, _player2!, _remoteJoystick, _activePowerup2);
    }

    // Birds
    _updateBirds(dt);

    // Magnet
    if (_activePowerup == AaPowerup.magnet) {
      for (final e in _eggs_) {
        if (e.type != EggType.normal) continue;
        final mdx=_player!.x-e.x, mdy=_player!.y-e.y;
        final mdist=math.sqrt(mdx*mdx+mdy*mdy);
        if (mdist<160 && mdist>1) {
          final pull=(160-mdist)/160*90*dt;
          e.x += (mdx/mdist)*pull; e.y += (mdy/mdist)*pull;
        }
      }
    }
    if (_isMulti && _activePowerup2 == AaPowerup.magnet && _player2 != null) {
      for (final e in _eggs_) {
        if (e.type != EggType.normal) continue;
        final mdx=_player2!.x-e.x, mdy=_player2!.y-e.y;
        final mdist=math.sqrt(mdx*mdx+mdy*mdy);
        if (mdist<160 && mdist>1) {
          final pull=(160-mdist)/160*90*dt;
          e.x += (mdx/mdist)*pull; e.y += (mdy/mdist)*pull;
        }
      }
    }

    // Egg timers + collection
    _updateEggs(dt, lv);

    // Heart pickups
    _updateHearts(dt);

    // Boswachter collision
    _updateBwCollision();

    // Cows
    _updateCows(dt);

    // Horizon scroll
    if (_horizonScrolling) _updateHorizonScroll(dt);

    // Clouds + particles + floating texts
    for (final c in _clouds) { c.x += c.speed*dt; if (c.x > W+100) c.x=-100; }
    _particles.removeWhere((p) {
      p.x+=p.vx*dt; p.y+=p.vy*dt; p.vy+=80*dt; p.life-=p.decay*dt; return p.life<=0;
    });
    _floatingTexts.removeWhere((ft) { ft.y+=ft.vy*dt; ft.life-=dt; return ft.life<=0; });
    _hatchingBirds.removeWhere((b) {
      b.x+=b.vx*dt; b.y+=b.vy*dt; b.vy-=28*dt; b.wingPhase+=dt*(b.isJackdaw?14:10); b.life-=dt; return b.life<=0;
    });

    if (_screenShake > 0.3) _screenShake *= 0.78; else _screenShake = 0;

    // Network tick — host broadcasts world snapshot at 30 Hz
    if (_isMulti && _net.isHost) {
      _netTickTimer += dt;
      if (_netTickTimer >= _netTickRate) {
        _netTickTimer = 0;
        _broadcastTick();
      }
    }
  }

  void _updatePlayer(double dt, AaisykjeLevel lv) =>
      _updatePlayerWith(dt, lv, _player!, _joystick, _activePowerup);

  void _updatePlayerWith(double dt, AaisykjeLevel lv, AaPlayer p, Offset joy, AaPowerup? powerup) {
    var dx = joy.dx, dy = joy.dy;
    final inputLen = math.sqrt(dx*dx+dy*dy);
    if (inputLen > 0.05) {
      final norm = inputLen > 1 ? inputLen : 1;
      final spMult = powerup==AaPowerup.speed ? 2.0 : 1.0;
      p.vx = (dx/norm)*p.speed*spMult;
      p.vy = (dy/norm)*p.speed*spMult;
      if (dx != 0) p.dir = dx>0?1:-1;
    } else { p.vx*=0.82; p.vy*=0.82; }

    p.x = (p.x+p.vx*dt).clamp(24, W-24);
    p.y = (p.y+p.vy*dt).clamp(groundY, H-24);

    // Ditch crossing → teleport + jump arc
    if (!p.jumping) {
      for (final ditchY in [ditch1, ditch2]) {
        if ((p.y-ditchY).abs() < kDitchHalfW) {
          p.y = ditchY + (p.vy>=0 ? kDitchHalfW+1 : -(kDitchHalfW+1));
          p.jumping=true; p.jumpZ=0; p.jumpVz=52;
          break;
        }
      }
    }
    if (p.jumping) {
      p.jumpVz -= 400*dt; p.jumpZ += p.jumpVz*dt;
      if (p.jumpZ<=0 && p.jumpVz<0) { p.jumpZ=0; p.jumpVz=0; p.jumping=false; }
    }
    if (!p.jumping) _resolveTreeCollision(p);
    p.bobPhase += dt*8;
    if (p.invincible>0) p.invincible-=dt;
  }

  void _updateBirds(double dt) {
    double maxWarning = 0;
    for (final b in _boswachters) {
      b.walkPhase += dt*(_timeBonusActive||_activePowerup==AaPowerup.freeze||(_isMulti&&_activePowerup2==AaPowerup.freeze)?0:4);
      if (_timeBonusActive||_activePowerup==AaPowerup.freeze||(_isMulti&&_activePowerup2==AaPowerup.freeze)) { b.vx=0; b.vy=0; continue; }
      if (b.stunned>0) { b.stunned-=dt; b.vx=0; b.vy=0; continue; }
      if (b.cowCooldown>0) b.cowCooldown-=dt;

      // Target refresh
      b.targetTimer -= dt;
      if (b.targetTimer<=0) {
        b.targetTimer=2;
        if (!b.targetPlayer && _eggs_.isNotEmpty) {
          final bwList = _boswachters.where((x)=>!x.targetPlayer).toList();
          final bwIdx = bwList.indexOf(b);
          final sorted = [..._eggs_]..sort((a,e2)=>(
              (a.x-b.x)*(a.x-b.x)+(a.y-b.y)*(a.y-b.y))
              .compareTo((e2.x-b.x)*(e2.x-b.x)+(e2.y-b.y)*(e2.y-b.y)));
          b.targetEgg = sorted[bwIdx % sorted.length];
        }
      }

      double tgx=_player!.x, tgy=_player!.y;
      // Odd-indexed boswachters target player2 in multiplayer
      final targetsP2 = _isMulti && _player2 != null && !b.targetPlayer;
      if (targetsP2) {
        // Check if this bw index is odd (p2 hunter)
        final bwIdx = _boswachters.indexOf(b);
        if (bwIdx.isOdd) { tgx = _player2!.x; tgy = _player2!.y; }
      }
      if (!targetsP2 && !b.targetPlayer && _eggs_.isNotEmpty) {
        if (b.targetEgg != null && _eggs_.contains(b.targetEgg)) {
          tgx=b.targetEgg!.x; tgy=b.targetEgg!.y;
        } else {
          AaEgg? best; double bestD=1e9;
          for (final e in _eggs_) {
            final dd=(e.x-b.x)*(e.x-b.x)+(e.y-b.y)*(e.y-b.y);
            if (dd<bestD){bestD=dd; best=e;}
          }
          if (best!=null){tgx=best.x; tgy=best.y;}
        }
      }

      final ddx=tgx-b.x, ddy=tgy-b.y;
      final d=math.sqrt(ddx*ddx+ddy*ddy);
      b.stuckAcc += dt;
      b.slideTimer = math.max(0, b.slideTimer-dt);
      if (b.stuckAcc>=0.6) {
        final progress=(b.lastD)-d;
        if (progress<2) {
          b.slideSign = b.slideTimer>0 ? b.slideSign : (_rng.nextBool()?1:-1);
          b.slideTimer=0.3;
        }
        b.lastD=d; b.stuckAcc=0;
      }

      double mvx, mvy;
      if (b.slideTimer>0 && d>60) {
        final dn=d==0?1:d;
        mvx = -(ddy/dn)*b.slideSign;
        mvy =  (ddx/dn)*b.slideSign.toDouble()*0.6;
      } else {
        mvx = d>2?ddx/d:0;
        mvy = d>2?ddy/d*0.55:0;
      }
      b.vx=mvx*b.speed; b.vy=mvy*b.speed;
      b.x=(b.x+b.vx*dt).clamp(28,W-28);
      b.y=(b.y+b.vy*dt).clamp(H*0.62,H*0.92);
      _resolveTreeCollisionBw(b);
      b.dir=b.vx>=0?1:-1;
      final dist=math.sqrt((_player!.x-b.x)*(_player!.x-b.x)+(_player!.y-b.y)*(_player!.y-b.y));
      double closestDist = dist;
      if (_isMulti && _player2 != null) {
        final d2=math.sqrt((_player2!.x-b.x)*(_player2!.x-b.x)+(_player2!.y-b.y)*(_player2!.y-b.y));
        closestDist = math.min(dist, d2);
      }
      final w=closestDist<160?math.max(0.0,(160-closestDist)/160):0.0;
      if (w>maxWarning) maxWarning=w;
    }
    _forestKeeperWarning=maxWarning;

    // Kievits
    for (final k in _kievits) {
      k.wingPhase += dt*2.8;
      if (k.layState==KievitState.cruise) {
        k.layTimer -= dt;
        k.vy += math.sin(k.wingPhase*0.4)*12*dt; k.vy*=0.97;
        if (_rng.nextDouble()<0.008) k.vx=(_rng.nextDouble()-0.5)*k.speed*2;
        k.dir=k.vx>=0?1:-1;
        if (k.y>H*0.38) k.vy-=60*dt;
        if (k.y<H*0.1)  k.vy+=40*dt;
        if (k.layTimer<=0) { k.layState=KievitState.dive; k.laidThisSwoop=false; k.vx*=0.5; SoundPlayer.i.aaisykjeKievit(); }
      } else if (k.layState==KievitState.dive) {
        k.vy+=320*dt; k.vy=k.vy.clamp(double.negativeInfinity,300);
        k.dir=k.vx>=0?1:-1;
        if (k.y>=groundY-10 && !k.laidThisSwoop && !_timeBonusActive) {
          k.laidThisSwoop=true;
          final pos=safePosOnGround(_rng, math.max(60,k.x-80), math.min(W-60,k.x+80),
              groundY, H, _trees, _cows, ditch1, ditch2);
          final isDecoy=_rng.nextDouble()<(1/6);
          _eggs_.add(AaEgg(x:pos.x, y:pos.y, type:isDecoy?EggType.decoy:EggType.normal));
          _spawnParticles(pos.x, pos.y-8, isDecoy?const Color(0xFF8A9440):const Color(0xFFFFE566), 6);
          k.layState=KievitState.climb; k.vy=-220;
        }
      } else if (k.layState==KievitState.climb) {
        k.vy -= 180*dt; k.dir=k.vx>=0?1:-1;
        if (k.y<=H*0.28) {
          k.layState=KievitState.cruise;
          k.layTimer=(k.layMin+_rng.nextDouble()*(k.layMax-k.layMin));
          k.vy=0;
        }
      }
      k.x=k.x+k.vx*dt;
      if (k.x<=40||k.x>=W-40) k.vx*=-1;
      k.x=k.x.clamp(40,W-40);
      final minY=k.layState==KievitState.cruise?H*0.08:H*0.06;
      k.y=math.max(minY, k.y+k.vy*dt);
    }
  }

  void _updateEggs(double dt, AaisykjeLevel lv) {
    final toHatch = <AaEgg>[];
    _eggs_.removeWhere((e) {
      e.timer += dt;
      final p=_player;
      if (p==null) return false;
      final ddx=p.x-e.x, ddy=p.y-e.y;
      if (math.sqrt(ddx*ddx+ddy*ddy)<26) {
        _collectEgg(e, lv, byP2: false);
        return true;
      }
      // Player 2 collection (host authoritative)
      if (_isMulti && _net.isHost && _player2 != null) {
        final d2x=_player2!.x-e.x, d2y=_player2!.y-e.y;
        if (math.sqrt(d2x*d2x+d2y*d2y)<26) {
          _collectEgg(e, lv, byP2: true);
          return true;
        }
      }
      // Surprise + time eggs expire after 25s
      if ((e.type==EggType.surprise||e.type==EggType.timeEgg) && e.timer>=25) {
        _spawnParticles(e.x, e.y, e.type==EggType.timeEgg?const Color(0xFF44CCFF):_powerupColor(e.powerup!), 8);
        return true;
      }
      if (e.type==EggType.normal||e.type==EggType.decoy) {
        if (e.timer>=lv.hatchTime) { toHatch.add(e); return true; }
      }
      return false;
    });

    for (final e in toHatch) {
      if (e.type==EggType.decoy) {
        _spawnParticles(e.x,e.y,const Color(0xFF444466),14);
        _addFloatingText(e.x,e.y-28,L.aaisykje.decoy.replaceAll('{n}','0'),const Color(0xFF8888CC));
        _hatchingBirds.add(AaHatchingBird(x:e.x,y:e.y,
            vx:(_rng.nextBool()?1:-1)*(90+_rng.nextDouble()*60),vy:-140-_rng.nextDouble()*60,isJackdaw:true));
      } else {
        _score=math.max(0,_score-lv.eggPenalty); _combo=1;
        _spawnParticles(e.x,e.y,const Color(0xFFA0D860),18);
        _addFloatingText(e.x,e.y-28,L.aaisykje.hatched.replaceAll('{n}','${lv.eggPenalty}'),const Color(0xFFFF8844));
        _hatchingBirds.add(AaHatchingBird(x:e.x,y:e.y,
            vx:(_rng.nextDouble()-0.5)*130,vy:-100-_rng.nextDouble()*50,isJackdaw:false));
      }
    }

    // Deferred clear: _startTimeBonus can't call _eggs_.clear() while removeWhere
    // is iterating, so we do it here after iteration is complete.
    if (_timeBonusActive && _eggs_.isNotEmpty) {
      _eggs_.clear();
    }
  }

  void _collectEgg(AaEgg e, AaisykjeLevel lv, {bool byP2 = false}) {
    final idx = _isMulti && _net.isHost ? _eggs_.indexOf(e) : -1;
    // Apply collection locally first so scores are current
    if (byP2) {
      _collectEggForPlayer2(e, lv);
    } else {
      _collectEggForPlayer1(e, lv);
    }
    // Then broadcast updated state to client
    if (_isMulti && _net.isHost && idx >= 0) {
      _net.send('AAI_EGG_COLLECTED', {
        'idx': idx, 'p2': byP2,
        'score': _score, 'score2': _score2,
        'eggs': _eggs, 'eggs2': _eggs2,
        'combo': _combo, 'combo2': _combo2,
      });
    }
  }

  void _collectEggForPlayer1(AaEgg e, AaisykjeLevel lv) {
    switch (e.type) {
      case EggType.timeEgg:
        _timeLeft = math.min(_timeLeft+10, lv.duration.toDouble());
        _spawnParticles(e.x,e.y,const Color(0xFF44CCFF),18);
        _addFloatingText(e.x,e.y-20,L.aaisykje.timePlus,const Color(0xFF44CCFF));
        SoundPlayer.i.aaisykjeTimeEgg();
        break;
      case EggType.decoy:
        _score=math.max(0,_score-15); _combo=1; _comboTimer=0;
        _spawnParticles(e.x,e.y,const Color(0xFFAA4400),14);
        _addFloatingText(e.x,e.y-20,L.aaisykje.decoy,const Color(0xFFFF6633));
        _screenShake=5;
        SoundPlayer.i.aaisykjeDecoy();
        break;
      case EggType.surprise:
        _activatePowerup(e.powerup!);
        _spawnParticles(e.x,e.y,_powerupColor(e.powerup!),20);
        _addFloatingText(e.x,e.y-22,_powerupLabel(e.powerup!),_powerupColor(e.powerup!));
        SoundPlayer.i.aaisykjePowerup();
        break;
      case EggType.normal:
        _eggs++; _combo++; _comboTimer=3;
        final pts=10*_combo; _score+=pts;
        _spawnParticles(e.x,e.y,const Color(0xFFFFE566),14);
        _addFloatingText(e.x,e.y-20,_combo>1?'x$_combo +$pts':'+$pts',const Color(0xFFFFE566));
        if (_combo>1) SoundPlayer.i.aaisykjeCombo(); else SoundPlayer.i.aaisykjePickup();
        if ((_eggs+_eggs2)>=lv.eggTarget && !_timeBonusActive) _startTimeBonus();
        break;
    }
  }

  void _collectEggForPlayer2(AaEgg e, AaisykjeLevel lv) {
    switch (e.type) {
      case EggType.timeEgg:
        _timeLeft = math.min(_timeLeft+10, lv.duration.toDouble());
        _spawnParticles(e.x,e.y,const Color(0xFF44CCFF),18);
        _addFloatingText(e.x,e.y-20,L.aaisykje.timePlus,const Color(0xFF44CCFF));
        SoundPlayer.i.aaisykjeTimeEgg();
        break;
      case EggType.decoy:
        _score2=math.max(0,_score2-15); _combo2=1; _comboTimer2=0;
        _spawnParticles(e.x,e.y,const Color(0xFFAA4400),14);
        _addFloatingText(e.x,e.y-20,L.aaisykje.decoy,const Color(0xFFFF6633));
        _screenShake=5;
        SoundPlayer.i.aaisykjeDecoy();
        break;
      case EggType.surprise:
        _activatePowerup2(e.powerup!);
        _spawnParticles(e.x,e.y,_powerupColor(e.powerup!),20);
        _addFloatingText(e.x,e.y-22,_powerupLabel(e.powerup!),_powerupColor(e.powerup!));
        SoundPlayer.i.aaisykjePowerup();
        break;
      case EggType.normal:
        _eggs2++; _combo2++; _comboTimer2=3;
        final pts=10*_combo2; _score2+=pts;
        _spawnParticles(e.x,e.y,const Color(0xFF44CCFF),14);
        _addFloatingText(e.x,e.y-20,_combo2>1?'x$_combo2 +$pts':'+$pts',const Color(0xFF44CCFF));
        if (_combo2>1) SoundPlayer.i.aaisykjeCombo(); else SoundPlayer.i.aaisykjePickup();
        if ((_eggs+_eggs2)>=lv.eggTarget && !_timeBonusActive) _startTimeBonus();
        break;
    }
  }

  void _updateHearts(double dt) {
    if (_timeBonusActive) {
      _heartItems.removeWhere((h) {
        h.bob += dt*3;
        // Check P1
        if (_player != null) {
          final ddx=_player!.x-h.x, ddy=_player!.y-h.y;
          if (math.sqrt(ddx*ddx+ddy*ddy)<28) {
            if (_lives<5) {
              _lives++;
              _spawnParticles(h.x,h.y,const Color(0xFFFF4466),14);
              _addFloatingText(h.x,h.y-20,'+1 ♥',const Color(0xFFFF4466));
            } else {
              _score+=100;
              _spawnParticles(h.x,h.y,const Color(0xFFFFE566),10);
              _addFloatingText(h.x,h.y-20,'+100',const Color(0xFFFFE566));
            }
            return true;
          }
        }
        // Check P2 (host authoritative)
        if (_isMulti && _net.isHost && _player2 != null) {
          final ddx=_player2!.x-h.x, ddy=_player2!.y-h.y;
          if (math.sqrt(ddx*ddx+ddy*ddy)<28) {
            if (_lives2<5) {
              _lives2++;
              _spawnParticles(h.x,h.y,const Color(0xFFFF4466),14);
              _addFloatingText(h.x,h.y-20,'+1 ♥',const Color(0xFFFF4466));
            } else {
              _score2+=100;
              _spawnParticles(h.x,h.y,const Color(0xFFFFE566),10);
              _addFloatingText(h.x,h.y-20,'+100',const Color(0xFFFFE566));
            }
            return true;
          }
        }
        return false;
      });
    } else {
      _heartItems.clear();
    }
  }

  void _updateBwCollision() {
    for (final b in _boswachters) {
      if (_player!=null && _player!.invincible<=0 && _activePowerup!=AaPowerup.ghost) {
        final ddx=_player!.x-b.x, ddy=_player!.y-b.y;
        if (math.sqrt(ddx*ddx+ddy*ddy)<38) {
          _hitPlayerByBw(b, isP2: false);
        }
      }
      // Check player 2 (host authoritative)
      if (_isMulti && _net.isHost && _player2!=null && _player2!.invincible<=0 && _activePowerup2!=AaPowerup.ghost) {
        final ddx=_player2!.x-b.x, ddy=_player2!.y-b.y;
        if (math.sqrt(ddx*ddx+ddy*ddy)<38) {
          _hitPlayerByBw(b, isP2: true);
        }
      }
    }
  }

  void _hitPlayerByBw(AaBoswachter b, {required bool isP2}) {
    final p = isP2 ? _player2! : _player!;
    final shield = isP2 ? _activePowerup2==AaPowerup.shield : _activePowerup==AaPowerup.shield;
    if (shield) {
      final ba=math.atan2(b.y-p.y, b.x-p.x);
      b.vx=math.cos(ba)*180; b.vy=math.sin(ba)*140;
      _spawnParticles(p.x,p.y,const Color(0xFFFFD700),12);
      _addFloatingText(p.x,p.y-30,'🛡️',const Color(0xFFFFD700));
      _screenShake=3;
    } else {
      if (isP2) {
        _lives2=math.max(0,_lives2-1); _combo2=1;
      } else {
        _lives=math.max(0,_lives-1); _combo=1;
      }
      p.invincible=2;
      _spawnParticles(p.x,p.y,const Color(0xFFFF6060),16);
      _screenShake=9;
      SoundPlayer.i.aaisykjeBoswachter();
      final lives = isP2 ? _lives2 : _lives;
      _addFloatingText(p.x,p.y-30,'♥ $lives over!',const Color(0xFFFF4444));
      // Game over only when both players are out of lives
      final bothDead = _lives<=0 && (!_isMulti || _lives2<=0);
      if (bothDead) { _endGame(); return; }
      // If only one player is dead, keep going (they're a ghost spectator)
      if (!isP2 && _lives<=0) { _player!.invincible=9999; }
      if (isP2 && _lives2<=0) { _player2!.invincible=9999; }
    }
  }

  void _updateCows(double dt) {
    for (final cow in _cows) {
      cow.walkPhase += dt*(0.8+cow.vx.abs()*0.12);
      cow.wanderTimer -= dt;
      if (cow.wanderTimer<=0) {
        cow.vx=(_rng.nextDouble()-0.5)*38;
        cow.vy=(_rng.nextDouble()-0.5)*10;
        if (cow.vx!=0) cow.dir=cow.vx>0?1:-1;
        cow.wanderTimer=1.2+_rng.nextDouble()*2.5;
      }
      // Push away from players
      if (_player!=null) {
        final cdx=cow.x-_player!.x, cdy=cow.y-_player!.y;
        final cdist=math.sqrt(cdx*cdx+cdy*cdy);
        if (cdist<55&&cdist>1) {
          final push=(55-cdist)/55*7;
          cow.vx+=(cdx/cdist)*push*dt*60;
          cow.vy+=(cdy/cdist)*push*dt*60;
          if (cow.vx!=0) cow.dir=cow.vx>0?1:-1;
        }
      }
      if (_isMulti && _player2!=null) {
        final cdx=cow.x-_player2!.x, cdy=cow.y-_player2!.y;
        final cdist=math.sqrt(cdx*cdx+cdy*cdy);
        if (cdist<55&&cdist>1) {
          final push=(55-cdist)/55*7;
          cow.vx+=(cdx/cdist)*push*dt*60;
          cow.vy+=(cdy/cdist)*push*dt*60;
          if (cow.vx!=0) cow.dir=cow.vx>0?1:-1;
        }
      }
      // Don't stomp eggs
      for (final egg in _eggs_) {
        final edx=cow.x-egg.x, edy=cow.y-egg.y;
        final edist=math.sqrt(edx*edx+edy*edy);
        if (edist<kCowCollideR+10&&edist>0.5) {
          final ea=math.atan2(edy,edx);
          cow.x=egg.x+math.cos(ea)*(kCowCollideR+10);
          cow.y=egg.y+math.sin(ea)*(kCowCollideR+10);
          cow.vx*=0.1; cow.vy*=0.1;
        }
      }
      if (cow.vx.abs()<2) cow.vx+=(_rng.nextDouble()-0.5)*3;
      cow.vx*=0.92; cow.vy*=0.92;
      final nx=(cow.x+cow.vx*dt).clamp(40.0,W-40);
      final ny=(cow.y+cow.vy*dt).clamp(groundY+10,H-30);
      if (!_isInDitch(ny.toDouble())) { cow.x=nx.toDouble(); cow.y=ny.toDouble(); }
      else { cow.vy*=-0.5; }
    }
  }

  // ── Horizon scroll ─────────────────────────────────────────────────────────
  void _startLevelComplete(int nextLvIdx) {
    _state = _AaState.levelComplete;
    SoundPlayer.i.aaisykjeLevelDone();
    _horizonScrolling = true;
    _horizonScrollDone = false;
    _nextHorizonScene = nextLvIdx % kHorizonScenes.length;
    _horizonOffsetX = 0;
    _horizonScrollSpeed = W/3; // scroll at W pixels/sec for ~3s
    if (_isMulti && _net.isHost) {
      _net.send('AAI_LEVEL_DONE', {
        'next': nextLvIdx,
        'ts1': _totalScore, 'ts2': _totalScore2,
      });
    }
    if (mounted) setState((){});
  }

  void _updateHorizonScroll(double dt) {
    if (!_horizonScrolling) return;
    _horizonOffsetX += _horizonScrollSpeed*dt;
    if (_horizonOffsetX >= W+80) {
      _horizonScrolling = false;
      _horizonScene = _nextHorizonScene;
      _horizonOffsetX = 0;
      if (_state == _AaState.levelComplete && !_horizonScrollDone) {
        _horizonScrollDone = true;
        _currentLevel++;
        _initLevel(_currentLevel);
      }
    }
  }

  // ── Game events ────────────────────────────────────────────────────────────
  void _startTimeBonus() {
    _timeBonusActive = true;
    _timeBonusRemaining = _timeLeft;
    _timeBonusFlash = 1.0;
    _spawnParticles(W/2,H/2,const Color(0xFFFFE566),30);
    _spawnParticles(W/2,H/2,const Color(0xFF66FF99),20);
    _addFloatingText(W/2,H*0.4,L.aaisykje.goalReached.replaceAll('{s}','${_timeLeft.round()}'),const Color(0xFFFFE566));
    _heartItems.addAll(_eggs_.map((e)=>AaHeartItem(x:e.x,y:e.y)));
    // _eggs_.clear() deferred — called after removeWhere finishes in _updateEggs
    if (_isMulti && _net.isHost) {
      _net.send('AAI_BONUS_START', {'time': _timeLeft});
    }
  }

  void _endGame() {
    WakeLock.release();
    _rainActive=false; _rainIntensity=0;
    _state = _AaState.gameOver;
    SoundPlayer.i.gameLoss();
    _saveBest(_totalScore+_score);
    if (_isMulti) {
      // Determine winner by total score
      final myTotal  = _totalScore + _score;
      final oppTotal = _totalScore2 + _score2;
      final myIdx  = _net.myIdx.clamp(0, widget.players.length - 1);
      final oppIdx = myIdx == 0 ? 1 : 0;
      final winnerIdx = myTotal > oppTotal ? myIdx
                      : oppTotal > myTotal ? oppIdx : -1;
      recordResult('aaisykje', winnerIdx);
      if (_net.isHost) {
        _net.send('AAI_GAME_OVER', {
          's1': _score, 's2': _score2,
          'ts1': _totalScore, 'ts2': _totalScore2,
        });
        SessionState().advanceGame();
      }
    } else {
      recordResult('aaisykje', -1); // solo loss
    }
    if (mounted) setState((){});
  }

  void _restartGame() {
    resetConfetti();
    resetStats();
    _currentLevel=0; _totalScore=0; _totalScore2=0;
    _score=0; _lives=5;
    _score2=0; _eggs2=0; _combo2=1; _comboTimer2=0; _lives2=5;
    _horizonScene=0; _horizonOffsetX=0; _horizonScrolling=false;
    _targetSet=false; _target2Set=false;
    _initLevel(0); // must be called explicitly — W!=0 so layout guard won't trigger
    // No AAI_START here: joiner reaches levelIntro via GAME_RESET and only starts
    // playing when the host taps Start (_startPlaying sends AAI_START).
    _state = _AaState.levelIntro;
  }

  // ── Powerup helpers ────────────────────────────────────────────────────────
  void _activatePowerup(AaPowerup type) {
    _activePowerup=type; _powerupTimer=10;
  }
  void _deactivatePowerup() { _activePowerup=null; _powerupTimer=0; }

  void _activatePowerup2(AaPowerup type) {
    _activePowerup2=type; _powerupTimer2=10;
  }
  void _deactivatePowerup2() { _activePowerup2=null; _powerupTimer2=0; }

  /// Broadcast full world snapshot to all clients at ~15 Hz.
  void _broadcastTick() {
    if (_player==null || W==0 || H==0) return;
    final p1 = _player!;
    // All positions transmitted as normalised 0..1 fractions so clients with
    // different screen sizes / orientations can map them to their own W×H.
    List<num> _np(double x, double y, int dir, double inv) =>
        [x/W, y/H, dir, inv];

    final tick = <String,dynamic>{
      'p1': _np(p1.x, p1.y, p1.dir, p1.invincible),
      'kv': _kievits.map((k)=>[k.x/W, k.y/H, k.dir, k.wingPhase]).toList(),
      'bw': _boswachters.map((b)=>[b.x/W, b.y/H, b.dir, b.walkPhase, b.stunned]).toList(),
      'eg': _eggs_.map((e)=>[e.x/W, e.y/H, e.type.index, e.timer]).toList(),
      's1': _score, 's2': _score2,
      'e1': _eggs,  'e2': _eggs2,
      'l1': _lives, 'l2': _lives2,
      't':  _timeLeft,
      'ts1': _totalScore, 'ts2': _totalScore2,
      'pw1': _activePowerup?.index ?? -1,
      'pt1': _powerupTimer,
      'pw2': _activePowerup2?.index ?? -1,
      'pt2': _powerupTimer2,
    };
    if (_player2 != null) {
      tick['p2'] = _np(_player2!.x, _player2!.y, _player2!.dir, _player2!.invincible);
    }
    _net.send('AAI_TICK', tick);
  }

  /// Host: send full game state snapshot to a reconnected client.
  void _sendSync() {
    if (_player == null || W == 0 || H == 0) return;
    List<num> _np(double x, double y, int dir, double inv) => [x/W, y/H, dir, inv];
    final sync = <String,dynamic>{
      'level':  _currentLevel,
      'state':  _state.index,
      'p1':     _np(_player!.x, _player!.y, _player!.dir, _player!.invincible),
      'kv':     _kievits.map((k)=>[k.x/W, k.y/H, k.dir, k.wingPhase]).toList(),
      'bw':     _boswachters.map((b)=>[b.x/W, b.y/H, b.dir, b.walkPhase, b.stunned]).toList(),
      'eg':     _eggs_.map((e)=>[e.x/W, e.y/H, e.type.index, e.timer]).toList(),
      's1': _score,  's2': _score2,
      'e1': _eggs,   'e2': _eggs2,
      'l1': _lives,  'l2': _lives2,
      't':  _timeLeft,
      'ts1': _totalScore, 'ts2': _totalScore2,
      'pw1': _activePowerup?.index ?? -1,
      'pt1': _powerupTimer,
      'pw2': _activePowerup2?.index ?? -1,
      'pt2': _powerupTimer2,
      'bonus': _timeBonusActive,
      'bonusT': _timeBonusRemaining,
    };
    if (_player2 != null) {
      sync['p2'] = _np(_player2!.x, _player2!.y, _player2!.dir, _player2!.invincible);
    }
    _net.send('AAI_SYNC', sync);
  }

  /// Client: re-initialise game state from host's full snapshot after reconnect.
  void _applySync(Map<String,dynamic> msg) {
    if (W == 0 || H == 0) return;
    double dx(num v) => v.toDouble() * W;
    double dy(num v) => v.toDouble() * H;

    final lvIdx = msg['level'] as int? ?? _currentLevel;
    if (lvIdx < kAaisyLevels.length) _currentLevel = lvIdx;

    // Restore state
    final stateIdx = msg['state'] as int? ?? _AaState.playing.index;
    _state = _AaState.values[stateIdx.clamp(0, _AaState.values.length-1)];

    // Ensure player exists (may be null after reconnect)
    final p2raw = msg['p2'] as List?;
    if (p2raw != null) {
      _player ??= AaPlayer(x: dx(p2raw[0] as num), y: dy(p2raw[1] as num));
      _targetX = dx(p2raw[0] as num);
      _targetY = dy(p2raw[1] as num);
      _targetSet = true;
      _player!.dir = p2raw[2] as int? ?? _player!.dir;
      _player!.invincible = (p2raw[3] as num? ?? 0).toDouble();
      _player!.x = _targetX; _player!.y = _targetY;
    }
    final p1raw = msg['p1'] as List?;
    if (p1raw != null) {
      _target2X = dx(p1raw[0] as num);
      _target2Y = dy(p1raw[1] as num);
      _target2Set = true;
      _player2 ??= AaPlayer(x: _target2X, y: _target2Y);
      _player2!.dir = p1raw[2] as int? ?? _player2!.dir;
      _player2!.invincible = (p1raw[3] as num? ?? 0).toDouble();
      _player2!.x = _target2X; _player2!.y = _target2Y;
    }

    // Kievits
    final kv = msg['kv'] as List?;
    if (kv != null) {
      if (_kievits.length != kv.length) {
        _kievits.clear();
        final lv = kAaisyLevels[_currentLevel];
        for (int i=0; i<kv.length; i++) {
          _kievits.add(AaKievit(x:0,y:0,vx:0,speed:lv.kievitSpeed,
              layMin:lv.layMin,layMax:lv.layMax,initialLayTimer:5));
        }
      }
      for (int i=0; i<kv.length && i<_kievits.length; i++) {
        final k = kv[i] as List;
        _kievits[i].x = dx(k[0] as num); _kievits[i].y = dy(k[1] as num);
        _kievits[i].dir = k[2] as int? ?? 1;
        _kievits[i].wingPhase = (k[3] as num? ?? 0).toDouble();
      }
    }

    // Boswachters
    final bw = msg['bw'] as List?;
    if (bw != null) {
      if (_boswachters.length != bw.length) {
        _boswachters.clear();
        final lv = kAaisyLevels[_currentLevel];
        for (int i=0; i<bw.length; i++) {
          _boswachters.add(AaBoswachter(x:0,y:0,speed:lv.bwSpeed,targetPlayer:i.isEven));
        }
      }
      for (int i=0; i<bw.length && i<_boswachters.length; i++) {
        final b = bw[i] as List;
        _boswachters[i].x = dx(b[0] as num); _boswachters[i].y = dy(b[1] as num);
        _boswachters[i].dir = b[2] as int? ?? 1;
        _boswachters[i].walkPhase = (b[3] as num? ?? 0).toDouble();
        _boswachters[i].stunned = (b[4] as num? ?? 0).toDouble();
      }
    }

    // Eggs
    final eg = msg['eg'] as List?;
    if (eg != null) {
      _eggs_.clear();
      for (final e in eg) {
        final el = e as List;
        _eggs_.add(AaEgg(
          x: dx(el[0] as num), y: dy(el[1] as num),
          type: EggType.values[(el[2] as int? ?? 0).clamp(0, EggType.values.length-1)],
        )..timer = (el[3] as num? ?? 0).toDouble());
      }
    }

    // Scores / lives / time
    _score  = msg['s2'] as int? ?? _score;
    _score2 = msg['s1'] as int? ?? _score2;
    _eggs   = msg['e2'] as int? ?? _eggs;
    _eggs2  = msg['e1'] as int? ?? _eggs2;
    _lives  = msg['l2'] as int? ?? _lives;
    _lives2 = msg['l1'] as int? ?? _lives2;
    _timeLeft = (msg['t'] as num? ?? _timeLeft).toDouble();

    // Powerups — same swap as _applyTick: pw2 = client's own, pw1 = opponent
    final pw1 = msg['pw1'] as int? ?? -1;
    _activePowerup2 = pw1 >= 0 ? AaPowerup.values[pw1.clamp(0, AaPowerup.values.length-1)] : null;
    _powerupTimer2  = (msg['pt1'] as num? ?? 0).toDouble();
    final pw2 = msg['pw2'] as int? ?? -1;
    _activePowerup = pw2 >= 0 ? AaPowerup.values[pw2.clamp(0, AaPowerup.values.length-1)] : null;
    _powerupTimer  = (msg['pt2'] as num? ?? 0).toDouble();

    // Time bonus
    _timeBonusActive    = msg['bonus'] as bool? ?? false;
    _timeBonusRemaining = (msg['bonusT'] as num? ?? 0).toDouble();

    // Rebuild static decorations for current W/H
    if (_trees.isEmpty) _trees = buildTrees(W, H, groundY);

    if (mounted) setState(() {});
  }

  Color _powerupColor(AaPowerup t) => switch(t) {
    AaPowerup.ghost  => const Color(0xFFAADDFF),
    AaPowerup.shield => const Color(0xFFFFD700),
    AaPowerup.speed  => const Color(0xFFFFE033),
    AaPowerup.magnet => const Color(0xFFDD88FF),
    AaPowerup.freeze => const Color(0xFF88EEFF),
  };

  String _powerupLabel(AaPowerup t) => switch(t) {
    AaPowerup.ghost  => '👻',
    AaPowerup.shield => '🛡️',
    AaPowerup.speed  => '⚡',
    AaPowerup.magnet => '🧲',
    AaPowerup.freeze => '❄️',
  };

  // ── Geometry helpers ───────────────────────────────────────────────────────
  bool _isInDitch(double y) => isInDitch(y, ditch1, ditch2);

  bool _isInTreeOrCow(double x, double y) =>
      isInTreeList(x, y, _trees, _cows);

  ({double x, double y}) _safePos(double minX, double maxX) =>
      safePosOnGround(_rng, minX, maxX, groundY, H, _trees, _cows, ditch1, ditch2);

  void _resolveTreeCollision(AaPlayer obj) {
    for (final (tx,ty,tsz) in _trees) {
      final r=kTreeCollideR+tsz*0.1;
      final dx=obj.x-tx, dy=obj.y-ty;
      final dist=math.sqrt(dx*dx+dy*dy*0.7);
      if (dist<r) {
        final angle=math.atan2(dy*0.7,dx);
        obj.x=tx+math.cos(angle)*r;
        obj.y=ty+math.sin(angle)/0.7*r;
        obj.vx*=0.3; obj.vy*=0.3;
      }
    }
    for (final cow in _cows) {
      final dx=obj.x-cow.x, dy=obj.y-cow.y;
      final dist=math.sqrt(dx*dx+dy*dy);
      if (dist<kCowCollideR+8) {
        final angle=math.atan2(dy,dx);
        obj.x=cow.x+math.cos(angle)*(kCowCollideR+8);
        obj.y=cow.y+math.sin(angle)*(kCowCollideR+8);
        obj.vx*=0.2; obj.vy*=0.2;
        SoundPlayer.i.aaisykjeMoo();
      }
    }
  }

  void _resolveTreeCollisionBw(AaBoswachter obj) {
    for (final (tx,ty,tsz) in _trees) {
      final r=kTreeCollideR+tsz*0.1;
      final dx=obj.x-tx, dy=obj.y-ty;
      final dist=math.sqrt(dx*dx+dy*dy*0.7);
      if (dist<r) {
        final angle=math.atan2(dy*0.7,dx);
        obj.x=tx+math.cos(angle)*r;
        obj.y=ty+math.sin(angle)/0.7*r;
        obj.vx*=0.3; obj.vy*=0.3;
      }
    }
    for (final cow in _cows) {
      final dx=obj.x-cow.x, dy=obj.y-cow.y;
      final dist=math.sqrt(dx*dx+dy*dy);
      if (dist<kCowCollideR+8) {
        final angle=math.atan2(dy,dx);
        obj.x=cow.x+math.cos(angle)*(kCowCollideR+8);
        obj.y=cow.y+math.sin(angle)*(kCowCollideR+8);
        obj.vx*=0.2; obj.vy*=0.2;
        if (obj.cowCooldown<=0 && _rng.nextDouble()<0.30 && obj.stunned<=0) {
          obj.stunned=0.55+_rng.nextDouble()*0.25;
          obj.cowCooldown=1.5; // won't stun again for 1.5s
          obj.vx=0; obj.vy=0;
        } else {
          // Deflect velocity away from cow so BW slides around
          final nx=dist>0?dx/dist:1.0, ny=dist>0?dy/dist:0.0;
          final dot=obj.vx*nx+obj.vy*ny;
          if (dot<0) { obj.vx-=dot*nx; obj.vy-=dot*ny; }
        }
      }
    }
  }

  // ── Particles / text helpers ───────────────────────────────────────────────
  void _spawnParticles(double x, double y, Color color, int count) {
    for (int i=0; i<count; i++) {
      final a=_rng.nextDouble()*math.pi*2;
      final sp=60+_rng.nextDouble()*120;
      _particles.add(AaParticle(x:x,y:y,vx:math.cos(a)*sp,vy:math.sin(a)*sp-40,
          r:3+_rng.nextDouble()*4, color:color.value, life:1, decay:0.8+_rng.nextDouble()*0.4));
    }
  }

  void _addFloatingText(double x, double y, String text, Color color) {
    _floatingTexts.add(AaFloatingText(x:x,y:y,text:text,color:color.value));
  }

  // ── Joystick ───────────────────────────────────────────────────────────────
  Offset? _joystickCenter;
  Offset? _joystickPointer;

  void _joystickStart(Offset pos) {
    _joystickCenter = pos;
    _joystickPointer = pos;
    _joystick = Offset.zero;
  }

  void _joystickMove(Offset pos) {
    if (_joystickCenter == null) return;
    _joystickPointer = pos;
    final delta = pos - _joystickCenter!;
    const maxR = 60.0;
    final dist = delta.distance;
    if (dist > 0) {
      _joystick = dist > maxR ? (delta/dist) : (delta/maxR);
    }
  }

  void _joystickEnd() {
    _joystickCenter = null; _joystickPointer = null;
    _joystick = Offset.zero;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = L.aaisykje;
    return GameScaffold(
      key: scaffoldKey,
      title: s.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: s.rules,
      child: Column(children: [
        const GameStatusBar(),
        Expanded(child: LayoutBuilder(builder: (ctx, constraints) {
        final newW = constraints.maxWidth;
        final newH = constraints.maxHeight;
        if (W == 0) {
          // First layout: set dimensions and init level next frame
          W = newW; H = newH;
          horizonY = H*0.46; groundY = H*0.60;
          ditch1 = horizonY + (H-horizonY)*0.38;
          ditch2 = horizonY + (H-horizonY)*0.72;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _initLevel(_currentLevel));
          });
        } else if ((newW - W).abs() > 2 || (newH - H).abs() > 2) {
          // Screen rotated / resized while playing — rescale entity positions, never reinit
          final scaleX = newW / W;
          final scaleY = newH / H;
          W = newW; H = newH;
          horizonY = H*0.46; groundY = H*0.60;
          ditch1 = horizonY + (H-horizonY)*0.38;
          ditch2 = horizonY + (H-horizonY)*0.72;
          // Rescale all entity positions proportionally
          void scaleP(AaPlayer? p) { if (p==null) return; p.x*=scaleX; p.y*=scaleY; }
          scaleP(_player); scaleP(_player2);
          for (final k in _kievits) { k.x*=scaleX; k.y*=scaleY; }
          for (final b in _boswachters) { b.x*=scaleX; b.y*=scaleY; }
          for (final e in _eggs_) { e.x*=scaleX; e.y*=scaleY; }
          for (final c in _cows) { c.x*=scaleX; c.y*=scaleY; }
          // Also rescale lerp targets so eggie doesn't jump on next tick
          _targetX*=scaleX; _targetY*=scaleY;
          _target2X*=scaleX; _target2Y*=scaleY;
          _trees = buildTrees(W, H, groundY); // trees are static decorations, just rebuild
        }

        return Stack(children: [
          // ── Canvas ─────────────────────────────────────────────────────────
          GestureDetector(
            onPanStart:  (d) => _joystickStart(d.localPosition),
            onPanUpdate: (d) => _joystickMove(d.localPosition),
            onPanEnd:    (_) => _joystickEnd(),
            onPanCancel: ()  => _joystickEnd(),
            child: CustomPaint(
              size: Size(W, H),
              painter: AaisykjePainter(
                W:W, H:H, groundY:groundY, horizonY:horizonY,
                ditch1:ditch1, ditch2:ditch2, gameTime:_gameTime,
                player: _state==_AaState.playing ? _player : null,
                kievits:_kievits, boswachters:_boswachters,
                eggs:_eggs_, cows:_cows, particles:_particles,
                floatingTexts:_floatingTexts, hatchingBirds:_hatchingBirds,
                hearts:_heartItems, clouds:_clouds, trees:_trees, flowers:_flowers,
                rainDrops:_rainDrops, rainIntensity:_rainIntensity,
                screenShake:_screenShake, forestKeeperWarning:_forestKeeperWarning,
                timeBonusFlash:_timeBonusFlash, timeBonusActive:_timeBonusActive,
                currentHorizonScene:_horizonScene, horizonOffsetX:_horizonOffsetX,
                horizonScrolling:_horizonScrolling, activePowerup:_activePowerup,
                eggsCollected:_eggs+(_isMulti?_eggs2:0),
                eggTarget:_currentLevel<kAaisyLevels.length?kAaisyLevels[_currentLevel].eggTarget:1,
                hatchTime:_currentLevel<kAaisyLevels.length?kAaisyLevels[_currentLevel].hatchTime.toDouble():10,
                timeBonusLabel:s.timeBonus,
                // "My" eggie uses my profile colour; opponent uses theirs.
                playerColor: widget.players.isNotEmpty
                    ? widget.players[_net.myIdx.clamp(0, widget.players.length-1)].color
                    : const Color(0xFFE040FB),
                player2: _state==_AaState.playing ? _player2 : null,
                player2Color: widget.players.length > (_net.myIdx==0?1:0)
                    ? widget.players[_net.myIdx==0?1:0].color
                    : const Color(0xFF00E5FF),
                p2Powerup: _activePowerup2,
              ),
            ),
          ),

          // ── Virtual joystick visualiser ────────────────────────────────────
          if (_joystickCenter != null && _state == _AaState.playing) ...[
            Positioned(
              left: _joystickCenter!.dx - 40,
              top:  _joystickCenter!.dy - 40,
              child: Container(
                width:80, height:80,
                decoration: BoxDecoration(
                  shape:BoxShape.circle,
                  border:Border.all(color:Colors.white30, width:2),
                ),
              ),
            ),
            if (_joystickPointer != null)
              Positioned(
                left: _joystickPointer!.dx - 20,
                top:  _joystickPointer!.dy - 20,
                child: Container(
                  width:40, height:40,
                  decoration: BoxDecoration(
                    shape:BoxShape.circle,
                    color:Colors.white38,
                    border:Border.all(color:Colors.white60,width:1.5),
                  ),
                ),
              ),
          ],

          // ── HUD ────────────────────────────────────────────────────────────
          if (_state == _AaState.playing) _buildHud(s),

          // ── Powerup indicator ─────────────────────────────────────────────
          if (_activePowerup != null && _state == _AaState.playing)
            Positioned(
              top:42, right:8,
              child: Container(
                padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
                decoration:BoxDecoration(
                  color:kCard.withValues(alpha: 0.85),
                  borderRadius:BorderRadius.circular(20),
                  border:Border.all(color:_powerupColor(_activePowerup!),width:2),
                ),
                child:Row(mainAxisSize:MainAxisSize.min, children:[
                  Text(_powerupLabel(_activePowerup!),style:const TextStyle(fontSize:18)),
                  const SizedBox(width:6),
                  Text('${_powerupTimer.ceil()}s',
                    style:TextStyle(color:_powerupColor(_activePowerup!),
                        fontWeight:FontWeight.bold,fontSize:13)),
                ]),
              ),
            ),

          // ── Level intro overlay ────────────────────────────────────────────
          if (_state == _AaState.levelIntro) _buildLevelIntro(s),

          // ── Game over ─────────────────────────────────────────────────────
          if (_state == _AaState.gameOver) _buildGameOver(s),

          // ── Win ───────────────────────────────────────────────────────────
          if (_state == _AaState.won) _buildWin(s),
        ]);
      })),
      ]),
    );
  }

  Widget _buildHud(s) {
    if (_currentLevel >= kAaisyLevels.length) return const SizedBox.shrink();
    final lv = kAaisyLevels[_currentLevel];
    final combinedEggs = _eggs + (_isMulti ? _eggs2 : 0);
    // In multiplayer, _score/_lives = "my" player (local), _score2/_lives2 = opponent.
    // Colours: myIdx=0 → host (players[0]); myIdx=1 → client (players[1]).
    final myColor  = widget.players.isNotEmpty ? widget.players[_net.myIdx.clamp(0, widget.players.length-1)].color : const Color(0xFFE040FB);
    final oppIdx   = _net.myIdx == 0 ? 1 : 0;
    final oppColor = widget.players.length > oppIdx ? widget.players[oppIdx].color : const Color(0xFF00E5FF);
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal:12, vertical:6),
        color: const Color(0xD91A0A1E),
        child: _isMulti
          ? Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[
              // My lives + combo
              Row(children: List.generate(5, (i) => Icon(
                i<_lives ? Icons.favorite : Icons.favorite_border,
                color: i<_lives ? Colors.pinkAccent : Colors.white24, size:14))),
              if (_combo > 1) Text('x$_combo ',
                  style:TextStyle(color:const Color(0xFFFFE566),fontWeight:FontWeight.bold,fontSize:12)),
              Text('$_score',
                  style:TextStyle(color:myColor, fontWeight:FontWeight.bold, fontSize:14)),
              // Centre: eggs + level + timer
              Column(mainAxisSize:MainAxisSize.min, children:[
                Text('$combinedEggs/${lv.eggTarget} 🥚',
                    style:const TextStyle(color:Color(0xFFC8F59A),fontWeight:FontWeight.bold,fontSize:13)),
                Text(s.level.replaceAll('{n}','${_currentLevel+1}') + '  ${_timeLeft.ceil()}s',
                    style:TextStyle(color:_timeLeft<10?Colors.redAccent:Colors.white54, fontSize:11)),
              ]),
              // Opponent score + combo
              Text('$_score2',
                  style:TextStyle(color:oppColor, fontWeight:FontWeight.bold, fontSize:14)),
              if (_combo2 > 1) Text(' x$_combo2',
                  style:TextStyle(color:const Color(0xFFFFE566),fontWeight:FontWeight.bold,fontSize:12)),
              Row(children: List.generate(5, (i) => Icon(
                i<_lives2 ? Icons.favorite : Icons.favorite_border,
                color: i<_lives2 ? Colors.pinkAccent : Colors.white24, size:14))),
            ])
          : Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[
              // Solo HUD (unchanged)
              Row(children: List.generate(5, (i) => Icon(
                i<_lives ? Icons.favorite : Icons.favorite_border,
                color: i<_lives ? Colors.pinkAccent : Colors.white24, size:18))),
              Text('${_eggs}/${lv.eggTarget} 🥚',
                  style:const TextStyle(color:Color(0xFFC8F59A),fontWeight:FontWeight.bold,fontSize:14)),
              Text('x$_combo',
                  style:TextStyle(color:_combo>2?const Color(0xFFFFE566):Colors.white54,
                      fontWeight:FontWeight.bold,fontSize:14)),
              Text('$_score',
                  style:const TextStyle(color:Color(0xFFFFE566),fontWeight:FontWeight.bold,fontSize:14)),
              Text('${_timeLeft.ceil()}s',
                  style:TextStyle(color:_timeLeft<10?Colors.redAccent:Colors.white,
                      fontWeight:FontWeight.bold,fontSize:14)),
              Text(L.aaisykje.level.replaceAll('{n}','${_currentLevel+1}'),
                  style:const TextStyle(color:Color(0xFFC8F59A),fontSize:13)),
            ]),
      ),
    );
  }

  Widget _buildLevelIntro(s) {
    final lv = kAaisyLevels[_currentLevel];
    final lang = L.lang;
    final sub = lang==AppLang.fy?lv.subFy:lang==AppLang.nl?lv.subNl:lv.subEn;
    return Center(child:Container(
      margin:const EdgeInsets.symmetric(horizontal:24),
      padding:const EdgeInsets.all(24),
      decoration:BoxDecoration(
        color:const Color(0xF0100820),
        borderRadius:BorderRadius.circular(20),
        border:Border.all(color:kBorder),
      ),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(s.level.replaceAll('{n}','${_currentLevel+1}'),
            style:const TextStyle(color:kPurple,fontSize:44,fontWeight:FontWeight.bold)),
        const SizedBox(height:4),
        Text(sub,style:const TextStyle(color:kText,fontSize:17,fontWeight:FontWeight.w600)),
        const SizedBox(height:14),
        Container(
          padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
          decoration:BoxDecoration(
            color:Colors.white.withValues(alpha: 0.05),
            borderRadius:BorderRadius.circular(10),
            border:Border.all(color:kBorder.withValues(alpha: 0.5)),
          ),
          child:Column(children:[
            Text(s.collectN(lv.eggTarget),style:const TextStyle(color:kMuted,fontSize:13)),
            const SizedBox(height:2),
            Text('${s.hatchInN(lv.hatchTime)}  ·  ${s.guardsN(lv.numBoswachters)}  ·  ${s.lapwingsN(lv.numKievits)}',
                style:const TextStyle(color:kMuted,fontSize:12)),
          ]),
        ),
        const SizedBox(height:18),
        SizedBox(
          width:double.infinity,
          child: _isMulti && !_net.isHost
            ? Container(
                padding:const EdgeInsets.symmetric(vertical:14),
                child:Row(mainAxisAlignment:MainAxisAlignment.center, children:[
                  const SizedBox(width:16,height:16,
                      child:CircularProgressIndicator(strokeWidth:2,color:kMuted)),
                  const SizedBox(width:10),
                  Text(L.common.waitingForHost,
                      style:const TextStyle(color:kMuted,fontSize:16)),
                ]),
              )
            : ElevatedButton(
                onPressed: () => setState(()=>_startPlaying()),
                style:primaryButton(),
                child:Text('▶  ${L.common.startGame}',
                    style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold,letterSpacing:1)),
              ),
        ),
        if (_bestScore>0) ...[
          const SizedBox(height:10),
          Text('🏆 $_bestScore pts',style:const TextStyle(color:kMuted,fontSize:12)),
        ],
      ]),
    ));
  }

  Widget _buildGameOver(s) {
    final lvIdx = _currentLevel.clamp(0, kAaisyLevels.length-1);
    return Center(child:Container(
      margin:const EdgeInsets.symmetric(horizontal:24),
      padding:const EdgeInsets.all(24),
      decoration:BoxDecoration(
        color:const Color(0xF0100820),
        borderRadius:BorderRadius.circular(20),
        border:Border.all(color:Colors.redAccent.withValues(alpha: 0.5),width:1.5),
      ),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('💀',style:TextStyle(fontSize:40,fontFamilyFallback:['NotoColorEmoji'])),
        const SizedBox(height:4),
        Text(s.gameOver,style:const TextStyle(color:Color(0xFFFF6B6B),fontSize:32,fontWeight:FontWeight.bold)),
        const SizedBox(height:10),
        if (_isMulti) Builder(builder: (_) {
          final myIdx  = _net.myIdx.clamp(0, widget.players.length-1);
          final oppIdx = myIdx == 0 ? 1 : 0;
          final myTotal  = _totalScore+_score;
          final oppTotal = _totalScore2+_score2;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            _buildScoreRow(widget.players[myIdx].color, widget.players[myIdx].name, myTotal,
                isWinner: myTotal > oppTotal),
            const SizedBox(height:4),
            _buildScoreRow(
                widget.players.length>oppIdx ? widget.players[oppIdx].color : const Color(0xFF00E5FF),
                widget.players.length>oppIdx ? widget.players[oppIdx].name  : 'P2',
                oppTotal, isWinner: oppTotal > myTotal),
          ]);
        }) else ...[
          Text(s.eggs.replaceAll('{n}','$_eggs').replaceAll('{t}','${kAaisyLevels[lvIdx].eggTarget}'),
              style:const TextStyle(color:kText,fontSize:16)),
          const SizedBox(height:2),
          Text('${s.level.replaceAll('{n}','${_currentLevel+1}')}  ·  ${_totalScore+_score} pts',
              style:const TextStyle(color:kMuted,fontSize:13)),
          if ((_totalScore+_score)>_bestScore) ...[
            const SizedBox(height:6),
            Text('🌟 ${s.newBest}',style:const TextStyle(color:Color(0xFFFFE566),fontSize:15)),
          ],
        ],
        const SizedBox(height:18),
        _buildOverButtons(s),
      ]),
    ));
  }

  Widget _buildWin(s) {
    return Center(child:Container(
      margin:const EdgeInsets.symmetric(horizontal:24),
      padding:const EdgeInsets.all(24),
      decoration:BoxDecoration(
        color:const Color(0xF0100820),
        borderRadius:BorderRadius.circular(20),
        border:Border.all(color:kPurple.withValues(alpha: 0.6),width:1.5),
      ),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('🏆',style:TextStyle(fontSize:48,fontFamilyFallback:['NotoColorEmoji'])),
        const SizedBox(height:4),
        Text(s.youWon,style:const TextStyle(color:kPurple,fontSize:32,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Text(s.allLevels,style:const TextStyle(color:kText,fontSize:15)),
        const SizedBox(height:8),
        if (_isMulti) Builder(builder: (_) {
          final myIdx  = _net.myIdx.clamp(0, widget.players.length-1);
          final oppIdx = myIdx == 0 ? 1 : 0;
          final myTotal  = _totalScore+_score;
          final oppTotal = _totalScore2+_score2;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            _buildScoreRow(widget.players[myIdx].color, widget.players[myIdx].name, myTotal,
                isWinner: myTotal > oppTotal),
            const SizedBox(height:4),
            _buildScoreRow(
                widget.players.length>oppIdx ? widget.players[oppIdx].color : const Color(0xFF00E5FF),
                widget.players.length>oppIdx ? widget.players[oppIdx].name  : 'P2',
                oppTotal, isWinner: oppTotal > myTotal),
          ]);
        }) else ...[
          Text('${_totalScore+_score} pts',style:const TextStyle(color:Color(0xFFFFE566),fontSize:24,fontWeight:FontWeight.bold)),
          if ((_totalScore+_score)>_bestScore) ...[
            const SizedBox(height:6),
            Text('🌟 ${s.newBest}',style:const TextStyle(color:Color(0xFFFFE566),fontSize:15)),
          ],
        ],
        const SizedBox(height:18),
        _buildOverButtons(s),
      ]),
    ));
  }

  Widget _buildScoreRow(Color color, String name, int score, {required bool isWinner}) {
    return Container(
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
      decoration:BoxDecoration(
        color:isWinner?color.withValues(alpha: 0.12):Colors.transparent,
        borderRadius:BorderRadius.circular(8),
        border:Border.all(color:isWinner?color.withValues(alpha: 0.5):Colors.transparent),
      ),
      child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[
        Row(children:[
          if (isWinner) const Text('🏆 ',style:TextStyle(fontSize:14,fontFamilyFallback:['NotoColorEmoji'])),
          Container(width:10,height:10,decoration:BoxDecoration(color:color,shape:BoxShape.circle)),
          const SizedBox(width:6),
          Text(name,style:TextStyle(color:color,fontWeight:FontWeight.bold,fontSize:14)),
        ]),
        Text('$score pts',style:const TextStyle(color:Color(0xFFFFE566),fontWeight:FontWeight.bold,fontSize:14)),
      ]),
    );
  }

  Widget _buildOverButtons(s) {
    if (_isMulti) {
      // Multiplayer: GameOverActions handles Play Again (host only) → WaitingScreen,
      // and Game Select → WaitingScreen for both.
      return GameOverActions(
        players: widget.players,
        onReset: () => setState(() => _restartGame()),
      );
    }
    // Solo: original buttons
    return Wrap(
      alignment:WrapAlignment.center,
      spacing:12, runSpacing:10,
      children:[
        ElevatedButton.icon(
          onPressed: () => setState(()=>_restartGame()),
          icon:const Text('🔄',style:TextStyle(fontFamilyFallback:['NotoColorEmoji'],fontSize:16)),
          label:Text(L.common.playAgain),
          style:ElevatedButton.styleFrom(
            backgroundColor:kPurple2, foregroundColor:Colors.white,
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
            padding:const EdgeInsets.symmetric(horizontal:18,vertical:10)),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            WakeLock.release();
            final human = widget.players.isNotEmpty ? widget.players[0] : null;
            await _net.reset();
            if (mounted && human != null) Navigator.pushAndRemoveUntil(context,
              fadeScaleRoute(SoloSetupScreen(humanPlayer:human)),(_)=>false);
          },
          icon:const Text('🎮',style:TextStyle(fontFamilyFallback:['NotoColorEmoji'],fontSize:14)),
          label:Text(L.common.gameSelect),
          style:OutlinedButton.styleFrom(
            foregroundColor:kText,
            side:const BorderSide(color:kBorder),
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
            padding:const EdgeInsets.symmetric(horizontal:18,vertical:10)),
        ),
      ],
    );
  }
}
