import 'dart:async';
import 'dart:math' as math;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/timer/next_briefing_timer.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The top of Home: sections to swipe through — the [masthead], the day as a
/// line, and the next-briefing countdown. Home opens on whichever section it
/// was last left on; there's no setting beyond that.
class HomeGlance extends StatefulWidget {
  final Widget masthead;

  const HomeGlance({super.key, required this.masthead});

  @override
  State<HomeGlance> createState() => _HomeGlanceState();
}

class _HomeGlanceState extends State<HomeGlance> {
  static const _pageKey = 'home_glance_page';
  static const _pages = 3;

  PageController? _controller;
  int _page = 0;

  /// The masthead's own height; the other sections share the countdown's.
  double? _mastheadHeight;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = (prefs.getInt(_pageKey) ?? 0).clamp(0, _pages - 1);
      if (!mounted) return;
      setState(() {
        _page = saved;
        _controller = PageController(initialPage: saved);
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onPage(int page) async {
    setState(() => _page = page);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pageKey, page);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The countdown is a 1.6:1 drawing; the day line shares its height,
        // while the masthead takes only what its text needs. Mid-swipe the
        // height eases between the two.
        final full = (constraints.maxWidth - 48) / 1.6;
        final heights = [_mastheadHeight ?? full, full, full];
        final controller = _controller;
        return Column(
          children: [
            if (controller == null)
              SizedBox(height: heights[_page])
            else
              AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  final page =
                      controller.hasClients &&
                          controller.position.haveDimensions
                      ? controller.page ?? _page.toDouble()
                      : _page.toDouble();
                  final lo = page.floor().clamp(0, _pages - 1);
                  final hi = page.ceil().clamp(0, _pages - 1);
                  final height = lerpDouble(
                    heights[lo],
                    heights[hi],
                    page - page.floor(),
                  )!;
                  // Sections always lay out at full height; only what's
                  // shown shrinks, so none is squeezed mid-swipe.
                  return SizedBox(
                    height: height,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: full,
                        maxHeight: math.max(full, heights[0]),
                        child: child,
                      ),
                    ),
                  );
                },
                child: PageView(
                  controller: controller,
                  onPageChanged: _onPage,
                  children: [
                    _Section(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _SizeReporter(
                          onHeight: (h) {
                            if (h != _mastheadHeight) {
                              setState(() => _mastheadHeight = h);
                            }
                          },
                          child: widget.masthead,
                        ),
                      ),
                    ),
                    const _Section(child: DayLine()),
                    const _Section(child: NextBriefingTimer()),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _Dots(count: _pages, current: _page),
          ],
        );
      },
    );
  }
}

