import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/vault/presentation/cubit/vault_cubit.dart';
import 'package:project_echo/features/vault/presentation/widgets/pie_chart_geometry.dart';
import 'package:project_echo/features/vault/presentation/widgets/vault_utils.dart';

/// A tonal ramp of category colours derived from the app's own theme green —
/// so it's always literally the app's palette (and adapts with light/dark
/// mode), rather than a separate hardcoded set that only happened to look
/// similar in one theme.
List<Color> _categoryPalette(BuildContext context) {
  final base = context.colors.primaryGreen;
  return [
    base,
    Color.lerp(base, Colors.white, 0.4)!,
    Color.lerp(base, Colors.black, 0.28)!,
    Color.lerp(base, Colors.white, 0.68)!,
    Color.lerp(base, Colors.black, 0.5)!,
  ];
}

Color _colorForCategory(List<Color> palette, List<String> categories, String category) {
  final idx = categories.indexOf(category);
  return idx >= 0 ? palette[idx % palette.length] : palette.last;
}

/// Reproduces VaultCubit's alias-mapping logic so each row can be coloured by
/// its own (aliased) category even while viewing "All".
String _displaySourceFor(RawData item, Map<String, String> aliases) {
  final sourceKey = item.source.trim();
  final defaultSource = sourceKey.isEmpty
      ? 'Unknown'
      : '${sourceKey[0].toUpperCase()}${sourceKey.substring(1).toLowerCase()}';
  return aliases[defaultSource] ?? defaultSource;
}

