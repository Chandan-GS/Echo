import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';

class GeneratingView extends StatefulWidget {
  final String partial;
  const GeneratingView({super.key, required this.partial});

  @override
  State<GeneratingView> createState() => _GeneratingViewState();
}

class _GeneratingViewState extends State<GeneratingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _stepTimer;
  int _currentStepIndex = 0;

  static const List<String> _reasoningSteps = [
    'Accessing secure local vault…',
    'Analyzing semantic priority contexts…',
    'Ranking notification signals…',
    'Synthesizing summary briefings…',
    'Polishing output commentary…',
  ];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _stepTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          _currentStepIndex = (_currentStepIndex + 1) % _reasoningSteps.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusText = widget.partial.isNotEmpty
        ? widget.partial
        : _reasoningSteps[_currentStepIndex];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Echo is\nthinking…',
              style: GoogleFonts.oldStandardTt(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                height: 1.15,
                letterSpacing: -0.5,
              ),
            ),

            // Breathing gradient orb with sonar ripples — echoes the app's
            // audio/waveform identity. Expanded + FittedBox keeps it centered
            // and shrinks it gracefully on short/landscape layouts.
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return RepaintBoundary(
                          child: CustomPaint(
                            painter: _AuraPainter(
                              t: _controller.value,
                              green: colors.primaryGreen,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    axis: Axis.horizontal,
                    child: child,
                  ),
                ),
                child: _StatusPill(
                  key: ValueKey<String>(statusText),
                  text: statusText,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// The status chip using the app's contrast-safe selection colours so it reads
/// well in both light and dark mode.
class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final onSel = context.onSelection;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: context.selectionFill,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: onSel, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
                color: onSel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuraPainter extends CustomPainter {
  /// Repeating 0..1 animation phase.
  final double t;
  final Color green;

  _AuraPainter({required this.t, required this.green});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // ── Sonar ripples: three staggered rings expanding outward and fading ──
    const ringCount = 3;
    for (int i = 0; i < ringCount; i++) {
      final phase = (t + i / ringCount) % 1.0;
      final radius = 50 + phase * 58; // 50 → 108
      final opacity = (1 - phase) * 0.5;
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = green.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, ringPaint);
    }

    // ── Breathing orb ──────────────────────────────────────────────────────
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final orbRadius = 46 + 6 * breathe; // 46 → 52

    // Soft outer glow.
    final glowPaint = Paint()
      ..color = green.withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, orbRadius + 8, glowPaint);

    // Gradient body — lit from the upper-left, matching the streak/voice cards.
    final light = Color.lerp(green, Colors.white, 0.45)!;
    final dark = Color.lerp(green, Colors.black, 0.40)!;
    final orbRect = Rect.fromCircle(center: center, radius: orbRadius);
    final orbPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        radius: 1.1,
        colors: [light, green, dark],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(orbRect);
    canvas.drawCircle(center, orbRadius, orbPaint);

    // ── Inner audio bars ───────────────────────────────────────────────────
    const barCount = 5;
    const barWidth = 5.0;
    const gap = 5.0;
    const maxBarHeight = 34.0;
    final totalWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = center.dx - totalWidth / 2;
    final barPaint = Paint()..color = Colors.white.withValues(alpha: 0.95);
    // Per-bar resting heights give the cluster a natural waveform silhouette.
    const rest = [0.45, 0.85, 0.6, 0.95, 0.4];
    for (int i = 0; i < barCount; i++) {
      final wobble = 0.5 + 0.5 * math.sin((t * 1.6 + i * 0.16) * 2 * math.pi);
      final h = maxBarHeight * (0.35 + 0.65 * rest[i] * wobble + 0.1);
      final clamped = h.clamp(6.0, maxBarHeight);
      final left = startX + i * (barWidth + gap);
      final rect = Rect.fromLTWH(
        left,
        center.dy - clamped / 2,
        barWidth,
        clamped,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuraPainter old) =>
      old.t != t || old.green != green;
}
