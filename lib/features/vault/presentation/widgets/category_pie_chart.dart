import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';

class CategoryPieChart extends StatefulWidget {
  final Map<String, int> categoryCounts;
  final Function(String) onCategorySelected;

  const CategoryPieChart({
    super.key,
    required this.categoryCounts,
    required this.onCategorySelected,
  });

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _PieSlice {
  final String category;
  final int count;
  final double startAngle;
  final double sweepAngle;
  final Color color;

  _PieSlice({
    required this.category,
    required this.count,
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
  });
}

class _CategoryPieChartState extends State<CategoryPieChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  int? _hoveredIndex;
  List<_PieSlice> _slices = [];

  // Used to interpolate hover states smoothly
  final Map<int, double> _hoverValues = {};

  List<Color> get _palette {
    final colors = context.colors;
    return [
      colors.primaryGreen,
      colors.textPrimary,
      colors.textSecondary,
      colors.buttonDark,
      colors.lightGreenBackground,
      colors.dividerColor,
    ];
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _animController.addListener(() {
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calculateSlices();
  }

  @override
  void didUpdateWidget(covariant CategoryPieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryCounts != widget.categoryCounts) {
      _calculateSlices();
    }
  }

  void _calculateSlices() {
    _slices.clear();
    final categories = widget.categoryCounts.keys
        .where((k) => k != 'All')
        .toList();

    if (categories.isEmpty) return;

    final int total = categories.fold(
      0,
      (sum, cat) => sum + widget.categoryCounts[cat]!,
    );

    // Ensure small slices are at least 15 degrees so they can be scrubbed
    const double minSweepRadians = 15 * (math.pi / 180.0);
    int bigCountTotal = 0;
    int smallSlicesCount = 0;

    for (final cat in categories) {
      final proportion = widget.categoryCounts[cat]! / total;
      if (proportion * 2 * math.pi < minSweepRadians) {
        smallSlicesCount++;
      } else {
        bigCountTotal += widget.categoryCounts[cat]!;
      }
    }

    final double availableRadians =
        (2 * math.pi) - (smallSlicesCount * minSweepRadians);

    double currentAngle = -math.pi / 2; // Start at top
    int colorIdx = 0;

    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final count = widget.categoryCounts[cat]!;
      final proportion = count / total;

      double sweepAngle = proportion * 2 * math.pi;
      if (sweepAngle < minSweepRadians) {
        sweepAngle = minSweepRadians;
      } else if (bigCountTotal > 0 && availableRadians > 0) {
        // Recalculate based on available space for big slices
        sweepAngle = (count / bigCountTotal) * availableRadians;
      }

      _slices.add(
        _PieSlice(
          category: cat,
          count: count,
          startAngle: currentAngle,
          sweepAngle: sweepAngle,
          color: _palette[colorIdx % _palette.length],
        ),
      );

      currentAngle += sweepAngle;
      colorIdx++;

      if (!_hoverValues.containsKey(i)) {
        _hoverValues[i] = 0.0;
      }
    }
  }

