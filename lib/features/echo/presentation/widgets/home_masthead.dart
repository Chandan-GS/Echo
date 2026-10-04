import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';

/// The top of Home: the day set large like a newspaper's masthead, then the
/// greeting and one plain line about the day: who's waiting on the owner,
/// and what's left on the to-do list.
class HomeMasthead extends StatelessWidget {
  final String greeting;
  final String name;

  /// Shown instead of the to-do line until there's a list (the briefing's
  /// state: "Your briefing is ready." and so on).
  final String fallback;

  /// How many chats are waiting on the owner.
  final int waiting;

  const HomeMasthead({
    super.key,
    required this.greeting,
    required this.name,
    required this.fallback,
    this.waiting = 0,
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          _weekdays[now.weekday - 1],
          style: GoogleFonts.oldStandardTt(
            fontSize: 50,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${now.day} ${_months[now.month - 1]}',
          style: GoogleFonts.oldStandardTt(
            fontSize: 22,
            fontStyle: FontStyle.italic,
            height: 1.1,
            color: c.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        Container(height: 1, color: c.dividerColor),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: name.isEmpty ? greeting : '$greeting, '),
              if (name.isNotEmpty)
                TextSpan(
                  text: name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              const TextSpan(text: '.'),
            ],
          ),
          style: GoogleFonts.nunito(fontSize: 16, color: c.textSecondary),
        ),
        const SizedBox(height: 6),
        BlocBuilder<TodoCubit, TodoState>(
          builder: (context, todo) => Text.rich(
            TextSpan(children: _glance(context, todo)),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 16,
              height: 1.45,
              color: c.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  static const _words = [
    'No',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
  ];

  static String _count(int n) => n < _words.length ? _words[n] : '$n';

  /// "Two people are waiting on you. Three things left today, the next at
  /// 8 PM. Two on tomorrow's list."
  List<InlineSpan> _glance(BuildContext context, TodoState todo) {
    final people = waiting == 0
        ? null
        : TextSpan(
            text:
                '${_count(waiting)} ${waiting == 1 ? 'person is' : 'people are'}'
                ' waiting on you. ',
          );
    if (!todo.hasList || todo.phase == TodoPhase.writing) {
      return [?people, TextSpan(text: fallback)];
    }
    final today = todo.today;
    final left = today.where((i) => !i.done).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    // The next one still to come, not one whose time has passed.
    final minutes = todo.now.hour * 60 + todo.now.minute;
    final next = left
        .where((i) => i.time != null && i.sort >= minutes)
        .firstOrNull;
    final tomorrow = todo.tomorrow.length;

    final spans = <InlineSpan>[?people];
    if (today.isEmpty) {
      spans.add(const TextSpan(text: "Nothing on today's list."));
    } else if (left.isEmpty) {
      spans.add(const TextSpan(text: "Everything's done for today."));
    } else {
      spans.add(
        TextSpan(
          text:
              '${_count(left.length)} thing${left.length == 1 ? '' : 's'} '
              'left today',
        ),
      );
      if (next != null) {
        spans
          ..add(const TextSpan(text: ', the next at '))
          ..add(
            TextSpan(
              text: _startTime(next.time!),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: context.colors.primaryGreen,
              ),
            ),
          );
      }
      spans.add(const TextSpan(text: '.'));
    }
    if (tomorrow > 0) {
      spans.add(TextSpan(text: " ${_count(tomorrow)} on tomorrow's list."));
    }
    return spans;
  }

  /// "8:00 PM" → "8 PM"; "4 PM to 6 PM" → "4 PM".
  static String _startTime(String time) =>
      time.split(' to ').first.replaceFirst(':00 ', ' ');
}
