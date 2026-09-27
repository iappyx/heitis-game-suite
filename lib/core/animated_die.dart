import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'theme.dart';

/// A die that animates through random faces before landing on [value].
/// [white] = white background with dark dots (Boppeslach).
/// [bgColor] = custom background color (Krúske colored dice). Dot color
///             is chosen automatically for contrast.
class AnimatedDie extends StatefulWidget {
  final int value;
  final bool rolling;
  final bool held;
  final bool white;
  final bool rupsFace; // if true, face 6 shows 🐛 instead of pips
  final Color? bgColor;
  final double size;
  final VoidCallback? onTap;

  const AnimatedDie({
    super.key,
    required this.value,
    this.rolling = false,
    this.rupsFace = false,
    this.held = false,
    this.white = false,
    this.bgColor,
    this.size = 44,
    this.onTap,
  });

  @override State<AnimatedDie> createState() => _AnimatedDieState();
}

class _AnimatedDieState extends State<AnimatedDie>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _wobble;
  int _displayValue = 1;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _displayValue = widget.value;
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
    _wobble = Tween(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticInOut));
  }

  @override
  void didUpdateWidget(AnimatedDie old) {
    super.didUpdateWidget(old);
    if (widget.rolling && !old.rolling) _startRoll();
    if (!widget.rolling && old.rolling) _stopRoll();
  }

  void _startRoll() {
    _ctrl.repeat(reverse: true);
    _ticker = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) setState(() => _displayValue = Random().nextInt(6) + 1);
    });
  }

  void _stopRoll() {
    _ticker?.cancel();
    _ctrl.stop();
    _ctrl.reset();
    if (mounted) setState(() => _displayValue = widget.value);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // Pick black or white dot color based on background luminance.
  Color _dotColor(Color bg) {
    final r = bg.red / 255.0;
    final g = bg.green / 255.0;
    final b = bg.blue / 255.0;
    final luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return luminance > 0.45 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color faceColor;

    if (widget.held) {
      bg        = const Color(0xFF2D1060);
      faceColor = kPurple;
    } else if (widget.bgColor != null) {
      bg        = widget.bgColor!;
      faceColor = _dotColor(bg);
    } else if (widget.white) {
      bg        = Colors.white;
      faceColor = kBg;
    } else {
      bg        = const Color(0xFF1F1035);
      faceColor = Colors.white;
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _wobble,
        builder: (_, child) => Transform.rotate(
          angle: _wobble.value * 0.03,
          child: Transform.translate(
            offset: Offset(_wobble.value * 0.5, 0),
            child: child,
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.size, height: widget.size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.size * 0.2),
            border: Border.all(
              color: widget.held ? kPurple : Colors.white24,
              width: widget.held ? 2 : 1),
            boxShadow: widget.held
                ? [BoxShadow(color: kPurple.withValues(alpha: .5), blurRadius: 10)]
                : [BoxShadow(color: Colors.black38, blurRadius: 4,
                    offset: const Offset(1, 2))],
          ),
          child: _displayValue == 6 && widget.rupsFace
              ? Center(child: Text('🐛',
                  style: TextStyle(fontSize: widget.size * 0.52, fontFamilyFallback: ['NotoColorEmoji']),
                  textAlign: TextAlign.center))
              : CustomPaint(
                  painter: _PuntenEnFakjesPainter(value: _displayValue, color: faceColor),
                ),
        ),
      ),
    );
  }
}

class _PuntenEnFakjesPainter extends CustomPainter {
  final int value;
  final Color color;
  _PuntenEnFakjesPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = size.width * 0.09;
    for (final p in _pips(value, size)) canvas.drawCircle(p, r, paint);
  }

  List<Offset> _pips(int v, Size s) {
    final x1 = s.width * 0.28, x2 = s.width * 0.5, x3 = s.width * 0.72;
    final y1 = s.height * 0.28, y2 = s.height * 0.5, y3 = s.height * 0.72;
    switch (v) {
      case 1: return [Offset(x2, y2)];
      case 2: return [Offset(x1, y1), Offset(x3, y3)];
      case 3: return [Offset(x1, y1), Offset(x2, y2), Offset(x3, y3)];
      case 4: return [Offset(x1, y1), Offset(x3, y1), Offset(x1, y3), Offset(x3, y3)];
      case 5: return [Offset(x1, y1), Offset(x3, y1), Offset(x2, y2),
                      Offset(x1, y3), Offset(x3, y3)];
      case 6: return [Offset(x1, y1), Offset(x3, y1), Offset(x1, y2),
                      Offset(x3, y2), Offset(x1, y3), Offset(x3, y3)];
      default: return [];
    }
  }

  @override bool shouldRepaint(_PuntenEnFakjesPainter old) =>
      old.value != value || old.color != color;
}
