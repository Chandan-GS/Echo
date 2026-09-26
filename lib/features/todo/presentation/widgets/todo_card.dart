import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/todo/presentation/screens/todo_celebration_screen.dart';
import 'package:project_echo/features/todo/presentation/widgets/drafting_skeleton.dart';

/// The home screen's to-do card. Before a list exists it shows placeholder
/// rows (and, once there's a briefing, a way to make one); while Echo writes
/// it, the rows draft themselves; then the list arrives item by item.
class TodoCard extends StatefulWidget {
  /// Whether today's briefing exists — the list is made from it.
  final bool hasBriefing;

  const TodoCard({super.key, required this.hasBriefing});

  @override
  State<TodoCard> createState() => _TodoCardState();
}

const _visible = 4;

/// Ticks an item on or off; finishing today's list opens the celebration.
Future<void> toggleTodo(BuildContext context, TodoItem item) async {
  HapticFeedback.lightImpact();
  final cubit = context.read<TodoCubit>();
  final navigator = Navigator.of(context, rootNavigator: true);
  final finished = await cubit.toggle(item.id);
  if (!finished) return;
  final s = cubit.state;
  await Future<void>.delayed(const Duration(milliseconds: 380));
  navigator.push(
    bouncyRoute(
      TodoCelebrationScreen(done: s.today.length, tomorrow: s.tomorrow.length),
    ),
  );
}

/// The full list — today, then tomorrow — in a bottom sheet.
Future<void> showTodoSheet(BuildContext context, {bool tomorrow = false}) {
  final cubit = context.read<TodoCubit>();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: _TodoSheet(startAtTomorrow: tomorrow),
    ),
  );
}

