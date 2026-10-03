import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/echo/presentation/screens/echo_mascot_preview.dart';
import 'package:project_echo/features/echo/presentation/screens/streak_celebration_screen.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Debug builds only: flows that normally need a real scheduled time or
/// several real days to pass.
class DebugTools extends StatelessWidget {
  /// The streak changed (the calendar showing it can reload).
  final VoidCallback? onStreakChanged;

  const DebugTools({super.key, this.onStreakChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('onboarding_finished', false);
              if (!context.mounted) return;
              context.read<OnBoardingCubit>().startOnboarding();
              context.go('/');
            },
            icon: const Icon(Symbols.replay_rounded, size: 18),
            label: const Text('Replay onboarding (debug)'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _sendTestNotification(context),
            icon: const Icon(Symbols.notifications_active_rounded, size: 18),
            label: const Text('Send test briefing notification (debug)'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _bumpStreak(context),
            icon: const Icon(Symbols.local_fire_department_rounded, size: 18),
            label: const Text('+1 streak day (debug)'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _resetStreak(context),
            icon: const Icon(Symbols.restart_alt_rounded, size: 18),
            label: const Text('Reset streak (debug)'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _previewStreakAnimation(context),
            icon: const Icon(Symbols.play_circle_rounded, size: 18),
            label: const Text('Preview streak animation (debug)'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.of(
              context,
              rootNavigator: true,
            ).push(bouncyRoute(const EchoMascotPreview())),
            icon: const Icon(Symbols.blur_on_rounded, size: 18),
            label: const Text('Preview Echo mascot (debug)'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// Debug-only: fires the same notification `alarmCallback` shows when a
  /// scheduled briefing is ready — including the "Play" action — without
  /// waiting for a real scheduled time. Swipe the app away first to test the
  /// fully-terminated tap-to-play path.
  Future<void> _sendTestNotification(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    if (prefs.getString('cached_briefing_date') != today) {
      await prefs.setString('cached_briefing_date', today);
      await prefs.setString(
        'cached_briefing_text',
        'This is a debug test briefing so you can try tap-to-play from the '
            'notification without waiting for a real one.',
      );
    }

    final streak = await StreakService().current();
    final service = LocalNotificationService();
    await service.init();
    await service.showNotification(
      id: 999999,
      title: 'Daily Briefing Ready (debug)',
      body: streak.current > 0
          ? 'Day ${streak.current} — tap to keep your streak going.'
          : 'Your personalized AI briefing is ready for today!',
    );

    // Give a clear, honest signal instead of a silent no-op: on Android 13+
    // the OS requires POST_NOTIFICATIONS to be granted, which `init()` now
    // requests — but the user may still have denied it.
    final androidPlugin = service.flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = await androidPlugin?.areNotificationsEnabled() ?? true;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Test notification sent — check your notification shade.'
                : 'Notifications are disabled for Echo — enable them in system '
                      'settings to see this.',
          ),
        ),
      );
    }
  }

  Future<void> _bumpStreak(BuildContext context) async {
    final info = await StreakService().debugBumpStreak();
    onStreakChanged?.call();
    WidgetRefreshService.refresh();
    if (context.mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(bouncyRoute(StreakCelebrationScreen(days: info.current)));
    }
  }

  /// Non-destructive: replays the celebration animation without touching the
  /// real streak count, so you can restest the visual as many times as you
  /// like. Falls back to a demo value when there's no streak yet.
  Future<void> _previewStreakAnimation(BuildContext context) async {
    final info = await StreakService().current();
    final days = info.current > 0 ? info.current : 3;
    if (context.mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(bouncyRoute(StreakCelebrationScreen(days: days)));
    }
  }

  Future<void> _resetStreak(BuildContext context) async {
    await StreakService().debugResetStreak();
    onStreakChanged?.call();
    WidgetRefreshService.refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Streak reset to 0.')));
    }
  }
}
