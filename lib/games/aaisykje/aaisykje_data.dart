import 'dart:math' as math;

// ── Level definitions ─────────────────────────────────────────────────────────
class AaisykjeLevel {
  final int duration;
  final int hatchTime;
  final int numKievits;
  final int numBoswachters;
  final double kievitSpeed;
  final double bwSpeed;
  final int layMin;
  final int layMax;
  final int eggTarget;
  final int eggPenalty;
  final int bwPenalty;
  final String subFy;
  final String subNl;
  final String subEn;

  const AaisykjeLevel({
    required this.duration,
    required this.hatchTime,
    required this.numKievits,
    required this.numBoswachters,
    required this.kievitSpeed,
    required this.bwSpeed,
    required this.layMin,
    required this.layMax,
    required this.eggTarget,
    required this.eggPenalty,
    required this.bwPenalty,
    required this.subFy,
    required this.subNl,
    required this.subEn,
  });
}

const List<AaisykjeLevel> kAaisyLevels = [
  AaisykjeLevel(duration:60, hatchTime:10, numKievits:2, numBoswachters:1, kievitSpeed:60,  bwSpeed:42,  layMin:7,  layMax:11, eggTarget:5,  eggPenalty:10, bwPenalty:20, subFy:'Maitiid op de greide', subNl:'Lente op de wei',       subEn:'Spring in the meadow'),
  AaisykjeLevel(duration:60, hatchTime:9,  numKievits:2, numBoswachters:1, kievitSpeed:65,  bwSpeed:46,  layMin:6,  layMax:10, eggTarget:7,  eggPenalty:12, bwPenalty:22, subFy:'Mear fûgels',         subNl:'Meer vogels',           subEn:'More birds'),
  AaisykjeLevel(duration:60, hatchTime:9,  numKievits:3, numBoswachters:1, kievitSpeed:68,  bwSpeed:50,  layMin:6,  layMax:9,  eggTarget:8,  eggPenalty:14, bwPenalty:25, subFy:'De boswachter wit it', subNl:'De boswachter weet het', subEn:'The keeper knows'),
  AaisykjeLevel(duration:65, hatchTime:8,  numKievits:3, numBoswachters:2, kievitSpeed:70,  bwSpeed:52,  layMin:5,  layMax:9,  eggTarget:10, eggPenalty:15, bwPenalty:25, subFy:'Twa handhavers',      subNl:'Twee handhavers',       subEn:'Two wardens'),
  AaisykjeLevel(duration:65, hatchTime:8,  numKievits:3, numBoswachters:2, kievitSpeed:75,  bwSpeed:54,  layMin:5,  layMax:8,  eggTarget:11, eggPenalty:16, bwPenalty:28, subFy:'Rappe ljipkes',       subNl:'Snelle kieviten',       subEn:'Fast lapwings'),
  AaisykjeLevel(duration:65, hatchTime:7,  numKievits:4, numBoswachters:2, kievitSpeed:78,  bwSpeed:56,  layMin:5,  layMax:8,  eggTarget:12, eggPenalty:18, bwPenalty:28, subFy:'Briedseizoen',        subNl:'Broedseizoen',          subEn:'Breeding season'),
  AaisykjeLevel(duration:70, hatchTime:7,  numKievits:4, numBoswachters:3, kievitSpeed:80,  bwSpeed:58,  layMin:4,  layMax:7,  eggTarget:14, eggPenalty:18, bwPenalty:30, subFy:'Mear bewakers',       subNl:'Meer bewakers',         subEn:'More wardens'),
  AaisykjeLevel(duration:70, hatchTime:6,  numKievits:4, numBoswachters:3, kievitSpeed:82,  bwSpeed:60,  layMin:4,  layMax:7,  eggTarget:15, eggPenalty:20, bwPenalty:30, subFy:'Razendsnel útkomme',  subNl:'Razendsnelle uitkomst', subEn:'Lightning hatch'),
  AaisykjeLevel(duration:70, hatchTime:6,  numKievits:5, numBoswachters:3, kievitSpeed:85,  bwSpeed:62,  layMin:4,  layMax:6,  eggTarget:16, eggPenalty:20, bwPenalty:32, subFy:'Fjouwer ljipkes',     subNl:'Vier kieviten',         subEn:'Four lapwings'),
  AaisykjeLevel(duration:75, hatchTime:6,  numKievits:5, numBoswachters:3, kievitSpeed:88,  bwSpeed:64,  layMin:3,  layMax:6,  eggTarget:18, eggPenalty:22, bwPenalty:32, subFy:'Healwei!',            subNl:'Halverwege!',           subEn:'Halfway!'),
  AaisykjeLevel(duration:75, hatchTime:5,  numKievits:5, numBoswachters:4, kievitSpeed:90,  bwSpeed:66,  layMin:3,  layMax:6,  eggTarget:19, eggPenalty:22, bwPenalty:35, subFy:'Fjouwer bewakers',    subNl:'Vier bewakers',         subEn:'Four wardens'),
  AaisykjeLevel(duration:75, hatchTime:5,  numKievits:6, numBoswachters:4, kievitSpeed:92,  bwSpeed:68,  layMin:3,  layMax:5,  eggTarget:21, eggPenalty:24, bwPenalty:35, subFy:'Koart briedtiid',     subNl:'Korte broedtijd',       subEn:'Short hatch time'),
  AaisykjeLevel(duration:80, hatchTime:5,  numKievits:6, numBoswachters:4, kievitSpeed:94,  bwSpeed:70,  layMin:3,  layMax:5,  eggTarget:22, eggPenalty:24, bwPenalty:38, subFy:'Fiif ljipkes',        subNl:'Vijf kieviten',         subEn:'Five lapwings'),
  AaisykjeLevel(duration:80, hatchTime:4,  numKievits:6, numBoswachters:5, kievitSpeed:96,  bwSpeed:72,  layMin:2,  layMax:5,  eggTarget:24, eggPenalty:26, bwPenalty:38, subFy:'Drok!',               subNl:'Druk!',                 subEn:'Hectic!'),
  AaisykjeLevel(duration:80, hatchTime:4,  numKievits:7, numBoswachters:5, kievitSpeed:98,  bwSpeed:74,  layMin:2,  layMax:4,  eggTarget:25, eggPenalty:26, bwPenalty:40, subFy:'Fiif bewakers',       subNl:'Vijf bewakers',         subEn:'Five wardens'),
  AaisykjeLevel(duration:85, hatchTime:4,  numKievits:7, numBoswachters:5, kievitSpeed:100, bwSpeed:76,  layMin:2,  layMax:4,  eggTarget:27, eggPenalty:28, bwPenalty:40, subFy:'Rap rap rap!',        subNl:'Snel snel snel!',       subEn:'Fast fast fast!'),
  AaisykjeLevel(duration:85, hatchTime:3,  numKievits:8, numBoswachters:5, kievitSpeed:105, bwSpeed:78,  layMin:2,  layMax:4,  eggTarget:28, eggPenalty:28, bwPenalty:42, subFy:'Kaos op de polder',   subNl:'Chaos op de polder',    subEn:'Polder chaos'),
  AaisykjeLevel(duration:85, hatchTime:3,  numKievits:8, numBoswachters:6, kievitSpeed:108, bwSpeed:80,  layMin:2,  layMax:3,  eggTarget:30, eggPenalty:30, bwPenalty:42, subFy:'Kritysk briedtiid',   subNl:'Kritieke broedtijd',    subEn:'Critical hatch time'),
  AaisykjeLevel(duration:90, hatchTime:3,  numKievits:9, numBoswachters:6, kievitSpeed:112, bwSpeed:82,  layMin:2,  layMax:3,  eggTarget:32, eggPenalty:30, bwPenalty:45, subFy:'Maksimale druk',      subNl:'Maximale druk',         subEn:'Maximum pressure'),
  AaisykjeLevel(duration:90, hatchTime:2,  numKievits:10,numBoswachters:6, kievitSpeed:120, bwSpeed:85,  layMin:1,  layMax:3,  eggTarget:35, eggPenalty:32, bwPenalty:48, subFy:'De einstriid!',       subNl:'De eindstrijd!',        subEn:'The final battle!'),
];

