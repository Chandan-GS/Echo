import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The moods Echo — the "sound sprite" mascot — can express. Each maps to a
/// real app moment: [idle] resting on the home screen, [listening] while
/// notifications are captured, [thinking] while a briefing generates,
/// [speaking] during playback, and [sleeping] for empty / inactive states.
enum EchoState { idle, listening, thinking, speaking, sleeping }

/// A self-contained, animated rendering of the Echo mascot — a luminous
/// pearlescent orb with a calm two-eye face and soft light rings that ripple
/// inward (listening) or outward (speaking), swirl into an orbital band
/// (thinking), or settle with a gentle glow (idle / sleeping).
///
/// Drop it in anywhere and drive it with [state]; it owns its own animation.
class EchoMascot extends StatefulWidget {
  final EchoState state;
  final double size;

  const EchoMascot({super.key, this.state = EchoState.idle, this.size = 140});

  @override
  State<EchoMascot> createState() => _EchoMascotState();
}

class _EchoMascotState extends State<EchoMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) =>
              CustomPaint(painter: _EchoPainter(_c.value, widget.state, isDark)),
        ),
      ),
    );
  }
}

// ── Painting ─────────────────────────────────────────────────────────────────

const _eye = Color(0xFF222F27);
const _glow = Color(0xFFD6EBDA);
const _botShade = Color(0xFF5E8568);

class _EchoPainter extends CustomPainter {
  final double t; // repeating 0..1
  final EchoState state;
  final bool isDark;
  _EchoPainter(this.t, this.state, this.isDark);

  static const _tau = 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 240; // design space is a 240×240 box
    Offset p(double x, double y) => Offset(x * k, y * k);
    double s(double v) => v * k;

    final orbC = p(120, 120);
    final orbR = s(56);
    final dim = state == EchoState.sleeping;

