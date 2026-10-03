import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/services/reminder_settings.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';

/// What the owner picked in the reminder sheet.
sealed class ReminderChoice {
  const ReminderChoice();
}

class RemindAt extends ReminderChoice {
  final DateTime at;
  const RemindAt(this.at);
}

class RemoveReminder extends ReminderChoice {
  const RemoveReminder();
}

/// "Remind me": Echo's suggestion first, with its reason, then a few quick
/// picks, then any day and time. [current] is the reminder already set.
Future<ReminderChoice?> showReminderSheet(
  BuildContext context,
  TodoItem item, {
  DateTime? current,
}) {
  return showModalBottomSheet<ReminderChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 460),
      curve: Cubic(0.2, 0.9, 0.25, 1),
      reverseDuration: Duration(milliseconds: 240),
      reverseCurve: Curves.easeInCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (context) => _ReminderSheet(item: item, current: current),
  );
}

/// One of the sheet's choices: a time, what it is, and how it's drawn.
class _Option {
  final String id;
  final DateTime at;
  final String note;
  final IconData? icon;
  const _Option(this.id, this.at, this.note, {this.icon});
}

class _ReminderSheet extends StatefulWidget {
  final TodoItem item;
  final DateTime? current;
  const _ReminderSheet({required this.item, required this.current});

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  static const _custom = 'custom';

  final _now = DateTime.now();
  late final List<_Option> _options = _optionsFor(widget.item, _now);
  late String _choice;

  /// The custom pick: a day from today, and a time on the wheels.
  late int _day;
  late final _hour = FixedExtentScrollController(initialItem: _initial.$1);
  late final _minute = FixedExtentScrollController(initialItem: _initial.$2);
  late final _half = FixedExtentScrollController(initialItem: _initial.$3);