/// The desktop Vault — a real dashboard rather than the phone's tabbed
/// list/pie-chart-with-modal: filter chips, a donut+legend card, and an
/// always-visible notification list side by side. Selecting a category (chip
/// or legend row) just re-filters the list in place — no bottom sheet, no
/// phone-style "N signals / Rename / Block / Clear" modal.
class DesktopVaultScreen extends StatelessWidget {
  const DesktopVaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VaultCubit, VaultState>(
      listener: (context, state) {
        if (state is VaultError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is VaultInitial || state is VaultLoading) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (state is VaultLoaded) {
          if (state.allItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EchoMascot(state: EchoState.sleeping, size: 120),
                  const SizedBox(height: 12),
                  Text(
                    'No signals captured yet',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }
          return _Loaded(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  final VaultLoaded state;
  const _Loaded({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = state.categoryCounts['All'] ?? 0;
    final categories = state.categories.where((c) => c != 'All').toList();
    final palette = _categoryPalette(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 32, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The Vault',
            style: GoogleFonts.oldStandardTt(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$total notifications captured today · kept on your device',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: 'All',
                selected: state.selectedCategory == 'All',
                onTap: () => context.read<VaultCubit>().selectCategory('All'),
              ),
              for (final c in categories)
                _FilterChip(
                  label: c,
                  selected: state.selectedCategory == c,
                  onTap: () => context.read<VaultCubit>().selectCategory(c),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: _DonutCard(
                    state: state,
                    categories: categories,
                    palette: palette,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _VaultList(
                    items: state.displayedItems,
                    categories: categories,
                    palette: palette,
                    categoryAliases: state.categoryAliases,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? context.selectionFill : colors.surface,
      borderRadius: BorderRadius.circular(100),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? context.onSelection : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed-width card: a donut ring — scrub it with the mouse to preview a
/// category, release to select it (same interaction as the phone's
/// [CategoryPieChart]) — with a clickable legend beneath it.
class _DonutCard extends StatelessWidget {
  final VaultLoaded state;
  final List<String> categories;
  final List<Color> palette;
  const _DonutCard({
    required this.state,
    required this.categories,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = state.categoryCounts['All'] ?? 0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.dividerColor.withValues(alpha: 0.6)),
      ),
      // The donut stays fixed; only a long legend (many categories) scrolls
      // within the card's height instead of overflowing past its border.
      child: Column(
        children: [
          _InteractiveDonut(
            categoryCounts: state.categoryCounts,
            categories: categories,
            palette: palette,
            trackColor: colors.dividerColor,
            total: total,
            onCategorySelected: (category) =>
                context.read<VaultCubit>().selectCategory(category),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in categories)
                    _LegendRow(
                      label: c,
                      count: state.categoryCounts[c] ?? 0,
                      color: _colorForCategory(palette, categories, c),
                      selected: state.selectedCategory == c,
                      onTap: () => context.read<VaultCubit>().selectCategory(c),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _LegendRow({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.background : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                '$count',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The donut ring — scrub with the mouse to preview a category (it docks
/// outward and the center swaps to that category's name + count), release to
/// select it. Mirrors the phone's [CategoryPieChart] interaction, sized for
/// this fixed-width rail card.
class _InteractiveDonut extends StatefulWidget {
  final Map<String, int> categoryCounts;
  final List<String> categories;
  final List<Color> palette;
  final Color trackColor;
  final int total;
  final ValueChanged<String> onCategorySelected;

  const _InteractiveDonut({
    required this.categoryCounts,
    required this.categories,
    required this.palette,
    required this.trackColor,
    required this.total,
    required this.onCategorySelected,
  });

  @override
  State<_InteractiveDonut> createState() => _InteractiveDonutState();
}

class _InteractiveDonutState extends State<_InteractiveDonut>
    with SingleTickerProviderStateMixin {
  static const _size = 190.0;

  late final AnimationController _animController;
  int? _hoveredIndex;
  List<PieSliceGeometry> _slices = [];
  final Map<int, double> _hoverValues = {};

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(() => setState(() {}));
    _calculateSlices();
  }

  @override
  void didUpdateWidget(covariant _InteractiveDonut oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.categoryCounts, widget.categoryCounts)) {
      _calculateSlices();
    }
  }

  void _calculateSlices() {
    _slices = computePieSlices(widget.categoryCounts);
    for (int i = 0; i < _slices.length; i++) {
      _hoverValues.putIfAbsent(i, () => 0.0);
    }
  }

  void _updateHover(Offset localPosition) {
    if (_slices.isEmpty) return;
    const center = Offset(_size / 2, _size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    if (distance > _size / 2 + 16 || distance < 20) {
      if (_hoveredIndex != null) {
        _hoveredIndex = null;
        _startAnimation();
      }
      return;
    }

    var angle = math.atan2(dy, dx);
    if (angle < 0) angle += 2 * math.pi;

    int? foundIndex;
    for (int i = 0; i < _slices.length; i++) {
      final s = _slices[i];
      var sStart = s.startAngle % (2 * math.pi);
      if (sStart < 0) sStart += 2 * math.pi;
      final sEnd = (sStart + s.sweepAngle) % (2 * math.pi);

      final inside = sStart < sEnd
          ? (angle >= sStart && angle <= sEnd)
          : (angle >= sStart || angle <= sEnd);
      if (inside) {
        foundIndex = i;
        break;
      }
    }

    if (foundIndex != _hoveredIndex) {
      _hoveredIndex = foundIndex;
      _startAnimation();
    }
  }

  void _startAnimation() {
    _animController.stop();
    final snapshot = Map<int, double>.from(_hoverValues);
    final curved = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    curved.addListener(() {
      for (int i = 0; i < _slices.length; i++) {
        final target = i == _hoveredIndex ? 1.0 : 0.0;
        _hoverValues[i] = snapshot[i]! + (target - snapshot[i]!) * curved.value;
      }
    });
    _animController.forward(from: 0.0);
  }

  void _handleRelease() {
    if (_hoveredIndex != null && _hoveredIndex! < _slices.length) {
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
    final colors = context.colors;
    final hovered = _hoveredIndex != null && _hoveredIndex! < _slices.length
        ? _slices[_hoveredIndex!]
        : null;

    return GestureDetector(
      onPanDown: (d) => _updateHover(d.localPosition),
      onPanUpdate: (d) => _updateHover(d.localPosition),
      onPanEnd: (_) => _handleRelease(),
      onPanCancel: () {
        _hoveredIndex = null;
        _startAnimation();
      },
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(_size, _size),
              painter: _DonutPainter(
                categoryCounts: widget.categoryCounts,
                categories: widget.categories,
                palette: widget.palette,
                trackColor: widget.trackColor,
                hoverValues: _hoverValues,
              ),
            ),
            IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: hovered != null
                    ? [
                        Text(
                          hovered.category,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${hovered.count} signals',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ]
                    : [
                        Text(
                          '${widget.total}',
                          style: GoogleFonts.oldStandardTt(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'TODAY',
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final Map<String, int> categoryCounts;
  final List<String> categories;
  final List<Color> palette;
  final Color trackColor;
  final Map<int, double> hoverValues;
  static const _strokeWidth = 20.0;

  _DonutPainter({
    required this.categoryCounts,
    required this.categories,
    required this.palette,
    required this.trackColor,
    this.hoverValues = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2 - _strokeWidth / 2;

    canvas.drawCircle(
      center,
      baseRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = trackColor,
    );

    final slices = computePieSlices(categoryCounts);

    // Non-hovered slices first, then the hovered one on top so its expanded
    // (docked-out) stroke isn't overdrawn by its neighbours.
    for (var pass = 0; pass < 2; pass++) {
      for (int i = 0; i < slices.length; i++) {
        final hoverVal = hoverValues[i] ?? 0.0;
        final isHovered = hoverVal > 0.01;
        if ((pass == 0) == isHovered) continue;

        final s = slices[i];
        final radius = baseRadius + hoverVal * 10.0;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          s.startAngle,
          s.sweepAngle,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _strokeWidth + hoverVal * 8.0
            ..strokeCap = StrokeCap.butt
            ..color = _colorForCategory(palette, categories, s.category),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.categoryCounts != categoryCounts ||
      old.categories != categories ||
      old.hoverValues != hoverValues;
}

/// A flat, single-column list of compact rows — no phone-style stacked-card
/// treatment. Fills the full width of its parent.
class _VaultList extends StatelessWidget {
  final List<RawData> items;
  final List<String> categories;
  final List<Color> palette;
  final Map<String, String> categoryAliases;
  const _VaultList({
    required this.items,
    required this.categories,
    required this.palette,
    required this.categoryAliases,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Nothing here yet',
          style: GoogleFonts.nunito(
            fontSize: 14,
            color: context.colors.textSecondary,
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final cat = _displaySourceFor(item, categoryAliases);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _VaultRow(
            item: item,
            color: _colorForCategory(palette, categories, cat),
          ),
        );
      },
    );
  }
}

class _VaultRow extends StatelessWidget {
  final RawData item;
  final Color color;
  const _VaultRow({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final who = item.sender.trim().isNotEmpty ? item.sender : item.source;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(getSourceIcon(item.source), size: 18, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatTime(item.timestamp),
            style: GoogleFonts.nunito(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}
