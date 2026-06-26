import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Tangent;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/core/theme/app_theme.dart';

class NextBriefingTimer extends StatefulWidget {
  const NextBriefingTimer({super.key});

  @override
  State<NextBriefingTimer> createState() => _NextBriefingTimerState();
}

class _NextBriefingTimerState extends State<NextBriefingTimer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweepController;
  Timer? _ticker;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();

    // Looping animation controller to tick at device frame rate
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    // Rebuilds the countdown text exactly once per second (1 FPS)
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final hourStr = hour12.toString().padLeft(2, '0');
    return '$hourStr:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final times = state.briefingTimes.isEmpty
            ? const ['07:00']
            : state.briefingTimes;

        // Generate scheduled times for yesterday, today, and tomorrow
        final List<DateTime> instances = [];
        for (final date in [
          _now.subtract(const Duration(days: 1)),
          _now,
          _now.add(const Duration(days: 1)),
        ]) {
          for (final timeStr in times) {
            final parts = timeStr.split(':');
            if (parts.length != 2) continue;
            final hour = int.tryParse(parts[0]) ?? 0;
            final minute = int.tryParse(parts[1]) ?? 0;
            instances.add(
              DateTime(date.year, date.month, date.day, hour, minute),
            );
          }
        }
        instances.sort();

        // Find next briefing relative to _now
        final nextBriefing = instances.firstWhere(
          (dt) => dt.isAfter(_now),
          orElse: () => _now.add(const Duration(hours: 24)),
        );

        final remaining = nextBriefing.difference(_now);

        // AspectRatio 1.6 gives a nice rectangular shape
        return AspectRatio(
          aspectRatio: 1.6,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final primaryColor = context.colors.primaryGreen;
              final dividerColor = context.colors.dividerColor;

              return Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _sweepController,
                    builder: (context, child) {
                      return RepaintBoundary(
                        child: CustomPaint(
                          size: Size(width, height),
                          painter: TimerPainter(
                            now:
                                DateTime.now(), // Uses actual wall time to avoid frame-drift
                            primaryColor: primaryColor,
                            dividerColor: dividerColor,
                          ),
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: width * 0.1),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Next Briefing in',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: context.colors.textSecondary,
                            ),
                          ),
                          SizedBox(height: height * 0.02),
                          Text(
                            _formatDuration(remaining),
                            style: GoogleFonts.nunito(
                              fontSize: height * 0.25,
                              fontWeight: FontWeight.bold,
                              color: context.colors.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          SizedBox(height: height * 0.02),
                          Text(
                            'at ${_formatTime(nextBriefing)}',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class TimerPainter extends CustomPainter {
  final DateTime now;
  final Color primaryColor;
  final Color dividerColor;

  TimerPainter({
    required this.now,
    required this.primaryColor,
    required this.dividerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Define the bounding box constraints
    final double padding = 8.0;
    final double w = size.width - padding * 2;
    final double h = size.height - padding * 2;

    // Maintain a consistent circular corner radius
    final double r = math.min(28.0, math.min(w / 2, h / 2));

    // Construct a custom Rounded Rectangle Path starting strictly at Top Center
    final path = Path()
      ..moveTo(padding + w / 2, padding) // Top center
      ..lineTo(padding + w - r, padding)
      ..arcToPoint(Offset(padding + w, padding + r), radius: Radius.circular(r))
      ..lineTo(padding + w, padding + h - r)
      ..arcToPoint(
        Offset(padding + w - r, padding + h),
        radius: Radius.circular(r),
      )
      ..lineTo(padding + r, padding + h)
      ..arcToPoint(Offset(padding, padding + h - r), radius: Radius.circular(r))
      ..lineTo(padding, padding + r)
      ..arcToPoint(Offset(padding + r, padding), radius: Radius.circular(r))
      ..close(); // Return to Top center

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final double totalLength = metric.length;

    // --- Draw Sweeping Outer Dial Ticks around the Rounded Rectangle ---
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    final currentSecond = now.second + now.millisecond / 1000.0;

    for (int i = 0; i < 60; i++) {
      // Calculate distance along the path perimeter for this exact tick
      final double distance = (i * totalLength) / 60.0;

      final Tangent? tangent = metric.getTangentForOffset(distance);
      if (tangent == null) continue;

      final isMajor = i % 5 == 0;
      final double tickLength = isMajor ? 12.0 : 6.0;
      final double tickThickness = isMajor ? 2.5 : 1.2;

      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);

      final startOffset = tangent.position;
      final endOffset = tangent.position + normal * tickLength;

      // Calculate sweeping trail effect behind the current second
      double diff = currentSecond - i;
      if (diff < 0) {
        diff += 60;
      }

      double opacity = 0.0;
      if (diff <= 18) {
        opacity = 1.0 - (diff / 18.0);
      }

      // 1. Draw base faded tick
      tickPaint
        ..color = dividerColor.withValues(alpha: 0.25)
        ..strokeWidth = tickThickness;
      canvas.drawLine(startOffset, endOffset, tickPaint);

      // 2. Draw glowing active tick overlay if inside trailing wave
      if (opacity > 0.0) {
        tickPaint
          ..color = primaryColor.withValues(alpha: opacity)
          ..strokeWidth = tickThickness * 1.5;
        canvas.drawLine(startOffset, endOffset, tickPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TimerPainter oldDelegate) {
    return oldDelegate.now != now ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.dividerColor != dividerColor;
  }
}