  /// The wheels start on the reminder already set, else the suggestion, else
  /// an hour from now: (hour index, minute index, AM/PM index).
  late final (int, int, int) _initial = () {
    final t =
        widget.current ??
        _options.firstOrNull?.at ??
        _now.add(const Duration(hours: 1));
    return (
      t.hour % 12 == 0 ? 11 : t.hour % 12 - 1,
      t.minute ~/ 5,
      t.hour < 12 ? 0 : 1,
    );
  }();

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    final match = current == null
        ? null
        : _options.where((o) => o.at == current).firstOrNull;
    _choice = current == null
        ? (_options.firstOrNull?.id ?? _custom)
        : (match?.id ?? _custom);
    final from = DateTime(_now.year, _now.month, _now.day);
    final day = current ?? widget.item.day;
    _day = DateTime(
      day.year,
      day.month,
      day.day,
    ).difference(from).inDays.clamp(0, 6);
  }

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    _half.dispose();
    super.dispose();
  }

  static List<_Option> _optionsFor(TodoItem item, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final options = <_Option>[];
    final suggested = suggestedReminder(item, now);
    if (suggested != null) {
      options.add(
        _Option(
          'echo',
          suggested,
          'Echo suggests · ${ReminderSettings.label(reminderLead)} before '
              '${clockLabel(item.startsAt!).replaceFirst(':00', '')}',
        ),
      );
    }
    final inAnHour = now.add(const Duration(hours: 1));
    final rounded = DateTime(
      inAnHour.year,
      inAnHour.month,
      inAnHour.day,
      inAnHour.hour,
      (inAnHour.minute ~/ 5) * 5,
    );
    if (rounded.day == now.day) {
      options.add(
        _Option(
          'hour',
          rounded,
          'In an hour',
          icon: Symbols.hourglass_top_rounded,
        ),
      );
    }
    final evening = today.add(const Duration(hours: 19));
    if (evening.isAfter(now.add(const Duration(minutes: 30)))) {
      options.add(
        _Option(
          'evening',
          evening,
          'This evening',
          icon: Symbols.dark_mode_rounded,
        ),
      );
    }
    options.add(
      _Option(
        'morning',
        today.add(const Duration(days: 1, hours: 9)),
        'Tomorrow morning',
        icon: Symbols.wb_sunny_rounded,
      ),
    );
    return options;
  }

  DateTime get _customAt {
    final from = DateTime(_now.year, _now.month, _now.day);
    final hour = (_hour.hasClients ? _hour.selectedItem : _initial.$1) % 12 + 1;
    final minute =
        (_minute.hasClients ? _minute.selectedItem : _initial.$2) % 12 * 5;
    final pm = (_half.hasClients ? _half.selectedItem : _initial.$3) == 1;
    return from.add(
      Duration(days: _day, hours: hour % 12 + (pm ? 12 : 0), minutes: minute),
    );
  }

  DateTime get _at => _choice == _custom
      ? _customAt
      : _options.firstWhere((o) => o.id == _choice).at;

  /// "9:50 PM", "Tomorrow 9:00 AM", "Mon 9:00 AM".
  String _label(DateTime t) {
    final l = whenLabel(t, _now).replaceFirst('at ', '');
    return l[0].toUpperCase() + l.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    final at = _at;
    final tooSoon = !at.isAfter(_now.add(const Duration(minutes: 1)));
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: c.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Remind me',
              style: GoogleFonts.oldStandardTt(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.time == null ? item.title : '${item.title} · ${item.time}',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            for (final o in _options) ...[
              _OptionTile(
                selected: _choice == o.id,
                leading: o.icon == null
                    ? const SizedBox(
                        width: 30,
                        height: 30,
                        child: OverflowBox(
                          maxWidth: 48,
                          maxHeight: 48,
                          child: EchoMascot(
                            size: 48,
                            showRings: false,
                            glow: false,
                          ),
                        ),
                      )
                    : Icon(o.icon, size: 22, color: c.textSecondary),
                title: _label(o.at),
                note: o.note,
                onTap: () => setState(() => _choice = o.id),
              ),
              const SizedBox(height: 8),
            ],
            _OptionTile(
              selected: _choice == _custom,
              leading: Icon(
                Symbols.edit_calendar_rounded,
                size: 22,
                color: c.textSecondary,
              ),
              title: 'Pick a day and time',
              note: _choice == _custom ? _label(at) : 'Any time you like',
              onTap: () => setState(() => _choice = _custom),
            ),
            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.emphasized,
              alignment: Alignment.topCenter,
              child: _choice == _custom
                  ? _picker(context)
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 16),
            AskSolidButton(
              label: tooSoon
                  ? 'Pick a time after now'
                  : 'Remind me ${whenLabel(at, _now)}',
              icon: Symbols.notifications_active_rounded,
              onTap: tooSoon
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop(RemindAt(at));
                    },
            ),
            if (widget.current != null)
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(const RemoveReminder()),
                child: Text(
                  'Remove reminder',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.primaryGreen,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Arrives within ten minutes of the time.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12.5, color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _picker(BuildContext context) {
    final c = context.colors;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String dayName(int n) {
      if (n == 0) return 'Today';
      if (n == 1) return 'Tomorrow';
      final d = _now.add(Duration(days: n));
      return '${weekdays[d.weekday - 1]} ${d.day}';
    }

    Widget wheel(
      FixedExtentScrollController controller,
      List<String> labels, {
      bool loop = true,
    }) => SizedBox(
      width: 66,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 40,
        diameterRatio: 1.6,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (_) {
          HapticFeedback.selectionClick();
          setState(() {});
        },
        childDelegate: loop
            ? ListWheelChildLoopingListDelegate(
                children: [for (final l in labels) _wheelText(context, l)],
              )
            : ListWheelChildListDelegate(
                children: [for (final l in labels) _wheelText(context, l)],
              ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 7,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, n) => AskPill(
                label: dayName(n),
                filled: n == _day,
                onTap: () => setState(() => _day = n),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The band the chosen time sits in.
                Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: context.selectionFill.withValues(
                      alpha: context.isDarkMode ? 0.3 : 0.55,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    wheel(_hour, [for (var h = 1; h <= 12; h++) '$h']),
                    _wheelText(context, ':'),
                    wheel(_minute, [
                      for (var m = 0; m < 60; m += 5)
                        m.toString().padLeft(2, '0'),
                    ]),
                    wheel(_half, const ['AM', 'PM'], loop: false),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _wheelText(BuildContext context, String text) => Center(
    child: Text(
      text,
      style: GoogleFonts.nunito(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: context.colors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// A choice in the sheet: a radio on the right, green when picked.
class _OptionTile extends StatelessWidget {
  final bool selected;
  final Widget leading;
  final String title;
  final String note;
  final VoidCallback onTap;

  const _OptionTile({
    required this.selected,
    required this.leading,
    required this.title,
    required this.note,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.98,
      haptic: false,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          color: selected
              ? Color.lerp(
                  c.surface,
                  context.selectionFill,
                  context.isDarkMode ? 0.12 : 0.3,
                )
              : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? c.primaryGreen
                : c.dividerColor.withValues(alpha: 0.7),
            width: 1.5,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  SizedBox(width: 30, child: Center(child: leading)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          note,
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: AppMotion.fast,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? c.primaryGreen
                            : c.textSecondary.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: AnimatedScale(
                        duration: AppMotion.medium,
                        curve: AppMotion.spring,
                        scale: selected ? 1 : 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: c.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