    // ── Ambient glow (softer on dark so Echo melts into the background) ──────
    final glowC = p(120, 122);
    final glowR = s(98);
    final glowAlpha = dim ? 0.5 : (isDark ? 0.5 : 0.9);
    canvas.drawCircle(
      glowC,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [_glow.withValues(alpha: glowAlpha), _glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: glowC, radius: glowR))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s(6)),
    );

    // ── Behind the orb: rings / orbital band back ─────────────────────────────
    switch (state) {
      case EchoState.idle:
        _ring(canvas, orbC, s(72), 0.75, k);
        _ring(canvas, orbC, s(88), 0.5, k);
        _ring(canvas, orbC, s(104), 0.3, k);
        break;
      case EchoState.listening:
        _rippleRings(canvas, orbC, s(76), k, inward: true);
        break;
      case EchoState.speaking:
        _rippleRings(canvas, orbC, s(76), k, inward: false);
        break;
      case EchoState.thinking:
        _band(canvas, orbC, k, front: false);
        break;
      case EchoState.sleeping:
        break;
    }

    // ── Orb + face (gentle float + breathe) ─────────────────────────────────
    final floatDy = s(dim ? 3 : 4) * math.sin(t * _tau);
    final breathe = 1 + 0.03 * math.sin(t * _tau);
    canvas.save();
    canvas.translate(0, floatDy);
    canvas.translate(orbC.dx, orbC.dy);
    canvas.scale(breathe);
    canvas.translate(-orbC.dx, -orbC.dy);
    _orb(canvas, orbC, orbR, dim);
    _eyes(canvas, p, s);
    canvas.restore();

    // ── In front of the orb ─────────────────────────────────────────────────
    if (state == EchoState.thinking) _band(canvas, orbC, k, front: true);
    if (state == EchoState.sleeping) _zzz(canvas, p, s);
  }

  // The glossy pearlescent sphere.
  void _orb(Canvas canvas, Offset c, double r, bool dim) {
    final rect = Rect.fromCircle(center: c, radius: r);
    final body = dim
        ? const [
            Color(0xFFF1F2EC),
            Color(0xFFD6E0D4),
            Color(0xFFAAC0AE),
          ]
        : const [
            Color(0xFFFFFFFF),
            Color(0xFFF4F9F0),
            Color(0xFFD9E8DB),
            Color(0xFFB4D1BA),
            Color(0xFF9EC0A6),
          ];
    final stops = dim ? const [0.0, 0.55, 1.0] : const [0.0, 0.30, 0.60, 0.84, 1.0];
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.10, 0.14),
          radius: 0.72,
          colors: body,
          stops: stops,
        ).createShader(rect),
    );
    // Bottom volume shading.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0.6),
          radius: 0.62,
          colors: [_botShade.withValues(alpha: 0), _botShade.withValues(alpha: 0), _botShade.withValues(alpha: 0.30)],
          stops: const [0.0, 0.72, 1.0],
        ).createShader(rect),
    );
    // Specular sheen + crisp catchlight (upper-left).
    final specC = Offset(c.dx - r * 0.32, c.dy - r * 0.46);
    canvas.save();
    canvas.translate(specC.dx, specC.dy);
    canvas.rotate(-0.42);
    final specRect = Rect.fromCenter(center: Offset.zero, width: r * 0.86, height: r * 0.54);
    canvas.drawOval(
      specRect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.95), Colors.white.withValues(alpha: 0)],
        ).createShader(specRect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
    );
    canvas.restore();
    canvas.drawCircle(
      Offset(c.dx - r * 0.39, c.dy - r * 0.54),
      r * 0.09,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04),
    );
  }

  void _eyes(Canvas canvas, Offset Function(double, double) p, double Function(double) s) {
    final open = state == EchoState.idle || state == EchoState.listening;
    if (open) {
      final paint = Paint()..color = _eye;
      canvas.drawOval(Rect.fromCenter(center: p(108, 120), width: s(11), height: s(17)), paint);
      canvas.drawOval(Rect.fromCenter(center: p(132, 120), width: s(11), height: s(17)), paint);
    } else {
      final paint = Paint()
        ..color = _eye
        ..style = PaintingStyle.stroke
        ..strokeWidth = s(3.2)
        ..strokeCap = StrokeCap.round;
      final l = Path()
        ..moveTo(p(101, 119).dx, p(101, 119).dy)
        ..quadraticBezierTo(p(108, 127).dx, p(108, 127).dy, p(115, 119).dx, p(115, 119).dy);
      final r = Path()
        ..moveTo(p(125, 119).dx, p(125, 119).dy)
        ..quadraticBezierTo(p(132, 127).dx, p(132, 127).dy, p(139, 119).dx, p(139, 119).dy);
      canvas.drawPath(l, paint);
      canvas.drawPath(r, paint);
    }
  }

  // A single soft glossy ring. On a dark background the bright white top of
  // the sheen reads as a harsh bold edge, so in dark mode we drop the top's
  // opacity right down and lean on the softer green so the ring melts into the
  // background instead of ringing out against it.
  void _ring(Canvas canvas, Offset c, double radius, double opacity, double k) {
    final rect = Rect.fromCircle(center: c, radius: radius);
    final f = opacity / 0.75;
    final topA = (isDark ? 0.06 : 0.92) * f;
    final midA = (isDark ? 0.16 : 0.6) * f;
    final botA = (isDark ? 0.12 : 0.3) * f;
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11 * k
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: topA),
            const Color(0xFFD8EADC).withValues(alpha: midA),
            const Color(0xFF98BEA2).withValues(alpha: botA),
          ],
          stops: const [0.0, 0.46, 1.0],
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.8 * k),
    );
  }

  // Three staggered rings rippling inward (listening) or outward (speaking).
  void _rippleRings(Canvas canvas, Offset c, double base, double k, {required bool inward}) {
    for (int i = 0; i < 3; i++) {
      final ph = (t + i / 3) % 1.0;
      final double scale;
      final double op;
      if (inward) {
        scale = _lerp(1.35, 0.55, ph);
        op = ph < 0.42 ? _lerp(0, 0.9, ph / 0.42) : _lerp(0.9, 0, (ph - 0.42) / 0.58);
      } else {
        scale = _lerp(0.62, 1.35, ph);
        op = _lerp(0.9, 0, ph);
      }
      _ring(canvas, c, base * scale, (op * 0.75).clamp(0.0, 0.75), k);
    }
  }

  // The tilted orbital "swirl" band for thinking — drawn in two halves so it
  // wraps behind and in front of the orb.
  void _band(Canvas canvas, Offset c, double k, {required bool front}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.32 + math.sin(t * _tau) * 0.05);
    final rect = Rect.fromCenter(center: Offset.zero, width: 164 * k, height: 66 * k);
    final topA = isDark ? (front ? 0.34 : 0.22) : (front ? 0.9 : 0.5);
    final midA = isDark ? (front ? 0.5 : 0.34) : (front ? 0.7 : 0.4);
    final botA = isDark ? (front ? 0.4 : 0.24) : (front ? 0.5 : 0.28);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (front ? 19 : 17) * k
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: topA),
          const Color(0xFFD8EADC).withValues(alpha: midA),
          const Color(0xFF98BEA2).withValues(alpha: botA),
        ],
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.8 * k);
    // front = lower half (nearest viewer), back = upper half.
    final path = Path()..addArc(rect, front ? 0 : math.pi, math.pi);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _zzz(Canvas canvas, Offset Function(double, double) p, double Function(double) s) {
    final paint = Paint()
      ..color = const Color(0xFF5A6B5C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s(2.8)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void z(double x, double y, double w, double delay) {
      final ph = (t + delay) % 1.0;
      final op = ph < 0.3 ? ph / 0.3 : (1 - (ph - 0.3) / 0.7);
      final rise = -ph * s(16);
      final dx = ph * s(8);
      paint.color = const Color(0xFF5A6B5C).withValues(alpha: op.clamp(0.0, 1.0));
      final path = Path()
        ..moveTo(p(x, y).dx + dx, p(x, y).dy + rise)
        ..lineTo(p(x + w, y).dx + dx, p(x + w, y).dy + rise)
        ..lineTo(p(x, y + w * 1.1).dx + dx, p(x, y + w * 1.1).dy + rise)
        ..lineTo(p(x + w, y + w * 1.1).dx + dx, p(x + w, y + w * 1.1).dy + rise);
      canvas.drawPath(path, paint);
    }

    z(158, 68, 10, 0);
    z(176, 54, 8, 0.5);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

  @override
  bool shouldRepaint(covariant _EchoPainter old) =>
      old.t != t || old.state != state || old.isDark != isDark;
}
