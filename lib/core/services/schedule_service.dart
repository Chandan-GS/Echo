import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:project_echo/core/services/gentle_nudges.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/core/services/remote_config_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:project_echo/core/utils/time_utils.dart';

/// The longest a briefing alarm may spend catching up and generating. Past
/// it the run is abandoned so a stalled model stream can't keep the
/// background isolate, and its Isar handle, alive indefinitely.
const _alarmBudget = Duration(minutes: 4);

@pragma('vm:entry-point')
Future<void> alarmCallback() async {
  BriefingCubit? cubit;
  // Set once the budget runs out, so a generation that finishes afterwards
  // can't still record the slot or post a notification.
  var abandoned = false;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final briefingTimes = prefs.getStringList('briefing_times') ?? ['07:00'];

    // Inexact alarms can arrive late, so run whichever slot has most
    // recently come due and hasn't run yet, rather than requiring the alarm
    // to land on its exact minute.
    final slot = dueBriefingSlot(
      now: DateTime.now(),
      times: briefingTimes,
      lastRunKey: prefs.getString('cached_briefing_slot'),
    );
    if (slot == null) return; // Nothing due, or already run for this slot

    Future<void> run() async {
      // The cloud model name comes from remote config, which only main()
      // loads; without this the alarm would use the compiled-in default.
      // Bounded, since load() falls back to the cached value on failure.
      await RemoteConfigService.instance.load().timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );

      await IsarDataSource.instance;

      // If the app hasn't been opened since last night, everything captured
      // meanwhile is still in the native buffer. Pull it (plus today's and
      // tomorrow's calendar) into Isar before deciding what the briefing
      // covers.
      await NotificationIngest.drainBuffer();
      await NotificationIngest.syncCalendar();
      await IsarDataSource.deleteOldNotifications();

      final briefing = cubit = BriefingCubit();

      // Only this run's result counts: the cubit can first emit a briefing
      // already cached today (when an autoplay tap is pending).
      var started = false;
      final futureState = briefing.stream.firstWhere((state) {
        if (state is BriefingGenerating) started = true;
        return started && (state is BriefingReady || state is BriefingError);
      });

      await briefing.generateBriefing();
      final state = await futureState;

      if (state is BriefingReady && !abandoned) {
        await prefs.setString('cached_briefing_slot', slot.key);
        await LocalNotificationService().init();

        // Read-only: the streak itself is only recorded once playback
        // actually starts (see StreakService.recordHeard in
        // daily_briefing_screen.dart). A live streak here just personalizes
        // today's notification body.
        final streak = await StreakService().current();
        // After two mornings unheard, one gentle nudge instead (at most one
        // per lapse; see GentleNudges).
        final nudge = await GentleNudges.missedMorningsDue(prefs);
        final body = nudge
            ? GentleNudges.missedMorningsBody
            : streak.current > 0
            ? 'Day ${streak.current} — tap to keep your streak going.'
            : 'Your personalized AI briefing is ready for today!';

        await LocalNotificationService().showNotification(
          id: slot.time.hour * 100 + slot.time.minute, // One per slot
          title: 'Daily Briefing Ready',
          body: body,
        );
        if (nudge) await GentleNudges.markMissedMorningsNudged(prefs);
      }
    }

    await run().timeout(
      _alarmBudget,
      onTimeout: () {
        abandoned = true;
        debugPrint('Background alarm task gave up after $_alarmBudget');
      },
    );
  } catch (e) {
    debugPrint('Background alarm task failed: $e');
  } finally {
    await cubit?.close();
    // Always set up the next alarm, whatever became of this one: the alarms
    // are one-shot, so a run that skipped or failed without rescheduling
    // would end briefings until the app was next opened. (iOS's periodic
    // task repeats by itself, and re-registering it from inside would cancel
    // the run in progress.)
    try {
      if (Platform.isAndroid) {
        final prefs = await SharedPreferences.getInstance();
        await ScheduleService.updateSchedules(
          prefs.getStringList('briefing_times') ?? ['07:00'],
        );
      }
    } catch (e) {
      debugPrint('Background alarm reschedule failed: $e');
    }
    // This runs in a short-lived background isolate. Release Isar before the
    // isolate is torn down — an abandoned open handle leaves the MDBX lock in a
    // state the main app's next open can't acquire (MdbxError 11: Try again).
    await IsarDataSource.close();
  }
}