/// Reports its child's laid-out height (after the frame, so it can setState).
class _SizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _SizeReporter({required this.onHeight, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderSizeReporter extends RenderProxyBox {
  ValueChanged<double> onHeight;
  double? _last;
  _RenderSizeReporter(this.onHeight);

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}

class _Section extends StatelessWidget {
  final Widget child;
  const _Section({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: child,
  );
}

class _Dots extends StatelessWidget {
  final int count;
  final int current;
  const _Dots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == current ? c.textPrimary : c.dividerColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// A to-do with a time, placed on the line.
class DayStop {
  final TodoItem item;
  final DateTime at;
  const DayStop(this.item, this.at);
}

/// Timed to-dos from now until the end of tomorrow, soonest first. Anything
/// that started within the last quarter hour still counts as "now".
List<DayStop> dayStops(Iterable<TodoItem> items, DateTime now) {
  final end = DateTime(now.year, now.month, now.day + 2);
  final from = now.subtract(const Duration(minutes: 15));
  final stops = <DayStop>[];
  for (final item in items) {
    if (item.done || item.time == null) continue;
    final at = item.startsAt;
    if (at == null || at.isBefore(from) || !at.isBefore(end)) continue;
    stops.add(DayStop(item, at));
  }
  stops.sort((a, b) => a.at.compareTo(b.at));
  return stops;
}

/// Now to the end of tomorrow as one line, with each timed to-do as a dot.
/// What's next is written above it; tap a dot to read that one instead.
class DayLine extends StatefulWidget {
  const DayLine({super.key});

  @override
  State<DayLine> createState() => _DayLineState();
}

class _DayLineState extends State<DayLine> {
  Timer? _minute;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    // Keeps "in 12 min" honest and moves "now" along the line.
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TodoCubit, TodoState>(
      builder: (context, todo) {
        final now = DateTime.now();
        final stops = dayStops([...todo.today, ...todo.tomorrow], now);
        final selected =
            stops.where((s) => s.item.id == _selectedId).firstOrNull ??
            stops.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 18),
            Expanded(
              child: selected == null
                  ? _nothing(context)
                  : _next(context, selected, now),
            ),
            _Line(
              now: now,
              stops: stops,
              selectedId: selected?.item.id,
              onSelect: (id) => setState(() => _selectedId = id),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _nothing(BuildContext context) => Text(
    'Nothing with a time\nuntil the end of tomorrow.',
    style: GoogleFonts.oldStandardTt(
      fontSize: 26,
      height: 1.2,
      color: context.colors.textSecondary,
    ),
  );

  Widget _next(BuildContext context, DayStop stop, DateTime now) {
    final c = context.colors;
    final item = stop.item;
    final source = [
      item.sender,
      item.app,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _clock(stop.at),
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: c.primaryGreen,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.oldStandardTt(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.12,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [_until(stop.at, now), if (source.isNotEmpty) source].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.nunito(fontSize: 14, color: c.textSecondary),
        ),
      ],
    );
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute == 0 ? '' : ':${t.minute.toString().padLeft(2, '0')}';
    return '$h$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "In 25 min", "In 2 h 10 min", "Tomorrow".
  static String _until(DateTime at, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (!at.isBefore(today.add(const Duration(days: 1)))) return 'Tomorrow';
    final d = at.difference(now);
    if (d.inMinutes <= 0) return 'Now';
    if (d.inMinutes < 60) return 'In ${d.inMinutes} min';
    final m = d.inMinutes % 60;
    return 'In ${d.inHours} h${m == 0 ? '' : ' $m min'}';
  }
}

/// The line itself: "now" at the left, midnight a third of the way along
/// (so tonight's hours don't crowd the edge), the end of tomorrow at the
/// right, and a dot per stop.
class _Line extends StatelessWidget {
  final DateTime now;
  final List<DayStop> stops;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  const _Line({
    required this.now,
    required this.stops,
    required this.selectedId,
    required this.onSelect,
  });

  static const _tonight = 0.34;

  double _position(DateTime at) {
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final end = DateTime(now.year, now.month, now.day + 2);
    if (at.isBefore(midnight)) {
      final span = midnight.difference(now).inMinutes;
      final off = at.difference(now).inMinutes.clamp(0, span);
      return span == 0 ? 0 : off / span * _tonight;
    }
    final off = at.difference(midnight).inMinutes;
    return _tonight + off / end.difference(midnight).inMinutes * (1 - _tonight);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = GoogleFonts.nunito(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: c.textSecondary,
    );
    return SizedBox(
      height: 58,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          const lineY = 28.0;
          final midX = w * _tonight;

          // Time labels over the dots, skipping any that would collide.
          final labels = <Widget>[];
          var lastLabelX = -100.0;
          for (final s in stops) {
            final x = _position(s.at) * w;
            if (x - lastLabelX < 44) continue;
            lastLabelX = x;
            labels.add(
              Positioned(
                left: (x - 30).clamp(0, w - 60),
                width: 60,
                top: 0,
                child: Text(
                  _DayLineState._clock(s.at),
                  textAlign: TextAlign.center,
                  style: label,
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: lineY - 1.5,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Midnight, and "Tomorrow" just after it.
              Positioned(
                left: midX,
                top: lineY - 9,
                width: 1.5,
                height: 18,
                child: ColoredBox(
                  color: c.textSecondary.withValues(alpha: 0.5),
                ),
              ),
              Positioned(
                left: midX + 6,
                top: lineY + 12,
                child: Text('Tomorrow', style: label),
              ),
              ...labels,
              // Now.
              Positioned(
                left: -1,
                top: lineY - 6,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: c.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              for (final s in stops)
                Positioned(
                  left: _position(s.at) * w - 16,
                  top: lineY - 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(s.item.id),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: s.item.id == selectedId ? 14 : 11,
                          height: s.item.id == selectedId ? 14 : 11,
                          decoration: BoxDecoration(
                            color: s.item.id == selectedId
                                ? c.textPrimary
                                : c.background,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.textPrimary,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
