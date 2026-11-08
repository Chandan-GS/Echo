import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';
import 'package:project_echo/core/services/model_download_service.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/core/services/reminder_settings.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';
import 'package:project_echo/features/quiet/data/quiet_settings.dart';
import 'package:project_echo/features/settings/data/engine_status.dart';
import 'package:project_echo/features/settings/data/schedule_prefs.dart';
import 'package:project_echo/features/settings/data/writing_pack.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/screens/briefing_settings_page.dart';
import 'package:project_echo/features/settings/presentation/screens/cloud_engine_page.dart';
import 'package:project_echo/features/settings/presentation/screens/evening_wrap_page.dart';
import 'package:project_echo/features/settings/presentation/screens/writing_pack_page.dart';
import 'package:project_echo/features/settings/presentation/widgets/appearance_segmented_control.dart';
import 'package:project_echo/features/settings/presentation/widgets/debug_tools.dart';
import 'package:project_echo/features/settings/presentation/widgets/desktop_engine_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/history_settings_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/reminder_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/settings_kit.dart';
import 'package:project_echo/features/settings/presentation/widgets/tone_settings_section.dart';
import 'package:project_echo/features/settings/presentation/widgets/voice_settings_section.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/widgets/presentation/screens/widgets_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Every setting, regrouped around the day: rows that say their current
/// value and open a page of their own, with History and Appearance in place.
class PhoneSettingsScreen extends StatefulWidget {
  /// The old Profile screen passes its to-do list for the Widgets page; the
  /// `/settings` route opens Widgets by route instead.
  final TodoCubit? todoCubit;

  const PhoneSettingsScreen({super.key, this.todoCubit});

  @override
  State<PhoneSettingsScreen> createState() => _PhoneSettingsScreenState();
}

class _PhoneSettingsScreenState extends State<PhoneSettingsScreen> {
  String? _voice;
  String? _tone;
  String _name = '';
  int _widgetsPlaced = 0;
  String _version = '';
  QuietConfig? _quiet;

  @override
  void initState() {
    super.initState();
    WritingPack.refresh();
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
    final quiet = await QuietSettings.load();
    if (!mounted) return;
    setState(() {
      _voice = '${pref.voice.label} · ${pref.accent.label}';
      _tone = onboardingToneFromId(prefs.getString('briefing_tone')).label;
      _name = prefs.getString('user_name')?.trim() ?? '';
      _widgetsPlaced = widgets?.kindsPlaced ?? 0;
      _version = '${info.version} (${info.buildNumber})';
      _quiet = quiet;
    });
  }

  Future<void> _open(String title, Widget page, {String? subtitle}) async {
    await Navigator.of(context).push(
      bouncyRoute(SettingsPage(title: title, subtitle: subtitle, child: page)),
    );
    await _load();
  }

  Future<void> _route(String location) async {
    await context.push(location);
    await _load();
  }