// ── Powerup types ─────────────────────────────────────────────────────────────
enum AaPowerup { ghost, shield, speed, magnet, freeze }

// ── Entity state ──────────────────────────────────────────────────────────────
class AaPlayer {
  double x, y, vx, vy;
  double speed;
  double size;
  double bobPhase;
  int dir;            // 1=right, -1=left
  double invincible;  // seconds remaining
  double jumpZ;
  double jumpVz;
  bool jumping;

  AaPlayer({required this.x, required this.y})
      : vx=0, vy=0, speed=185, size=28, bobPhase=0,
        dir=1, invincible=0, jumpZ=0, jumpVz=0, jumping=false;
}

enum KievitState { cruise, dive, climb }

class AaKievit {
  double x, y, vx, vy;
  final double speed;
  double wingPhase;
  int dir;
  final double size;
  KievitState layState;
  double layTimer;
  bool laidThisSwoop;
  final int layMin, layMax;

  AaKievit({
    required this.x, required this.y,
    required this.vx, required this.speed,
    required this.layMin, required this.layMax,
    required double initialLayTimer,
  }) : vy=0, wingPhase=0, dir=vx>=0?1:-1, size=34,
       layState=KievitState.cruise, layTimer=initialLayTimer, laidThisSwoop=false;
}

