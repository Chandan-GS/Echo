import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// A static, full-bleed rendering of Echo's face for use as an app icon or
/// small brand mark — unlike [EchoMascot] (a small pearlescent orb floating
/// over a dark background with glow rings, meant for in-app moments), this
/// fills the entire square with Echo's green body and two eyes, edge to edge,
/// so the OS's own icon mask (circle, squircle, rounded square) can crop it
/// without ever revealing a background behind Echo.
class EchoIconArt extends StatelessWidget {
  final double size;
  const EchoIconArt({super.key, this.size = 1024});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EchoIconPainter()),
    );
  }
}

class _EchoIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Full-bleed green body, built from the app's own brand green — the
    // brighter "dark" variant (AppTheme.primaryGreenDark) rather than the
    // light-theme one: it's the exact same green family, just the version
    // the app itself already reaches for when it needs to read clearly and
    // vividly rather than sit quietly next to body text, which is exactly
    // what an icon needs. The plain primaryGreen rendered noticeably flatter
    // and duller once it filled the whole frame.
    const brandGreen = AppTheme.primaryGreenDark; // 0xFF5CA363
    final highlight = Color.lerp(brandGreen, Colors.white, 0.6)!;

    // Bright throughout — just a highlight fading into the brand green, no
    // darkened edge/shadow stop. The earlier version shaded down to near-
    // black at the corners and along the bottom, which read as a dull, dark
    // icon once it was shrunk to Dock/launcher size.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -0.25),
          radius: 1.2,
          colors: [highlight, brandGreen],
          stops: const [0.0, 1.0],
        ).createShader(rect),
    );

    // Specular sheen + crisp catchlight (upper-left) — the same glossy touch
    // as the orb, scaled to the full frame.
    final specC = Offset(c.dx - r * 0.32, c.dy - r * 0.46);
    canvas.save();
    canvas.translate(specC.dx, specC.dy);
    canvas.rotate(-0.42);
    final specRect = Rect.fromCenter(center: Offset.zero, width: r * 0.86, height: r * 0.54);
    canvas.drawOval(
      specRect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0)],
        ).createShader(specRect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
    );
    canvas.restore();
    canvas.drawCircle(
      Offset(c.dx - r * 0.39, c.dy - r * 0.54),
      r * 0.09,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.65)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05),
    );

    // Eyes — same proportions/spacing as EchoMascot's idle eyes, scaled from
    // the orb's own radius up to this full-frame radius.
    final eyeW = r * (11 / 56);
    final eyeH = r * (17 / 56);
    final eyeDx = r * (12 / 56);
    final eyePaint = Paint()..color = const Color(0xFF16241A);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx - eyeDx, c.dy), width: eyeW, height: eyeH),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx + eyeDx, c.dy), width: eyeW, height: eyeH),
      eyePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _EchoIconPainter oldDelegate) => false;
}
