import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// How many calendar days [day] is before [now]'s date: 0 today, 1
/// yesterday. Counted on the dates alone (as UTC, where every day is 24
/// hours), so a daylight-saving change in between can't make yesterday
/// "Today" or shift the count by one.
@visibleForTesting
int calendarDaysAgo(DateTime day, DateTime now) => DateTime.utc(
  now.year,
  now.month,
  now.day,
).difference(DateTime.utc(day.year, day.month, day.day)).inDays;

/// "Today · 117 signals", above that day's notifications.
class VaultDayHeading extends StatelessWidget {
  final DateTime day;
  final int count;
  final bool first;
  const VaultDayHeading({
    super.key,
    required this.day,
    required this.count,
    required this.first,
  });

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

  String get _label {
    final ago = calendarDaysAgo(day, DateTime.now());
    if (ago == 0) return 'Today';
    if (ago == 1) return 'Yesterday';
    if (ago < 7) return _weekdays[day.weekday - 1];
    return '${_weekdays[day.weekday - 1].substring(0, 3)} ${day.day} '
        '${_months[day.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, first ? 0 : 18, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              _label,
              style: GoogleFonts.oldStandardTt(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          Text(
            '$count signal${count == 1 ? '' : 's'}',
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: c.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