  Future<void> _openWidgets() async {
    final cubit = widget.todoCubit;
    if (cubit == null) return _route('/you/widgets');
    await Navigator.of(context).push(
      bouncyRoute(
        BlocProvider.value(value: cubit, child: const WidgetsScreen()),
      ),
    );
    await _load();
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      settingsToast(context, "That link couldn't be opened.");
    }
  }

  Future<void> _rename() async {
    final next = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _NameSheet(current: _name),
    );
    final trimmed = next?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _name) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', trimmed);
    if (!mounted) return;
    setState(() => _name = trimmed);
    settingsToast(context, 'Echo will call you $trimmed');
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
      // Both listenables feed row values, so a download finishing, or an
      // engine chosen on the first-use sheet, shows here without a reopen.
      body: ListenableBuilder(
        listenable: Listenable.merge([
          WritingPack.status,
          ModelDownloadService.instance.state,
          ReminderSettings.lead,
          ReminderSettings.suggest,
        ]),
        builder: (context, _) => BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, settings) {
            n = 0;
            final pack = WritingPack.status.value;
            final download = ModelDownloadService.instance.state.value;
            final engine = engineInUse(
              isOffline: settings.isOfflineEngine,
              geminiKey: settings.geminiApiKey,
              packReady: pack.ready,
            );
            final computer = settings.preferDesktopEngine &&
                settings.desktopEngineHost != null;
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                24,
                8,
                24,
                MediaQuery.paddingOf(context).bottom + 32,
              ),
              children: [
                enter(const SettingsGroupLabel('Echo', first: true)),
                enter(
                  SettingsGroup(
                    rows: [
                      SettingsRow(
                        icon: Symbols.record_voice_over_rounded,
                        title: 'Voice',
                        value: _voice,
                        onTap: () => _open(
                          'Voice',
                          const VoiceSettingsSection(),
                          subtitle: 'How Echo sounds when it reads to you.',
                        ),
                      ),
                      SettingsRow(
                        icon: Symbols.sentiment_satisfied_rounded,
                        title: 'Tone',
                        value: _tone,
                        onTap: () => _open(
                          'Tone',
                          const ToneSettingsSection(),
                          subtitle:
                              'How Echo talks to you, and how its suggested '
                              'replies sound.',
                        ),
                      ),
                      SettingsRow(
                        icon: Symbols.badge_rounded,
                        title: 'What Echo calls you',
                        value: _name.isEmpty ? 'Not set' : _name,
                        onTap: _rename,
                      ),
                    ],
                  ),
                ),
                enter(const SettingsGroupLabel('Your day')),
                enter(
                  SettingsGroup(
                    rows: [
                      SettingsRow(
                        icon: Symbols.bedtime_rounded,
                        title: 'Evening wrap',
                        value: settings.eveningWrapEnabled
                            ? '${clockLabel(settings.eveningWrapTime)} · '
                                  'who’s waiting, tomorrow’s to-dos'
                            : 'Off',
                        onTap: () => _open(
                          'Evening wrap',
                          const EveningWrapPage(),
                          subtitle:
                              'One quiet notification in the evening: who’s '
                              'still waiting, and tomorrow’s to-dos.',
                        ),
                      ),
                      SettingsRow(
                        icon: Symbols.wb_twilight_rounded,
                        title: 'Morning briefing',
                        value: !settings.briefingEnabled
                            ? 'Off'
                            : settings.briefingTimes.isEmpty
                            ? 'None scheduled'
                            : joinClockLabels(settings.briefingTimes),
                        onTap: () => _open(
                          'Morning briefing',
                          const BriefingSettingsPage(),
                          subtitle:
                              'A spoken summary in the morning. Optional: the '
                              'evening wrap does the daily check-in.',
                        ),
                      ),
                      SettingsRow(
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
                              'For things with a time, Echo suggests a '
                              'reminder this long before. You can always pick '
                              'your own.',
                        ),
                      ),
                    ],
                  ),
                ),
                enter(const SettingsGroupLabel('Quiet hours')),
                enter(
                  SettingsGroup(
                    rows: [
                      SettingsRow(
                        icon: Symbols.do_not_disturb_on_rounded,
                        title: 'Schedule',
                        value: _quietWhen(_quiet),
                        onTap: () => _route('/quiet'),
                      ),
                      SettingsRow(
                        icon: Symbols.how_to_reg_rounded,
                        title: 'Who gets through',
                        value: _quietThrough(_quiet),
                        onTap: () => _route('/quiet'),
                      ),
                    ],
                  ),
                ),
                enter(const SettingsGroupLabel('Understanding')),
                enter(
                  SettingsGroup(
                    rows: [
                      SettingsRow(
                        icon: Symbols.auto_awesome_rounded,
                        title: 'Echo writes with',
                        value: engineSummary(
                          engine,
                          packName: offlineModelDisplayName(),
                          computerPaired: computer,
                        ),
                        onTap: () => engine == EngineInUse.cloud
                            ? _openCloud()
                            : _openPack(),
                      ),
                      SettingsRow(
                        icon: Symbols.download_for_offline_rounded,
                        title: 'Writing pack',
                        value: _packValue(download, pack),
                        onTap: _openPack,
                      ),
                      SettingsRow(
                        icon: Symbols.cloud_rounded,
                        title: 'Cloud engine',
                        value: settings.isOfflineEngine
                            ? 'Off · nothing goes to Google'
                            : settings.geminiApiKey.isEmpty
                            ? 'On · add your Gemini key'
                            : 'On · Gemini with your own key',
                        onTap: _openCloud,
                      ),
                      SettingsRow(
                        icon: Symbols.apps_rounded,
                        title: 'What Echo reads',
                        value: 'Choose which apps Echo reads',
                        onTap: () => _route('/you/hears'),
                      ),
                    ],
                  ),
                ),
                enter(const SettingsGroupLabel('History')),
                enter(const HistorySettingsCard()),
                enter(const SettingsGroupLabel('Appearance')),
                enter(const AppearanceSegmentedControl()),
                enter(const SettingsGroupLabel('Privacy')),
                enter(const _AnalyticsCard()),
                enter(const SettingsGroupLabel('More')),
                enter(
                  SettingsGroup(
                    rows: [
                      if (HomeWidgetsService.supported)
                        SettingsRow(
                          icon: Symbols.widgets_rounded,
                          title: 'Widgets',
                          value: _widgetsPlaced == 0
                              ? 'None on your home screen yet'
                              : '$_widgetsPlaced on your home screen',
                          onTap: _openWidgets,
                        ),
                      SettingsRow(
                        icon: Symbols.computer_rounded,
                        title: 'Echo on your computer',
                        value: settings.desktopEngineHost == null
                            ? 'Not paired'
                            : '${settings.desktopEngineName ?? settings.desktopEngineHost} '
                                  '· paired',
                        onTap: () => _route('/you/desktop'),
                      ),
                      SettingsRow(
                        icon: Symbols.wifi_find_rounded,
                        title: 'Use my computer',
                        value: settings.preferDesktopEngine
                            ? 'On · finds it on your Wi-Fi'
                            : 'Off',
                        onTap: () => _open(
                          'Use my computer',
                          const DesktopEngineSection(),
                        ),
                      ),
                      SettingsRow(
                        icon: Symbols.policy_rounded,
                        title: 'Privacy policy',
                        value: 'How your data is handled',
                        trailing: _externalIcon(context),
                        onTap: () => _openUrl(
                          'https://echo-mobileapp.vercel.app/privacy',
                        ),
                      ),
                      SettingsRow(
                        icon: Symbols.mail_rounded,
                        title: 'Contact the founder',
                        value: 'Questions or bug reports',
                        trailing: _externalIcon(context),
                        onTap: () => _openUrl(
                          'mailto:chandan1204@gmail.com?subject=Echo%20feedback',
                        ),
                      ),
                      SettingsRow(
                        icon: Symbols.info_rounded,
                        title: 'Version',
                        value: _version.isEmpty ? null : _version,
                        hideChevron: true,
                        onTap: null,
                      ),
                    ],
                  ),
                ),
                if (kDebugMode) ...[
                  enter(const SettingsGroupLabel('Developer · debug builds only')),
                  enter(
                    SettingsGroup(
                      rows: [
                        SettingsRow(
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
            );
          },
        ),
      ),
    );
  }

  Widget _externalIcon(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Icon(
      Symbols.open_in_new_rounded,
      size: 19,
      color: context.colors.textSecondary.withValues(alpha: 0.7),
    ),
  );

  Future<void> _openPack() => _open(
    'Writing pack',
    const WritingPackPage(),
    subtitle: writingPackIntro,
  );

  Future<void> _openCloud() => _open(
    'Cloud engine',
    const CloudEnginePage(),
    subtitle:
        'Off by default. When it’s on, only what a question or a draft needs '
        'is sent to Google’s Gemini, using your own key.',
  );

  static String? _quietWhen(QuietConfig? q) {
    if (q == null) return null;
    return q.enabled
        ? quietWhenLabel(q.days, q.startMin, q.endMin)
        : 'Off';
  }

  static String? _quietThrough(QuietConfig? q) {
    if (q == null) return null;
    final parts = [
      if (q.people) 'People who need you',
      if (q.calendar) 'calendar',
      if (q.deliveries) 'deliveries',
      if (q.through.isNotEmpty) '${q.through.length} always',
    ];
    return parts.isEmpty ? 'Nobody extra' : parts.join(', ');
  }

  static String _packValue(ModelDownloadState d, WritingPackStatus pack) {
    if (d.phase == ModelDownloadPhase.downloading) {
      return 'Downloading · ${(d.progress * 100).toInt()}%';
    }
    return pack.ready
        ? 'Ready · ${pack.size ?? offlineModelSizeLabel()} on this phone'
        : 'Optional · ${offlineModelSizeLabel()} download';
  }
}

