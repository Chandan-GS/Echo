import 'dart:math';
import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/animations/pressable.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/features/echo/presentation/screens/streak_celebration_screen.dart';
import 'package:project_echo/features/echo/presentation/widgets/streak_flame.dart';

/// The default in-app streak view: a bold green hero header with the streak
/// count, and a month calendar where consecutive counted days join into a
/// continuous green "streak trail" — today ringed, skipped days marked, and
/// mended days ringed on the trail. A missed day is only ever marked; nothing
/// here says whose fault it was. The flame animation is reserved for the
/// celebration (tap the header).
class StreakCalendar extends StatefulWidget {
  /// Opens the streak page. Without it, pushes the celebration directly.
  final VoidCallback? onOpen;

  const StreakCalendar({super.key, this.onOpen});

  @override
  State<StreakCalendar> createState() => StreakCalendarState();
}

class StreakCalendarState extends State<StreakCalendar> {
  final _service = StreakService();
  StreakInfo _streak = StreakInfo.zero;
  Set<String> _heard = <String>{};
  Set<String> _mended = <String>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final streak = await _service.current();
    final heard = await _service.heardDates();
    final mended = await _service.mendedDates();
    if (!mounted) return;
    setState(() {
      _streak = streak;
      _heard = heard;
      _mended = mended;
      _loaded = true;
    });
  }

  /// Public so the host screen can refresh after debug actions / on resume.
  Future<void> reload() => _load();

  void _celebrate() {
    if (widget.onOpen case final open?) return open();
    final days = _streak.current > 0 ? _streak.current : 1;
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(bouncyRoute(StreakCelebrationScreen(days: days)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(streak: _streak, onTap: _celebrate),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: _loaded
                ? _buildCalendar(context)
                : const SizedBox(height: 60),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final todayKey = _service.dateKeyFor(now);
    final monthPrefix = todayKey.substring(0, 8);
    final mendedThisMonth = _mended.any((d) => d.startsWith(monthPrefix));
    final earliest = _heard.isEmpty ? null : (_heard.toList()..sort()).first;

    final firstOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leadingBlanks = (firstOfMonth.weekday - 1) % 7; // Monday-first

    final cells = <_DayInfo?>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(null);
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(now.year, now.month, day);
      cells.add(_DayInfo(day, _stateFor(date, todayKey, earliest)));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_monthNames[now.month - 1]} ${now.year}',
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final l in _weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: colors.textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final cellW = c.maxWidth / 7;
            final dot = min(cellW - 6, 36.0);
            final weeks = <Widget>[];
            for (int i = 0; i < cells.length; i += 7) {
              weeks.add(
                _WeekRow(week: cells.sublist(i, i + 7), cellW: cellW, dot: dot),
              );
            }
            return Column(children: weeks);
          },
        ),
        if (_streak.mendable != null || mendedThisMonth) ...[
          const SizedBox(height: 6),
          Text(
            _streak.mendable != null
                ? 'Yesterday got away. Clear tonight’s wrap or play a briefing '
                      'and your streak carries on.'
                : 'A ringed day was mended the day after.',
            style: GoogleFonts.nunito(
              fontSize: 13,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  _DayState _stateFor(DateTime date, String todayKey, String? earliest) {
    final key = _service.dateKeyFor(date);
    if (_mended.contains(key)) return _DayState.mended;
    if (_heard.contains(key)) return _DayState.done;
    if (key == todayKey) return _DayState.today;
    if (key.compareTo(todayKey) < 0 &&
        earliest != null &&
        key.compareTo(earliest) > 0) {
      return _DayState.missed;
    }
    return _DayState.plain;
  }
}

// ── Hero header ─────────────────────────────────────────────────────────────
class _Hero extends StatelessWidget {
  final StreakInfo streak;
  final VoidCallback onTap;
  const _Hero({required this.streak, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final green = context.colors.primaryGreen;
    final hasStreak = streak.current > 0;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [green, Color.lerp(green, Colors.black, 0.42)!],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const StreakFlame(size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasStreak) ...[
                    Text(
                      '${streak.current}',
                      style: GoogleFonts.oldStandardTt(
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'day streak',
                      style: GoogleFonts.oldStandardTt(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ] else
                    Text(
                      'Start your\nstreak today',
                      style: GoogleFonts.oldStandardTt(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            if (streak.longest > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'LONGEST',
                    style: GoogleFonts.nunito(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${streak.longest} '
                    '${streak.longest == 1 ? 'day' : 'days'}',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── One week row, with the connecting "streak trail" behind done days ───────
class _WeekRow extends StatelessWidget {
  final List<_DayInfo?> week;
  final double cellW;
  final double dot;
  const _WeekRow({required this.week, required this.cellW, required this.dot});

  @override
  Widget build(BuildContext context) {
    final green = context.colors.primaryGreen;
    final hPad = (cellW - dot) / 2;

    // Runs of consecutive done days → one rounded trail each.
    final trails = <Widget>[];
    int? start;
    for (int i = 0; i <= 7; i++) {
      final state = i < 7 ? week[i]?.state : null;
      final isDone = state == _DayState.done || state == _DayState.mended;
      if (isDone && start == null) start = i;
      if (!isDone && start != null) {
        trails.add(
          Positioned(
            left: start * cellW + hPad,
            top: 0,
            width: (i - start) * cellW - 2 * hPad,
            height: dot,
            child: Container(
              decoration: BoxDecoration(
                color: green,
                borderRadius: BorderRadius.circular(dot / 2),
              ),
            ),
          ),
        );
        start = null;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: dot,
        child: Stack(
          children: [
            ...trails,
            Row(
              children: [
                for (int i = 0; i < 7; i++)
                  SizedBox(
                    width: cellW,
                    child: Center(
                      child: _DayDot(info: week[i], dot: dot),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  final _DayInfo? info;
  final double dot;
  const _DayDot({required this.info, required this.dot});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (info == null) return SizedBox(width: dot, height: dot);

    Color bg = Colors.transparent;
    Color fg = colors.textPrimary;
    Border? border;
    FontWeight weight = FontWeight.w600;

    switch (info!.state) {
      case _DayState.done: // sits on the green trail
        fg = Colors.white;
        weight = FontWeight.w800;
        break;
      case _DayState.mended: // on the trail, but ringed
        fg = Colors.white;
        weight = FontWeight.w800;
        border = Border.all(
          color: Colors.white.withValues(alpha: 0.75),
          width: 1.5,
        );
        break;
      case _DayState.today:
        border = Border.all(color: colors.primaryGreen, width: 2);
        fg = colors.primaryGreen;
        weight = FontWeight.w800;
        break;
      case _DayState.missed:
        bg = const Color(0xFFFBDCD4);
        fg = const Color(0xFFC0503B);
        break;
      case _DayState.plain:
        fg = colors.textSecondary.withValues(alpha: 0.7);
        break;
    }

    return Container(
      width: dot,
      height: dot,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Text(
        '${info!.day}',
        style: GoogleFonts.nunito(fontSize: 13, fontWeight: weight, color: fg),
      ),
    );
  }
}

enum _DayState { done, mended, missed, today, plain }

class _DayInfo {
  final int day;
  final _DayState state;
  const _DayInfo(this.day, this.state);
}

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
