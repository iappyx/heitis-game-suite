import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'aaisykje_data.dart';

// ── Colour helpers ────────────────────────────────────────────────────────────
Paint _fill(Color c) => Paint()..color=c..style=PaintingStyle.fill;
Paint _stroke(Color c, double w) => Paint()..color=c..style=PaintingStyle.stroke..strokeWidth=w..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round;
Color _rgb(int r,int g,int b,[double a=1]) => Color.fromARGB((a*255).round(),r,g,b);


// ── Main Painter ──────────────────────────────────────────────────────────────
class AaisykjePainter extends CustomPainter {
  final double W, H, groundY, horizonY, ditch1, ditch2;
  final double gameTime;
  final AaPlayer? player;
  final List<AaKievit> kievits;
  final List<AaBoswachter> boswachters;
  final List<AaEgg> eggs;
  final List<AaCow> cows;
  final List<AaParticle> particles;
  final List<AaFloatingText> floatingTexts;
  final List<AaHatchingBird> hatchingBirds;
  final List<AaHeartItem> hearts;
  final List<AaCloud> clouds;
  final List<(double,double,double)> trees;
  final List<AaFlower> flowers;
  final List<AaRainDrop> rainDrops;
  final double rainIntensity;
  final double screenShake;
  final double forestKeeperWarning;
  final double timeBonusFlash;
  final bool timeBonusActive;
  final int currentHorizonScene;
  final double horizonOffsetX;
  final bool horizonScrolling;
  final AaPowerup? activePowerup;
  final int eggsCollected;
  final int eggTarget;
  final double hatchTime;
  final String timeBonusLabel;
  final Color playerColor;
  // Multiplayer: second player (null in solo)
  final AaPlayer? player2;
  final Color player2Color;
  final AaPowerup? p2Powerup;

  const AaisykjePainter({
    required this.W, required this.H, required this.groundY,
    required this.horizonY, required this.ditch1, required this.ditch2,
    required this.gameTime, required this.player,
    required this.kievits, required this.boswachters,
    required this.eggs, required this.cows, required this.particles,
    required this.floatingTexts, required this.hatchingBirds,
    required this.hearts, required this.clouds, required this.trees,
    required this.flowers, required this.rainDrops,
    required this.rainIntensity, required this.screenShake,
    required this.forestKeeperWarning, required this.timeBonusFlash,
    required this.timeBonusActive, required this.currentHorizonScene,
    required this.horizonOffsetX, required this.horizonScrolling,
    required this.activePowerup, required this.eggsCollected,
    required this.eggTarget, required this.hatchTime,
    required this.timeBonusLabel, required this.playerColor,
    this.player2, this.player2Color = const Color(0xFF00E5FF),
    this.p2Powerup,
  });

  @override
  bool shouldRepaint(covariant AaisykjePainter o) => true;

  @override
  void paint(Canvas canvas, Size size) {
    // Clip everything to the game bounds so nothing bleeds outside
    canvas.clipRect(Rect.fromLTWH(0, 0, W, H));

    final shake = screenShake > 0.3 ? screenShake : 0.0;
    if (shake > 0) {
      canvas.save();
      final r = math.Random();
      canvas.translate((r.nextDouble()-0.5)*shake, (r.nextDouble()-0.5)*shake*0.6);
    }

    _drawGrass(canvas);
    for (final t in trees) _drawTree(canvas, t.$1, t.$2, t.$3);
    for (final f in flowers) _drawFlower(canvas, f.x, f.y, f.r, Color(f.color));
    for (final c in cows) _drawCow(canvas, c.x, c.y, c.dir, c.walkPhase, c.sz);
    for (final c in clouds) _drawCloud(canvas, c.x, c.y, c.r, c.alpha);

    if (forestKeeperWarning > 0) {
      final gradient = ui.Gradient.radial(
        Offset(W/2, H/2), H*0.8,
        [Colors.transparent, Color.fromARGB((forestKeeperWarning*0.28*255).round(), 255, 80, 0)],
        [0.25, 1.0],
      );
      canvas.drawRect(Rect.fromLTWH(0,0,W,H), Paint()..shader=gradient);
    }

    // Egg nests + eggs
    for (final e in eggs) _drawNest(canvas, e.x, e.y);
    for (final e in eggs) _drawEggItem(canvas, e, hatchTime);
    for (final h in hearts) _drawHeartPickup(canvas, h.x, h.y, h.bob);
    for (final b in hatchingBirds) {
      if (b.isJackdaw) _drawJackdaw(canvas, b);
      else _drawHatchingBird(canvas, b);
    }
    for (final k in kievits) _drawKievit(canvas, k);
    for (final b in boswachters) _drawBoswachter(canvas, b);

    if (player != null) _drawPlayer(canvas, player!);
    if (player2 != null) _drawPlayer2(canvas, player2!);

    if (rainIntensity > 0.01) _drawRain(canvas);

    _drawTimeBonusOverlay(canvas);
    for (final p in particles) _drawParticle(canvas, p);
    for (final ft in floatingTexts) _drawFloatingText(canvas, ft);

    // Progress bar
    final prog = (eggsCollected / eggTarget).clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(10,8,180,10), _fill(const Color(0x59000000)));
    final barColor = prog < 0.5 ? _rgb(68,204,68) : prog < 0.8 ? _rgb(170,221,34) : _rgb(255,204,0);
    canvas.drawRect(Rect.fromLTWH(10,8,180*prog,10), _fill(barColor));
    canvas.drawRect(Rect.fromLTWH(10,8,180,10), _stroke(const Color(0x4DFFFFFF),1));

