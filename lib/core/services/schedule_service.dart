import 'dart:io';
import 'package:flutter/material.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:project_echo/core/utils/time_utils.dart';

@pragma('vm:entry-point')
Future<void> alarmCallback() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    final now = DateTime.now();

    // We check which schedule this alarm belongs to
    final briefingTimes = prefs.getStringList('briefing_times') ?? ['07:00'];
    String? matchedTimeSlot;

    for (final timeStr in briefingTimes) {
      final parsed = parseBriefingTime(timeStr);
      if (parsed == null) continue; // Skip malformed persisted entries

      // Check if current time is roughly the scheduled time (within 2 minutes)
      final diff = (now.hour * 60 + now.minute) - parsed.minutesOfDay;
      if (diff.abs() <= 2) {
        final compositeKey = '${today}_$timeStr';
        final cachedSlot = prefs.getString('cached_briefing_slot');

        if (cachedSlot != compositeKey) {
          matchedTimeSlot = compositeKey;
          break;
        }
      }
    }

    if (matchedTimeSlot == null) {
      return; // Already executed for this slot
    }

    await IsarDataSource.instance;

    final cubit = BriefingCubit();

    final futureState = cubit.stream.firstWhere(
      (state) => state is BriefingReady || state is BriefingError,
    );

    await cubit.generateBriefing();
    final state = await futureState;

    if (state is BriefingReady) {
      await prefs.setString('cached_briefing_slot', matchedTimeSlot!);
      await LocalNotificationService().init();

      // Read-only: the streak itself is only recorded once playback actually
      // starts (see StreakService.recordHeard in daily_briefing_screen.dart).
      // A live streak here just personalizes today's notification body.
      final streak = await StreakService().current();
      final body = streak.current > 0
          ? 'Day ${streak.current} — tap to keep your streak going.'
          : 'Your personalized AI briefing is ready for today!';

      await LocalNotificationService().showNotification(
        id: now.hour * 100 + now.minute, // Unique per hour+minute slot
        title: 'Daily Briefing Ready',
        body: body,
      );
    }

    await cubit.close();

    // Re-schedule for next days
    await ScheduleService.updateSchedules(briefingTimes);
  } catch (e) {
    debugPrint('Background alarm task failed: $e');
  } finally {
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

  static Future<void> updateSchedules(List<String> times) async {
    if (Platform.isAndroid) {
      // Cancel existing ones (we'll just use a large range since ID is hour*100+min)
      for (int i = 0; i < 2400; i++) {
        await AndroidAlarmManager.cancel(i);
      }

      DateTime? earliest;

      for (int i = 0; i < times.length; i++) {
        final parsed = parseBriefingTime(times[i]);
        if (parsed == null) continue; // Skip malformed entries instead of crashing

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

      // Persisted for the native widget, which can't easily decode Dart's
      // internal StringList encoding — a plain epoch millis is robust to read
      // directly, and lets the widget compute its own "ready in Xh Ym" text.
      if (earliest != null) {
        final prefs = await SharedPreferences.getInstance();
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
