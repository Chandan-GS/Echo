import 'dart:math';
import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// A modern audio-style slider: the track is a sine wave (filled green up to the
/// value, muted after it) and the handle is a tall rounded vertical bar rather
/// than a dot. Drag or tap anywhere along it to set a 0..1 value.
class WaveSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double height;

  const WaveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.height = 48,
  });

  @override
  State<WaveSlider> createState() => _WaveSliderState();
}

class _WaveSliderState extends State<WaveSlider> {
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _last = widget.value;
  }

  void _update(double dx, double width) {
    final v = (dx / width).clamp(0.0, 1.0);
    _last = v;
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _update(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => widget.onChangeEnd?.call(_last),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WavePainter(
                value: widget.value.clamp(0.0, 1.0),
                active: colors.primaryGreen,
                inactive: colors.dividerColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double value;
  final Color active;
  final Color inactive;

  _WavePainter({
    required this.value,
    required this.active,
    required this.inactive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const amp = 7.0;
    const wavelength = 26.0;
    final thumbX = (size.width * value).clamp(0.0, size.width);

    Path buildWave() {
      final p = Path();
      for (double x = 0; x <= size.width; x += 1) {
        final y = cy + amp * sin((x / wavelength) * 2 * pi);
        if (x == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      return p;
    }

    final wave = buildWave();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Inactive (right of the handle).
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(thumbX, 0, size.width - thumbX, size.height));
    canvas.drawPath(wave, stroke..color = inactive);
    canvas.restore();

    // Active (left of the handle).
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, thumbX, size.height));
    canvas.drawPath(wave, stroke..color = active);
    canvas.restore();

    // Vertical bar handle.
    final barRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(thumbX, cy), width: 6, height: 30),
      const Radius.circular(3),
    );
    canvas.drawRRect(barRect, Paint()..color = active);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.value != value || old.active != active || old.inactive != inactive;
}