// Keep the old workmanager logic for iOS fallback
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await alarmCallback();
    return Future.value(true);
  });
}

class ScheduleService {
  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
    } else if (Platform.isIOS) {
      // iOS Fallback
      Workmanager().initialize(callbackDispatcher);
    }
    // Workmanager has no macOS/Windows implementation — desktop briefing
    // scheduling isn't wired up yet (this milestone is phone-first; the
    // desktop build is the optional Echo Engine, not its own alarm clock).
  }

  /// The alarm IDs (hour*100+minute) last scheduled, so rescheduling cancels
  /// just those rather than every minute of the day.
  static const _alarmIdsKey = 'scheduled_briefing_alarm_ids';

  static Future<void> _last = Future.value();

  /// Schedules a briefing at each of [times], replacing the ones set before.
  /// Calls run one after another, so a change made in Settings while the
  /// launch's call is still going can't be undone by it.
  static Future<void> updateSchedules(List<String> times) {
    final run = _last.catchError((_) {}).then((_) => _update(times));
    _last = run;
    return run;
  }

  static Future<void> _update(List<String> times) async {
    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      final ids = {
        for (final t in times)
          if (parseBriefingTime(t) case final p?) p.hour * 100 + p.minute,
      };
      // Versions before this one kept no record, but cancelled every other
      // time of day whenever they scheduled, so only the saved times can
      // be set.
      final previous =
          prefs.getStringList(_alarmIdsKey)?.map(int.tryParse).nonNulls ?? ids;
      for (final id in {...previous, ...ids}) {
        await AndroidAlarmManager.cancel(id);
      }

      DateTime? earliest;

      for (int i = 0; i < times.length; i++) {
        final parsed = parseBriefingTime(times[i]);
        if (parsed == null)
          continue; // Skip malformed entries instead of crashing

        final now = DateTime.now();
        var alarmTime = DateTime(
          now.year,
          now.month,
          now.day,
          parsed.hour,
          parsed.minute,
        );

        // If the time has already passed today, schedule for tomorrow
        if (alarmTime.isBefore(now)) {
          alarmTime = alarmTime.add(const Duration(days: 1));
        }

        if (earliest == null || alarmTime.isBefore(earliest)) {
          earliest = alarmTime;
        }

        final alarmId = parsed.hour * 100 + parsed.minute;
        // Wrap per-alarm so one failure (e.g. missing exact-alarm permission)
        // does not abort scheduling of the remaining times.
        try {
          await AndroidAlarmManager.oneShotAt(
            alarmTime,
            alarmId,
            alarmCallback,
            // Inexact by design: Echo no longer declares the policy-restricted
            // exact-alarm permissions, so this schedules a windowed alarm. A
            // morning briefing arriving a few minutes after the set time is
            // acceptable; allowWhileIdle keeps it from being deferred for hours
            // in Doze.
            exact: false,
            wakeup: true,
            allowWhileIdle: true,
            rescheduleOnReboot: true,
          );
        } catch (e) {
          debugPrint('Failed to schedule alarm for ${times[i]}: $e');
        }
      }

      await prefs.setStringList(_alarmIdsKey, [for (final id in ids) '$id']);

      // Persisted for the native widget, which can't easily decode Dart's
      // internal StringList encoding — a plain epoch millis is robust to read
      // directly, and lets the widget compute its own "ready in Xh Ym" text.
      if (earliest != null) {
        await prefs.setInt(
          'next_briefing_epoch_ms',
          earliest.millisecondsSinceEpoch,
        );
        await WidgetRefreshService.refresh();
      }
    } else if (Platform.isIOS) {
      // iOS uses generic periodic task, exact scheduling is not possible
      Workmanager().cancelAll();
      Workmanager().registerPeriodicTask(
        "daily_briefing_1",
        "daily_briefing_task",
        frequency: const Duration(hours: 1),
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: true,
          requiresDeviceIdle: false,
        ),
      );
    }
    // macOS/Windows: no-op — see initialize() above.
  }
}
