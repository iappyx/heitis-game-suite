import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/wake_lock.dart';
import '../../core/sound_player.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';

// ── Character definitions ─────────────────────────────────────────────────────

class WaBistDoCharacter {
  final String id;
  final String name;
  final double skinTone;    // 0=light, 1=dark
  final double hairColor;   // 0=blonde, 0.3=brown, 0.6=red, 1=black
  final double hairLength;  // 0=bald, 0.5=short, 1=long
  final bool hasCurlyHair;
  final bool hasBeard;
  final bool hasMoustache;
  final bool hasGlasses;
  final bool hasHat;
  final bool isWoman;
  final double age;         // 0=young, 1=old
  final double noseSize;    // 0=small, 1=large
  final double eyeColor;    // 0=blue, 0.5=green, 1=brown

  const WaBistDoCharacter({
    required this.id, required this.name,
    this.skinTone = .2, this.hairColor = .3, this.hairLength = .5,
    this.hasCurlyHair = false, this.hasBeard = false, this.hasMoustache = false,
    this.hasGlasses = false, this.hasHat = false, this.isWoman = false,
    this.age = .3, this.noseSize = .4, this.eyeColor = .7,
  });
}

const List<WaBistDoCharacter> kWaBistDoCharacters = [
  WaBistDoCharacter(id:'sjoerd',  name:'Sjoerd',  skinTone:.2,  hairColor:.6,  hairLength:.5,  hasBeard:true,  age:.35, noseSize:.5, eyeColor:.8),
  WaBistDoCharacter(id:'nynke',   name:'Nynke',   skinTone:.15, hairColor:.0,  hairLength:.9,  isWoman:true,   age:.25, noseSize:.3, eyeColor:.3),
  WaBistDoCharacter(id:'jelle',   name:'Jelle',   skinTone:.2,  hairColor:.3,  hairLength:.3,  hasGlasses:true, age:.4, noseSize:.4, eyeColor:.1),
  WaBistDoCharacter(id:'sietske', name:'Sietske', skinTone:.25, hairColor:.6,  hairLength:.7,  isWoman:true,   hasHat:true,  age:.3,  noseSize:.3, eyeColor:.6),
  WaBistDoCharacter(id:'oebele',  name:'Oebele',  skinTone:.2,  hairColor:.9,  hairLength:.1,  hasMoustache:true, age:.75, noseSize:.6, eyeColor:.8),
  WaBistDoCharacter(id:'wytske',  name:'Wytske',  skinTone:.3,  hairColor:1.0, hairLength:.8,  isWoman:true,   hasCurlyHair:true, age:.28, noseSize:.3, eyeColor:.9),
  WaBistDoCharacter(id:'tsjerk',  name:'Tsjerk',  skinTone:.15, hairColor:1.0, hairLength:.4,  hasHat:true,    age:.38, noseSize:.5, eyeColor:.7),
  WaBistDoCharacter(id:'grytsje', name:'Grytsje', skinTone:.2,  hairColor:.9,  hairLength:.6,  isWoman:true,   age:.7,  noseSize:.35, eyeColor:.2),
  WaBistDoCharacter(id:'douwe',   name:'Douwe',   skinTone:.55, hairColor:1.0, hairLength:.4,  hasBeard:true,  age:.4,  noseSize:.7, eyeColor:.9),
  WaBistDoCharacter(id:'froukje', name:'Froukje', skinTone:.15, hairColor:.15, hairLength:.7,  isWoman:true,   hasCurlyHair:true, age:.22, noseSize:.25, eyeColor:.15),
  WaBistDoCharacter(id:'hessel',  name:'Hessel',  skinTone:.2,  hairColor:.8,  hairLength:.2,  hasMoustache:true, age:.5, noseSize:.55, eyeColor:.5),
  WaBistDoCharacter(id:'hiske',   name:'Hiske',   skinTone:.4,  hairColor:.9,  hairLength:.8,  isWoman:true,   hasHat:true,  age:.35, noseSize:.3, eyeColor:.85),
  WaBistDoCharacter(id:'wiebe',   name:'Wiebe',   skinTone:.2,  hairColor:.5,  hairLength:.35, hasGlasses:true, age:.45, noseSize:.45, eyeColor:.6),
  WaBistDoCharacter(id:'jildou',  name:'Jildou',  skinTone:.45, hairColor:.7,  hairLength:.85, isWoman:true,   age:.28, noseSize:.35, eyeColor:.9),
  WaBistDoCharacter(id:'auke',    name:'Auke',    skinTone:.15, hairColor:.9,  hairLength:.05, age:.5,  noseSize:.8, eyeColor:.3),
  WaBistDoCharacter(id:'ymkje',   name:'Ymkje',   skinTone:.18, hairColor:.6,  hairLength:.5,  isWoman:true,   hasGlasses:true, age:.26, noseSize:.28, eyeColor:.2),
  WaBistDoCharacter(id:'lolke',   name:'Lolke',   skinTone:.2,  hairColor:.85, hairLength:.15, hasGlasses:true, age:.8, noseSize:.6, eyeColor:.4),
  WaBistDoCharacter(id:'tjitske', name:'Tjitske', skinTone:.35, hairColor:.9,  hairLength:.75, isWoman:true,   hasCurlyHair:true, hasGlasses:true, age:.38, noseSize:.3, eyeColor:.8),
  WaBistDoCharacter(id:'hidde',   name:'Hidde',   skinTone:.45, hairColor:1.0, hairLength:.4,  age:.3,  noseSize:.35, eyeColor:.9),
  WaBistDoCharacter(id:'rixt',    name:'Rixt',    skinTone:.5,  hairColor:.9,  hairLength:.85, isWoman:true,   age:.32, noseSize:.3, eyeColor:.85),
  WaBistDoCharacter(id:'wopke',   name:'Wopke',   skinTone:.2,  hairColor:.8,  hairLength:.1,  hasGlasses:true, hasMoustache:true, age:.72, noseSize:.65, eyeColor:.4),
  WaBistDoCharacter(id:'fokje',   name:'Fokje',   skinTone:.2,  hairColor:.6,  hairLength:.9,  isWoman:true,   hasCurlyHair:true, age:.25, noseSize:.25, eyeColor:.0),
  WaBistDoCharacter(id:'siebe',   name:'Siebe',   skinTone:.18, hairColor:.1,  hairLength:.3,  hasGlasses:true, age:.27, noseSize:.38, eyeColor:.15),
  WaBistDoCharacter(id:'janke',   name:'Janke',   skinTone:.2,  hairColor:.05, hairLength:.9,  isWoman:true,   age:.24, noseSize:.28, eyeColor:.25),
  WaBistDoCharacter(id:'tjeerd',  name:'Tjeerd',  skinTone:.3,  hairColor:.6,  hairLength:.45, hasCurlyHair:true, age:.2, noseSize:.45, eyeColor:.5),
  WaBistDoCharacter(id:'sjoukje', name:'Sjoukje', skinTone:.25, hairColor:.9,  hairLength:.5,  isWoman:true,   hasGlasses:true, hasHat:true, age:.78, noseSize:.35, eyeColor:.45),
];

