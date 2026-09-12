import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/appearance_segmented_control.dart';
import 'package:project_echo/features/settings/presentation/widgets/cloud_engine_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/scheduled_briefings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/voice_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/tone_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/model_management_section.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/features/echo/presentation/screens/streak_celebration_screen.dart';
import 'package:project_echo/features/profile/presentation/widgets/streak_calendar.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// The Profile tab: your streak calendar up top, then all app settings merged
/// into the same screen (appearance, voice, tone, AI engine, schedule, debug).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProfileView();
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView>
    with WidgetsBindingObserver {
  final _calendarKey = GlobalKey<StreakCalendarState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _calendarKey.currentState?.reload();
    }
  }

  void _refreshCalendar() => _calendarKey.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              FadeSlideIn(
                child: Text(
                  'Profile',
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    height: 1.15,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Streak — the default view is the calendar, not the animation.
              FadeSlideIn(
                child: StreakCalendar(key: _calendarKey),
              ),

              const SizedBox(height: 32),

              // Appearance Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const AppearanceSegmentedControl(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Voice Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'How Echo sounds when it reads your briefing.',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const VoiceSettingsSection(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Tone Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tone',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'How Echo talks to you in every briefing.',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const ToneSettingsSection(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // AI Engine Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Engine',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    BlocBuilder<SettingsCubit, SettingsState>(
                      builder: (context, state) {
                        return FutureBuilder<String?>(
                          future: _getModelSize(),
                          builder: (context, snapshot) {
                            final sizeStr = snapshot.data;
                            return AiModeCard(
                              isSelected: state.isOfflineEngine,
                              icon: Icons.laptop_mac,
                              title: 'Offline (Private)',
                              tags: [
                                'Qwen2.5 1.5B',
                                sizeStr ?? '0.9 GB',
                                'No API cost',
                              ],
                              speedLabel: 'Fast',
                              isFast: true,
                              onTap: () {
                                context.read<SettingsCubit>().setAiEngine(
                                  isOffline: true,
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    const CloudEngineCard(),
                    const SizedBox(height: 16),
                    const ModelManagementSection(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Scheduled Briefings Section
              FadeSlideIn(
                delay: AppMotion.staggerDelay(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scheduled Briefings',
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const ScheduledBriefingsSection(),
                  ],
                ),
              ),
              // Debug-only tools: exercise flows that normally require waiting
              // for a real scheduled time or several real days to pass.
              if (kDebugMode) ...[
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
                    icon: const Icon(Icons.replay_rounded, size: 18),
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
                    icon: const Icon(Icons.notifications_active_outlined, size: 18),
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
                    icon: const Icon(Icons.local_fire_department_outlined, size: 18),
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
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
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
                    icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                    label: const Text('Preview streak animation (debug)'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 120), // Padding for the bottom nav bar
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _getModelSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf';
      final file = File(modelPath);
      if (await file.exists()) {
        final bytes = await file.length();
        final gb = bytes / (1024 * 1024 * 1024);
        return '${gb.toStringAsFixed(1)} GB';
      }
    } catch (e) {
      // Ignore
    }
    return null;
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
            AndroidFlutterLocalNotificationsPlugin>();
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
    _refreshCalendar();
    WidgetRefreshService.refresh();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => StreakCelebrationScreen(days: info.current),
        ),
      );
    }
  }

  /// Non-destructive: replays the celebration animation without touching the
  /// real streak count, so you can restest the visual as many times as you
  /// like. Falls back to a demo value when there's no streak yet.
  Future<void> _previewStreakAnimation(BuildContext context) async {
    final info = await StreakService().current();
    final days = info.current > 0 ? info.current : 3;
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => StreakCelebrationScreen(days: days),
        ),
      );
    }
  }

  Future<void> _resetStreak(BuildContext context) async {
    await StreakService().debugResetStreak();
    _refreshCalendar();
    WidgetRefreshService.refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Streak reset to 0.')),
      );
    }
  }
}