class AaBoswachter {
  double x, y, vx, vy;
  final double speed;
  double walkPhase;
  int dir;
  bool targetPlayer;
  double stuckAcc;
  double slideTimer;
  int slideSign;
  double lastD;
  double targetTimer;
  AaEgg? targetEgg;
  double stunned;
  double cowCooldown; // prevents repeated stun from sustained cow contact

  AaBoswachter({
    required this.x, required this.y,
    required this.speed,
    required this.targetPlayer,
  }) : vx=0, vy=0, walkPhase=0, dir=1,
       stuckAcc=0, slideTimer=0, slideSign=1, lastD=0,
       targetTimer=0, targetEgg=null, stunned=0, cowCooldown=0;
}

enum EggType { normal, decoy, timeEgg, surprise }

class AaEgg {
  double x, y;
  double timer;      // seconds since laid
  EggType type;
  AaPowerup? powerup; // only for type==surprise

  AaEgg({required this.x, required this.y, required this.type, this.powerup})
      : timer=0;
}

class AaCow {
  double x, y, vx, vy;
  double walkPhase;
  int dir;
  double sz;
  double wanderTimer;

  AaCow({required this.x, required this.y, required this.sz})
      : vx=0, vy=0, walkPhase=0, dir=1, wanderTimer=2;
}

class AaParticle {
  double x, y, vx, vy;
  double r;
  final int color; // ARGB packed
  double life, maxLife, decay;

  AaParticle({required this.x, required this.y, required this.vx, required this.vy,
              required this.r, required this.color,
              required this.life, required this.decay})
      : maxLife=life;
}

class AaFloatingText {
  double x, y;
  final String text;
  final int color;
  double life;
  final double vy;

  AaFloatingText({required this.x, required this.y, required this.text,
                  required this.color}) : life=1.5, vy=-60;
}

class AaHatchingBird {
  double x, y, vx, vy;
  double wingPhase;
  double life;
  bool isJackdaw;

  AaHatchingBird({required this.x, required this.y,
                  required this.vx, required this.vy,
                  required this.isJackdaw})
      : wingPhase=0, life=isJackdaw?2.5:2.2;
}

