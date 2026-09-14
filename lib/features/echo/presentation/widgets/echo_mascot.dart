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

  /// Forces the ring/glow treatment instead of auto-detecting the theme
  /// brightness. Pass `false` to keep the bright, glowing rings even on a dark
  /// surface (e.g. the immersive voice mode's dark focus background).
  final bool? isDark;

  /// Renders soft, symmetric *green glowing* sonar rings and a green halo
  /// instead of the pearlescent white sheen — the polished look for the large,
  /// hero mascot on the immersive voice mode's dark focus background.
  final bool voiceGlow;

  /// Optional tap handler. Tapping Echo always plays a one-shot wink; if this
  /// is provided it's also called (so a surface that already reacts to a tap —
  /// e.g. voice mode's tap-to-speak — keeps working while Echo winks back).
  final VoidCallback? onTap;

  const EchoMascot({
    super.key,
    this.state = EchoState.idle,
    this.size = 140,
    this.isDark,
    this.voiceGlow = false,
    this.onTap,
  });

  @override
  State<EchoMascot> createState() => _EchoMascotState();
}

class _EchoMascotState extends State<EchoMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  // A free-running clock (never wraps) so the personality touches below —
  // blink, glance, head-turn, per-phase tilt — can each run on their own
  // period independent of the ripple/band animation's 2800ms cycle in `_c`.
  final Stopwatch _clock = Stopwatch()..start();

  // When a wink was last triggered (hover/tap), in clock-ms. null = not winking.
  double? _winkStartMs;
  static const double _winkDurationMs = 440;

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

  void _triggerWink() {
    // Ignore re-triggers while a wink is still playing so a hover jitter or
    // rapid taps don't stutter the eye.
    final now = _clock.elapsedMilliseconds.toDouble();
    if (_winkStartMs != null && now - _winkStartMs! < _winkDurationMs) return;
    _winkStartMs = now;
  }

  /// 1.0 = eye fully open; dips toward a near-closed value across one wink,
  /// then returns to 1.0 and stays there until the next trigger.
  double _winkAmount() {
    final start = _winkStartMs;
    if (start == null) return 1.0;
    final e = _clock.elapsedMilliseconds - start;
    if (e >= _winkDurationMs) return 1.0;
    final f = e / _winkDurationMs; // 0..1
    final close = f < 0.5 ? f / 0.5 : (1 - f) / 0.5; // 0→1→0
    return 1.0 - close * (1.0 - 0.08);
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        widget.isDark ?? (Theme.of(context).brightness == Brightness.dark);
    Widget mascot = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _EchoPainter(
            _c.value,
            _clock.elapsedMilliseconds.toDouble(),
            widget.state,
            isDark,
            widget.voiceGlow,
            _winkAmount(),
          ),
        ),
      ),
    );

    // Wink on tap (always) and on hover (desktop). The GestureDetector is
    // translucent so it never blocks a parent's gestures, and it forwards the
    // tap to [onTap] when provided.
    mascot = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _triggerWink();
        widget.onTap?.call();
      },
      child: MouseRegion(
        onEnter: (_) => _triggerWink(),
        child: mascot,
      ),
    );

    return SizedBox(width: widget.size, height: widget.size, child: mascot);
  }
}

// ── Painting ─────────────────────────────────────────────────────────────────

const _eye = Color(0xFF222F27);
const _glow = Color(0xFFD6EBDA);
const _glowGreen = Color(0xFF7FE0A0);
const _ringGreen = Color(0xFF8FE0A6);
const _botShade = Color(0xFF5E8568);

class _EchoPainter extends CustomPainter {
  final double t; // repeating 0..1, drives ripples/band (unchanged timing)
  final double ms; // free-running elapsed ms, drives personality touches
  final EchoState state;
  final bool isDark;
  final bool voiceGlow;
  final double winkAmount; // 1.0 open; dips during a hover/tap-triggered wink
  _EchoPainter(
    this.t,
    this.ms,
    this.state,
    this.isDark,
    this.voiceGlow,
    this.winkAmount,
  );

  static const _tau = 2 * math.pi;

  double _smooth(double x) => x * x * (3 - 2 * x);

