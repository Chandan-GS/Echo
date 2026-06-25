import 'dart:io';
import 'package:flutter/material.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

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
      final parts = timeStr.split(':');
      final targetHour = int.tryParse(parts[0]);
      final targetMinute = int.tryParse(parts[1]);

      // Check if current time is roughly the scheduled time (within 2 minutes)
      if (targetHour != null && targetMinute != null) {
        final diff =
            (now.hour * 60 + now.minute) - (targetHour * 60 + targetMinute);
        if (diff.abs() <= 2) {
          final compositeKey = '${today}_$timeStr';
          final cachedSlot = prefs.getString('cached_briefing_slot');

          if (cachedSlot != compositeKey) {
            matchedTimeSlot = compositeKey;
            break;
          }
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
      await LocalNotificationService().showNotification(
        id: now.hour, // Unique ID per hour
        title: 'Daily Briefing Ready',
        body: 'Your personalized AI briefing is ready for today!',
      );
    }

    await cubit.close();

    // Re-schedule for next days
    await ScheduleService.updateSchedules(briefingTimes);
  } catch (e) {
    debugPrint('Background alarm task failed: $e');
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
    } else {
      // iOS Fallback
      Workmanager().initialize(callbackDispatcher);
    }
  }

  static Future<void> updateSchedules(List<String> times) async {
    if (Platform.isAndroid) {
      // Cancel existing ones (we'll just use a large range since ID is hour*100+min)
      for (int i = 0; i < 2400; i++) {
        await AndroidAlarmManager.cancel(i);
      }

      for (int i = 0; i < times.length; i++) {
        final parts = times[i].split(':');
        final targetHour = int.parse(parts[0]);
        final targetMinute = int.parse(parts[1]);

        final now = DateTime.now();
        var alarmTime = DateTime(
          now.year,
          now.month,
          now.day,
          targetHour,
          targetMinute,
        );

        // If the time has already passed today, schedule for tomorrow
        if (alarmTime.isBefore(now)) {
          alarmTime = alarmTime.add(const Duration(days: 1));
        }

        final alarmId = targetHour * 100 + targetMinute;
        await AndroidAlarmManager.oneShotAt(
          alarmTime,
          alarmId,
          alarmCallback,
          exact: true,
          wakeup: true,
          allowWhileIdle: true,
          rescheduleOnReboot: true,
        );
      }
    } else {
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
  }
}
