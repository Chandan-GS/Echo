import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/settings/presentation/widgets/appearance_segmented_control.dart';
import 'package:project_echo/features/settings/presentation/widgets/scheduled_briefings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/voice_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/tone_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/desktop_engine_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/ai_engine_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/debug_tools.dart';
import 'package:project_echo/features/settings/presentation/widgets/analytics_toggle_section.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/features/profile/presentation/widgets/streak_calendar.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/widgets/presentation/screens/widgets_screen.dart';
import 'dart:io';
import 'package:material_symbols_icons/symbols.dart';

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
      // Scrolls behind the phone's nav dock; MediaQuery's bottom padding is
      // the room it needs at the end (see MainScaffold).
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            _isDesktop ? 40.0 : 24.0,
            0,
            _isDesktop ? 40.0 : 24.0,
            MediaQuery.paddingOf(context).bottom + 16,
          ),
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
                  FadeSlideIn(child: StreakCalendar(key: _calendarKey)),

                  const SizedBox(height: 32),

                  if (HomeWidgetsService.supported) ...[
                    _widgetsSection(context),
                    const SizedBox(height: 32),
                  ],

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
                    DebugTools(onStreakChanged: _refreshCalendar),
                  ],

                  const SizedBox(height: 32),
                  _privacySection(context),

                  const SizedBox(height: 32),
                  _aboutSection(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(
    BuildContext context,
    String title, {
    String? subtitle,
  }) {
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
            style: GoogleFonts.nunito(
              fontSize: 14,
              color: context.colors.textSecondary,
            ),
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
          const AiEngineSection(),
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

  /// Home screen widgets: a row that opens the Widgets page, saying how many
  /// of Echo's widgets are already on the home screen.
  Widget _widgetsSection(BuildContext context) {
    return FadeSlideIn(
      delay: AppMotion.staggerDelay(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(context, 'Home screen widgets'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.dividerColor),
            ),
            child: FutureBuilder<HomeWidgetsState?>(
              key: ValueKey(_widgetsRefresh),
              future: HomeWidgetsService.state(),
              builder: (context, snap) {
                final placed = snap.data?.kindsPlaced ?? 0;
                return _aboutTile(
                  context,
                  icon: Symbols.widgets_rounded,
                  title: 'Widgets',
                  subtitle: placed == 0
                      ? '4 available · none on your home screen yet'
                      : '4 available · $placed on your home screen',
                  onTap: () async {
                    await Navigator.of(context, rootNavigator: true).push(
                      bouncyRoute(
                        BlocProvider.value(
                          value: context.read<TodoCubit>(),
                          child: const WidgetsScreen(),
                        ),
                      ),
                    );
                    if (mounted) setState(() => _widgetsRefresh++);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _widgetsRefresh = 0;

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
                  icon: Symbols.privacy_tip_rounded,
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
                  icon: Symbols.mail_rounded,
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
                Symbols.chevron_right_rounded,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't open that link: $e")));
    }
  }










}
