import 'dart:math';
import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _entranceController;
  late Animation<double> _titleSlide;
  late Animation<double> _titleFade;

  @override
  void initState() {
    super.initState();

    // Continuous wave animation — runs forever
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // Staggered entrance for text elements
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    // Title: slides up and fades in (0.3 - 0.65)
    _titleSlide = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.6, curve: Curves.easeOut),
      ),
    );

    // Delay before the staggered entrance begins
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // — Full-screen flowing waveform background —
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _FlowingWavesPainter(
                    progress: _waveController.value,
                  ),
                );
              },
            ),
          ),

          // — Bottom gradient so text is readable —
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: screenHeight * 0.55,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0xCC0D0D0D),
                    Color(0xFF0D0D0D),
                  ],
                  stops: [0.0, 0.4, 0.7],
                ),
              ),
            ),
          ),

          // — Content —
          SafeArea(
            child: AnimatedBuilder(
              animation: _entranceController,
              builder: (context, _) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(flex: 5),

                      // Title
                      Transform.translate(
                        offset: Offset(0, _titleSlide.value),
                        child: Opacity(
                          opacity: _titleFade.value,
                          child: Text(
                            'Echo',
                            style: GoogleFonts.oldStandardTt(
                              fontSize: 80,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      EchoButton(
                        text: "Get Started",
                        backgroundColor: const Color(0xFFF4F2EE),
                        textColor: const Color(0xFF1E1E1E),
                        showArrow: true,
                        onPressed: () {
                          context.read<OnBoardingCubit>().completeWelcome();
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom Painter: Flowing Audio Waveforms
//
// Draws multiple layered organic sine waves that morph independently,
// giving the feel of a living, breathing audio signal visualization.
// ---------------------------------------------------------------------------
class _FlowingWavesPainter extends CustomPainter {
  final double progress; // 0..1, loops

  _FlowingWavesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress * 2 * pi;

    // Each wave definition: [yRatio, amplitude, frequency, phaseShift, color]
    final waves = <_WaveConfig>[
      // Top-most, very faint / wide
      _WaveConfig(
        yRatio: 0.28,
        amplitude: 40,
        frequency: 1.2,
        phaseShift: 0,
        color: const Color(0xFF166648).withValues(alpha: 0.08),
        strokeWidth: 2.0,
      ),
      // Primary wave — green, prominent
      _WaveConfig(
        yRatio: 0.35,
        amplitude: 55,
        frequency: 1.8,
        phaseShift: 0.5,
        color: const Color(0xFF166648).withValues(alpha: 0.25),
        strokeWidth: 2.5,
      ),
      // Secondary — offset, lighter
      _WaveConfig(
        yRatio: 0.38,
        amplitude: 35,
        frequency: 2.5,
        phaseShift: 1.2,
        color: const Color(0xFF2BB386).withValues(alpha: 0.15),
        strokeWidth: 1.8,
      ),
      // Middle band — the "heartbeat" wave
      _WaveConfig(
        yRatio: 0.42,
        amplitude: 70,
        frequency: 1.0,
        phaseShift: 2.0,
        color: const Color(0xFF166648).withValues(alpha: 0.35),
        strokeWidth: 3.0,
      ),
      // Lower accent
      _WaveConfig(
        yRatio: 0.48,
        amplitude: 25,
        frequency: 3.2,
        phaseShift: 3.5,
        color: const Color(0xFFD4A373).withValues(alpha: 0.10),
        strokeWidth: 1.5,
      ),
      // Bottom faint wave
      _WaveConfig(
        yRatio: 0.52,
        amplitude: 45,
        frequency: 1.5,
        phaseShift: 4.0,
        color: const Color(0xFF166648).withValues(alpha: 0.12),
        strokeWidth: 2.0,
      ),
    ];

    for (final wave in waves) {
      _drawOrganicWave(canvas, size, t, wave);
    }

    // Draw a subtle center glow at the wave convergence zone
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Color.fromRGBO(22, 102, 72, 0.06 + 0.03 * sin(t)),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.40),
              radius: size.width * 0.45,
            ),
          );
    canvas.drawRect(Offset.zero & size, glowPaint);
  }

  void _drawOrganicWave(
    Canvas canvas,
    Size size,
    double t,
    _WaveConfig config,
  ) {
    final paint = Paint()
      ..color = config.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = config.strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final baseY = size.height * config.yRatio;
    final segmentCount = 200;
    final dx = size.width / segmentCount;

    for (int i = 0; i <= segmentCount; i++) {
      final x = i * dx;
      final normalizedX = x / size.width; // 0..1

      // Envelope: wave is strongest in center, fades at edges
      final envelope = sin(normalizedX * pi);

      // Combine multiple sine components for organic feel
      final y =
          baseY +
          config.amplitude *
              envelope *
              (sin(
                        config.frequency * normalizedX * 2 * pi +
                            t +
                            config.phaseShift,
                      ) *
                      0.6 +
                  sin(
                        config.frequency * 1.7 * normalizedX * 2 * pi -
                            t * 0.7 +
                            config.phaseShift * 1.3,
                      ) *
                      0.3 +
                  sin(
                        config.frequency * 0.5 * normalizedX * 2 * pi +
                            t * 1.3 +
                            config.phaseShift * 0.7,
                      ) *
                      0.1);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlowingWavesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _WaveConfig {
  final double yRatio;
  final double amplitude;
  final double frequency;
  final double phaseShift;
  final Color color;
  final double strokeWidth;

  _WaveConfig({
    required this.yRatio,
    required this.amplitude,
    required this.frequency,
    required this.phaseShift,
    required this.color,
    required this.strokeWidth,
  });
}
