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
    'Accessing secure local vault...',
    'Analyzing semantic priority contexts...',
    'Ranking notification signals...',
    'Synthesizing summary briefings...',
    'Polishing output commentary...',
  ];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
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
              'Echo is\nthinking...',
              style: GoogleFonts.oldStandardTt(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                height: 1.15,
              ),
            ),

            const Spacer(),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return RepaintBoundary(
                          child: CustomPaint(
                            painter: _MinimalSpinnerPainter(
                              animationValue: _controller.value,
                              primaryColor: context.colors.primaryGreen,
                              dividerColor: context.colors.dividerColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 40),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      statusText,
                      key: ValueKey<String>(statusText),
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        color: context.colors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _MinimalSpinnerPainter extends CustomPainter {
  final double animationValue;
  final Color primaryColor;
  final Color dividerColor;

  _MinimalSpinnerPainter({
    required this.animationValue,
    required this.primaryColor,
    required this.dividerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background tracking circle
    final trackPaint = Paint()
      ..color = dividerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius - 4, trackPaint);

    // Active sweep segment
    final sweepPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final sweepAngle = animationValue * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      sweepAngle - math.pi / 4, // Starts 45 degrees back
      math.pi / 2, // Covers 90 degrees segment
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimalSpinnerPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.dividerColor != dividerColor;
  }
}
