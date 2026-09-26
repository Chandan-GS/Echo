import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';

/// Flutter renderings of Echo's home-screen widgets, matching their Android
/// layouts (res/layout/widget_*.xml) and colours, fed with live data.

class _WidgetColors {
  final Color bg, text, text2, green, stroke, track, divider;
  const _WidgetColors(
    this.bg,
    this.text,
    this.text2,
    this.green,
    this.stroke,
    this.track,
    this.divider,
  );

  static _WidgetColors of(BuildContext context) => context.isDarkMode
      ? const _WidgetColors(
          Color(0xFF262626),
          Color(0xFFEFEFEF),
          Color(0xFFA0A0A0),
          Color(0xFF6EBC76),
          Color(0x296EBC76),
          Color(0xFF3A3A3A),
          Color(0x26A0A0A0),
        )
      : const _WidgetColors(
          Color(0xFFF4F2EE),
          Color(0xFF1E1E1E),
          Color(0xFF5A5A5A),
          Color(0xFF49884F),
          Color(0x1A49884F),
          Color(0xFFDCDAD3),
          Color(0x1F5A5A5A),
        );
}

BoxDecoration _card(Color bg, Color stroke) => BoxDecoration(
  color: bg,
  borderRadius: BorderRadius.circular(24),
  border: Border.all(color: stroke),
  boxShadow: const [
    BoxShadow(color: Color(0x47000000), blurRadius: 28, offset: Offset(0, 10)),
  ],
);

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
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

/// Echo To-do (4 × 3).
class TodoWidgetPreview extends StatelessWidget {
  final TodoState todo;
  const TodoWidgetPreview({super.key, required this.todo});

  @override
  Widget build(BuildContext context) {
    final c = _WidgetColors.of(context);
    final now = DateTime.now();
    final today = todo.today;
    final left = today.length - todo.doneToday;
    final rows = [
      ...today.where((i) => !i.done),
      ...today.where((i) => i.done),
    ].take(4).toList();

    Widget body;
    if (!todo.hasList) {
      body = Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          "No list yet. Make one from today's briefing.",
          style: GoogleFonts.nunito(fontSize: 13.5, color: c.text2),
        ),
      );
    } else if (today.isNotEmpty && left == 0) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _Dot(size: 34, color: c.green, done: true, tick: c.bg),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "That's everything for today",
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                Text(
                  '${today.length} done',
                  style: GoogleFonts.nunito(fontSize: 12.5, color: c.text2),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: c.divider)),
              ),
              child: Row(
                children: [
                  _Dot(
                    size: 22,
                    color: c.green,
                    done: rows[i].done,
                    tick: c.bg,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: rows[i].done
                            ? c.text.withValues(alpha: 0.45)
                            : c.text,
                        decoration: rows[i].done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (rows[i].time != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      rows[i].time!,
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: c.green,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    }

    return Container(
      width: 312,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: _card(c.bg, c.stroke),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Today',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_weekdays[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.text2,
                  ),
                ),
              ),
              if (todo.hasList)
                Text(
                  today.isEmpty
                      ? 'Nothing today'
                      : (left == 0 ? 'All done' : '$left left'),
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: c.green,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          body,
          if (todo.hasList)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      today.length > 4 && left > 0
                          ? '+${today.length - 4} more today'
                          : '',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.text2,
                      ),
                    ),
                  ),
                  if (todo.tomorrow.isNotEmpty)
                    Text(
                      'Tomorrow · ${todo.tomorrow.length}',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.text2,
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

/// Echo To-do Progress (2 × 2).
class RingWidgetPreview extends StatelessWidget {
  final TodoState todo;
  const RingWidgetPreview({super.key, required this.todo});

  @override
  Widget build(BuildContext context) {
    final c = _WidgetColors.of(context);
    final today = todo.today;
    final done = todo.doneToday;
    final left = today.length - done;
    final next = today.where((i) => !i.done).firstOrNull;
    return Container(
      width: 150,
      height: 164,
      padding: const EdgeInsets.all(12),
      decoration: _card(c.bg, c.stroke),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: CustomPaint(
              painter: _Ring(
                today.isEmpty ? 0 : done / today.length,
                c.green,
                c.track,
              ),
              child: Center(
                child: todo.hasList && today.isNotEmpty
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$done'),
                            TextSpan(
                              text: '/${today.length}',
                              style: TextStyle(fontSize: 15, color: c.text2),
                            ),
                          ],
                        ),
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            !todo.hasList
                ? 'No list yet'
                : today.isEmpty
                ? 'Nothing today'
                : (left == 0 ? 'All done today' : '$left left today'),
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.text2,
            ),
          ),
          if (next != null)
            Text.rich(
              TextSpan(
                children: [
                  if (next.time != null)
                    TextSpan(
                      text: '${next.time} · ',
                      style: TextStyle(color: c.green),
                    ),
                  TextSpan(text: next.title),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
        ],
      ),
    );
  }
}

/// Echo Briefing (4 × 2) — always the paper card, like widget_briefing.xml.
class BriefingWidgetPreview extends StatelessWidget {
  final HomeWidgetsState? data;
  const BriefingWidgetPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF49884F);
    final streak = data?.streak ?? 0;
    final week = (data?.week.length == 7) ? data!.week : List.filled(7, 0);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Container(
      width: 312,
      padding: const EdgeInsets.all(16),
      decoration: _card(const Color(0xFFF4F2EE), const Color(0x1A49884F)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$streak Day Streak',
                      style: GoogleFonts.nunito(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E1E1E),
                      ),
                    ),
                    Text(
                      data?.status ?? '',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: green,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        letters[i],
                        style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF5A5A5A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: switch (week[i]) {
                            2 => green,
                            1 => const Color(0xFFFBDCD4),
                            3 => Colors.transparent,
                            _ => const Color(0xFFEAE6DD),
                          },
                          border: week[i] == 3
                              ? Border.all(color: green, width: 2.4)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Echo Streak (2 × 2) — the deep-green card, like widget_streak_ring.xml.
class StreakWidgetPreview extends StatelessWidget {
  final HomeWidgetsState? data;
  const StreakWidgetPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 164,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [Color(0xFF0C1E10), Color(0xFF16301B), Color(0xFF234A29)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x47000000),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${data?.streak ?? 0}',
            style: GoogleFonts.nunito(
              fontSize: 46,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1,
            ),
          ),
          Text(
            'DAY STREAK',
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.65),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              data?.status ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final double size;
  final Color color;
  final bool done;
  final Color tick;
  const _Dot({
    required this.size,
    required this.color,
    required this.done,
    required this.tick,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: done ? color : Colors.transparent,
      border: done
          ? null
          : Border.all(color: color.withValues(alpha: 0.55), width: 2),
    ),
    child: done
        ? Icon(Icons.check_rounded, size: size * 0.62, color: tick)
        : null,
  );
}

class _Ring extends CustomPainter {
  final double value;
  final Color fill, track;
  _Ring(this.value, this.fill, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, p..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        p..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Ring old) =>
      old.value != value || old.fill != fill || old.track != track;
}
