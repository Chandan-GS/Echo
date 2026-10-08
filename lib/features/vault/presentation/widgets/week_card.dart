import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:project_echo/features/vault/presentation/cubit/vault_cubit.dart';
import 'package:project_echo/features/vault/presentation/widgets/source_icon.dart';
import 'package:project_echo/features/vault/presentation/widgets/vault_utils.dart';

/// The top of the Vault: one day's signals (total, busiest apps, hour by
/// hour) and the last seven days as bars to tap between, with a dashed line
/// at the daily average.
class WeekCard extends StatefulWidget {
  /// For a wide window: the day, its hours and the week side by side.
  final bool wide;

  const WeekCard({super.key, this.wide = false});

  @override
  State<WeekCard> createState() => _WeekCardState();
}

class _WeekCardState extends State<WeekCard> {
  List<DayStats>? _week;
  int _selected = DailyStats.days - 1; // today

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    // On a computer the numbers arrive with the phone's sync.
    EchoServerService.instance.syncTick.addListener(_load);
  }

  @override
  void dispose() {
    EchoServerService.instance.syncTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final week = await DailyStats.week(DateTime.now());
      if (mounted) setState(() => _week = week);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final week = _week;
    return BlocListener<VaultCubit, VaultState>(
      // New notifications (or a cleared category) change today's numbers.
      listenWhen: (a, b) =>
          a is! VaultLoaded ||
          b is! VaultLoaded ||
          a.allItems.length != b.allItems.length,
      listener: (_, _) => _load(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
        ),
        child: week == null
            ? const SizedBox(height: 280)
            : _content(context, week),
      ),
    );
  }

  Widget _content(BuildContext context, List<DayStats> week) {
    final c = context.colors;
    final day = week[_selected];
    final isToday = _selected == week.length - 1;
    final summary = _summary(context, day, week);
    final hours = _hoursWithAxis(context, day, isToday);
    final days = _Days(
      week: week,
      selected: _selected,
      onSelect: (i) => setState(() => _selected = i),
    );

    if (widget.wide) {
      Widget rule() => Container(
        width: 1,
        height: 96,
        margin: const EdgeInsets.symmetric(horizontal: 22),
        color: c.dividerColor,
      );
      return LayoutBuilder(
        builder: (context, box) {
          // Roomy: the day, its hours and the week in three columns.
          // Narrower windows put the hours under the day's total.
          final roomy = box.maxWidth >= 900;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: roomy
                ? [
                    SizedBox(width: 220, child: summary),
                    rule(),
                    Expanded(child: hours),
                    rule(),
                    SizedBox(width: 250, child: days),
                  ]
                : [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [summary, const SizedBox(height: 14), hours],
                      ),
                    ),
                    rule(),
                    SizedBox(width: 230, child: days),
                  ],
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summary,
        const SizedBox(height: 18),
        hours,
        const SizedBox(height: 16),
        Container(height: 1, color: c.dividerColor),
        const SizedBox(height: 12),
        days,
      ],
    );
  }

  /// The day's total, when it was, and its busiest apps.
  Widget _summary(BuildContext context, DayStats day, List<DayStats> week) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${day.total}',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 46,
                  fontWeight: FontWeight.w700,
                  height: 0.95,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _whenLabel(day.day, week.length - 1 - _selected),
                style: GoogleFonts.nunito(fontSize: 14, color: c.textSecondary),
              ),
            ],
          ),
        ),
        for (final app in day.top(3))
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Column(
              children: [
                SourceIcon(
                  source: app.key,
                  size: 30,
                  fallback: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.background,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      getSourceIcon(app.key),
                      size: 16,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${app.value}',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _hoursWithAxis(BuildContext context, DayStats day, bool isToday) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hours(day: day, upTo: isToday ? DateTime.now().hour : 23),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, box) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Every six hours when there's room, else every twelve.
              for (final t
                  in box.maxWidth >= 220
                      ? ['12 AM', '6 AM', '12 PM', '6 PM', '12 AM']
                      : ['12 AM', '12 PM', '12 AM'])
                Text(
                  t,
                  style: GoogleFonts.nunito(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _whenLabel(DateTime d, int daysAgo) {
    if (daysAgo == 0) return 'today, so far';
    if (daysAgo == 1) return 'yesterday';
    return 'on ${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
  }
}

/// One bar per hour; the busiest three in green, hours still to come dotted.
class _Hours extends StatelessWidget {
  final DayStats day;
  final int upTo;
  const _Hours({required this.day, required this.upTo});

  static const _height = 74.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = day.hours.take(upTo + 1).toList();
    final peak = shown.fold(0, math.max);
    final hot = ([
      ...shown,
    ]..sort((a, b) => b.compareTo(a))).take(3).where((n) => n > 0).toSet();
    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var h = 0; h < 24; h++) ...[
            if (h > 0) const SizedBox(width: 3),
            Expanded(
              child: h > upTo
                  ? Container(height: 2, color: c.dividerColor)
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      height: peak == 0
                          ? 3
                          : math.max(3, day.hours[h] / peak * _height),
                      decoration: BoxDecoration(
                        color: hot.contains(day.hours[h])
                            ? c.primaryGreen
                            : c.dividerColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                          bottom: Radius.circular(1),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The seven days as bars to tap, with the daily average as a dashed line.
class _Days extends StatelessWidget {
  final List<DayStats> week;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Days({
    required this.week,
    required this.selected,
    required this.onSelect,
  });

  static const _area = 64.0; // bar area above the labels
  static const _labels = 18.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final peak = math.max(1, week.map((d) => d.total).fold(0, math.max));
    // Average of the earlier days that have anything counted.
    final past = week.take(week.length - 1).where((d) => d.total > 0).toList();
    final avg = past.isEmpty
        ? null
        : past.map((d) => d.total).reduce((a, b) => a + b) / past.length;
    final label = GoogleFonts.nunito(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: c.textSecondary,
    );

    return SizedBox(
      height: _area + _labels,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < week.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selected,
                    label: '${week[i].total} signals',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelect(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 30,
                            height: math.max(
                              6,
                              week[i].total / peak * (_area - 6),
                            ),
                            decoration: BoxDecoration(
                              color: i == selected
                                  ? c.textPrimary
                                  : c.dividerColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'MTWTFSS'[week[i].day.weekday - 1],
                            style: label.copyWith(
                              height: 1,
                              color: i == selected
                                  ? c.textPrimary
                                  : i == week.length - 1
                                  ? c.primaryGreen
                                  : c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (avg != null) ...[
            Positioned(
              left: 0,
              right: 0,
              bottom: _labels + 6 + avg / peak * (_area - 6) - 0.75,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size.fromHeight(1.5),
                  painter: _Dashes(c.textSecondary.withValues(alpha: 0.6)),
                ),
              ),
            ),
            // At the start of the line: the latest days, on the right, are
            // the ones most likely to stand tall through it.
            Positioned(
              left: 0,
              bottom: _labels + 6 + avg / peak * (_area - 6) + 4,
              child: IgnorePointer(
                child: ColoredBox(
                  color: c.surface,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      'avg ${avg.round()}',
                      style: label.copyWith(fontSize: 10.5, height: 1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dashes extends CustomPainter {
  final Color color;
  _Dashes(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + 4, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Dashes old) => old.color != color;
}
