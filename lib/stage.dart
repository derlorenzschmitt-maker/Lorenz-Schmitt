import 'dart:math' as math;
import 'package:flutter/material.dart';

enum StageKind { blinds, light, search, weather, timer, home, climate, phone, whatsapp, translate, generic }

class ActionStage extends StatefulWidget {
  final StageKind kind;
  final bool done;
  final bool on;
  const ActionStage({super.key, required this.kind, this.done = false, this.on = true});
  @override
  State<ActionStage> createState() => _ActionStageState();
}

class _ActionStageState extends State<ActionStage> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => CustomPaint(
        painter: _StagePainter(widget.kind, c.value, widget.done, widget.on),
        size: Size.infinite,
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  final StageKind kind;
  final double t;
  final bool done;
  final bool on;
  _StagePainter(this.kind, this.t, this.done, this.on);

  static const gold = Color(0xFFFFC857);
  static const cyan = Color(0xFF4DD0E1);
  static const green = Color(0xFF69F0AE);

  Paint stroke(Color col, double w) => Paint()
    ..color = col
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;
  Paint fill(Color col) => Paint()
    ..color = col
    ..style = PaintingStyle.fill;

  void icon(Canvas canvas, IconData ic, Offset c, double size, Color col) {
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(ic.codePoint), style: TextStyle(fontSize: size, fontFamily: ic.fontFamily, package: ic.fontPackage, color: col)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = math.min(s.width, s.height) / 2 * 0.8;
    switch (kind) {
      case StageKind.blinds:
        blinds(canvas, c, r);
        break;
      case StageKind.light:
        light(canvas, c, r);
        break;
      case StageKind.search:
        search(canvas, c, r);
        break;
      case StageKind.weather:
        weather(canvas, c, r);
        break;
      case StageKind.timer:
        timer(canvas, c, r);
        break;
      case StageKind.home:
        home(canvas, c, r);
        break;
      case StageKind.climate:
        climate(canvas, c, r);
        break;
      case StageKind.phone:
        phone(canvas, c, r);
        break;
      case StageKind.whatsapp:
        whatsapp(canvas, c, r);
        break;
      case StageKind.translate:
        translate(canvas, c, r);
        break;
      case StageKind.generic:
        generic(canvas, c, r);
        break;
    }
    if (done) {
      final p = c + Offset(r * 0.85, r * 0.85);
      canvas.drawCircle(p, r * 0.22, fill(green));
      icon(canvas, Icons.check, p, r * 0.3, Colors.black);
    }
  }

  void blinds(Canvas canvas, Offset c, double r) {
    final w = r * 1.5;
    final h = r * 1.8;
    final rect = Rect.fromCenter(center: c, width: w, height: h);
    final e = Curves.easeInOut.transform(t);
    final p = done ? (on ? 1.0 : 0.0) : (on ? e : 1 - e);
    canvas.drawRect(rect, fill(const Color(0xFF1B2A41)));
    final glow = Paint()..shader = LinearGradient(colors: [gold.withOpacity(0.35), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(rect);
    canvas.drawRect(rect, glow);
    const n = 10;
    final sh = h / n;
    final covered = h * p;
    for (var i = 0; i < n; i++) {
      final y = rect.top + i * sh;
      if (y + sh * 0.5 > rect.top + covered) break;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.left + 4, y + 2, w - 8, sh - 4), const Radius.circular(3)), fill(const Color(0xFFB0BEC5)));
    }
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + covered - 3, w, 6), fill(gold));
    canvas.drawRect(rect, stroke(Colors.white70, 6));
  }

  void light(Canvas canvas, Offset c, double r) {
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final lit = on;
    final col = lit ? gold : Colors.blueGrey;
    if (lit) {
      final gr = r * (0.9 + 0.25 * pulse);
      canvas.drawCircle(c, gr, Paint()..shader = RadialGradient(colors: [gold.withOpacity(0.55), Colors.transparent]).createShader(Rect.fromCircle(center: c, radius: gr)));
      for (var i = 0; i < 12; i++) {
        final a = t * 2 * math.pi * 0.25 + i * math.pi / 6;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r * 0.62, c + Offset(math.cos(a), math.sin(a)) * r * (0.78 + 0.1 * pulse), stroke(gold, 5));
      }
    }
    canvas.drawCircle(c - Offset(0, r * 0.08), r * 0.38, fill(lit ? Color.lerp(gold, Colors.white, 0.5 * pulse)! : const Color(0xFF37474F)));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, r * 0.38), width: r * 0.34, height: r * 0.24), const Radius.circular(6)), fill(col));
    canvas.drawLine(c + Offset(-r * 0.12, r * 0.5), c + Offset(r * 0.12, r * 0.5), stroke(Colors.black54, 4));
  }

  void search(Canvas canvas, Offset c, double r) {
    final gr = r * 0.6;
    canvas.drawCircle(c, gr, stroke(cyan, 5));
    canvas.drawLine(c - Offset(gr, 0), c + Offset(gr, 0), stroke(cyan.withOpacity(0.5), 3));
    for (var i = 0; i < 3; i++) {
      final k = math.cos(t * 2 * math.pi + i * math.pi / 3).abs();
      canvas.drawOval(Rect.fromCenter(center: c, width: gr * 2 * k, height: gr * 2), stroke(cyan.withOpacity(0.7), 3));
    }
    for (var i = -1; i <= 1; i += 2) {
      final yy = gr * 0.5 * i;
      final hw = math.sqrt(gr * gr - yy * yy);
      canvas.drawLine(c + Offset(-hw, yy), c + Offset(hw, yy), stroke(cyan.withOpacity(0.4), 2));
    }
    final a = t * 2 * math.pi;
    final lp = c + Offset(math.cos(a), math.sin(a)) * r * 0.85;
    canvas.drawCircle(lp, r * 0.2, fill(Colors.white10));
    canvas.drawCircle(lp, r * 0.2, stroke(gold, 6));
    canvas.drawLine(lp + Offset(math.cos(a + 0.8), math.sin(a + 0.8)) * r * 0.2, lp + Offset(math.cos(a + 0.8), math.sin(a + 0.8)) * r * 0.42, stroke(gold, 9));
  }

  void weather(Canvas canvas, Offset c, double r) {
    final sc = c + Offset(-r * 0.2, -r * 0.2);
    for (var i = 0; i < 12; i++) {
      final a = t * 2 * math.pi * 0.3 + i * math.pi / 6;
      canvas.drawLine(sc + Offset(math.cos(a), math.sin(a)) * r * 0.5, sc + Offset(math.cos(a), math.sin(a)) * r * 0.68, stroke(gold, 5));
    }
    canvas.drawCircle(sc, r * 0.38, fill(gold));
    final bob = math.sin(t * 2 * math.pi) * r * 0.05;
    final cc = c + Offset(r * 0.1, r * 0.25 + bob);
    final cf = fill(Colors.white);
    canvas.drawCircle(cc + Offset(-r * 0.3, 0), r * 0.25, cf);
    canvas.drawCircle(cc + Offset(0, -r * 0.15), r * 0.32, cf);
    canvas.drawCircle(cc + Offset(r * 0.32, 0), r * 0.22, cf);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: cc + Offset(0, r * 0.08), width: r * 0.95, height: r * 0.3), const Radius.circular(20)), cf);
  }

  void timer(Canvas canvas, Offset c, double r) {
    final rr = r * 0.75;
    canvas.drawCircle(c, rr, stroke(Colors.white24, 10));
    canvas.drawArc(Rect.fromCircle(center: c, radius: rr), -math.pi / 2, t * 2 * math.pi, false, stroke(gold, 10));
    final a = -math.pi / 2 + t * 2 * math.pi;
    canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * rr * 0.85, stroke(Colors.white, 6));
    canvas.drawCircle(c, 9, fill(Colors.white));
    canvas.drawRect(Rect.fromCenter(center: c - Offset(0, rr + 18), width: 26, height: 12), fill(Colors.white70));
  }

  void home(Canvas canvas, Offset c, double r) {
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final roof = Path()
      ..moveTo(c.dx - r * 0.8, c.dy - r * 0.1)
      ..lineTo(c.dx, c.dy - r * 0.8)
      ..lineTo(c.dx + r * 0.8, c.dy - r * 0.1);
    canvas.drawPath(roof, stroke(cyan, 8));
    final body = Rect.fromLTRB(c.dx - r * 0.65, c.dy - r * 0.1, c.dx + r * 0.65, c.dy + r * 0.7);
    canvas.drawRect(body, stroke(cyan, 8));
    final win = fill(gold.withOpacity(0.3 + 0.7 * pulse));
    canvas.drawRect(Rect.fromLTWH(body.left + r * 0.2, body.top + r * 0.2, r * 0.3, r * 0.3), win);
    canvas.drawRect(Rect.fromLTWH(body.right - r * 0.5, body.top + r * 0.2, r * 0.3, r * 0.3), win);
    canvas.drawRect(Rect.fromLTWH(c.dx - r * 0.12, body.bottom - r * 0.4, r * 0.24, r * 0.4), fill(cyan));
    final sa = t * 2 * math.pi;
    canvas.drawCircle(c + Offset(math.cos(sa), math.sin(sa)) * r * 0.95, 8, fill(gold));
  }

  void climate(Canvas canvas, Offset c, double r) {
    final col = on ? cyan : Colors.deepOrangeAccent;
    for (var i = 0; i < 6; i++) {
      final a = t * 2 * math.pi * 0.2 + i * math.pi / 3;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c - d * r * 0.55, c + d * r * 0.55, stroke(col, 6));
      final tip = c + d * r * 0.55;
      final n = Offset(-d.dy, d.dx);
      canvas.drawLine(tip, tip - d * r * 0.15 + n * r * 0.12, stroke(col, 4));
      canvas.drawLine(tip, tip - d * r * 0.15 - n * r * 0.12, stroke(col, 4));
    }
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1;
      canvas.drawCircle(c, r * (0.3 + 0.7 * k), stroke(col.withOpacity(1 - k), 3));
    }
  }

  void phone(Canvas canvas, Offset c, double r) {
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1;
      canvas.drawCircle(c, r * (0.35 + 0.65 * k), stroke(green.withOpacity(1 - k), 5));
    }
    canvas.drawCircle(c, r * 0.38, fill(green));
    final sh = math.sin(t * 2 * math.pi * 6) * 0.12;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(sh);
    canvas.translate(-c.dx, -c.dy);
    icon(canvas, Icons.call, c, r * 0.45, Colors.black);
    canvas.restore();
  }

  void whatsapp(Canvas canvas, Offset c, double r) {
    final rect = Rect.fromCenter(center: c, width: r * 1.5, height: r * 1.1);
    final pop = 1 + 0.04 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(pop);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r * 0.3)), fill(const Color(0xFF25D366)));
    final tail = Path()
      ..moveTo(rect.left + r * 0.2, rect.bottom - 4)
      ..lineTo(rect.left - r * 0.05, rect.bottom + r * 0.3)
      ..lineTo(rect.left + r * 0.5, rect.bottom - 4);
    canvas.drawPath(tail, fill(const Color(0xFF25D366)));
    for (var i = 0; i < 3; i++) {
      final up = math.max(0.0, math.sin((t - i * 0.12) * 2 * math.pi));
      canvas.drawCircle(c + Offset((i - 1) * r * 0.3, -up * r * 0.12), r * 0.09, fill(Colors.white));
    }
    canvas.restore();
  }

  void translate(Canvas canvas, Offset c, double r) {
    final k = math.sin(t * 2 * math.pi);
    canvas.drawCircle(c + Offset(-r * 0.5 + k * r * 0.1, 0), r * 0.35, stroke(cyan, 6));
    canvas.drawCircle(c + Offset(r * 0.5 - k * r * 0.1, 0), r * 0.35, stroke(gold, 6));
    icon(canvas, Icons.translate, c + Offset(-r * 0.5 + k * r * 0.1, 0), r * 0.4, cyan);
    icon(canvas, Icons.language, c + Offset(r * 0.5 - k * r * 0.1, 0), r * 0.4, gold);
    icon(canvas, Icons.swap_horiz, c, r * 0.35, Colors.white);
  }

  void generic(Canvas canvas, Offset c, double r) {
    for (var i = 0; i < 8; i++) {
      final a = t * 2 * math.pi + i * math.pi / 4;
      final rad = r * 0.6;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * rad, 6 + 8 * ((i / 8 + t) % 1), fill(gold.withOpacity(0.3 + 0.7 * ((i / 8 + t) % 1))));
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => true;
}
