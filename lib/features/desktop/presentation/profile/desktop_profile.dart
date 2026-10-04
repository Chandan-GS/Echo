import 'package:flutter/material.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/profile/presentation/screens/profile_screen.dart';
import 'package:project_echo/features/profile/presentation/widgets/streak_calendar.dart';
import 'package:project_echo/features/settings/presentation/screens/settings_screen.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profile on the computer: who the owner is, their week and their streak
/// side by side, then every setting below.
class DesktopProfile extends StatelessWidget {
  const DesktopProfile({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsScreen(profile: _Summary());
}

/// The name and week the phone last sent, and the streak calendar.
class _Summary extends StatefulWidget {
  const _Summary();

  @override
  State<_Summary> createState() => _SummaryState();
}

class _SummaryState extends State<_Summary> {
  final _calendarKey = GlobalKey<StreakCalendarState>();
  String _name = '';
  DateTime? _since;
  WeekStats? _week;

  @override
  void initState() {
    super.initState();
    _load();
    EchoServerService.instance.syncTick.addListener(_load);
    TodoStore.changed.addListener(_load);
  }

  @override
  void dispose() {
    EchoServerService.instance.syncTick.removeListener(_load);
    TodoStore.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    WeekStats? week;
    try {
      week = await WeekStats.load(DateTime.now());
    } catch (e) {
      // A bad snapshot from the phone: keep showing the last good week.
      debugPrint('Desktop profile: week not loaded: $e');
    }
    if (!mounted) return;
    setState(() {
      _name = prefs.getString('user_name')?.trim() ?? '';
      // Since the owner started on the phone, not since this computer.
      _since = DateTime.tryParse(
        prefs.getString(EchoServerService.phoneFirstLaunchKey) ?? '',
      );
      if (week != null) _week = week;
    });
    _calendarKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The phone's name for the owner; it's changed there.
              ProfileIdentity(name: _name, since: _since, onRename: null),
              WeekInNumbers(week: _week),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(flex: 5, child: StreakCalendar(key: _calendarKey)),
      ],
    );
  }
}