/// "What Echo calls you": a field, and Save.
class _NameSheet extends StatefulWidget {
  final String current;
  const _NameSheet({required this.current});

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _field = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_field.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, insets + bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What should Echo call you?',
            style: GoogleFonts.oldStandardTt(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _field,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: GoogleFonts.nunito(fontSize: 18, color: c.textPrimary),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Your name',
              hintStyle: GoogleFonts.nunito(color: c.textSecondary),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          EchoButton(text: 'Save', onPressed: _save),
        ],
      ),
    );
  }
}

/// The analytics switch, kept right on the hub.
class _AnalyticsCard extends StatefulWidget {
  const _AnalyticsCard();

  @override
  State<_AnalyticsCard> createState() => _AnalyticsCardState();
}

class _AnalyticsCardState extends State<_AnalyticsCard> {
  late bool _on = Analytics.isEnabled;

  Future<void> _set(bool on) async {
    await Analytics.setEnabled(on);
    if (mounted) setState(() => _on = on);
  }

  @override
  Widget build(BuildContext context) => SettingsGroup(
    rows: [
      SettingsSwitchRow(
        icon: Symbols.analytics_rounded,
        title: 'Share anonymous usage data',
        value:
            'Helps improve Echo. Counts which features are used — never your '
            'notifications, messages, or briefings. No account, no personal '
            'data.',
        tall: true,
        on: _on,
        onChanged: _set,
      ),
    ],
  );
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