  // A calm "looking around" value in [-1, 1]: Echo darts its gaze to a new
  // spot every few seconds and holds it, rather than sweeping mechanically.
  // Deterministic (seeded off the segment index) so it needs no stored state
  // and stays smooth frame-to-frame. Drives both the idle head-turn and the
  // eye glance so the eyes lead where the head leans — like the website mascot.
  double _idleLook(double ms) {
    const seg = 3200.0; // a new glance target roughly every ~3s
    final idx = (ms / seg).floor();
    double target(int i) {
      final r = ((i * 1103515245 + 12345) & 0x7fffffff) % 1000 / 1000.0;
      return r * 2 - 1; // -1..1
    }
    final prev = target(idx - 1);
    final cur = target(idx);
    final f = (ms % seg) / seg; // 0..1 within the segment
    final e = f < 0.28 ? _smooth(f / 0.28) : 1.0; // quick move, then hold
    return prev + (cur - prev) * e;
  }

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
    final glowR = s(voiceGlow ? 104 : 98);
    final glowBase = voiceGlow ? _glowGreen : _glow;
    final glowAlpha = voiceGlow ? 0.5 : (dim ? 0.5 : (isDark ? 0.5 : 0.9));
    canvas.drawCircle(
      glowC,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glowBase.withValues(alpha: glowAlpha),
            glowBase.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: glowC, radius: glowR))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s(voiceGlow ? 10 : 6)),
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

    // ── Orb + face (gentle float + breathe + a per-phase head tilt) ─────────
    // The tilt/scale-per-phase is the same personality touch as the website
    // mascot: a small perk-up while listening, a lean-in while thinking, a
    // little pop while speaking — Echo reacting rather than just idling.
    final floatDy = s(dim ? 3 : 4) * math.sin(t * _tau);
    final breathe = 1 + 0.03 * math.sin(t * _tau);
    double tiltDx = 0, tiltDy = 0, tiltRot = 0, tiltScale = 1.0;
    switch (state) {
      case EchoState.listening:
        tiltDy = -s(1.5);
        tiltRot = 0.035;
        tiltScale = 1.02;
        break;
      case EchoState.thinking:
        tiltDx = -s(2.5);
        tiltDy = -s(3);
        tiltRot = -0.1;
        break;
      case EchoState.speaking:
        tiltDy = s(0.6);
        tiltRot = 0.026;
        tiltScale = 1.015;
        break;
      case EchoState.idle:
        // Occasional gentle head-turn — Echo glancing about while it rests,
        // leaning slightly toward wherever it just looked.
        final look = _idleLook(ms);
        tiltDx = s(3.0) * look;
        tiltRot = 0.05 * look;
        break;
      case EchoState.sleeping:
        break;
    }
    canvas.save();
    canvas.translate(0, floatDy);
    canvas.translate(orbC.dx, orbC.dy);
    canvas.scale(breathe);
    canvas.translate(tiltDx, tiltDy);
    canvas.rotate(tiltRot);
    canvas.scale(tiltScale);
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

  // Periodic pulse: 1.0 most of the time, briefly dipping toward `min` once
  // per `periodMs`, at `phaseMs` into the cycle. Used for both the full blink
  // (both eyes) and the solo wink (left eye only, its own period/phase so it
  // never coincides with the blink).
  double _pulse(double ms, double periodMs, double phaseMs, double min) {
    final ph = ((ms + phaseMs) % periodMs) / periodMs;
    if (ph < 0.9) return 1.0;
    // 0.9..1.0 of the cycle: dip down and back up (a quick close-open).
    final d = (ph - 0.9) / 0.1; // 0..1
    final close = d < 0.5 ? d / 0.5 : (1 - d) / 0.5;
    return 1.0 - close * (1.0 - min);
  }

  void _eyes(Canvas canvas, Offset Function(double, double) p, double Function(double) s) {
    final open = state == EchoState.idle || state == EchoState.listening;
    if (open) {
      final listening = state == EchoState.listening;
      // A little wider and taller when listening — Echo perking up to hear —
      // matching the "surprised" eyes on the website mascot.
      final w = listening ? s(12.5) : s(11);
      final h = listening ? s(19) : s(17);
      final blink = _pulse(ms, 4600, 0, 0.12);
      final paint = Paint()..color = _eye;

      void eye(double cx, double cy, double scaleY) {
        canvas.save();
        canvas.translate(p(cx, cy).dx, p(cx, cy).dy);
        canvas.scale(1, scaleY);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          paint,
        );
        canvas.restore();
      }

      // Eyes follow the idle head-turn (leading it slightly) so the gaze tracks
      // where Echo is looking; held fixed/alert while listening. The wink is no
      // longer automatic — it only plays on hover/tap, applied to the left eye.
      final look = listening ? 0.0 : _idleLook(ms);
      final glance = s(4.2) * look;
      canvas.save();
      canvas.translate(glance, 0);
      eye(108, 120, blink * winkAmount); // left eye: blink + interactive wink
      eye(132, 120, blink); // right eye: blink only
      canvas.restore();
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
    // Voice mode: a soft, symmetric green glow ring — no white sheen, wider
    // blur so it reads as a luminous sonar wave rather than a hard band.
    if (voiceGlow) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5 * k
          ..color = _ringGreen.withValues(alpha: (opacity * 0.85).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.5 * k),
      );
      return;
    }
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
    final Paint paint;
    if (voiceGlow) {
      paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (front ? 12 : 10) * k
        ..strokeCap = StrokeCap.round
        ..color = _ringGreen.withValues(alpha: front ? 0.85 : 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.5 * k);
    } else {
      final topA = isDark ? (front ? 0.34 : 0.22) : (front ? 0.9 : 0.5);
      final midA = isDark ? (front ? 0.5 : 0.34) : (front ? 0.7 : 0.4);
      final botA = isDark ? (front ? 0.4 : 0.24) : (front ? 0.5 : 0.28);
      paint = Paint()
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
    }
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
      old.t != t ||
      old.ms != ms ||
      old.state != state ||
      old.isDark != isDark ||
      old.voiceGlow != voiceGlow ||
      old.winkAmount != winkAmount;
}
