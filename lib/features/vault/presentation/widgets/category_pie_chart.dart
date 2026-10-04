import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/vault/presentation/cubit/vault_cubit.dart';
import 'package:project_echo/features/vault/presentation/widgets/pie_chart_geometry.dart';
import 'package:project_echo/features/vault/presentation/widgets/source_icon.dart';
import 'package:project_echo/features/vault/presentation/widgets/vault_utils.dart';
import 'package:material_symbols_icons/symbols.dart';

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
    with TickerProviderStateMixin {
  late AnimationController _animController;

  // Fades each slice's app icon in while the ring is being scrubbed, and out
  // on release, so the resting ring stays clean.
  late final AnimationController _iconsController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _icons = CurvedAnimation(
    parent: _iconsController,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );
  int? _hoveredIndex;
  bool _scrubbing = false;
  final List<_PieSlice> _slices = [];

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
    if (!mapEquals(oldWidget.categoryCounts, widget.categoryCounts)) {
      _calculateSlices();
    }
  }

  void _calculateSlices() {
    _slices.clear();

    // Pure geometry: guards total<=0 and normalizes sweeps to exactly 2π so
    // many tiny categories can't overflow past 360° and overlap.
    // Wider floor than the default so the thinnest slices still hold an icon
    // and are easy to land on while scrubbing.
    final geometry = computePieSlices(
      widget.categoryCounts,
      minSweepDegrees: 20,
    );

    for (int i = 0; i < geometry.length; i++) {
      final g = geometry[i];
      _slices.add(
        _PieSlice(
          category: g.category,
          count: g.count,
          startAngle: g.startAngle,
          sweepAngle: g.sweepAngle,
          color: _palette[i % _palette.length],
        ),
      );

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
      while (sStart < 0) {
        sStart += 2 * math.pi;
      }
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
    _iconsController.reverse();
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
    _iconsController.dispose();
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

        final box = Size(constraints.maxWidth, constraints.maxHeight);
        // A touch that starts on the ring is the ring's (so the Vault around
        // it doesn't scroll away mid-scrub); one that starts elsewhere still
        // scrolls the page.
        bool onRing(Offset local) {
          final d = (local - box.center(Offset.zero)).distance;
          return d >= 20 && d <= box.width / 2 + 40;
        }

        return RawGestureDetector(
          gestures: {
            _RingGrab: GestureRecognizerFactoryWithHandlers<_RingGrab>(
              () => _RingGrab(),
              (r) => r.accepts = (global) {
                final ro = context.findRenderObject();
                return ro is RenderBox && onRing(ro.globalToLocal(global));
              },
            ),
          },
          child: Listener(
            onPointerDown: (e) {
              if (!onRing(e.localPosition)) return;
              _scrubbing = true;
              _iconsController.forward();
              _updateHover(e.localPosition, box);
            },
            onPointerMove: (e) {
              if (_scrubbing) _updateHover(e.localPosition, box);
            },
            onPointerUp: (_) {
              if (!_scrubbing) return;
              _scrubbing = false;
              _handlePanEnd();
            },
            onPointerCancel: (_) {
              if (!_scrubbing) return;
              _scrubbing = false;
              _iconsController.reverse();
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
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _PieChartPainter(
                          slices: _slices,
                          hoverValues: _hoverValues,
                          surfaceColor: context.colors.surface,
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(child: _sliceIcons(size)),
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
                            Symbols.touch_app_rounded,
                            color: context.colors.textSecondary,
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
          ),
        );
      },
    );
  }
}

extension on _CategoryPieChartState {
  /// Each slice's icon, centred on its arc and riding out with the dock
  /// effect. Built only while the ring is being scrubbed.
  Widget _sliceIcons(double ringSize) {
    return AnimatedBuilder(
      animation: _icons,
      builder: (context, _) {
        final t = _icons.value;
        if (_iconsController.isDismissed) return const SizedBox.shrink();

        Map<String, int> customIcons = const {};
        try {
          final vault = context.read<VaultCubit>().state;
          if (vault is VaultLoaded) customIcons = vault.categoryIcons;
        } catch (_) {}

        // The chart's full square (the ring is inset 40 on each side), which
        // holds the hovered slice's dock (+25) and its bigger icon.
        final box = ringSize + 80;
        final center = box / 2;
        final children = <Widget>[];
        for (int i = 0; i < _slices.length; i++) {
          final s = _slices[i];
          final hover = _hoverValues[i] ?? 0.0;
          final radius = ringSize / 2 + hover * 25.0;
          final iconSize = 26.0 + hover * 8.0;
          // Judged on the resting ring, so hovering never drops an icon.
          if (s.sweepAngle * ringSize / 2 < 26.0 + 4) continue;

          final mid = s.startAngle + s.sweepAngle / 2;
          final custom = customIconFor(s.category, customIcons);
          final glyph = Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: context.colors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              custom ?? getSourceIcon(s.category),
              size: iconSize * 0.6,
              color: context.colors.textPrimary,
            ),
          );
          children.add(
            Positioned(
              left: center + math.cos(mid) * radius - iconSize / 2,
              top: center + math.sin(mid) * radius - iconSize / 2,
              child: custom != null
                  ? glyph
                  : SourceIcon(
                      source: s.category,
                      size: iconSize,
                      fallback: glyph,
                    ),
            ),
          );
        }

        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.85 + 0.15 * t,
            child: SizedBox(
              width: box,
              height: box,
              child: Stack(clipBehavior: Clip.none, children: children),
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
          44.0 +
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

/// Wins the gesture arena at once for a touch that starts on the ring, so a
/// scroll view around the chart never takes it; other touches are ignored.
class _RingGrab extends OneSequenceGestureRecognizer {
  bool Function(Offset global) accepts = (_) => false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!accepts(event.position)) return;
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'ring grab';
}
