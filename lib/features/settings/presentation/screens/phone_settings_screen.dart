import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/presentation/widgets/pressable.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';
import 'package:project_echo/core/services/reminder_settings.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/widgets/ai_engine_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/analytics_toggle_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/appearance_segmented_control.dart';
import 'package:project_echo/features/settings/presentation/widgets/debug_tools.dart';
import 'package:project_echo/features/settings/presentation/widgets/desktop_engine_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/reminder_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/scheduled_briefings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/tone_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/voice_settings_section.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/vault/presentation/screens/app_access_screen.dart';
import 'package:project_echo/features/widgets/presentation/screens/widgets_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Every setting, behind Profile's gear: Appearance in place (it's the one
/// changed most), everything else a row with its current value that opens a
/// page of its own.
class PhoneSettingsScreen extends StatefulWidget {
  /// The to-do list, for the Widgets page's previews.
  final TodoCubit todoCubit;

  const PhoneSettingsScreen({super.key, required this.todoCubit});

  @override
  State<PhoneSettingsScreen> createState() => _PhoneSettingsScreenState();
}

class _PhoneSettingsScreenState extends State<PhoneSettingsScreen> {
  String? _voice;
  String? _tone;
  int _widgetsPlaced = 0;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The values rows show, read again whenever a page closes.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final pref = VoicePreference.read(prefs);
    final widgets = HomeWidgetsService.supported
        ? await HomeWidgetsService.state()
        : null;
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _voice = '${pref.voice.label} · ${pref.accent.label}';
      _tone = onboardingToneFromId(prefs.getString('briefing_tone')).label;
      _widgetsPlaced = widgets?.kindsPlaced ?? 0;
      _version = info.version;
    });
  }

  Future<void> _open(String title, Widget page, {String? subtitle}) async {
    await Navigator.of(context).push(
      bouncyRoute(SettingsPage(title: title, subtitle: subtitle, child: page)),
    );
    await _load();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(bouncyRoute(screen));
    await _load();
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That link couldn't be opened.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var n = 0;
    Widget enter(Widget child) =>
        FadeSlideIn(delay: AppMotion.staggerDelay(n++), child: child);
    return Scaffold(
      backgroundColor: c.background,
      appBar: const EchoAppBar(title: 'Settings'),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settings) => ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.paddingOf(context).bottom + 32,
          ),
          children: [
            enter(const _GroupLabel('Appearance', first: true)),
            enter(const AppearanceSegmentedControl()),
            enter(const _GroupLabel('Echo')),
            enter(
              _Group(
                rows: [
                  _Row(
                    icon: Symbols.record_voice_over_rounded,
                    title: 'Voice',
                    value: _voice,
                    onTap: () => _open(
                      'Voice',
                      const VoiceSettingsSection(),
                      subtitle: 'How Echo sounds when it reads to you.',
                    ),
                  ),
                  _Row(
                    icon: Symbols.sentiment_satisfied_rounded,
                    title: 'Tone',
                    value: _tone,
                    onTap: () => _open(
                      'Tone',
                      const ToneSettingsSection(),
                      subtitle: 'How Echo talks to you in every briefing.',
                    ),
                  ),
                  _Row(
                    icon: Symbols.schedule_rounded,
                    title: 'Briefings',
                    value: _times(settings.briefingTimes),
                    onTap: () =>
                        _open('Briefings', const ScheduledBriefingsSection()),
                  ),
                  _Row(
                    icon: Symbols.notifications_active_rounded,
                    title: 'Reminders',
                    value:
                        '${ReminderSettings.label(ReminderSettings.lead.value)} '
                        'before · suggestions '
                        '${ReminderSettings.suggest.value ? 'on' : 'off'}',
                    onTap: () => _open(
                      'Reminders',
                      const ReminderSettingsSection(),
                      subtitle:
                          'For things with a time, Echo suggests a reminder '
                          'this long before. You can always pick your own.',
                    ),
                  ),
                ],
              ),
            ),
            enter(const _GroupLabel('Intelligence')),
            enter(
              _Group(
                rows: [
                  _Row(
                    icon: Symbols.memory_rounded,
                    title: 'AI engine',
                    value: settings.isOfflineEngine
                        ? 'Offline, on this phone'
                        : 'Cloud (Gemini)',
                    onTap: () => _open(
                      'AI engine',
                      const AiEngineSection(),
                      subtitle:
                          'Where Echo thinks. Your messages stay on the phone '
                          'either way; only what a question needs is sent.',
                    ),
                  ),
                  _Row(
                    icon: Symbols.computer_rounded,
                    title: 'Desktop engine',
                    value: settings.desktopEngineHost == null
                        ? 'Not paired'
                        : 'Paired',
                    onTap: () =>
                        _open('Desktop engine', const DesktopEngineSection()),
                  ),
                ],
              ),
            ),
            enter(const _GroupLabel('Privacy')),
            enter(
              _Group(
                rows: [
                  _Row(
                    icon: Symbols.apps_rounded,
                    title: 'Apps Echo hears',
                    value: 'Choose which apps Echo reads',
                    onTap: () => _push(const AppAccessScreen()),
                  ),
                  _Row(
                    icon: Symbols.analytics_rounded,
                    title: 'Usage analytics',
                    value: Analytics.isEnabled ? 'On' : 'Off',
                    onTap: () => _open(
                      'Usage analytics',
                      const AnalyticsToggleSection(),
                      subtitle:
                          'Echo runs on your device. This stays optional.',
                    ),
                  ),
                ],
              ),
            ),
            enter(const _GroupLabel('More')),
            enter(
              _Group(
                rows: [
                  if (HomeWidgetsService.supported)
                    _Row(
                      icon: Symbols.widgets_rounded,
                      title: 'Widgets',
                      value: _widgetsPlaced == 0
                          ? 'None on your home screen yet'
                          : '$_widgetsPlaced on your home screen',
                      onTap: () => _push(
                        BlocProvider.value(
                          value: widget.todoCubit,
                          child: const WidgetsScreen(),
                        ),
                      ),
                    ),
                  _Row(
                    icon: Symbols.policy_rounded,
                    title: 'Privacy policy',
                    value: 'How your data is handled',
                    onTap: () =>
                        _openUrl('https://echo-mobileapp.vercel.app/privacy'),
                  ),
                  _Row(
                    icon: Symbols.mail_rounded,
                    title: 'Contact the founder',
                    value: 'Questions or bug reports',
                    onTap: () => _openUrl(
                      'mailto:chandan1204@gmail.com?subject=Echo%20feedback',
                    ),
                  ),
                ],
              ),
            ),
            if (kDebugMode) ...[
              enter(const _GroupLabel('Developer')),
              enter(
                _Group(
                  rows: [
                    _Row(
                      icon: Symbols.build_rounded,
                      title: 'Debug tools',
                      value: 'Onboarding, test notification, streak',
                      onTap: () => _open('Debug tools', const DebugTools()),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              _version.isEmpty ? '' : 'Echo $_version',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                color: c.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ["07:00", "19:00"] → "7:00 AM and 7:00 PM".
  static String _times(List<String> times) {
    final labels = [
      for (final t in times)
        if (t.split(':') case [final h, final m])
          '${(int.parse(h) % 12 == 0 ? 12 : int.parse(h) % 12)}:$m '
              '${int.parse(h) < 12 ? 'AM' : 'PM'}',
    ];
    if (labels.isEmpty) return 'None scheduled';
    if (labels.length == 1) return labels.single;
    return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
  }
}

/// One setting's own page: the app bar, a line about it, and its controls.
class SettingsPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const SettingsPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: EchoAppBar(title: title),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          MediaQuery.paddingOf(context).bottom + 32,
        ),
        child: FadeSlideIn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subtitle != null) ...[
                Text(
                  subtitle!,
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    height: 1.5,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// "ECHO", over a group of rows.
class _GroupLabel extends StatelessWidget {
  final String text;
  final bool first;
  const _GroupLabel(this.text, {this.first = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(6, first ? 8 : 26, 6, 10),
    child: Text(
      text.toUpperCase(),
      style: GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: context.colors.textSecondary,
      ),
    ),
  );
}

/// Rows in one rounded card, divided by hairlines.
class _Group extends StatelessWidget {
  final List<_Row> rows;
  const _Group({required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 64,
                color: c.dividerColor.withValues(alpha: 0.6),
              ),
            row,
          ],
        ],
      ),
    );
  }
}

/// A setting: its icon, its name, its current value, and a chevron.
class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      scale: 0.98,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color.lerp(c.background, c.surface, 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: c.textPrimary),
                ),
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
                          color: c.textPrimary,
                        ),
                      ),
                      if (value != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Symbols.chevron_right_rounded,
                  size: 22,
                  color: c.textSecondary.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