  void _updateHover(Offset localPosition, Size size) {
    if (_slices.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    // Only trigger if inside the rough radius of the chart + some padding
    if (distance > size.width / 2 + 40 || distance < 20) {
      if (_hoveredIndex != null) {
        _hoveredIndex = null;
        _startAnimation();
      }
      return;
    }

    double angle = math.atan2(dy, dx);
    if (angle < 0) {
      angle += 2 * math.pi;
    }

    // Adjust for starting at -pi/2
    double adjustedAngle = angle;

    int? foundIndex;
    for (int i = 0; i < _slices.length; i++) {
      final s = _slices[i];
      // Normalize start angle
      double sStart = s.startAngle;
      while (sStart < 0) sStart += 2 * math.pi;
      sStart = sStart % (2 * math.pi);

      double sEnd = (sStart + s.sweepAngle) % (2 * math.pi);

      if (sStart < sEnd) {
        if (adjustedAngle >= sStart && adjustedAngle <= sEnd) {
          foundIndex = i;
          break;
        }
      } else {
        if (adjustedAngle >= sStart || adjustedAngle <= sEnd) {
          foundIndex = i;
          break;
        }
      }
    }

    if (foundIndex != _hoveredIndex) {
      _hoveredIndex = foundIndex;
      _startAnimation();
    }
  }

  void _startAnimation() {
    _animController.stop();
    // Snapshot current values
    final mapSnapshots = Map<int, double>.from(_hoverValues);

    Animation<double> curved = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    curved.addListener(() {
      for (int i = 0; i < _slices.length; i++) {
        final target = (i == _hoveredIndex) ? 1.0 : 0.0;
        _hoverValues[i] =
            mapSnapshots[i]! + (target - mapSnapshots[i]!) * curved.value;
      }
    });

    _animController.forward(from: 0.0);
  }

  void _handlePanEnd() {
    if (_hoveredIndex != null &&
        _hoveredIndex! >= 0 &&
        _hoveredIndex! < _slices.length) {
      widget.onCategorySelected(_slices[_hoveredIndex!].category);
    }
    _hoveredIndex = null;
    _startAnimation();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slices.isEmpty) {
      return Center(
        child: Text(
          'No categories to display',
          style: GoogleFonts.nunito(
            fontSize: 16,
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight) - 80;

        return GestureDetector(
          onPanDown: (details) => _updateHover(
            details.localPosition,
            Size(constraints.maxWidth, constraints.maxHeight),
          ),
          onPanUpdate: (details) => _updateHover(
            details.localPosition,
            Size(constraints.maxWidth, constraints.maxHeight),
          ),
          onPanEnd: (details) => _handlePanEnd(),
          onPanCancel: () {
            _hoveredIndex = null;
            _startAnimation();
          },
          child: Container(
            color: Colors.transparent, // Capture gestures
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: _PieChartPainter(
                      slices: _slices,
                      hoverValues: _hoverValues,
                      surfaceColor: context.colors.surface,
                    ),
                  ),
                ),
                // Center text for hovered item
                if (_hoveredIndex != null &&
                    _hoveredIndex! >= 0 &&
                    _hoveredIndex! < _slices.length)
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _slices[_hoveredIndex!].category,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_slices[_hoveredIndex!].count} signals',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Release to open',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          color: context.colors.dividerColor,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scrub to explore',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<_PieSlice> slices;
  final Map<int, double> hoverValues;
  final Color surfaceColor;

  _PieChartPainter({
    required this.slices,
    required this.hoverValues,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    // Draw non-hovered slices first
    for (int i = 0; i < slices.length; i++) {
      final s = slices[i];
      final hoverVal = hoverValues[i] ?? 0.0;
      if (hoverVal > 0.01) continue; // Skip hovering ones to draw them on top

      _drawSlice(canvas, center, baseRadius, s, 0.0);
    }

    // Draw hovered slices on top
    for (int i = 0; i < slices.length; i++) {
      final s = slices[i];
      final hoverVal = hoverValues[i] ?? 0.0;
      if (hoverVal <= 0.01) continue;

      _drawSlice(canvas, center, baseRadius, s, hoverVal);
    }
  }

  void _drawSlice(
    Canvas canvas,
    Offset center,
    double baseRadius,
    _PieSlice s,
    double hoverVal,
  ) {
    // Dock effect: expand radius by up to 25px
    final radius = baseRadius + (hoverVal * 25.0);

    final paint = Paint()
      ..color = s.color
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          30.0 +
          (hoverVal * 15.0) // Thicker when hovered
      ..strokeCap = StrokeCap.butt;

    // Removed shadow paint to adhere to no-alpha requirement.

    // To add a slight gap between slices, we inset the sweep angle
    final gap = 0.04 - (hoverVal * 0.02); // Gap gets smaller as it expands
    final drawSweep = s.sweepAngle > gap * 2
        ? s.sweepAngle - gap
        : s.sweepAngle;
    final drawStart = s.startAngle + (s.sweepAngle > gap * 2 ? gap / 2 : 0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      drawStart,
      drawSweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return true;
  }
}