class AaHeartItem {
  double x, y;
  double bob;

  AaHeartItem({required this.x, required this.y}) : bob=0;
}

class AaCloud {
  double x, y, r, speed, alpha;
  AaCloud({required this.x, required this.y, required this.r,
           required this.speed, required this.alpha});
}

class AaFlower {
  double x, y, r;
  int color;
  AaFlower({required this.x, required this.y, required this.r, required this.color});
}

class AaRainDrop {
  double x, y, speed, len, alpha;
  AaRainDrop({required this.x, required this.y, required this.speed,
               required this.len, required this.alpha});
}

// Fixed tree layout [x, groundY, size]
List<(double,double,double)> buildTrees(double W, double H, double groundY) => [
  (110,   H*0.68, 36),
  (260,   H*0.78, 30),
  (420,   H*0.65, 34),
  (580,   H*0.74, 28),
  (700,   H*0.70, 38),
  (160,   H*0.88, 26),
  (500,   H*0.88, 32),
  (680,   H*0.86, 28),
  (340,   H*0.92, 24),
];

// Horizon scene data: treeline points and landmark types
class HorizonScene {
  final List<double> treeline;
  final List<({String type, double x})> landmarks;
  const HorizonScene({required this.treeline, required this.landmarks});
}

const kHorizonScenes = [
  HorizonScene(
    treeline: [0,0,80,18,160,10,240,22,320,14,400,25,480,12,560,20,640,16,720,22,800,8,800,0],
    landmarks: [(type:'farm', x:100), (type:'windmill', x:350), (type:'oldehove', x:580)],
  ),
  HorizonScene(
    treeline: [0,0,60,14,140,8,220,18,300,10,380,22,460,16,540,8,620,20,700,12,800,6,800,0],
    landmarks: [(type:'watergate', x:200), (type:'farm', x:500), (type:'windmill', x:680)],
  ),
  HorizonScene(
    treeline: [0,0,100,20,180,12,260,16,340,24,420,10,500,18,580,14,660,22,740,8,800,10,800,0],
    landmarks: [(type:'skutsje', x:150), (type:'oldehove', x:400), (type:'farm', x:650)],
  ),
  HorizonScene(
    treeline: [0,0,70,16,150,24,230,8,310,20,390,14,470,20,550,10,630,18,710,16,800,12,800,0],
    landmarks: [(type:'windmill', x:120), (type:'watergate', x:380), (type:'skutsje', x:620)],
  ),
];

const kTreeCollideR = 18.0;
const kCowCollideR  = 22.0;
const kDitchHalfW   = 8.0;

bool isInDitch(double y, double ditch1, double ditch2) =>
    (y - ditch1).abs() < kDitchHalfW || (y - ditch2).abs() < kDitchHalfW;

bool isInTreeList(double x, double y, List<(double,double,double)> trees,
    List<AaCow> cows) {
  for (final (tx,ty,tsz) in trees) {
    final r = kTreeCollideR + tsz*0.1;
    if ((x-tx).abs() < r && (y-ty).abs() < r*1.2) return true;
  }
  for (final cow in cows) {
    final dx=x-cow.x, dy=y-cow.y;
    if (math.sqrt(dx*dx+dy*dy*0.5) < kCowCollideR) return true;
  }
  return false;
}

// Returns a safe ground position
({double x, double y}) safePosOnGround(
    math.Random rng, double minX, double maxX,
    double groundY, double H,
    List<(double,double,double)> trees, List<AaCow> cows,
    double ditch1, double ditch2) {
  for (int i=0; i<80; i++) {
    final x = minX + rng.nextDouble()*(maxX-minX);
    final y = groundY + 8 + rng.nextDouble()*(H*0.28);
    if (!isInTreeList(x,y,trees,cows) && !isInDitch(y,ditch1,ditch2)) {
      return (x:x, y:y);
    }
  }
  return (x:(minX+maxX)/2, y:(ditch1+ditch2)/2);
}
