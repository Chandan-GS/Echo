import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// Placeholder to-do rows. At rest they breathe gently, standing in for a list
/// that hasn't been made. While [writing], each row firms up in turn, its bar
/// draws across from the left and a green sheen runs through it — the list
/// visibly drafting itself instead of a spinner.
class DraftingSkeleton extends StatefulWidget {
  final int rows;
  final bool writing;

  const DraftingSkeleton({super.key, this.rows = 3, this.writing = false});

  @override
  State<DraftingSkeleton> createState() => _DraftingSkeletonState();
}

class _DraftingSkeletonState extends State<DraftingSkeleton>
    with TickerProviderStateMixin {
  static const _widths = [0.72, 0.55, 0.64, 0.48, 0.60];
  static const _rowStagger = 160; // ms

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.writing ? 1300 : 2400),
  )..repeat();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 550 + _rowStagger * widget.rows),
  );

  @override
  void initState() {
    super.initState();
    if (widget.writing) _entrance.forward();
  }

  @override
  void dispose() {
    _loop.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final green = context.colors.primaryGreen;
    final bar = context.colors.dividerColor.withValues(alpha: 0.7);
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _entrance]),
      builder: (context, _) {
        return Column(
          children: [
            for (var r = 0; r < widget.rows; r++) ...[
              if (r > 0) const SizedBox(height: 12),
              _row(context, r, green, bar),
            ],
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, int r, Color green, Color bar) {
    final width = _widths[r % _widths.length];

    if (!widget.writing) {
      final pulse =
          0.72 +
          0.28 * (0.5 + 0.5 * math.cos((_loop.value - r * 0.08) * 2 * math.pi));
      return Opacity(
        opacity: pulse,
        child: Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CustomPaint(
                painter: _DashedRing(green.withValues(alpha: 0.35)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _bar(width, bar)),
          ],
        ),
      );
    }

    // Writing: fade in, draw the bar, then a sheen loops through it.
    final totalMs = _entrance.duration!.inMilliseconds;
    final startMs = r * _rowStagger;
    final t = ((_entrance.value * totalMs - startMs) / 550).clamp(0.0, 1.0);
    final drawn = Curves.easeOutCubic.transform(t);
    final phase = (_loop.value - r * 0.12) % 1.0;
    final dotPulse = 1 + 0.12 * math.sin(phase * math.pi);
    final sheenX = -2.0 + 4.0 * phase;

    return Opacity(
      opacity: t,
      child: Row(
        children: [
          Transform.scale(
            scale: dotPulse,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: green.withValues(
                  alpha: 0.10 * math.sin(phase * math.pi),
                ),
                border: Border.all(
                  color: green.withValues(alpha: 0.45),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: width * drawn,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      begin: Alignment(sheenX - 1, 0),
                      end: Alignment(sheenX + 1, 0),
                      colors: [bar, green.withValues(alpha: 0.28), bar],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(double width, Color color) => Align(
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: width,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
  );
}

class _DashedRing extends CustomPainter {
  final Color color;
  _DashedRing(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    const dashes = 12;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(1), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRing old) => old.color != color;
}
