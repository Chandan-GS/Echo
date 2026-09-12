import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/features/echo/presentation/widgets/pulsing_flame.dart';

/// A full-screen, immersive celebration shown the moment the user's streak
/// advances — a pulsing flame with rising embers, a bouncing count-up number,
/// and timed haptic pulses. Deliberately goes bold/dark (unlike the rest of
/// the app's warm paper palette) for dramatic impact, echoing the same
/// dark-canvas-with-glow language as the onboarding welcome screen.
class StreakCelebrationScreen extends StatefulWidget {
  final int days;

  const StreakCelebrationScreen({super.key, required this.days});

  @override
  State<StreakCelebrationScreen> createState() =>
      _StreakCelebrationScreenState();
}

class _StreakCelebrationScreenState extends State<StreakCelebrationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _emberLoop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  late final Animation<double> _numberCount = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: (widget.days - 1).clamp(0, widget.days).toDouble(),
        end: widget.days + 0.18,
      ),
      weight: 70,
    ),
    TweenSequenceItem(
      tween: Tween(begin: widget.days + 0.18, end: widget.days.toDouble()),
      weight: 30,
    ),
  ]).animate(CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
  ));

  late final Animation<double> _flameScaleIn = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
  );

  late final Animation<double> _fadeIn = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _entrance.forward();
    // A second, heavier pulse right as the number lands.
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _emberLoop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // Rising embers drifting up behind everything.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _emberLoop,
              builder: (context, _) => CustomPaint(
                painter: _EmberPainter(progress: _emberLoop.value),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // Pulsing flame emoji that springs in — no number overlaid,
                  // the count lives in the caption below.
                  AnimatedBuilder(
                    animation: _entrance,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _flameScaleIn.value,
                        child: child,
                      );
                    },
                    child: const PulsingFlame(size: 96),
                  ),

                  const SizedBox(height: 28),

                  FadeTransition(
                    opacity: _fadeIn,
                    child: AnimatedBuilder(
                      animation: _numberCount,
                      builder: (context, _) {
                        final n = _numberCount.value.round();
                        return Text(
                          '$n day${n == 1 ? '' : 's'} strong',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.oldStandardTt(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  FadeTransition(
                    opacity: _fadeIn,
                    child: Text(
                      "You're keeping the habit alive. Echo's proud of you.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                    ),
                  ),

                  const Spacer(),

                  FadeTransition(
                    opacity: _fadeIn,
                    child: EchoButton(
                      text: 'Continue',
                      backgroundColor: const Color(0xFFF4F2EE),
                      textColor: const Color(0xFF1E1E1E),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A handful of small warm-colored embers drifting upward and fading, looping
/// seamlessly — a lightweight hand-rolled particle effect (no new dependency),
/// matching the welcome screen's precedent of a bespoke CustomPainter effect.
class _EmberPainter extends CustomPainter {
  final double progress; // 0..1, loops

  _EmberPainter({required this.progress});

  static const _seeds = [0.05, 0.2, 0.35, 0.5, 0.65, 0.8, 0.92];

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(7); // fixed seed → stable layout across frames
    for (int i = 0; i < _seeds.length; i++) {
      final xFrac = _seeds[i];
      final speedJitter = 0.6 + random.nextDouble() * 0.8;
      final phase = (progress * speedJitter + xFrac) % 1.0;

      final x = size.width * xFrac + sin(phase * 2 * pi) * 14;
      final y = size.height * (1 - phase);
      final opacity = (sin(phase * pi)).clamp(0.0, 1.0) * 0.6;
      final radius = 2.0 + 2.0 * ((i % 3) / 2);

      final paint = Paint()
        ..color = const Color(0xFFFFA24D).withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmberPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
