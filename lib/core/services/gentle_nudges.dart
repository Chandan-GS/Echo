import 'dart:async';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:isar_community/isar.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/core/services/reminder_settings.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/utils/nudge_rules.dart';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Echo's two gentle reminders, both off with Settings → Briefings → Gentle
/// reminders ([ReminderSettings.gentle]):
///
/// On the owner's first day, one evening note at about 8 PM saying how much
/// Echo has heard and when the first briefing comes, counted when it fires.
/// It's an inexact alarm, like the briefings, so it may land a little late.
///
/// After two mornings in a row without a briefing heard, that morning's
/// briefing notification says it's waiting, once; then nothing more until
/// one is heard again (see [missedMorningsNudgeDue]).
class GentleNudges {
  GentleNudges._();

  /// The day-one note's alarm (and notification) id. Briefing alarms use
  /// hour*100+minute, at most 2359, so this can't collide with one.
  static const dayOneAlarmId = 2400;

  /// The nudge alarm ids last scheduled, so they can be cancelled; kept
  /// apart from ScheduleService's `scheduled_briefing_alarm_ids`, which it
  /// cancels on every reschedule.
  static const alarmIdsKey = 'scheduled_nudge_alarm_ids';

  /// The day (YYYY-MM-DD) Echo first reached Home with no briefing yet: the
  /// owner's first day.
  static const dayOneKey = 'gentle_day_one_date';

  /// The day the day-one note was scheduled, so reopening Home doesn't set
  /// it again after it has fired.
  static const dayOneSetKey = 'gentle_day_one_scheduled';

  /// The day (YYYY-MM-DD) the missed-mornings nudge was last sent.
  static const missedNudgeKey = 'gentle_missed_nudge_date';

  /// The briefing notification's text when the missed-mornings nudge is due.
  static const missedMorningsBody =
      'Your briefing is waiting — 2 minutes, then you’re caught up.';

  static bool _enabled(SharedPreferences prefs) =>
      prefs.getBool(ReminderSettings.gentleKey) ?? true;

  /// Whether a briefing has ever been made or heard on this phone.
  static Future<bool> hasHadBriefing(SharedPreferences prefs) async =>
      prefs.getString('cached_briefing_date') != null ||
      await StreakService().briefingsHeard() > 0;

  /// How many messages Echo has saved since [since]. Calendar events, which
  /// are copied in rather than heard, don't count.
  static Future<int> heardSince(DateTime since) async {
    final isar = await IsarDataSource.instance;
    return isar.rawDatas
        .filter()
        .timestampGreaterThan(since, include: true)
        .not()
        .captureKeyStartsWith('calendar:')
        .count();
  }

  /// Sets the day-one evening note, when today is the owner's first day,
  /// it hasn't been set yet, and 8 PM is still ahead of both now and the
  /// first briefing. Called whenever Home opens; safe to call again.
  static Future<void> scheduleDayOneIfDue({DateTime? now}) async {
    if (!Platform.isAndroid || kEchoDemo) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await hasHadBriefing(prefs)) return;
      final at = now ?? DateTime.now();
      final today = dayKey(at);
      var dayOne = prefs.getString(dayOneKey);
      if (dayOne == null) {
        dayOne = today;
        await prefs.setString(dayOneKey, today);
      }
      if (dayOne != today || !_enabled(prefs)) return;
      if (prefs.getString(dayOneSetKey) == today) return;

      final first = nextBriefingAt(
        at,
        prefs.getStringList('briefing_times') ?? ['07:00'],
      );
      final fireAt = dayOneNudgeAt(now: at, firstBriefing: first);
      if (fireAt == null) return;

      await AndroidAlarmManager.oneShotAt(
        fireAt,
        dayOneAlarmId,
        dayOneNudgeCallback,
        // Inexact, as the briefings are: Echo declares no exact-alarm
        // permission, and "about 8 PM" is all this needs.
        exact: false,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
      await prefs.setStringList(alarmIdsKey, ['$dayOneAlarmId']);
      await prefs.setString(dayOneSetKey, today);
    } catch (e) {
      debugPrint('Scheduling the day-one note failed: $e');
    }
  }

  /// Cancels any nudge alarm still waiting (the toggle was turned off).
  static Future<void> cancelScheduled() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(alarmIdsKey) ?? const [];
      for (final id in ids.map(int.tryParse).nonNulls) {
        await AndroidAlarmManager.cancel(id);
      }
      await prefs.remove(alarmIdsKey);
      // So turning the toggle back on the same day sets it again.
      await prefs.remove(dayOneSetKey);
    } catch (e) {
      debugPrint('Cancelling gentle reminders failed: $e');
    }
  }

  /// Turns the gentle reminders on or off, setting or cancelling what's
  /// waiting to match.
  static Future<void> setEnabled(bool on) async {
    await ReminderSettings.setGentle(on);
    if (on) {
      await scheduleDayOneIfDue();
    } else {
      await cancelScheduled();
    }
  }

  /// Whether this briefing's notification should carry the missed-mornings
  /// nudge. Reads what the app's own isolate wrote (heard days), so call it
  /// from the briefing alarm just before posting.
  static Future<bool> missedMorningsDue(
    SharedPreferences prefs, {
    DateTime? now,
  }) async {
    try {
      await prefs.reload();
      if (!_enabled(prefs)) return false;
      final firstLaunch = DateTime.tryParse(
        prefs.getString('first_launch_date') ?? '',
      );
      return missedMorningsNudgeDue(
        now: now ?? DateTime.now(),
        heardDates: await StreakService().heardDates(),
        briefingTimes: prefs.getStringList('briefing_times') ?? ['07:00'],
        firstLaunch: firstLaunch,
        lastNudgeDate: prefs.getString(missedNudgeKey),
      );
    } catch (e) {
      debugPrint('Checking for missed mornings failed: $e');
      return false;
    }
  }

  /// Records that the missed-mornings nudge went out today.
  static Future<void> markMissedMorningsNudged(
    SharedPreferences prefs, {
    DateTime? now,
  }) => prefs.setString(missedNudgeKey, dayKey(now ?? DateTime.now()));
}

/// The day-one evening note's alarm. Runs in the alarm's background isolate:
/// it catches up on what the native buffer holds, counts today's messages,
/// and posts the note, unless the toggle went off or a briefing has already
/// come.
@pragma('vm:entry-point')
Future<void> dayOneNudgeCallback() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await prefs.remove(GentleNudges.alarmIdsKey);
    if (!(prefs.getBool(ReminderSettings.gentleKey) ?? true)) return;
    if (await GentleNudges.hasHadBriefing(prefs)) return;

    final now = DateTime.now();
    final first = nextBriefingAt(
      now,
      prefs.getStringList('briefing_times') ?? ['07:00'],
    );
    if (first == null) return;

    // What arrived while the app was closed is still in the native buffer.
    await NotificationIngest.drainBuffer().timeout(
      const Duration(minutes: 1),
      onTimeout: () {},
    );
    final heard = await GentleNudges.heardSince(
      DateTime(now.year, now.month, now.day),
    );
    final body = dayOneNudgeBody(heard, first);
    if (body == null) return;

    await LocalNotificationService().init();
    await LocalNotificationService().showGentleReminder(
      id: GentleNudges.dayOneAlarmId,
      title: 'Echo is listening',
      body: body,
    );
  } catch (e) {
    debugPrint('Day-one note failed: $e');
  } finally {
    // Release Isar before the background isolate goes (see alarmCallback).
    await IsarDataSource.close();
  }
}