// ── Face painter ───────────────────────────────────────────────────────────────

class FacePainter extends CustomPainter {
  final WaBistDoCharacter c;
  final bool eliminated;
  const FacePainter(this.c, {this.eliminated = false});

  static double _s(double a) {
    a = a % 6.2832;
    if (a < 0) a += 6.2832;
    if (a > 3.1416) return -_s(a - 3.1416);
    if (a > 1.5708) return _s(3.1416 - a);
    return a - a*a*a/6.0 + a*a*a*a*a/120.0;
  }
  static double _c(double a) => _s(a + 1.5708);

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height, cx = w / 2;
    final p = Paint()..isAntiAlias = true;

    // Background
    p.color = const Color(0xFFF2EDE6);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & sz, const Radius.circular(8)), p);

    if (eliminated) {
      p.color = Colors.red.withValues(alpha: .45);
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 2.5;
      p.strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(w*.22,h*.22), Offset(w*.78,h*.78), p);
      canvas.drawLine(Offset(w*.78,h*.22), Offset(w*.22,h*.78), p);
      p.style = PaintingStyle.fill;
      // Faded name
      _drawName(canvas, sz, opacity: .2);
      return;
    }

    final skin   = Color.lerp(const Color(0xFFFFDDB4), const Color(0xFF5C2A0A), c.skinTone)!;
    final skinDk = Color.lerp(skin, Colors.black, .18)!;
    final hairC  = _hairColor();

    // ── Back hair ──
    if (c.hairLength > .15) {
      p.color = hairC;
      if (c.hasCurlyHair) {
        for (int i = 0; i < 8; i++) {
          final a = i * 3.14159 / 4;
          canvas.drawCircle(Offset(cx + w*.32*_c(a), h*.27 + h*.14*_s(a)), w*.095, p);
        }
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(w*.13, h*.07, w*.74, h*(.16 + c.hairLength*.22)),
          Radius.circular(w*.24)), p);
        if (c.hairLength > .6) {
          canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(w*.08, h*.26, w*.12, h*(.18+c.hairLength*.2)), Radius.circular(w*.06)), p);
          canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(w*.80, h*.26, w*.12, h*(.18+c.hairLength*.2)), Radius.circular(w*.06)), p);
        }
      }
    }

    // ── Face oval ──
    p.color = skin;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, h*.45), width: w*.64, height: h*.62), p);

    // ── Ears ──
    p.color = skinDk;
    canvas.drawOval(Rect.fromCenter(center: Offset(w*.19, h*.44), width: w*.10, height: h*.10), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(w*.81, h*.44), width: w*.10, height: h*.10), p);

    // ── Wrinkles ──
    if (c.age > .6) {
      p.color = skinDk.withValues(alpha: .35);
      p.style = PaintingStyle.stroke; p.strokeWidth = .9;
      for (final ex in [cx - w*.13, cx + w*.13]) {
        canvas.drawArc(Rect.fromCenter(center: Offset(ex, h*.40), width:w*.13, height:h*.06), .3, 1.2, false, p);
      }
      p.style = PaintingStyle.fill;
    }

    // ── Eyes ──
    for (final ex in [cx - w*.175, cx + w*.175]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(ex, h*.40), width:w*.145, height:h*.098), Paint()..color=Colors.white..isAntiAlias=true);
      canvas.drawCircle(Offset(ex, h*.40), w*.044, Paint()..color=_eyeColor()..isAntiAlias=true);
      canvas.drawCircle(Offset(ex, h*.40), w*.027, Paint()..color=Colors.black87..isAntiAlias=true);
      canvas.drawCircle(Offset(ex - w*.01, h*.386), w*.009, Paint()..color=Colors.white70..isAntiAlias=true);
      if (c.isWoman) {
        final lp = Paint()..color=Colors.black..strokeWidth=1.1..strokeCap=StrokeCap.round;
        for (int i = -2; i<=2; i++) {
          canvas.drawLine(Offset(ex+i*w*.024, h*.375), Offset(ex+i*w*.028, h*.360), lp);
        }
      }
    }

    // ── Eyebrows ──
    p.color = c.age > .65 ? Colors.white.withValues(alpha: .75) : hairC.withValues(alpha: .9);
    p.style = PaintingStyle.stroke; p.strokeWidth = h*.019; p.strokeCap = StrokeCap.round;
    for (final ex in [cx - w*.175, cx + w*.175]) {
      final isLeft = ex < cx;
      // Left brow: arc on lower-left of ellipse; Right brow: mirrored on lower-right
      canvas.drawArc(Rect.fromCenter(center: Offset(ex, h*.345), width:w*.155, height:h*.072),
          isLeft ? 3.4 : -1.06, .8, false, p);
    }
    p.style = PaintingStyle.fill;

    // ── Nose ──
    final nw = w*(.042 + c.noseSize*.058), nh = h*(.058 + c.noseSize*.040);
    p.color = skinDk;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, h*.525), width:nw, height:nh), p);
    p.color = skinDk.withValues(alpha: .6);
    canvas.drawCircle(Offset(cx - nw*.6, h*.545), nw*.33, p);
    canvas.drawCircle(Offset(cx + nw*.6, h*.545), nw*.33, p);

    // ── Mouth ──
    p.color = Color.lerp(const Color(0xFFBB5544), skinDk, .28)!;
    p.style = PaintingStyle.stroke; p.strokeWidth = h*.022; p.strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, h*.592), width:w*.28, height:h*.10), .18, 2.78, false, p);
    p.style = PaintingStyle.fill;

    // ── Moustache ──
    if (c.hasMoustache) {
      p.color = hairC;
      canvas.drawOval(Rect.fromCenter(center:Offset(cx - w*.08, h*.573), width:w*.18, height:h*.054), p);
      canvas.drawOval(Rect.fromCenter(center:Offset(cx + w*.08, h*.573), width:w*.18, height:h*.054), p);
    }

    // ── Beard ──
    if (c.hasBeard) {
      p.color = hairC.withValues(alpha: .82);
      // Chin area: rounded oval
      canvas.drawOval(Rect.fromCenter(
        center: Offset(cx, h*.66), width: w*.46, height: h*.20), p);
      // Jaw sides blending into cheeks
      canvas.drawOval(Rect.fromCenter(
        center: Offset(cx - w*.14, h*.60), width: w*.22, height: h*.14), p);
      canvas.drawOval(Rect.fromCenter(
        center: Offset(cx + w*.14, h*.60), width: w*.22, height: h*.14), p);
    }

    // ── Glasses ──
    if (c.hasGlasses) {
      final gp = Paint()
        ..color = Color.lerp(const Color(0xFF6677AA), Colors.black87, .5)!
        ..style = PaintingStyle.stroke ..strokeWidth = 1.8 ..isAntiAlias = true;
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center:Offset(cx - w*.175, h*.40), width:w*.20, height:h*.12),
        Radius.circular(w*.038)), gp);
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center:Offset(cx + w*.175, h*.40), width:w*.20, height:h*.12),
        Radius.circular(w*.038)), gp);
      canvas.drawLine(Offset(cx - w*.075, h*.40), Offset(cx + w*.075, h*.40), gp);
      canvas.drawLine(Offset(cx - w*.275, h*.388), Offset(cx - w*.275, h*.412), gp);
      canvas.drawLine(Offset(cx + w*.275, h*.388), Offset(cx + w*.275, h*.412), gp);
    }

    // ── Hat ──
    if (c.hasHat) {
      p.color = c.isWoman ? const Color(0xFFBB2255) : const Color(0xFF1A2E4A);
      canvas.drawOval(Rect.fromCenter(center:Offset(cx, h*.195), width:w*.76, height:h*.095), p);
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w*.26, h*.055, w*.52, h*.155), Radius.circular(w*.06)), p);
      if (c.isWoman) {
        p.color = Colors.white.withValues(alpha: .25);
        canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - w*.26, h*.175, w*.52, h*.026), const Radius.circular(2)), p);
      }
    }

    // ── Front hair (over hat) ──
    if (c.hairLength > .15 && !c.hasHat && !c.hasCurlyHair) {
      p.color = hairC;
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(w*.19, h*.075, w*.62, h*.13), Radius.circular(w*.18)), p);
    }

    _drawName(canvas, sz);
  }

  void _drawName(Canvas canvas, Size sz, {double opacity = 1.0}) {
    final tp = TextPainter(
      text: TextSpan(text: c.name, style: TextStyle(
        color: Colors.black.withValues(alpha: opacity * .88),
        fontSize: sz.height * .115,
        fontWeight: FontWeight.bold,
      )),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: sz.width);
    tp.paint(canvas, Offset((sz.width - tp.width) / 2, sz.height * .865));
  }

  Color _hairColor() {
    if (c.hairColor < .3) return Color.lerp(const Color(0xFFF0DC6A), const Color(0xFFC8A020), c.hairColor / .3)!;
    if (c.hairColor < .6) return Color.lerp(const Color(0xFF7B4A1E), const Color(0xFF3A1A08), (c.hairColor-.3)/.3)!;
    if (c.hairColor < .8) return Color.lerp(const Color(0xFF8B2010), Colors.black87, (c.hairColor-.6)/.2)!;
    return Color.lerp(Colors.black87, Colors.white.withValues(alpha: .85), c.age > .7 ? (c.age-.7)/.3 : 0)!;
  }

  Color _eyeColor() {
    if (c.eyeColor < .5) return Color.lerp(const Color(0xFF4A9EFF), const Color(0xFF2D7A2D), c.eyeColor / .5)!;
    return Color.lerp(const Color(0xFF2D7A2D), const Color(0xFF6B3A0A), (c.eyeColor-.5)/.5)!;
  }

  @override bool shouldRepaint(FacePainter old) => old.c != c || old.eliminated != eliminated;
}