    if (shake > 0) canvas.restore();
  }

  // ── Background ──────────────────────────────────────────────────────────────
  void _drawGrass(Canvas canvas) {
    // Sky
    final sky = ui.Gradient.linear(Offset(0,0), Offset(0,horizonY), [
      _rgb(106,184,240), _rgb(168,216,245), _rgb(200,232,248)
    ], [0, 0.7, 1]);
    canvas.drawRect(Rect.fromLTWH(0,0,W,horizonY), Paint()..shader=sky);
    // Ground
    final ground = ui.Gradient.linear(Offset(0,horizonY), Offset(0,H), [
      _rgb(90,186,42), _rgb(74,170,30), _rgb(58,144,24), _rgb(42,112,16)
    ], [0, 0.15, 0.6, 1]);
    canvas.drawRect(Rect.fromLTWH(0,horizonY,W,H-horizonY), Paint()..shader=ground);
    // Horizon
    if (horizonScrolling) {
      final prevScene = (currentHorizonScene-1+kHorizonScenes.length) % kHorizonScenes.length;
      _drawHorizonContent(canvas, horizonOffsetX, prevScene);
      _drawHorizonContent(canvas, horizonOffsetX-W-80, currentHorizonScene);
    } else {
      _drawHorizonContent(canvas, 0, currentHorizonScene);
    }
    canvas.drawRect(Rect.fromLTWH(0,horizonY-2,W,3), _fill(_rgb(58,140,24)));
    _drawDitch(canvas, ditch1);
    _drawDitch(canvas, ditch2);
  }

  void _drawHorizonContent(Canvas canvas, double offsetX, int sceneIdx) {
    final scene = kHorizonScenes[sceneIdx % kHorizonScenes.length];
    final ox = -offsetX;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0,0,W,horizonY+2));

    // Treeline
    final tl = scene.treeline;
    final treePath = Path()..moveTo(ox-10, horizonY);
    for (int i=0; i<tl.length-2; i+=2) {
      treePath.lineTo(ox+tl[i], horizonY-tl[i+1]);
    }
    treePath.lineTo(ox+W+10, horizonY);
    treePath.close();
    canvas.drawPath(treePath, _fill(_rgb(42,90,24)));

    // Landmark silhouettes
    for (final lm in scene.landmarks) {
      final lx = ox + lm.x;
      if (lx > -150 && lx < W+150) {
        switch (lm.type) {
          case 'farm':     _drawHorizonFarm(canvas, lx, horizonY);
          case 'windmill': _drawHorizonWindmill(canvas, lx, horizonY);
          case 'oldehove': _drawOldehove(canvas, lx, horizonY);
          case 'watergate':_drawWatergate(canvas, lx, horizonY);
          case 'skutsje':  _drawSkutsje(canvas, lx, horizonY);
        }
      }
    }

    // Horizon poplar trees
    final poplarX = [45.0,130,210,310,390,470,560,640,720,780];
    for (final tx2 in poplarX) {
      final lx = ox+tx2;
      if (lx < -20 || lx > W+20) continue;
      final th = 14+math.sin(tx2*0.37)*5;
      final tw = 3+math.sin(tx2*0.19)*1.5;
      canvas.drawOval(Rect.fromCenter(center:Offset(lx,horizonY-th),width:tw*2,height:th*2),
          _fill(_rgb(34,78,16)));
    }
    canvas.restore();
  }

  void _drawDitch(Canvas canvas, double y) {
    final gradient = ui.Gradient.linear(Offset(0,y-3), Offset(0,y+5), [
      _rgb(42,90,58), _rgb(26,74,106), _rgb(26,74,106), _rgb(42,90,58)
    ], [0,0.3,0.7,1]);
    canvas.drawRect(Rect.fromLTWH(0,y-3,W,8), Paint()..shader=gradient);
    canvas.drawRect(Rect.fromLTWH(0,y-1,W,2), _fill(const Color(0x40B4DCFF)));
  }

  void _drawHorizonFarm(Canvas canvas, double x, double hy) {
    canvas.drawRect(Rect.fromLTWH(x,hy-18,28,18), _fill(_rgb(138,32,24)));
    final roof = Path()..moveTo(x-2,hy-18)..lineTo(x+14,hy-28)..lineTo(x+30,hy-18)..close();
    canvas.drawPath(roof, _fill(_rgb(106,24,16)));
    canvas.drawRect(Rect.fromLTWH(x+32,hy-14,20,14), _fill(_rgb(221,232,204)));
    final r2 = Path()..moveTo(x+30,hy-14)..lineTo(x+42,hy-22)..lineTo(x+54,hy-14)..close();
    canvas.drawPath(r2, _fill(_rgb(138,96,48)));
  }

  void _drawHorizonWindmill(Canvas canvas, double x, double hy) {
    canvas.drawLine(Offset(x,hy), Offset(x,hy-32), _stroke(_rgb(136,136,136),2));
    canvas.drawCircle(Offset(x,hy-32), 3, _fill(_rgb(170,170,170)));
    for (int i=0; i<4; i++) {
      final a = i*math.pi/2 + (gameTime*0.6 % (math.pi*2));
      canvas.drawLine(Offset(x,hy-32), Offset(x+math.cos(a)*14,hy-32+math.sin(a)*14),
          _stroke(_rgb(170,170,170),1.5));
    }
  }

  // ── Oldehove ─────────────────────────────────────────────────────────────────
  void _drawOldehove(Canvas canvas, double x, double hy) {
    const S = Color(0xFF1E1E2E);
    const sky = Color(0xFF6AB8F0);
    final p = _fill(S);
    void fp(List<double> pts) {
      final path = Path()..moveTo(pts[0],pts[1]);
      for (int i=2; i<pts.length; i+=2) path.lineTo(pts[i],pts[i+1]);
      path.close();
      canvas.drawPath(path, p);
    }
    void arch(double ax, double ay, double w, double h) {
      final path = Path()
        ..moveTo(ax-w/2,ay)..lineTo(ax-w/2,ay-h*0.55)
        ..arcToPoint(Offset(ax+w/2,ay-h*0.55), radius:Radius.circular(w/2), clockwise:false)
        ..lineTo(ax+w/2,ay)..close();
      canvas.drawPath(path, _fill(sky));
    }
    fp([x-17,hy, x-14,hy-22, x+15,hy-22, x+17,hy]);
    canvas.drawRect(Rect.fromLTWH(x-15,hy-25,31,4), p);
    fp([x-12,hy-25, x-9,hy-46, x+16,hy-46, x+14,hy-25]);
    canvas.drawRect(Rect.fromLTWH(x-10,hy-49,27,4), p);
    fp([x-7,hy-49, x-4,hy-68, x+16,hy-68, x+13,hy-49]);
    canvas.drawRect(Rect.fromLTWH(x-5,hy-71,22,4), p);
    canvas.drawRect(Rect.fromLTWH(x-6,hy-75,22,5), p);
    canvas.drawRect(Rect.fromLTWH(x-7,hy-81,7,7), p);
    canvas.drawRect(Rect.fromLTWH(x+2,hy-79,5,5), p);
    canvas.drawRect(Rect.fromLTWH(x+9,hy-82,8,8), p);
    canvas.drawRect(Rect.fromLTWH(x+17,hy-78,4,4), p);
    arch(x-8,hy-8,5,11); arch(x,hy-8,5,11); arch(x+8,hy-8,5,11);
    arch(x-4,hy-32,5,10); arch(x+4,hy-32,5,10); arch(x+12,hy-32,5,10);
    arch(x,hy-55,4,9); arch(x+9,hy-55,4,9);
  }

  // ── Watergate / Sneek Waterpoort ──────────────────────────────────────────
  void _drawWatergate(Canvas canvas, double x, double hy) {
    const S = Color(0xFF1E1E2E);
    const sky = Color(0xFF6AB8F0);
    final p = _fill(S);
    void fp(List<double> pts) {
      final path = Path()..moveTo(pts[0],pts[1]);
      for (int i=2; i<pts.length; i+=2) path.lineTo(pts[i],pts[i+1]);
      path.close(); canvas.drawPath(path, p);
    }
    // Left tower
    canvas.drawRect(Rect.fromLTWH(x-30,hy-14,22,14), p);
    canvas.drawRect(Rect.fromLTWH(x-29,hy-42,20,28), p);
    final arcL = Path()..addArc(Rect.fromCenter(center:Offset(x-19,hy-42),width:20,height:20),math.pi,math.pi);
    canvas.drawPath(arcL, p);
    final arcL2 = Path()..addArc(Rect.fromCenter(center:Offset(x-19,hy-43),width:24,height:24),math.pi,math.pi);
    canvas.drawPath(arcL2, p);
    canvas.drawRect(Rect.fromLTWH(x-31,hy-47,24,5), p);
    for (int i=0;i<4;i++) canvas.drawRect(Rect.fromLTWH(x-31+i*7.0,hy-53,5,7), p);
    fp([x-33,hy-46, x-19,hy-82, x-5,hy-46]);
    fp([x-24,hy-66, x-19,hy-74, x-14,hy-66]);
    canvas.drawRect(Rect.fromLTWH(x-23,hy-66,8,8), p);
    canvas.drawCircle(Offset(x-19,hy-84), 2.5, p);
    canvas.drawCircle(Offset(x-19,hy-24), 4, _fill(sky));
    canvas.drawCircle(Offset(x-19,hy-34), 3.5, _fill(sky));
    // Right tower
    canvas.drawRect(Rect.fromLTWH(x+8,hy-14,22,14), p);
    canvas.drawRect(Rect.fromLTWH(x+9,hy-42,20,28), p);
    final arcR = Path()..addArc(Rect.fromCenter(center:Offset(x+19,hy-42),width:20,height:20),math.pi,math.pi);
    canvas.drawPath(arcR, p);
    final arcR2 = Path()..addArc(Rect.fromCenter(center:Offset(x+19,hy-43),width:24,height:24),math.pi,math.pi);
    canvas.drawPath(arcR2, p);
    canvas.drawRect(Rect.fromLTWH(x+7,hy-47,24,5), p);
    for (int i=0;i<4;i++) canvas.drawRect(Rect.fromLTWH(x+8+i*7.0,hy-53,5,7), p);
    fp([x+5,hy-46, x+19,hy-82, x+33,hy-46]);
    fp([x+14,hy-66, x+19,hy-74, x+24,hy-66]);
    canvas.drawRect(Rect.fromLTWH(x+15,hy-66,8,8), p);
    canvas.drawCircle(Offset(x+19,hy-84), 2.5, p);
    canvas.drawCircle(Offset(x+19,hy-24), 4, _fill(sky));
    canvas.drawCircle(Offset(x+19,hy-34), 3.5, _fill(sky));
    // Central gate
    canvas.drawRect(Rect.fromLTWH(x-9,hy-38,18,38), p);
    fp([x-9,hy-38, x-9,hy-44, x-5,hy-44, x-5,hy-48, x,hy-54, x+5,hy-48, x+5,hy-44, x+9,hy-44, x+9,hy-38]);
    // Gate arch
    final gatePath = Path()..moveTo(x-7,hy)..lineTo(x-7,hy-20)
      ..arcToPoint(Offset(x+7,hy-20),radius:Radius.circular(7))
      ..lineTo(x+7,hy)..close();
    canvas.drawPath(gatePath, _fill(sky));
    // Portcullis bars
    for (double i=-5;i<=5;i+=3) {
      canvas.drawLine(Offset(x+i,hy-13), Offset(x+i,hy), _stroke(S,1.2));
    }
    canvas.drawLine(Offset(x-7,hy-10), Offset(x+7,hy-10), _stroke(S,1.2));
    canvas.drawRect(Rect.fromLTWH(x-8,hy-32,3,9), _fill(sky));
    canvas.drawRect(Rect.fromLTWH(x+5,hy-32,3,9), _fill(sky));
  }

  // ── Skutsje (Frisian spritsail barge) ─────────────────────────────────────
  void _drawSkutsje(Canvas canvas, double x, double hy) {
    const S = Color(0xFF1E1E2E);
    final bowX=x-44.0, stnX=x+46.0, mstX=x-4.0;
    final mstY=hy-14.0, mstTop=hy-84.0;
    final bspX=bowX-24.0, bspY=hy-10.0;
    // Bowsprit
    canvas.drawLine(Offset(bowX-2,hy-12), Offset(bspX,bspY), _stroke(S,2.5));
    // Hull
    final hull = Path()
      ..moveTo(bspX+2,hy-4)..lineTo(bowX+2,hy-18)
      ..cubicTo(bowX+8,hy-20, x-20,hy-17, mstX-8,hy-15)
      ..lineTo(mstX-8,hy-22)..lineTo(x+10,hy-22)..lineTo(x+10,hy-15)
      ..lineTo(x+28,hy-15)..lineTo(stnX-2,hy-10)..lineTo(stnX,hy)
      ..cubicTo(stnX-10,hy+8, bowX+10,hy+8, bspX+2,hy-4)..close();
    canvas.drawPath(hull, _fill(S));
    // Leeboard
    final board = Path()..moveTo(x-2,hy-2)
      ..cubicTo(x+8,hy-2,x+10,hy+14,x+4,hy+20)
      ..cubicTo(x-2,hy+24,x-10,hy+16,x-8,hy+4)..close();
    canvas.drawPath(board, _fill(S));
    // Mast
    canvas.drawLine(Offset(mstX,mstY), Offset(mstX,mstTop), _stroke(S,3.5));
    // Sprit
    final spritY = mstY-18.0;
    final peakX=mstX+56.0, peakY=mstTop+16.0;
    canvas.drawLine(Offset(mstX,spritY), Offset(peakX,peakY), _stroke(S,2));
    // Mainsail
    final sail = Path()..moveTo(mstX,mstTop)..lineTo(peakX,peakY)
      ..lineTo(peakX-2,hy-15)..lineTo(mstX,mstY-2)..close();
    canvas.drawPath(sail, _fill(S));
    // Jib
    final jib = Path()..moveTo(bspX,bspY)..lineTo(mstX,mstTop-4)..lineTo(mstX,mstY)
      ..cubicTo(mstX-14,mstY-12,bspX+6,hy-8,bspX,bspY)..close();
    canvas.drawPath(jib, _fill(S));
    // Forestay
    canvas.drawLine(Offset(mstX,mstTop), Offset(bspX,bspY), _stroke(S,1.2));
    // Backstay (semi-transparent)
    canvas.drawLine(Offset(mstX,mstTop), Offset(stnX-4,hy-10), _stroke(S.withValues(alpha: 0.5),1.2));
    // Vane
    canvas.drawLine(Offset(mstX,mstTop), Offset(mstX+10,mstTop-3), _stroke(S,2));
  }

  // ── Cloud ──────────────────────────────────────────────────────────────────
  void _drawCloud(Canvas canvas, double x, double y, double r, double alpha) {
    final p = Paint()..color=Colors.white.withValues(alpha: alpha)..style=PaintingStyle.fill;
    for (final (bx,by,br) in [(0.0,0.0,r),(r*0.7,-r*0.3,r*0.75),(r*1.3,0.0,r*0.65),(-r*0.6,-r*0.2,r*0.6)]) {
      canvas.drawCircle(Offset(x+bx,y+by), br, p);
    }
  }

  // ── Grass tuft (replaces "tree") ──────────────────────────────────────────
  void _drawTree(Canvas canvas, double x, double y, double sz) {
    final bladeColors = [_rgb(26,90,10),_rgb(30,110,14),_rgb(36,98,20),_rgb(26,82,10),_rgb(40,114,14)];
    final swayOff = math.sin(gameTime*1.1 + x*0.02 + y*0.013) * (0.10+math.sin(sz*0.41)*0.04);
    final numBlades = 4 + (sz % 7).floor();
    for (int i=0; i<numBlades; i++) {
      final baseAngle = (i/numBlades)*math.pi*2 + math.sin(sz*0.3+i)*0.5;
      final tipSway = swayOff*(0.6+i*0.1);
      final angle = baseAngle + tipSway;
      final len = sz*0.55 + math.sin(sz*0.7+i*1.3)*sz*0.12;
      final spread = sz*0.18;
      final cx1 = x + math.cos(angle-0.25)*len*0.5;
      final cy1 = y - len*0.4;
      final ex  = x + math.cos(angle)*spread;
      final ey  = y - len;
      final path = Path()..moveTo(x,y)..quadraticBezierTo(cx1,cy1,ex,ey);
      canvas.drawPath(path, _stroke(bladeColors[i%bladeColors.length], sz*0.07));
    }
    canvas.drawOval(Rect.fromCenter(center:Offset(x,y),width:sz*0.56,height:sz*0.2),
        _fill(const Color(0x4728140A)));
  }

  void _drawFlower(Canvas canvas, double x, double y, double r, Color color) {
    canvas.drawCircle(Offset(x,y), r*0.8, _fill(color));
    canvas.drawCircle(Offset(x,y), r*0.35, _fill(_rgb(255,229,102)));
  }

  // ── Cow ────────────────────────────────────────────────────────────────────
  void _drawCow(Canvas canvas, double x, double y, int dir, double walkPhase, double sz) {
    final s = sz;
    final facing = dir >= 0 ? 1.0 : -1.0;
    canvas.save();
    canvas.translate(x, y);
    if (facing < 0) canvas.scale(-1, 1);

    final walk = math.sin(walkPhase);

    // Shadow
    canvas.drawOval(Rect.fromCenter(center:Offset(s*0.05,s*0.38),width:s*0.76,height:s*0.14),
        _fill(const Color(0x1A000000)));

    // Back legs
    for (final (ox,rot) in [(s*0.18, walk*0.2),(- s*0.08, -walk*0.2)]) {
      canvas.save();
      canvas.translate(ox, s*0.18);
      canvas.rotate(rot);
      canvas.drawRect(Rect.fromLTWH(-s*0.055,0,s*0.11,s*0.22), _fill(_rgb(232,232,224)));
      canvas.drawRect(Rect.fromLTWH(-s*0.06,s*0.20,s*0.12,s*0.06), _fill(_rgb(26,26,26)));
      canvas.restore();
    }
    // Body
    final bg = ui.Gradient.linear(Offset(-s*0.20,-s*0.15), Offset(s*0.20,s*0.20),
        [_rgb(242,242,234),_rgb(216,216,204)]);
    canvas.drawOval(Rect.fromCenter(center:Offset.zero,width:s*0.76,height:s*0.44),
        Paint()..shader=bg..style=PaintingStyle.fill);
    // Spots
    final spots = [(-s*0.18,-s*0.08,s*0.14,s*0.10,0.3),(s*0.08,-s*0.04,s*0.12,s*0.09,-0.2),
                   (-s*0.05,s*0.08,s*0.10,s*0.08,0.4),(s*0.22,-s*0.10,s*0.08,s*0.07,0.1)];
    for (final (sx,sy,rx,ry,_) in spots) {
      canvas.drawOval(Rect.fromCenter(center:Offset(sx,sy),width:rx*2,height:ry*2),
          Paint()..color=_rgb(26,26,26)..style=PaintingStyle.fill);
    }
    // Front legs
    for (final (ox,rot) in [(-s*0.22,-walk*0.2),(s*0.06,walk*0.2)]) {
      canvas.save();
      canvas.translate(ox, s*0.18);
      canvas.rotate(rot);
      canvas.drawRect(Rect.fromLTWH(-s*0.055,0,s*0.11,s*0.22), _fill(_rgb(232,232,224)));
      canvas.drawRect(Rect.fromLTWH(-s*0.06,s*0.20,s*0.12,s*0.06), _fill(_rgb(26,26,26)));
      canvas.restore();
    }
    // Neck + head
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.38,-s*0.08),width:s*0.20,height:s*0.28),
        _fill(_rgb(232,232,224)));
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.50,-s*0.14),width:s*0.26,height:s*0.20),
        _fill(_rgb(232,232,224)));
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.52,-s*0.16),width:s*0.14,height:s*0.12),
        _fill(_rgb(26,26,26)));
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.44,-s*0.22),width:s*0.12,height:s*0.08),
        _fill(_rgb(232,208,184)));
    canvas.drawCircle(Offset(-s*0.56,-s*0.17), s*0.025, _fill(_rgb(26,26,26)));
    canvas.drawCircle(Offset(-s*0.555,-s*0.175), s*0.008, _fill(Colors.white));
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.60,-s*0.10),width:s*0.14,height:s*0.10),
        _fill(_rgb(232,200,168)));
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.62,-s*0.09),width:s*0.036,height:s*0.024),
        _fill(_rgb(192,144,128)));
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.57,-s*0.08),width:s*0.036,height:s*0.024),
        _fill(_rgb(192,144,128)));
    // Tail
    final tail = Path()..moveTo(s*0.36,-s*0.05)
      ..quadraticBezierTo(s*0.52,s*0.10+walk*s*0.08, s*0.48,s*0.22);
    canvas.drawPath(tail, _stroke(_rgb(136,136,136),s*0.03));
    canvas.drawCircle(Offset(s*0.48,s*0.22), s*0.04, _fill(_rgb(85,85,85)));
    // Udder
    canvas.drawOval(Rect.fromCenter(center:Offset(s*0.05,s*0.20),width:s*0.24,height:s*0.14),
        _fill(_rgb(232,184,168)));
    canvas.restore();
  }

  // ── Kievit (lapwing) ───────────────────────────────────────────────────────
  void _drawKievit(Canvas canvas, AaKievit k) {
    final s = k.size;
    canvas.save();
    canvas.translate(k.x, k.y);
    if (k.dir < 0) canvas.scale(-1, 1);
    final bodyTilt = k.layState==KievitState.dive ? 0.55 : k.layState==KievitState.climb ? -0.35 : 0.0;
    canvas.rotate(bodyTilt);
    final beat = math.sin(k.wingPhase);
    final wingLift = beat*0.45;
    // Left wing
    canvas.save(); canvas.rotate(-0.15-wingLift);
    final lwing = Path()..moveTo(0,-s*0.08)
      ..cubicTo(-s*0.25,-s*0.35,-s*0.7,-s*0.25,-s*0.85,s*0.05)
      ..cubicTo(-s*0.7,s*0.18,-s*0.35,s*0.22,-s*0.05,s*0.10)..close();
    final wg1 = ui.Gradient.linear(Offset(-s*0.85,0), Offset.zero,
        [_rgb(26,26,26),_rgb(42,24,8),_rgb(30,30,30),_rgb(17,17,17)],[0,0.3,0.7,1]);
    canvas.drawPath(lwing, Paint()..shader=wg1..style=PaintingStyle.fill);
    for (final (ox,oy,rx,ry,_) in [(-s*0.78,s*0.06,s*0.04,s*0.02,-0.4),(-s*0.72,-s*0.02,s*0.035,s*0.018,-0.5),(-s*0.65,-s*0.09,s*0.03,s*0.015,-0.6)]) {
      canvas.drawOval(Rect.fromCenter(center:Offset(ox,oy),width:rx*2,height:ry*2),
          _fill(const Color(0xE6F0F0F0)));
    }
    canvas.restore();
    // Right wing
    canvas.save(); canvas.rotate(0.15+wingLift);
    final rwing = Path()..moveTo(0,-s*0.08)
      ..cubicTo(s*0.25,-s*0.35,s*0.7,-s*0.25,s*0.85,s*0.05)
      ..cubicTo(s*0.7,s*0.18,s*0.35,s*0.22,s*0.05,s*0.10)..close();
    final wg2 = ui.Gradient.linear(Offset(s*0.85,0), Offset.zero,
        [_rgb(26,26,26),_rgb(42,24,8),_rgb(30,30,30),_rgb(17,17,17)],[0,0.3,0.7,1]);
    canvas.drawPath(rwing, Paint()..shader=wg2..style=PaintingStyle.fill);
    for (final (ox,oy,rx,ry,_) in [(s*0.78,s*0.06,s*0.04,s*0.02,0.4),(s*0.72,-s*0.02,s*0.035,s*0.018,0.5),(s*0.65,-s*0.09,s*0.03,s*0.015,0.6)]) {
      canvas.drawOval(Rect.fromCenter(center:Offset(ox,oy),width:rx*2,height:ry*2),
          _fill(const Color(0xE6F0F0F0)));
    }
    canvas.restore();
    // Body parts
    canvas.drawOval(Rect.fromCenter(center:Offset(0,s*0.04),width:s*0.28,height:s*0.64), _fill(_rgb(240,240,240)));
    canvas.drawOval(Rect.fromCenter(center:Offset(s*0.02,s*0.28),width:s*0.20,height:s*0.18), _fill(_rgb(200,100,10)));
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.18),width:s*0.20,height:s*0.20), _fill(_rgb(17,17,17)));
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.28),width:s*0.20,height:s*0.20), _fill(_rgb(232,232,232)));
    canvas.drawArc(Rect.fromCenter(center:Offset(0,-s*0.28),width:s*0.20,height:s*0.20), math.pi*0.9, math.pi*1.2, false, _fill(_rgb(17,17,17)));
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.22),width:s*0.10,height:s*0.14), _fill(_rgb(17,17,17)));
    canvas.drawCircle(Offset(s*0.04,-s*0.29), s*0.025, _fill(_rgb(17,17,17)));
    canvas.drawCircle(Offset(s*0.048,-s*0.295), s*0.008, _fill(Colors.white));
    // Beak
    final beak = Path()..moveTo(s*0.09,-s*0.28)..lineTo(s*0.18,-s*0.27)..lineTo(s*0.17,-s*0.24)..lineTo(s*0.09,-s*0.25)..close();
    canvas.drawPath(beak, _fill(_rgb(34,34,34)));
    // Crest
    final crest = Path()..moveTo(-s*0.04,-s*0.36)
      ..cubicTo(-s*0.12,-s*0.52,0,-s*0.58,s*0.08,-s*0.50);
    canvas.drawPath(crest, _stroke(_rgb(13,13,13),s*0.04));
    canvas.restore();
  }

  // ── Jackdaw ────────────────────────────────────────────────────────────────
  void _drawJackdaw(Canvas canvas, AaHatchingBird b) {
    canvas.save();
    canvas.translate(b.x, b.y);
    final alpha = (b.life*0.7).clamp(0.0,1.0);
    canvas.saveLayer(null, Paint()..color=Color.fromARGB((alpha*255).round(),255,255,255));
    final facing = b.vx>=0 ? 1.0 : -1.0;
    if (facing < 0) canvas.scale(-1,1);
    canvas.drawOval(Rect.fromCenter(center:Offset.zero,width:18,height:10),
        _fill(_rgb(42,42,58)));
    canvas.drawOval(Rect.fromCenter(center:Offset(-4,-2),width:8,height:6),
        _fill(_rgb(122,122,138)));
    final wf = math.sin(b.wingPhase);
    for (final (side) in [-1.0, 1.0]) {
      final w = Path()..moveTo(-2,0)
        ..lineTo(-2+wf*3*side, -10-wf.abs()*4)
        ..lineTo(10*side,-2)..close();
      canvas.drawPath(w, _fill(_rgb(26,26,42)));
    }
    canvas.drawCircle(Offset(6,-1), 1.5, _fill(_rgb(221,221,238)));
    final beak2 = Path()..moveTo(9,0)..lineTo(13,-1)..lineTo(9,2)..close();
    canvas.drawPath(beak2, _fill(_rgb(26,26,26)));
    canvas.restore();
    canvas.restore();
  }

  // ── Hatching bird ──────────────────────────────────────────────────────────
  void _drawHatchingBird(Canvas canvas, AaHatchingBird b) {
    canvas.save();
    canvas.translate(b.x, b.y);
    final alpha = (b.life*1.5).clamp(0.0,1.0);
    canvas.saveLayer(null, Paint()..color=Color.fromARGB((alpha*255).round(),255,255,255));
    final s = 28.0;
    final beat = math.sin(b.wingPhase)*0.7;
    for (final (side, wr) in [(-1.0,-0.2-beat),(1.0,0.2+beat)]) {
      canvas.save(); canvas.rotate(wr);
      final wing = Path()..moveTo(0,-s*0.06)
        ..cubicTo(side*s*0.22,-s*0.32, side*s*0.65,-s*0.22, side*s*0.78,s*0.06)
        ..cubicTo(side*s*0.62,s*0.16, side*s*0.28,s*0.18, side*s*0.04,s*0.08)..close();
      canvas.drawPath(wing, _fill(_rgb(26,26,26)));
      canvas.restore();
    }
    canvas.drawOval(Rect.fromCenter(center:Offset(0,s*0.04),width:s*0.24,height:s*0.50), _fill(_rgb(240,240,240)));
    canvas.drawOval(Rect.fromCenter(center:Offset(s*0.01,s*0.24),width:s*0.16,height:s*0.14), _fill(_rgb(192,80,8)));
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.15),width:s*0.16,height:s*0.16), _fill(_rgb(17,17,17)));
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.24),width:s*0.18,height:s*0.18), _fill(_rgb(224,224,224)));
    canvas.drawArc(Rect.fromCenter(center:Offset(0,-s*0.24),width:s*0.18,height:s*0.18), math.pi*0.9, math.pi*1.2, false, _fill(_rgb(17,17,17)));
    final c2 = Path()..moveTo(-s*0.03,-s*0.32)..cubicTo(-s*0.10,-s*0.46,s*0.02,-s*0.52,s*0.09,-s*0.45);
    canvas.drawPath(c2, _stroke(_rgb(13,13,13),s*0.038));
    canvas.restore();
    canvas.restore();
  }

  // ── Boswachter ─────────────────────────────────────────────────────────────
  void _drawBoswachterAt(Canvas canvas, double x, double y, double walkPhase, int dir) {
    final s = 36.0;
    final facing = dir>=0 ? 1.0 : -1.0;
    canvas.save();
    canvas.translate(x, y);
    if (facing < 0) canvas.scale(-1,1);
    final walk = math.sin(walkPhase);
    final legSwing = walk*0.38;
    final armSwing = -walk*0.32;
    canvas.translate(0, walk.abs()*2.5);
    // Legs
    for (final (ox, rot, col1, col2) in [
      (s*0.08, -legSwing, _rgb(36,78,20), _rgb(74,46,16)),
      (-s*0.08, legSwing, _rgb(46,96,24), _rgb(90,56,24))]) {
      canvas.save(); canvas.translate(ox, s*0.28); canvas.rotate(rot);
      canvas.drawRect(Rect.fromLTWH(-s*0.07,0,s*0.13,s*0.28), _fill(col1));
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(-s*0.08,s*0.25,s*0.19,s*0.11), Radius.circular(s*0.04));
      canvas.drawRRect(rr, _fill(col2));
      canvas.restore();
    }
    // Body
    final jg = ui.Gradient.linear(Offset(-s*0.22,0), Offset(s*0.22,s*0.30),
        [_rgb(61,122,34),_rgb(46,96,24),_rgb(36,78,18)],[0,0.5,1]);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-s*0.22,0,s*0.44,s*0.30), Radius.circular(s*0.05)),
        Paint()..shader=jg..style=PaintingStyle.fill);
    // Badge + details
    canvas.drawCircle(Offset(-s*0.11,s*0.10), s*0.05, _fill(_rgb(200,160,32)));
    canvas.drawCircle(Offset(-s*0.11,s*0.10), s*0.033, _fill(_rgb(28,62,12)));
    canvas.drawRect(Rect.fromLTWH(s*0.06,s*0.08,s*0.10,s*0.08), _stroke(_rgb(28,62,12),s*0.017));
    // Arms
    for (final (ox, rot) in [(s*0.23, armSwing+0.18),(-s*0.23,-armSwing-0.18)]) {
      canvas.save(); canvas.translate(ox, s*0.06); canvas.rotate(rot);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-s*0.06,0,s*0.12,s*0.26), Radius.circular(s*0.04)),
          _fill(ox>0 ? _rgb(46,96,24) : _rgb(58,112,32)));
      canvas.drawCircle(Offset(0,s*0.28), s*0.07, _fill(_rgb(212,149,106)));
      if (ox < 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-s*0.09,s*0.20,s*0.18,s*0.15), Radius.circular(s*0.02)),
            _fill(_rgb(200,160,96)));
      }
      canvas.restore();
    }
    // Head
    canvas.drawRect(Rect.fromLTWH(-s*0.07,-s*0.06,s*0.14,s*0.08), _fill(_rgb(212,149,106)));
    final fg = ui.Gradient.radial(Offset(-s*0.04,-s*0.22), s*0.18,
        [_rgb(232,170,122),_rgb(196,120,72)],[0.15,1.0]);
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.20),width:s*0.30,height:s*0.34),
        Paint()..shader=fg..style=PaintingStyle.fill);
    // Eyes
    for (final ox in [-s*0.05, s*0.05]) {
      canvas.drawOval(Rect.fromCenter(center:Offset(ox,-s*0.12),width:s*0.16,height:s*0.068),
          _fill(_rgb(90,56,24)));
      canvas.drawCircle(Offset(ox>0?s*0.06:-s*0.06,-s*0.22), s*0.03, _fill(_rgb(42,26,8)));
      canvas.drawCircle(Offset(ox>0?s*0.07:-s*0.05,-s*0.23), s*0.01, _fill(Colors.white));
    }
    // Hat
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.34),width:s*0.50,height:s*0.13),
        _fill(_rgb(42,80,16)));
    final hg = ui.Gradient.linear(Offset(-s*0.16,-s*0.58),Offset(s*0.16,-s*0.34),
        [_rgb(61,112,32),_rgb(42,80,16)],[0,1]);
    final hat = Path()..moveTo(-s*0.16,-s*0.34)..lineTo(-s*0.14,-s*0.57)
      ..cubicTo(-s*0.12,-s*0.64,s*0.12,-s*0.64,s*0.14,-s*0.57)
      ..lineTo(s*0.16,-s*0.34)..close();
    canvas.drawPath(hat, Paint()..shader=hg..style=PaintingStyle.fill);
    canvas.drawRect(Rect.fromLTWH(-s*0.16,-s*0.41,s*0.32,s*0.065), _fill(_rgb(26,48,8)));
    canvas.drawCircle(Offset(0,-s*0.375), s*0.038, _fill(_rgb(200,160,32)));
    canvas.drawCircle(Offset(0,-s*0.375), s*0.022, _fill(_rgb(26,48,8)));
    canvas.restore();
  }

  void _drawBoswachter(Canvas canvas, AaBoswachter b) {
    if (b.stunned > 0) {
      canvas.save();
      canvas.translate(b.x, b.y);
      canvas.rotate(math.sin(b.stunned*40)*0.35);
      _drawBoswachterAt(canvas, 0, 0, b.walkPhase, b.dir);
      canvas.restore();
      // Spinning stars
      for (int i=0; i<3; i++) {
        final a = (i/3)*math.pi*2 + gameTime*5;
        final sx = b.x + math.cos(a)*14;
        final sy = b.y - 38 + math.sin(a*2)*4;
        final c = i==0?_rgb(255,229,102):i==1?_rgb(255,136,68):_rgb(68,221,255);
        canvas.drawCircle(Offset(sx,sy), 3, _fill(c));
      }
    } else if (activePowerup == AaPowerup.freeze) {
      canvas.saveLayer(null, Paint()..color=const Color(0xB3FFFFFF));
      _drawBoswachterAt(canvas, b.x, b.y, 0, b.dir);
      canvas.restore();
      canvas.saveLayer(null, Paint()..color=const Color(0x5988CCFF));
      canvas.drawOval(Rect.fromCenter(center:Offset(b.x,b.y),width:36,height:48),
          _fill(const Color(0x5988CCFF)));
      canvas.restore();
    } else {
      _drawBoswachterAt(canvas, b.x, b.y, b.walkPhase, b.dir);
    }
  }

  // ── Player (Eggie) ─────────────────────────────────────────────────────────
  void _drawPlayer(Canvas canvas, AaPlayer p) {
    // Blink when invincible
    if (p.invincible > 0 && (p.invincible*10).floor() % 2 != 0 && activePowerup != AaPowerup.ghost) return;

    final s = p.size;
    final jz = p.jumpZ;

    // Jump shadow
    if (jz > 2) {
      final scale = (1-jz/55).clamp(0.4,1.0);
      canvas.drawOval(Rect.fromCenter(center:Offset(p.x,p.y+4),
          width:s*scale*1.8,height:s*scale*0.6),
          _fill(Color.fromARGB((0.18*scale*255).round(),0,0,0)));
    }

    // Powerup auras
    if (activePowerup == AaPowerup.ghost) {
      final alpha = 0.28+0.10*math.sin(gameTime*8);
      canvas.saveLayer(null, Paint()..color=Color.fromARGB((alpha*255).round(),255,255,255));
    }
    if (activePowerup == AaPowerup.shield) {
      final sr = 26+3*math.sin(gameTime*6);
      canvas.drawCircle(Offset(p.x,p.y-jz), sr,
          Paint()..color=Color.fromARGB(((0.6+0.3*math.sin(gameTime*8))*255).round(),255,215,0)
          ..style=PaintingStyle.stroke..strokeWidth=3);
    }
    if (activePowerup == AaPowerup.speed) {
      canvas.saveLayer(null, Paint()..color=const Color(0x40FFFFFF));
      _drawEggieAt(canvas, p.x-p.vx*0.04, p.y-p.vy*0.04-jz, p.dir, 0, s);
      canvas.saveLayer(null, Paint()..color=const Color(0x1FFFFFFF));
      _drawEggieAt(canvas, p.x-p.vx*0.08, p.y-p.vy*0.08-jz, p.dir, 0, s);
      canvas.restore();
      canvas.restore();
    }

    _drawEggieAt(canvas, p.x, p.y-jz, p.dir, math.sin(p.bobPhase)*2, s);

    if (activePowerup == AaPowerup.ghost) canvas.restore();
  }

  // ── Player 2 (remote / opponent) ──────────────────────────────────────────
  void _drawPlayer2(Canvas canvas, AaPlayer p) {
    if (p.invincible > 0 && (p.invincible*10).floor() % 2 != 0) return;
    final s = p.size;
    final jz = p.jumpZ;
    if (jz > 2) {
      final scale = (1-jz/55).clamp(0.4,1.0);
      canvas.drawOval(Rect.fromCenter(center:Offset(p.x,p.y+4),
          width:s*scale*1.8,height:s*scale*0.6),
          _fill(Color.fromARGB((0.18*scale*255).round(),0,0,0)));
    }
    if (p2Powerup == AaPowerup.ghost) {
      final alpha = 0.28+0.10*math.sin(gameTime*8);
      canvas.saveLayer(null, Paint()..color=Color.fromARGB((alpha*255).round(),255,255,255));
    }
    if (p2Powerup == AaPowerup.shield) {
      final sr = 26+3*math.sin(gameTime*6);
      canvas.drawCircle(Offset(p.x,p.y-jz), sr,
          Paint()..color=Color.fromARGB(((0.6+0.3*math.sin(gameTime*8))*255).round(),255,215,0)
          ..style=PaintingStyle.stroke..strokeWidth=3);
    }
    _drawEggieWithColor(canvas, p.x, p.y-jz, p.dir, math.sin(p.bobPhase)*2, s, player2Color);
    if (p2Powerup == AaPowerup.ghost) canvas.restore();
  }

  /// Draws an eggie with an explicit hat colour (used for player 2).
  void _drawEggieWithColor(Canvas canvas, double x, double y, int dir, double bobY, double sz, Color hatColor) {
    final s = sz;
    canvas.save();
    canvas.translate(x, y+bobY);
    canvas.drawOval(Rect.fromCenter(center:Offset(0,s*0.55),width:s*0.76,height:s*0.20),
        _fill(const Color(0x1F000000)));
    final bg = ui.Gradient.radial(Offset(-s*0.15,-s*0.20),s*0.55,
        [_rgb(255,249,240),_rgb(255,238,221),_rgb(255,204,153)],[0,0.6,1]);
    canvas.drawOval(Rect.fromCenter(center:Offset.zero,width:s*0.76,height:s*0.96),
        Paint()..shader=bg..style=PaintingStyle.fill);
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.20,s*0.10),width:s*0.20,height:s*0.14),
        _fill(const Color(0x59FF9678)));
    canvas.drawOval(Rect.fromCenter(center:Offset(s*0.20,s*0.10),width:s*0.20,height:s*0.14),
        _fill(const Color(0x59FF9678)));
    canvas.drawCircle(Offset(-s*0.12,-s*0.08), s*0.06, _fill(_rgb(42,26,10)));
    canvas.drawCircle(Offset(s*0.12,-s*0.08), s*0.06, _fill(_rgb(42,26,10)));
    canvas.drawCircle(Offset(-s*0.10,-s*0.10), s*0.02, _fill(Colors.white));
    canvas.drawCircle(Offset(s*0.14,-s*0.10), s*0.02, _fill(Colors.white));
    canvas.drawArc(Rect.fromCenter(center:Offset(0,s*0.05),width:s*0.24,height:s*0.16),
        0.2, math.pi-0.4, false, _stroke(_rgb(160,80,40),s*0.035));
    // Hat in player2Color
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.42),width:s*0.56,height:s*0.14),
        _fill(hatColor));
    canvas.drawRect(Rect.fromLTWH(-s*0.18,-s*0.75,s*0.36,s*0.36), _fill(hatColor));
    canvas.drawRect(Rect.fromLTWH(-s*0.18,-s*0.42,s*0.36,s*0.06), _fill(const Color(0xFFFFD700)));
    final la = math.sin(gameTime*3)*s*0.12;
    canvas.drawLine(Offset(-s*0.15,s*0.42), Offset(-s*0.20,s*0.58+la), _stroke(_rgb(204,136,68),s*0.07));
    canvas.drawLine(Offset(s*0.15,s*0.42), Offset(s*0.20,s*0.58-la), _stroke(_rgb(204,136,68),s*0.07));
    canvas.restore();
  }

  // ── Eggie (player 1, uses playerColor for hat) ────────────────────────────
  void _drawEggieAt(Canvas canvas, double x, double y, int dir, double bobY, double sz) {
    final s = sz;
    canvas.save();
    canvas.translate(x, y+bobY);
    // Shadow
    canvas.drawOval(Rect.fromCenter(center:Offset(0,s*0.55),width:s*0.76,height:s*0.20),
        _fill(const Color(0x1F000000)));
    // Body
    final bg = ui.Gradient.radial(Offset(-s*0.15,-s*0.20),s*0.55,
        [_rgb(255,249,240),_rgb(255,238,221),_rgb(255,204,153)],[0,0.6,1]);
    canvas.drawOval(Rect.fromCenter(center:Offset.zero,width:s*0.76,height:s*0.96),
        Paint()..shader=bg..style=PaintingStyle.fill);
    // Rosy cheeks
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.20,s*0.10),width:s*0.20,height:s*0.14),
        _fill(const Color(0x59FF9678)));
    canvas.drawOval(Rect.fromCenter(center:Offset(s*0.20,s*0.10),width:s*0.20,height:s*0.14),
        _fill(const Color(0x59FF9678)));
    // Eyes
    canvas.drawCircle(Offset(-s*0.12,-s*0.08), s*0.06, _fill(_rgb(42,26,10)));
    canvas.drawCircle(Offset(s*0.12,-s*0.08), s*0.06, _fill(_rgb(42,26,10)));
    canvas.drawCircle(Offset(-s*0.10,-s*0.10), s*0.02, _fill(Colors.white));
    canvas.drawCircle(Offset(s*0.14,-s*0.10), s*0.02, _fill(Colors.white));
    // Smile
    canvas.drawArc(Rect.fromCenter(center:Offset(0,s*0.05),width:s*0.24,height:s*0.16),
        0.2, math.pi-0.4, false, _stroke(_rgb(160,80,40),s*0.035));
    // Hat (in player profile color)
    final hatC = playerColor;
    final hatGold = const Color(0xFFFFD700);
    canvas.drawOval(Rect.fromCenter(center:Offset(0,-s*0.42),width:s*0.56,height:s*0.14),
        _fill(hatC));
    canvas.drawRect(Rect.fromLTWH(-s*0.18,-s*0.75,s*0.36,s*0.36), _fill(hatC));
    canvas.drawRect(Rect.fromLTWH(-s*0.18,-s*0.42,s*0.36,s*0.06), _fill(hatGold));
    // Legs
    final la = math.sin(gameTime*3)*s*0.12;
    canvas.drawLine(Offset(-s*0.15,s*0.42), Offset(-s*0.20,s*0.58+la), _stroke(_rgb(204,136,68),s*0.07));
    canvas.drawLine(Offset(s*0.15,s*0.42), Offset(s*0.20,s*0.58-la), _stroke(_rgb(204,136,68),s*0.07));
    canvas.restore();
  }

  // ── Nest ───────────────────────────────────────────────────────────────────
  void _drawNest(Canvas canvas, double x, double y) {
    final ny = y+7;
    final ng = ui.Gradient.radial(Offset(x,ny+2), 14,
        [_rgb(58,34,8),_rgb(90,52,18),const Color(0x00321C08)],[0,0.6,1]);
    canvas.drawOval(Rect.fromCenter(center:Offset(x,ny+2),width:28,height:14),
        Paint()..shader=ng..style=PaintingStyle.fill);
    // Grass blades
    final blades = [(-10.0,2.0,-13.0,-5.0),(10,1,-13,-4),(-6,-3,-8,-9),(6,-3,9,-8),(0,5,0,-2)];
    for (final (x1,y1,x2,y2) in blades) {
      canvas.drawLine(Offset(x+x1,ny+y1), Offset(x+x2,ny+y2), _stroke(_rgb(122,96,32),1.2));
    }
  }

  // ── Egg item ───────────────────────────────────────────────────────────────
  void _drawEggItem(Canvas canvas, AaEgg egg, double hatchTime) {
    final x=egg.x, y=egg.y;
    final frac = (egg.timer/hatchTime).clamp(0.0,1.0);
    final stage = frac<0.4?0:frac<0.75?1:2;

    canvas.save();
    canvas.translate(x, y);
    if (egg.type == EggType.decoy) canvas.saveLayer(null, Paint()..color=const Color(0xE0FFFFFF));
    if (frac > 0.65) canvas.rotate(math.sin(egg.timer*1000*0.028)*(frac-0.65)*22*0.045);
    if (frac < 0.65) canvas.translate(0, math.sin(egg.timer*1000*0.003)*3);

    // Glow
    final Color glowColor;
    switch (egg.type) {
      case EggType.surprise:
        glowColor = switch(egg.powerup) {
          AaPowerup.ghost => _rgb(180,200,255), AaPowerup.shield => _rgb(255,215,0),
          AaPowerup.speed => _rgb(255,240,50),  AaPowerup.magnet => _rgb(210,80,255),
          AaPowerup.freeze => _rgb(80,230,255), _ => _rgb(255,200,50),
        };
        break;
      case EggType.decoy:
        glowColor = _rgb(90,105,48);
        break;
      case EggType.timeEgg:
        glowColor = _rgb(40,160,220);
        break;
      default:
        glowColor = _rgb(
            (80+175*frac).round().clamp(0,255),
            (220*(1-frac*0.9)).round().clamp(0,255), 20);
    }
    final glowAlpha = 0.22+0.3*math.sin(egg.timer*1000*0.006);
    final glowGrad = ui.Gradient.radial(Offset.zero, 22,
        [glowColor.withValues(alpha: glowAlpha), Colors.transparent], [0.15,1.0]);
    canvas.drawCircle(Offset.zero, 22, Paint()..shader=glowGrad);

    // Egg body
    final Color eTop, eMid, eBot;
    switch (egg.type) {
      case EggType.surprise:
        (eTop,eMid,eBot) = switch(egg.powerup) {
          AaPowerup.ghost  => (_rgb(221,238,255),_rgb(136,170,221),_rgb(51,68,102)),
          AaPowerup.shield => (_rgb(255,232,138),_rgb(212,160,0),_rgb(122,92,0)),
          AaPowerup.speed  => (_rgb(255,255,136),_rgb(255,204,0),_rgb(136,102,0)),
          AaPowerup.magnet => (_rgb(238,136,255),_rgb(170,34,204),_rgb(85,0,102)),
          AaPowerup.freeze => (_rgb(204,248,255),_rgb(68,204,238),_rgb(0,102,136)),
          _ => (_rgb(207,192,106),_rgb(168,148,64),_rgb(122,104,32)),
        };
        break;
      case EggType.decoy:
        eTop = _rgb(154,170,72); eMid = _rgb(122,136,48); eBot = _rgb(74,88,24);
        break;
      case EggType.timeEgg:
        eTop = _rgb(170,238,255); eMid = _rgb(68,170,221); eBot = _rgb(17,102,170);
        break;
      default:
        eTop = _rgb(207,192,106); eMid = _rgb(168,148,64); eBot = _rgb(122,104,32);
    }
    final eg = ui.Gradient.radial(Offset(-3,-5), 12,
        [eTop, eMid, eBot],[0,0.5,1]);
    canvas.drawOval(Rect.fromCenter(center:Offset.zero,width:18,height:24),
        Paint()..shader=eg..style=PaintingStyle.fill);

    // Speckles
    final speckles = [(3.0,2.0,1.8,0.3),(-4.0,5.0,1.2,-0.5),(1.0,-4.0,1.5,0.8),
                      (-2.0,-1.0,2.0,-0.2),(5.0,-3.0,1.0,0.1),(-5.0,1.0,1.3,0.6),(2.0,7.0,1.4,-0.3),(-3.0,-6.0,1.0,0.9)];
    for (final (sx,sy,sr,_) in speckles) {
      canvas.drawOval(Rect.fromCenter(center:Offset(sx,sy),width:sr*2,height:sr*1.3),
          _fill(const Color(0x99231402)));
    }

    if (egg.type == EggType.timeEgg) {
      final pulse = 0.3+0.25*math.sin(egg.timer*1000*0.008);
      canvas.drawOval(Rect.fromCenter(center:Offset.zero,width:18,height:24),
          _fill(const Color(0x4FB4F0FF).withValues(alpha: pulse)));
      canvas.drawLine(Offset.zero, Offset(0,-7), _stroke(const Color(0xB3FFFFFF),1.2));
      canvas.drawLine(Offset.zero, Offset(4,3), _stroke(const Color(0xB3FFFFFF),1.2));
    }

    // Crack stages
    if (stage >= 1) {
      final crackP = _stroke(_rgb(50,28,3),0.9);
      canvas.drawLine(Offset(0,-9),Offset(3,-3),crackP);
      canvas.drawLine(Offset(0,-9),Offset(-4,-4),crackP);
      canvas.drawLine(Offset(3,-3),Offset(6,0),crackP);
    }
    if (stage >= 2) {
      final lift = ((frac-0.75)/0.25)*14;
      canvas.drawLine(Offset(-9,0),Offset(9,0), _stroke(_rgb(35,18,0),1.5));
      canvas.save(); canvas.translate(0,-lift);
      final tg = ui.Gradient.radial(Offset(-2,-8),10,[_rgb(207,192,106),_rgb(138,116,40)],[0,1]);
      canvas.drawArc(Rect.fromCenter(center:Offset(0,-4),width:18,height:14),math.pi,math.pi,false,
          Paint()..shader=tg..style=PaintingStyle.fill);
      canvas.restore();
      if (frac > 0.85) {
        final peek = ((frac-0.85)/0.15).clamp(0.0,1.0);
        canvas.saveLayer(null, Paint()..color=Color.fromARGB((peek*255).round(),255,255,255));
        canvas.translate(0,-2-lift*0.5);
        canvas.drawCircle(Offset(0,-3), 4, _fill(_rgb(62,80,32)));
        final cr = Path()..moveTo(0,-7)..cubicTo(-2,-10,2,-11,4,-8);
        canvas.drawPath(cr, _stroke(_rgb(10,10,10),1.8));
        canvas.drawCircle(Offset(1.5,-3.5), 1.5, _fill(_rgb(26,26,26)));
        canvas.restore();
      }
    }

    // Hatch timer arc
    canvas.drawArc(Rect.fromCenter(center:Offset.zero,width:32,height:32),
        -math.pi/2, math.pi*2, false,
        Paint()..color=const Color(0x59000000)..style=PaintingStyle.stroke..strokeWidth=3);
    final timerColor = frac<0.5?_rgb(68,255,102):frac<0.8?_rgb(255,204,0):_rgb(255,48,48);
    canvas.drawArc(Rect.fromCenter(center:Offset.zero,width:32,height:32),
        -math.pi/2, (1-frac)*math.pi*2, false,
        Paint()..color=timerColor..style=PaintingStyle.stroke..strokeWidth=3..strokeCap=StrokeCap.round);

    if (egg.type == EggType.decoy) canvas.restore();
    canvas.restore();
  }

  // ── Heart pickup ───────────────────────────────────────────────────────────
  void _drawHeartPickup(Canvas canvas, double x, double y, double bob) {
    final by = y + math.sin(bob)*5 - 8;
    canvas.save(); canvas.translate(x, by);
    final glow = ui.Gradient.radial(Offset.zero,18,[const Color(0x8CFF506E),Colors.transparent],[0,1]);
    canvas.drawCircle(Offset.zero,18,Paint()..shader=glow);
    final s = 10.0;
    final heart = Path()
      ..moveTo(0,s*0.3)
      ..cubicTo(0,-s*0.3,-s,-s*0.3,-s,s*0.1)
      ..cubicTo(-s,s*0.6,0,s*1.0,0,s*1.1)
      ..cubicTo(0,s*1.0,s,s*0.6,s,s*0.1)
      ..cubicTo(s,-s*0.3,0,-s*0.3,0,s*0.3);
    canvas.drawPath(heart, _fill(_rgb(255,68,102)));
    canvas.drawOval(Rect.fromCenter(center:Offset(-s*0.3,-s*0.1),width:s*0.56,height:s*0.44),
        _fill(const Color(0x99FFC8D2)));
    canvas.restore();
  }

  // ── Rain ───────────────────────────────────────────────────────────────────
  void _drawRain(Canvas canvas) {
    canvas.save();
    for (final d in rainDrops) {
      canvas.drawLine(Offset(d.x,d.y), Offset(d.x-d.len*0.18,d.y-d.len),
          Paint()..color=Color.fromARGB((d.alpha*rainIntensity*255).round(),170,204,238)
          ..strokeWidth=0.8..style=PaintingStyle.stroke);
    }
    canvas.drawRect(Rect.fromLTWH(0,groundY,W,6),
        _fill(Color.fromARGB((rainIntensity*0.12*255).round(),136,187,221)));
    canvas.restore();
  }

  // ── Particles ──────────────────────────────────────────────────────────────
  void _drawParticle(Canvas canvas, AaParticle p) {
    final alpha = p.life/p.maxLife;
    canvas.drawCircle(Offset(p.x,p.y), p.r*alpha,
        _fill(Color(p.color).withValues(alpha: alpha)));
  }

  // ── Floating text ─────────────────────────────────────────────────────────
  void _drawFloatingText(Canvas canvas, AaFloatingText ft) {
    final alpha = ft.life.clamp(0.0,1.0);
    final tp = TextPainter(
      text: TextSpan(text:ft.text, style: TextStyle(
        fontSize:15, fontWeight:FontWeight.bold,
        color: Color(ft.color).withValues(alpha: alpha),
        shadows: [Shadow(color:Color.fromARGB((0.55*alpha*255).round(),0,0,0), blurRadius:3)],
      )),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(ft.x-tp.width/2, ft.y-tp.height/2));
  }

  // ── Time bonus overlay ────────────────────────────────────────────────────
  void _drawTimeBonusOverlay(Canvas canvas) {
    if (timeBonusFlash > 0) {
      canvas.drawRect(Rect.fromLTWH(0,0,W,H),
          _fill(Color.fromARGB((timeBonusFlash*0.22*255).round(),255,229,102)));
    }
    if (timeBonusActive) {
      final pulse = 0.85+math.sin(gameTime*12)*0.15;
      final tp = TextPainter(
        text: TextSpan(text:'★ $timeBonusLabel  +10 pts/s', style: TextStyle(
          fontSize:28*pulse, fontWeight:FontWeight.bold, fontFamily:'monospace',
          color: const Color(0xFFFFE566).withValues(alpha: pulse),
          shadows: const [Shadow(color:Color(0xFFFF8800),blurRadius:18)],
        )),
        textAlign:TextAlign.center, textDirection:TextDirection.ltr,
      )..layout(maxWidth:W);
      tp.paint(canvas, Offset((W-tp.width)/2, 44));
    }
  }
}