class _TodoCardState extends State<TodoCard>
    with SingleTickerProviderStateMixin {
  final Set<int> _expanded = {};
  bool _arriving = false;
  int _arrivalKey = 0;

  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _playArrival(int arrival) {
    setState(() {
      _arriving = true;
      _arrivalKey = arrival;
    });
    _glow.forward(from: 0);
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _arriving = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TodoCubit, TodoState>(
      listenWhen: (a, b) => a.arrival != b.arrival,
      listener: (context, state) => _playArrival(state.arrival),
      builder: (context, state) {
        return AnimatedBuilder(
          animation: _glow,
          builder: (context, child) {
            final v = _glow.value;
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: context.colors.dividerColor.withValues(alpha: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  if (_glow.isAnimating)
                    BoxShadow(
                      color: context.colors.primaryGreen.withValues(
                        alpha: 0.45 * (1 - v),
                      ),
                      spreadRadius: 18 * v,
                    ),
                ],
              ),
              child: child,
            );
          },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_header(context, state), ..._body(context, state)],
            ),
          ),
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(BuildContext context, TodoState s) {
    final total = s.today.length;
    final done = s.doneToday;
    final String count;
    if (s.phase == TodoPhase.writing) {
      count = 'Writing your list…';
    } else if (s.phase == TodoPhase.updating) {
      count = 'Updating your list…';
    } else if (!s.hasList) {
      count = 'No list yet';
    } else if (total == 0) {
      count = 'Nothing left for today';
    } else if (done == total) {
      count = 'All done';
    } else {
      count = '${total - done} of $total left';
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Today',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  count,
                  key: ValueKey(count),
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (s.hasList) _ProgressRing(done: done, total: total),
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  List<Widget> _body(BuildContext context, TodoState s) {
    if (s.phase == TodoPhase.writing) {
      return [
        const SizedBox(height: 16),
        const DraftingSkeleton(
          key: ValueKey('draft-writing'),
          rows: 5,
          writing: true,
        ),
        _note(context, "Reading today's briefing for things to do"),
      ];
    }

    if (!s.hasList) {
      return [
        const SizedBox(height: 16),
        const DraftingSkeleton(key: ValueKey('draft-idle'), rows: 3),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
          child: Text(
            widget.hasBriefing
                ? "Turn today's briefing into a checklist for today and tomorrow."
                : "Generate today's briefing first. Then you can turn it into a checklist for today and tomorrow.",
            style: GoogleFonts.nunito(
              fontSize: 14,
              color: context.colors.textSecondary,
            ),
          ),
        ),
        if (widget.hasBriefing) ...[
          _SolidButton(
            icon: Icons.checklist_rounded,
            label: 'Make a to-do list',
            onTap: () => context.read<TodoCubit>().make(),
          ),
          const SizedBox(height: 12),
        ],
      ];
    }

    final today = s.today;
    final tomorrow = s.tomorrow;
    final added = s.justAdded.toList();
    // Home shows at most four: what's still to do first, by time. The rest
    // are one tap away in the sheet, so home never becomes a long scroll.
    final shown = [
      ...today.where((i) => !i.done),
      ...today.where((i) => i.done),
    ].take(_visible).toList();

    Widget rowFor(TodoItem item, int index) {
      Widget row = _TodoRow(
        key: ValueKey('todo-${item.id}'),
        item: item,
        first: index == 0,
        expanded: _expanded.contains(item.id),
        changed: s.justChanged.contains(item.id),
        onToggle: () => toggleTodo(context, item),
        onExpand: () => setState(() {
          _expanded.contains(item.id)
              ? _expanded.remove(item.id)
              : _expanded.add(item.id);
        }),
      );
      if (_arriving) {
        row = FadeSlideIn(
          key: ValueKey('arrive-$_arrivalKey-${item.id}'),
          delay: Duration(milliseconds: 350 + 90 * index),
          offsetY: 14,
          child: row,
        );
      } else if (added.contains(item.id)) {
        row = FadeSlideIn(
          key: ValueKey('added-${item.id}'),
          delay: Duration(milliseconds: 120 * added.indexOf(item.id)),
          offsetY: 14,
          child: row,
        );
      }
      return row;
    }

    final updatedAt = s.meta.updatedAt;
    final madeAt = s.meta.madeAt;
    final wasUpdated =
        updatedAt != null &&
        madeAt != null &&
        updatedAt.difference(madeAt).inSeconds > 1;

    return [
      if (s.phase == TodoPhase.idle && s.pendingNew > 0)
        _UpdateRow(
          count: s.pendingNew,
          since: updatedAt ?? madeAt,
          onUpdate: () => context.read<TodoCubit>().update(),
        )
      else if (s.phase == TodoPhase.idle && wasUpdated)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Up to date with everything until ${_clock(updatedAt)}.',
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      const SizedBox(height: 6),
      for (var i = 0; i < shown.length; i++) rowFor(shown[i], i),
      if (today.length > shown.length)
        _LinkRow(
          label: 'See all ${today.length} for today',
          onTap: () => showTodoSheet(context),
        ),
      if (s.phase == TodoPhase.updating) ...[
        const SizedBox(height: 12),
        const DraftingSkeleton(
          key: ValueKey('draft-updating'),
          rows: 2,
          writing: true,
        ),
        _note(context, 'Checking ${s.pendingNew} new notifications…'),
      ],
      if (tomorrow.isNotEmpty)
        _TomorrowRow(
          items: tomorrow,
          onTap: () => showTodoSheet(context, tomorrow: true),
        ),
      if (today.isEmpty && tomorrow.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            'Nothing to do for today or tomorrow.',
            style: GoogleFonts.nunito(
              fontSize: 14,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      const SizedBox(height: 6),
    ];
  }

  Widget _note(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
    child: Text(
      text,
      style: GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: context.colors.primaryGreen,
      ),
    ),
  );
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _ProgressRing extends StatelessWidget {
  final int done;
  final int total;
  const _ProgressRing({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final target = total == 0 ? 0.0 : done / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 600),
      curve: const Cubic(0.2, 0.8, 0.2, 1),
      builder: (context, value, _) => SizedBox(
        width: 48,
        height: 48,
        child: CustomPaint(
          painter: _RingPainter(
            value: value,
            track: context.colors.primaryGreen.withValues(
              alpha: context.isDarkMode ? 0.14 : 0.10,
            ),
            fill: context.colors.primaryGreen,
          ),
          child: Center(
            child: Text(
              total == 0 ? '–' : '$done/$total',
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color track;
  final Color fill;
  _RingPainter({required this.value, required this.track, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2.5);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        stroke..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// Solid, inverted like the Play button: white on dark, dark on light.
class _SolidButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SolidButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.textPrimary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: context.colors.textInverse),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textInverse,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  final int count;
  final DateTime? since;
  final VoidCallback onUpdate;
  const _UpdateRow({
    required this.count,
    required this.since,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final fg = context.colors.textInverse;
    return FadeSlideIn(
      offsetY: -6,
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        decoration: BoxDecoration(
          color: context.colors.textPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$count new'),
                    if (since != null)
                      TextSpan(
                        text: ' since ${_clock(since!)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: fg.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onUpdate();
              },
              style: TextButton.styleFrom(
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Update',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TomorrowRow extends StatelessWidget {
  final List<TodoItem> items;
  final VoidCallback onTap;
  const _TomorrowRow({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final first = items.first.title;
    final lead = first.isEmpty
        ? ''
        : first[0].toLowerCase() + first.substring(1);
    final n = items.length;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: context.colors.dividerColor.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Tomorrow  ',
                      style: GoogleFonts.oldStandardTt(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: '$n thing${n == 1 ? '' : 's'}, starting with $lead',
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 13.5,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: context.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// "See all 7 for today ›"
class _LinkRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LinkRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: context.colors.dividerColor.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: context.colors.primaryGreen,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.colors.primaryGreen,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoSheet extends StatefulWidget {
  final bool startAtTomorrow;
  const _TodoSheet({required this.startAtTomorrow});

  @override
  State<_TodoSheet> createState() => _TodoSheetState();
}

class _TodoSheetState extends State<_TodoSheet> {
  final Set<int> _expanded = {};
  final _tomorrowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.startAtTomorrow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _tomorrowKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<TodoCubit, TodoState>(
      builder: (context, s) {
        final today = s.today, tomorrow = s.tomorrow;
        Widget row(TodoItem item, int i) => _TodoRow(
          key: ValueKey('sheet-${item.id}'),
          item: item,
          first: i == 0,
          expanded: _expanded.contains(item.id),
          changed: false,
          onToggle: () => toggleTodo(context, item),
          onExpand: () => setState(() {
            _expanded.contains(item.id)
                ? _expanded.remove(item.id)
                : _expanded.add(item.id);
          }),
        );
        final left = today.length - s.doneToday;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(
                      color: c.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          'Today',
                          style: GoogleFonts.oldStandardTt(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        today.isEmpty
                            ? 'Nothing for today'
                            : (left == 0
                                  ? 'All done'
                                  : '$left of ${today.length} left'),
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < today.length; i++) row(today[i], i),
                        if (tomorrow.isNotEmpty) ...[
                          Padding(
                            key: _tomorrowKey,
                            padding: const EdgeInsets.fromLTRB(2, 20, 2, 4),
                            child: Text(
                              'Tomorrow',
                              style: GoogleFonts.oldStandardTt(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          for (var i = 0; i < tomorrow.length; i++)
                            row(tomorrow[i], i),
                        ],
                      ],
                    ),
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

class _TodoRow extends StatelessWidget {
  final TodoItem item;
  final bool first;
  final bool expanded;
  final bool changed;
  final VoidCallback onToggle;
  final VoidCallback onExpand;

  const _TodoRow({
    super.key,
    required this.item,
    required this.first,
    required this.expanded,
    required this.changed,
    required this.onToggle,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = <InlineSpan>[
      TextSpan(
        text: item.time ?? 'Anytime',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: c.primaryGreen,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      TextSpan(
        text: ' · ${item.sender}${item.app.isEmpty ? '' : ', ${item.app}'}',
      ),
      if (item.movedFrom != null)
        TextSpan(text: ' · moved from ${item.movedFrom}'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CheckCircle(done: item.done, onTap: onToggle, label: item.title),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedOpacity(
                      opacity: item.done ? 0.5 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (item.isNew)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: c.primaryGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            TextSpan(text: item.title),
                          ],
                        ),
                        style: GoogleFonts.nunito(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: c.textPrimary,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: c.textPrimary.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Highlight(
                      active: changed,
                      child: Text.rich(
                        TextSpan(children: meta),
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Show the notification this came from',
                  onPressed: onExpand,
                  icon: AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 22,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Container(
                    margin: const EdgeInsets.only(left: 38, top: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Color.lerp(c.background, c.surface, 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${item.sender}: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          TextSpan(text: '“${item.sourceText}”'),
                        ],
                      ),
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        color: c.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A brief green wash behind a line that just changed (e.g. a moved time).
class _Highlight extends StatelessWidget {
  final bool active;
  final Widget child;
  const _Highlight({required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final tint = context.colors.primaryGreen.withValues(
      alpha: context.isDarkMode ? 0.14 : 0.10,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1200),
      builder: (context, t, child) {
        final a = t < 0.3 ? t / 0.3 : (1 - t) / 0.7;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(Colors.transparent, tint, a.clamp(0.0, 1.0)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}

class _CheckCircle extends StatelessWidget {
  final bool done;
  final VoidCallback onTap;
  final String label;
  const _CheckCircle({
    required this.done,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final green = context.colors.primaryGreen;
    return Semantics(
      button: true,
      checked: done,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: AnimatedScale(
            scale: done ? 1.08 : 1,
            duration: const Duration(milliseconds: 220),
            curve: const Cubic(0.34, 1.56, 0.64, 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? green : Colors.transparent,
                border: Border.all(
                  color: done ? green : green.withValues(alpha: 0.55),
                  width: 2,
                ),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: done ? 1 : 0),
                duration: const Duration(milliseconds: 280),
                builder: (context, t, _) => CustomPaint(
                  painter: _CheckPainter(
                    t,
                    context.isDarkMode ? const Color(0xFF16301B) : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double t;
  final Color color;
  _CheckPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.44, h * 0.67)
      ..lineTo(w * 0.72, h * 0.36);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) =>
      old.t != t || old.color != color;
}
