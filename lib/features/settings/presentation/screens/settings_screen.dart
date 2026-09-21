import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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
import 'package:project_echo/features/settings/presentation/widgets/desktop_engine_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/analytics_toggle_section.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:project_echo/core/services/local_notification_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/features/echo/presentation/screens/streak_celebration_screen.dart';
import 'package:project_echo/features/echo/presentation/screens/echo_mascot_preview.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/features/profile/presentation/widgets/streak_calendar.dart';
import 'dart:io';
import 'package:project_echo/core/services/offline_model_repository.dart';

bool get _isDesktop => Platform.isMacOS || Platform.isWindows;

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
          padding: EdgeInsets.symmetric(horizontal: _isDesktop ? 40.0 : 24.0),
          // Desktop fills the window, so centre the content and cap it — a
          // full-bleed settings form across a wide window reads as unfinished;
          // ~1040 keeps the two columns comfortable.
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _isDesktop ? 1040 : double.infinity,
              ),
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

              // Desktop: a genuine two-column layout — not a narrow phone
              // list centered in empty space. Phone: unchanged single column.
              if (_isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _appearanceSection(context),
                          const SizedBox(height: 32),
                          _voiceSection(context),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _toneSection(context),
                          const SizedBox(height: 32),
                          _aiEngineSection(context),
                          const SizedBox(height: 32),
                          _scheduledSection(context),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _appearanceSection(context),
                const SizedBox(height: 32),
                _voiceSection(context),
                const SizedBox(height: 32),
                _toneSection(context),
                const SizedBox(height: 32),
                _aiEngineSection(context),
                const SizedBox(height: 32),
                _scheduledSection(context),
              ],

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
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context, rootNavigator: true)
                        .push(bouncyRoute(const EchoMascotPreview())),
                    icon: const Icon(Icons.blur_on_rounded, size: 18),
                    label: const Text('Preview Echo mascot (debug)'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],

                  const SizedBox(height: 32),
                  _privacySection(context),

                  const SizedBox(height: 32),
                  _aboutSection(context),

                  const SizedBox(height: 120), // Padding for the bottom nav bar
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(BuildContext context, String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.nunito(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.nunito(fontSize: 14, color: context.colors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _appearanceSection(BuildContext context) {
    return FadeSlideIn(
      delay: AppMotion.staggerDelay(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(context, 'Appearance'),
          const SizedBox(height: 16),
          const AppearanceSegmentedControl(),
        ],
      ),
    );
  }

  Widget _voiceSection(BuildContext context) {
    return FadeSlideIn(
      delay: AppMotion.staggerDelay(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            context,
            'Voice',
            subtitle: 'How Echo sounds when it reads your briefing.',
          ),
          const SizedBox(height: 16),
          const VoiceSettingsSection(),
        ],
      ),
    );
  }

  Widget _toneSection(BuildContext context) {
    return FadeSlideIn(
      delay: AppMotion.staggerDelay(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            context,
            'Tone',
            subtitle: 'How Echo talks to you in every briefing.',
          ),
          const SizedBox(height: 16),
          const ToneSettingsSection(),
        ],
      ),
    );
  }

  Widget _aiEngineSection(BuildContext context) {
    return FadeSlideIn(
      delay: AppMotion.staggerDelay(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(context, 'AI Engine'),
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
                      offlineModelDisplayName(),
                      sizeStr ?? offlineModelSizeLabel(),
                      'No API cost',
                    ],
                    speedLabel: 'Fast',
                    isFast: true,
                    onTap: () {
                      context.read<SettingsCubit>().setAiEngine(isOffline: true);
                    },
                  );
                },
              );
            },
          ),
          const CloudEngineCard(),
          const SizedBox(height: 16),
          const ModelManagementSection(),
          const SizedBox(height: 16),
          const DesktopEngineSection(),
        ],
      ),
    );
  }

  Widget _scheduledSection(BuildContext context) {
    return FadeSlideIn(
      delay: AppMotion.staggerDelay(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(context, 'Scheduled Briefings'),
          const SizedBox(height: 16),
          const ScheduledBriefingsSection(),
        ],
      ),
    );
  }

  Widget _privacySection(BuildContext context) {
    return FadeSlideIn(
      delay: AppMotion.staggerDelay(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            context,
            'Privacy',
            subtitle: 'Echo runs on your device. This stays optional.',
          ),
          const SizedBox(height: 16),
          const AnalyticsToggleSection(),
        ],
      ),
    );
  }

  Widget _aboutSection(BuildContext context) {
    return FadeSlideIn(
      delay: AppMotion.staggerDelay(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(context, 'About'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.dividerColor),
            ),
            child: Column(
              children: [
                _aboutTile(
                  context,
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'How your data is handled',
                  onTap: () => _openUrl(
                    context,
                    'https://echo-mobileapp.vercel.app/privacy',
                  ),
                ),
                Divider(height: 1, color: context.colors.dividerColor),
                _aboutTile(
                  context,
                  icon: Icons.mail_outline_rounded,
                  title: 'Contact the founder',
                  subtitle: 'chandan1204@gmail.com — questions or bug reports',
                  onTap: () => _openUrl(
                    context,
                    'mailto:chandan1204@gmail.com?subject=Echo%20feedback',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: context.colors.primaryGreen),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open that link: $e")),
      );
    }
  }

  Future<String?> _getModelSize() async {
    try {
      final path = await createOfflineModelRepository().downloadedPathOrNull();
      if (path != null) {
        final bytes = await File(path).length();
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
        bouncyRoute(StreakCelebrationScreen(days: info.current)),
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
        bouncyRoute(StreakCelebrationScreen(days: days)),
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