// ── Screen ────────────────────────────────────────────────────────────────────

enum _WaBistDoPhase { choosingCharacter, playing, gameOver }

class WaBistDoScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const WaBistDoScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<WaBistDoScreen> createState() => _WaBistDoState();
}

class _WaBistDoState extends State<WaBistDoScreen> with GameMixin {
  final _net     = Network();
  final _session = SessionState();

  _WaBistDoPhase _phase     = _WaBistDoPhase.choosingCharacter;
  String?  _myCharId;
  String?  _opCharId;
  final Set<String> _eliminated = {};
  bool _showMyChar = false;
  bool _guessMode  = false;
  int  _winner     = 0;
  bool _hostReady  = false;
  bool _joinReady  = false;

  @override List<Player> get gamePlayers => widget.players;
  int get _myIdx => _net.myIdx;

  @override void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    WakeLock.acquire();
    // Solo: host auto-picks CPU character immediately
    if (_net.isSolo) {
      final r = math.Random();
      _opCharId  = kWaBistDoCharacters[r.nextInt(kWaBistDoCharacters.length)].id;
      _joinReady = true;
    }
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    if (!mounted) return;
    switch (msg['type'] as String) {
      case 'WAB_CHOSEN':
        if (_net.isHost) {
          _opCharId  = msg['id'] as String;
          _joinReady = true;
          if (_hostReady) _startGame();
          setState(() {});
        }
        break;
      case 'WAB_START':
        setState(() { _phase = _WaBistDoPhase.playing; _eliminated.clear(); _guessMode = false; });
        break;
      case 'WAB_GUESS':
        // Ignore late guesses (dialog confirmed after game over / reset) — otherwise
        // only the host's _winner changes and the two tablets disagree.
        if (_net.isHost && _phase == _WaBistDoPhase.playing) {
          final guesser = msg['guesser'] as int;
          final correct = guesser == 1 ? msg['charId'] == _opCharId : msg['charId'] == _myCharId;
          _net.send('WAB_GUESS_RESULT', {
            'correct': correct, 'guesser': guesser,
            'realId': guesser == 1 ? _opCharId : _myCharId,
          });
          // Apply locally — send() doesn't loop back to the host
          setState(() {
            _winner = correct ? guesser : (guesser == 1 ? 2 : 1);
            _phase  = _WaBistDoPhase.gameOver;
          });
          SoundPlayer.i.uiConfirm();
        }
        break;
      case 'WAB_GUESS_RESULT':
        if (_phase != _WaBistDoPhase.playing) break; // guard against stale result after reset
        setState(() {
          final guesser = msg['guesser'] as int;
          final correct = msg['correct'] as bool;
          _winner   = correct ? guesser : (guesser == 1 ? 2 : 1);
          _phase    = _WaBistDoPhase.gameOver;
          _opCharId = msg['realId'] as String?;
        });
        SoundPlayer.i.uiConfirm();
        break;
      case 'GAME_RESET':
        GameOverActions.handleMessage(msg, _reset);
        break;
      case 'WAB_SYNC':
        if (!_net.isHost) {
          setState(() {
            _phase  = _WaBistDoPhase.values.firstWhere((p) => p.name == msg['phase'], orElse: () => _phase);
            _winner = msg['winner'] as int? ?? 0;
            // Keep our own _eliminated: each player's flipped-down faces are their own
          });
        }
        break;
      case 'WAB_SYNC_REQ':
        if (_net.isHost) _net.send('WAB_SYNC', {
          'phase': _phase.name, 'winner': _winner,
        });
        break;
    }
  }

  void _chooseCharacter(String charId) {
    setState(() => _myCharId = charId);
    if (_net.isHost) {
      _hostReady = true;
      if (_joinReady) _startGame();
    } else {
      _net.send('WAB_CHOSEN', {'id': charId});
    }
  }

  void _startGame() {
    setState(() => _phase = _WaBistDoPhase.playing);
    _net.send('WAB_START');
  }

  void _onTapFace(WaBistDoCharacter c) {
    if (_phase != _WaBistDoPhase.playing) return;
    if (_guessMode) {
      if (!_eliminated.contains(c.id)) _confirmGuess(c);
    } else {
      setState(() {
        if (_eliminated.contains(c.id)) _eliminated.remove(c.id);
        else _eliminated.add(c.id);
      });
      SoundPlayer.i.uiClick();
    }
  }

  void _confirmGuess(WaBistDoCharacter c) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kBg2,
      title: Text(L.wabistdo.guessBtn, style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 90, height: 115,
          child: CustomPaint(painter: FacePainter(c), child: const SizedBox.expand())),
        const SizedBox(height: 8),
        Text(c.name, style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(L.wabistdo.whoIsIt, style: const TextStyle(color: kMuted, fontSize: 13)),
      ]),
      actions: [
        TextButton(onPressed: () { Navigator.pop(context); setState(() => _guessMode = false); },
            child: Text(L.common.cancelBtn, style: const TextStyle(color: kMuted))),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            setState(() => _guessMode = false);
            if (_phase != _WaBistDoPhase.playing) return; // game ended / reset while dialog was open
            final guesser = _myIdx == 0 ? 1 : 2;
            if (_net.isHost) {
              final correct = c.id == _opCharId;
              _net.send('WAB_GUESS_RESULT', {'correct': correct, 'guesser': guesser, 'realId': _myCharId});
              // Apply locally too — send() doesn't loop back to host
              setState(() {
                _winner = correct ? guesser : (guesser == 1 ? 2 : 1);
                _phase  = _WaBistDoPhase.gameOver;
              });
              SoundPlayer.i.uiConfirm();
            } else {
              _net.send('WAB_GUESS', {'charId': c.id, 'guesser': guesser});
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: kGreen.withValues(alpha: .3), side: BorderSide(color: kGreen)),
          child: Text(L.wabistdo.yes, style: const TextStyle(color: kGreen))),
      ],
    ));
  }

  void _reset() {
    resetConfetti(); resetStats();
    setState(() {
      _phase = _WaBistDoPhase.choosingCharacter;
      _myCharId = null; _opCharId = null;
      _eliminated.clear(); _winner = 0;
      _hostReady = false; _joinReady = false;
      _guessMode = false; _showMyChar = false;
    });
    // Solo: re-pick CPU character so game doesn't get stuck
    if (_net.isSolo) {
      final r = math.Random();
      _opCharId  = kWaBistDoCharacters[r.nextInt(kWaBistDoCharacters.length)].id;
      _joinReady = true;
    }
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _net.send('WAB_SYNC', {
            'phase': _phase.name, 'winner': _winner,
          });
          else _net.send('WAB_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  @override void dispose() { super.dispose(); }

  @override Widget build(BuildContext context) => GameScaffold(
    key: scaffoldKey,
    title: L.wabistdo.gameName,
    players: widget.players,
    chatMessages: chatMessages,
    onSendChat: sendChat,
    onLocalTyping: onLocalTyping,
    onReadAck: sendReadAck,
    typingName: typingName,
    rules: L.wabistdo.rules,
    child: switch (_phase) {
      _WaBistDoPhase.choosingCharacter => _buildChoose(),
      _WaBistDoPhase.playing           => _buildPlay(),
      _WaBistDoPhase.gameOver          => _buildOver(),
    },
  );

  /// Calculate grid columns so all items fit without scrolling.
  int _gridCols(double w, double h, int count) {
    // Try increasing columns until all rows fit in available height
    for (int cols = 4; cols <= 12; cols++) {
      final rows = (count + cols - 1) ~/ cols;
      final cellW = (w - 10 - (cols - 1) * 5) / cols;
      final cellH = cellW / .78; // matches childAspectRatio
      final totalH = rows * cellH + (rows - 1) * 5 + 10;
      if (totalH <= h) return cols;
    }
    return 8;
  }

  // ── Choose character ───────────────────────────────────────────────────────

  Widget _buildChoose() {
    if (_myCharId != null) return Center(child: Padding(padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, color: kGreen, size: 48),
        const SizedBox(height: 12),
        Text(L.wabistdo.yourCharacter.fmt({'name': kWaBistDoCharacters.firstWhere((c) => c.id==_myCharId!, orElse: () => kWaBistDoCharacters.first).name}),
            style: const TextStyle(color: kText, fontSize: 16)),
        const SizedBox(height: 8),
        Text(L.wabistdo.waitingChoice.fmt({'player': (1-_myIdx >= 0 && 1-_myIdx < widget.players.length) ? widget.players[1-_myIdx].name : '?'}),
            style: const TextStyle(color: kMuted)),
      ]),
    ));

    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12,12,12,4),
        child: Text(L.wabistdo.chooseCharacter,
            style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.bold))),
      Expanded(child: LayoutBuilder(builder: (context, box) {
        final cols = _gridCols(box.maxWidth, box.maxHeight, kWaBistDoCharacters.length);
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols, childAspectRatio: .78, mainAxisSpacing: 5, crossAxisSpacing: 5),
          itemCount: kWaBistDoCharacters.length,
          itemBuilder: (_, i) {
            final c = kWaBistDoCharacters[i];
            return GestureDetector(
              onTap: () => _chooseCharacter(c.id),
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder)),
                child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(painter: FacePainter(c), child: const SizedBox.expand())),
              ),
            );
          },
        );
      })),
    ]);
  }

  // ── Playing ────────────────────────────────────────────────────────────────

  Widget _buildPlay() {
    final myChar   = _myCharId != null ? kWaBistDoCharacters.firstWhere((c) => c.id==_myCharId!, orElse: () => kWaBistDoCharacters.first) : null;
    final remaining = kWaBistDoCharacters.length - _eliminated.length;

    return Column(children: [
      PlayerBar(players: widget.players, activeIdx: -1),
      GameStatusBar(text: '${_eliminated.length} ↓  $remaining ↑'),

      // My character peek bar
      if (myChar != null) GestureDetector(
        onTap: () => setState(() => _showMyChar = !_showMyChar),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          height: _showMyChar ? 88 : 34,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(color: kBg2, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kPurple.withValues(alpha: .4))),
          clipBehavior: Clip.hardEdge,
          child: _showMyChar
            ? Row(children: [
                const SizedBox(width: 6),
                SizedBox(width: 58, height: 82,
                  child: CustomPaint(painter: FacePainter(myChar), child: const SizedBox.expand())),
                const SizedBox(width: 8),
                Expanded(child: Text(myChar.name,
                    style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.bold))),
                const Icon(Icons.visibility_off, color: kMuted, size: 16),
                const SizedBox(width: 8),
              ])
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.visibility, color: kMuted, size: 14),
                const SizedBox(width: 6),
                Text(L.wabistdo.yourCharacter.fmt({'name': '●●●'}),
                    style: const TextStyle(color: kMuted, fontSize: 11)),
              ]),
        ),
      ),

      // Mode hint
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Text(
          _guessMode ? '👆 ${L.wabistdo.guess}' : L.wabistdo.questionPrompt,
          style: TextStyle(color: _guessMode ? kGreen : kMuted, fontSize: 11,
              fontWeight: _guessMode ? FontWeight.bold : FontWeight.normal))),

      // Face grid
      Expanded(child: LayoutBuilder(builder: (context, box) {
        final cols = _gridCols(box.maxWidth, box.maxHeight, kWaBistDoCharacters.length);
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(5),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols, childAspectRatio: .78, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: kWaBistDoCharacters.length,
          itemBuilder: (_, i) {
            final c    = kWaBistDoCharacters[i];
            final elim = _eliminated.contains(c.id);
            return GestureDetector(
              onTap: () => _onTapFace(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _guessMode && !elim ? kGreen.withValues(alpha: .7) : elim ? Colors.black12 : kBorder,
                    width: _guessMode && !elim ? 2 : 1)),
                child: ClipRRect(borderRadius: BorderRadius.circular(7),
                  child: CustomPaint(painter: FacePainter(c, eliminated: elim),
                      child: const SizedBox.expand())),
              ),
            );
          },
        );
      })),

      // Action bar
      Padding(padding: const EdgeInsets.fromLTRB(12,4,12,10),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => setState(() => _guessMode = false),
            icon: const Icon(Icons.flip, size: 15),
            label: const Text('Flip'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _guessMode ? kMuted : kText,
              side: BorderSide(color: _guessMode ? kBorder : kPurple)))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            onPressed: () => setState(() => _guessMode = true),
            icon: const Icon(Icons.emoji_people, size: 15),
            label: Text(L.wabistdo.guessBtn),
            style: ElevatedButton.styleFrom(
              backgroundColor: _guessMode ? kGreen.withValues(alpha: .25) : kPurple.withValues(alpha: .25),
              foregroundColor: _guessMode ? kGreen : kText,
              side: BorderSide(color: _guessMode ? kGreen : kPurple)))),
        ]),
      ),
    ]);
  }

  // ── Game over ──────────────────────────────────────────────────────────────

  Widget _buildOver() {
    final opChar = _opCharId != null
        ? kWaBistDoCharacters.firstWhere((c) => c.id == _opCharId!, orElse: () => kWaBistDoCharacters.first)
        : null;
    return Column(children: [
      Expanded(child: Center(child: opChar == null ? const SizedBox() : Column(mainAxisSize: MainAxisSize.min, children: [
        Text(L.wabistdo.whoIsIt, style: const TextStyle(color: kMuted, fontSize: 14)),
        const SizedBox(height: 8),
        SizedBox(width: 120, height: 152,
          child: CustomPaint(painter: FacePainter(opChar), child: const SizedBox.expand())),
        const SizedBox(height: 6),
        Text(opChar.name, style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.bold)),
      ]))),
      GameResultBanner(
        players: widget.players,
        winnerIdx: _winner == 3 ? -1 : _winner - 1,
        onFirstRender: () {
          final wi = _winner == 3 ? -1 : _winner - 1;
          fireConfettiOnce(wi);
          recordResult('wabistdo', wi);
          if (_net.isHost) _session.advanceGame();
        },
      ),
      GameOverActions(players: widget.players, onReset: _reset),
    ]);
  }
}
