import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';

/// Shown when the last of today's to-dos is ticked off. Same dark canvas as
/// the streak celebration: a happy Echo springs in, a tick badge draws itself
/// on its corner, and a burst of green particles goes off behind it.
class TodoCelebrationScreen extends StatefulWidget {
  final int done;
  final int tomorrow;

  const TodoCelebrationScreen({
    super.key,
    required this.done,
    required this.tomorrow,
  });

  @override
  State<TodoCelebrationScreen> createState() => _TodoCelebrationScreenState();
}

class _TodoCelebrationScreenState extends State<TodoCelebrationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  late final Animation<double> _orbIn = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
  );
  late final Animation<double> _check = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.5, 0.85, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _text = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.35, 0.8, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _entrance.forward();
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _burst.forward();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.tomorrow > 0
        ? '${widget.done} of ${widget.done} done. Tomorrow has ${widget.tomorrow} waiting.'
        : '${widget.done} of ${widget.done} done. Nothing waiting for tomorrow yet.';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 0.8,
                  colors: [
                    const Color(0xFF49884F).withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _burst,
              builder: (context, _) =>
                  CustomPaint(painter: _BurstPainter(_burst.value)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _entrance,
                    builder: (context, _) => Transform.scale(
                      scale: _orbIn.value,
                      child: _Orb(check: _check.value),
                    ),
                  ),
                  const SizedBox(height: 30),
                  FadeTransition(
                    opacity: _text,
                    child: Column(
                      children: [
                        Text(
                          'All clear for today',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.oldStandardTt(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          sub,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.7),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  FadeTransition(
                    opacity: _text,
                    child: EchoButton(
                      text: 'Nice',
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

class _Orb extends StatelessWidget {
  final double check;
  const _Orb({required this.check});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: Stack(
        children: [
          const EchoMascot(
            state: EchoState.happy,
            size: 190,
            showRings: false,
            isDark: true,
          ),
          Positioned(
            right: 24,
            bottom: 26,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF49884F),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0D0D0D), width: 4),
              ),
              child: CustomPaint(painter: _BigCheck(check)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigCheck extends CustomPainter {
  final double t;
  _BigCheck(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.3, h * 0.52)
      ..lineTo(w * 0.45, h * 0.66)
      ..lineTo(w * 0.72, h * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BigCheck old) => old.t != t;
}

/// Green particles flung out from behind the orb, falling and fading.
class _BurstPainter extends CustomPainter {
  final double t;
  _BurstPainter(this.t);

  static const _colors = [
    Color(0xFF8FE0A6),
    Color(0xFF6EBC76),
    Color(0xFFD1E6D3),
    Color(0xFFF4F2EE),
    Color(0xFF49884F),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final random = Random(11); // fixed seed → the same burst every frame
    final origin = Offset(size.width / 2, size.height * 0.38);
    final paint = Paint();
    for (var i = 0; i < 70; i++) {
      final angle = random.nextDouble() * 2 * pi;
      final speed = 160 + random.nextDouble() * 320;
      final radius = 2 + random.nextDouble() * 4;
      final color = _colors[random.nextInt(_colors.length)];
      final dx = cos(angle) * speed * t;
      final dy = sin(angle) * speed * t - 120 * t + 380 * t * t;
      paint.color = color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(origin + Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}
