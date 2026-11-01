import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ButlerState { idle, listening, thinking, speaking, acting }

class ButlerAvatar extends StatefulWidget {
  final ButlerState state;
  const ButlerAvatar({super.key, required this.state});
  @override
  State<ButlerAvatar> createState() => _ButlerAvatarState();
}

class _ButlerAvatarState extends State<ButlerAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: c,
          builder: (_, __) => CustomPaint(painter: _ButlerPainter(c.value * 6, widget.state)),
        ),
      ),
    );
  }
}

class _ButlerPainter extends CustomPainter {
  final double t;
  final ButlerState s;
  _ButlerPainter(this.t, this.s);

  @override
  bool shouldRepaint(_ButlerPainter old) => old.t != t || old.s != s;

  Paint fill(int c) => Paint()..color = Color(c);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final cx = size.width / 2;
    final tau = 2 * math.pi;
    final b = math.sin(t * tau / 3) * 2;
    final blink = (t % 3) > 2.85;
    final acting = s == ButlerState.acting;
    final speaking = s == ButlerState.speaking;
    const skin = 0xFFEBC4A0;
    const gray = 0xFFD0D0D0;
    const brow = 0xFFB0B0B0;
    const black = 0xFF1B1B1F;
    const white = 0xFFFFFFFF;

    if (acting) {
      final on = (t % 3) > 1.5;
      final sw = Rect.fromCenter(center: Offset(cx + 112, 82), width: 28, height: 42);
      if (on) canvas.drawCircle(sw.center, 34, fill(0x44FFD54F));
      canvas.drawRRect(RRect.fromRectAndRadius(sw, const Radius.circular(5)), fill(0xFFEEEEEE));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(sw.center.dx, sw.center.dy + (on ? -6 : 6)), width: 12, height: 16),
            const Radius.circular(3)),
        fill(on ? 0xFFFFB300 : 0xFF9E9E9E),
      );
    }

    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cx - 72, 116 + b, 16, 56), const Radius.circular(8)), fill(black));
    canvas.drawCircle(Offset(cx - 64, 176 + b), 9, fill(white));

    canvas.drawRRect(
      RRect.fromRectAndCorners(Rect.fromLTWH(cx - 60, 106 + b, 120, h - 106),
          topLeft: const Radius.circular(40), topRight: const Radius.circular(40)),
      fill(black),
    );
    final shirt = Path()
      ..moveTo(cx - 18, 108 + b)
      ..lineTo(cx + 18, 108 + b)
      ..lineTo(cx + 10, h)
      ..lineTo(cx - 10, h)
      ..close();
    canvas.drawPath(shirt, fill(white));
    final bow = Path()
      ..moveTo(cx, 116 + b)
      ..lineTo(cx - 14, 108 + b)
      ..lineTo(cx - 14, 124 + b)
      ..close()
      ..moveTo(cx, 116 + b)
      ..lineTo(cx + 14, 108 + b)
      ..lineTo(cx + 14, 124 + b)
      ..close();
    canvas.drawPath(bow, fill(0xFF8B0000));
    canvas.drawCircle(Offset(cx, 116 + b), 3.5, fill(0xFF5C0000));

    canvas.save();
    canvas.translate(cx + 56, 116 + b);
    canvas.rotate(acting ? -2.2 + 0.1 * math.sin(t * tau * 2) : 0.0);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-8, 0, 16, 56), const Radius.circular(8)), fill(black));
    canvas.drawCircle(const Offset(0, 60), 9, fill(white));
    canvas.restore();

    canvas.save();
    canvas.translate(cx, 104 + b);
    canvas.rotate(s == ButlerState.listening ? 0.12 : 0.0);
    canvas.drawRect(Rect.fromCenter(center: const Offset(0, -6), width: 20, height: 16), fill(skin));
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -42), width: 62, height: 74), fill(skin));
    canvas.drawCircle(const Offset(-31, -42), 6, fill(skin));
    canvas.drawCircle(const Offset(31, -42), 6, fill(skin));
    canvas.drawOval(Rect.fromCenter(center: const Offset(-30, -52), width: 12, height: 30), fill(gray));
    canvas.drawOval(Rect.fromCenter(center: const Offset(30, -52), width: 12, height: 30), fill(gray));
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(0, -56), width: 62, height: 46),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = const Color(gray)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    for (final x in [-12.0, 12.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, -46), width: 12, height: blink ? 1.2 : 8), fill(white));
      if (!blink) canvas.drawCircle(Offset(x, -46), 2.6, fill(0xFF3B2F2F));
    }
    final browPaint = Paint()
      ..color = const Color(brow)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final up = s == ButlerState.thinking;
    canvas.drawLine(const Offset(-19, -55), const Offset(-6, -56), browPaint);
    canvas.drawLine(Offset(6, up ? -61 : -56), Offset(19, up ? -65 : -55), browPaint);
    final nose = Path()
      ..moveTo(0, -46)
      ..quadraticBezierTo(5, -34, -1, -32);
    canvas.drawPath(
      nose,
      Paint()
        ..color = const Color(0xFFC99A74)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (speaking) {
      final open = (0.5 + 0.5 * math.sin(t * tau * 2)) * 7;
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, -16), width: 14, height: 3 + open), fill(0xFF7A2E2E));
    } else {
      canvas.drawArc(
        Rect.fromCenter(center: const Offset(0, -19), width: 14, height: 8),
        0.2,
        math.pi - 0.4,
        false,
        Paint()
          ..color = const Color(0xFF7A2E2E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final mus = Path()
      ..moveTo(0, -27)
      ..quadraticBezierTo(-9, -35, -21, -25)
      ..quadraticBezierTo(-10, -21, 0, -24)
      ..quadraticBezierTo(10, -21, 21, -25)
      ..quadraticBezierTo(9, -35, 0, -27)
      ..close();
    canvas.drawPath(mus, fill(gray));
    canvas.restore();
  }
}
