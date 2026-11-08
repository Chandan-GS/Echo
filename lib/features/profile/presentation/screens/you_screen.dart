import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/header_icon_button.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/profile/presentation/screens/profile_screen.dart';
import 'package:project_echo/features/profile/presentation/widgets/share_week_sheet.dart';
import 'package:project_echo/features/profile/presentation/widgets/streak_calendar.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:project_echo/features/vault/presentation/widgets/source_icon.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "1,284".
String _number(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// What Echo heard this week, in one line for the You tab.
class HearsSummary {
  final int apps;
  final int signals;

  /// Busiest first.
  final List<String> top;

  const HearsSummary({
    required this.apps,
    required this.signals,
    required this.top,
  });

  /// Adds up [week], leaving out [excluded] apps. Pure, for tests.
  factory HearsSummary.of(List<DayStats> week, Set<String> excluded) {
    final totals = <String, int>{};
    for (final day in week) {
      day.apps.forEach((app, n) {
        if (!excluded.contains(app)) totals[app] = (totals[app] ?? 0) + n;
      });
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return HearsSummary(
      apps: totals.length,
      signals: totals.values.fold(0, (a, n) => a + n),
      top: [for (final e in sorted.take(4)) e.key],
    );
  }

  String get title =>
      '$apps ${apps == 1 ? 'app' : 'apps'} · ${_number(signals)} '
      '${signals == 1 ? 'signal' : 'signals'} this week';

  /// "Work, Friends and Groups are the busiest".
  String get busiest {
    final names = top.take(3).map(appLabel).toList();
    if (names.isEmpty) return '';
    if (names.length == 1) return '${names.first} is the busiest';
    final head = names.sublist(0, names.length - 1).join(', ');
    return '$head and ${names.last} are the busiest';
  }
}

/// The You tab: the owner, their streak, their week with people, what Echo
/// hears, and the way to widgets, the computer and settings.
class YouScreen extends StatefulWidget {
  const YouScreen({super.key});

  @override
  State<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends State<YouScreen> with WidgetsBindingObserver {
  final _calendarKey = GlobalKey<StreakCalendarState>();
  String _name = '';
  DateTime? _since;
  WeekStats? _week;
  HearsSummary? _hears;
  int? _widgetsPlaced;
  String? _computer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TodoStore.changed.addListener(_loadWeek);
    StreakService.changed.addListener(_reloadStreak);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TodoStore.changed.removeListener(_loadWeek);
    StreakService.changed.removeListener(_reloadStreak);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  void _reloadStreak() => _calendarKey.currentState?.reload();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!mounted) return;
    final host = prefs.getString('desktop_engine_host');
    setState(() {
      _name = prefs.getString('user_name')?.trim() ?? '';
      _since = DateTime.tryParse(prefs.getString('first_launch_date') ?? '');
      _computer = host == null
          ? null
          : prefs.getString('desktop_engine_name') ?? 'Your computer';
    });
    _reloadStreak();
    unawaited(_loadWeek());
    unawaited(_loadHears());
    unawaited(_loadWidgets());
  }

  Future<void> _loadWeek() async {
    try {
      final week = await WeekStats.load(DateTime.now());
      if (mounted) setState(() => _week = week);
    } catch (e) {
      debugPrint('Loading the week failed: $e');
    }
  }

  Future<void> _loadHears() async {
    try {
      final week = await DailyStats.week(DateTime.now());
      final excluded = await loadExcludedSources();
      if (mounted) setState(() => _hears = HearsSummary.of(week, excluded));
    } catch (e) {
      debugPrint('Loading what Echo hears failed: $e');
    }
  }

  Future<void> _loadWidgets() async {
    if (!HomeWidgetsService.supported) return;
    try {
      final state = await HomeWidgetsService.state();
      if (mounted) setState(() => _widgetsPlaced = state?.totalPlaced);
    } catch (_) {}
  }

  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) _load();
  }

  Future<void> _rename() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _RenameSheet(name: _name),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _name || !mounted) return;
    setState(() => _name = trimmed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', trimmed);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          // Above the nav dock, which the tab's bottom padding clears.
          margin: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.paddingOf(context).bottom,
          ),
          content: Text('Echo will call you $trimmed'),
        ),
      );
  }

  Future<void> _share(WeekStats week, String range) async {
    final streak = await StreakService().current();
    if (!mounted) return;
    await showShareWeekSheet(
      context,
      week: week,
      streak: streak.current,
      range: range,
    );
  }

  static Future<void> _launch(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Opening $url failed: $e');
    }
  }

  static String _date(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final since = _since;
    final week = _week;
    final now = DateTime.now();
    final from = week?.from ?? DateTime(now.year, now.month, now.day - 6);
    final range =
        '${from.day} ${_months[from.month - 1]} – '
        '${now.day} ${_months[now.month - 1]}';
    final placed = _widgetsPlaced ?? 0;
    var n = 0;
    Widget enter(Widget child) =>
        FadeSlideIn(delay: AppMotion.staggerDelay(n++), child: child);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          // Clears the nav dock (MainScaffold sets the bottom padding).
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              enter(
                Row(
                  children: [
                    Expanded(
                      child: _NameButton(
                        name: _name.isEmpty ? 'You' : _name,
                        onTap: _rename,
                      ),
                    ),
                    HeaderIconButton(
                      icon: Symbols.settings_rounded,
                      label: 'Settings',
                      onTap: () => _open('/settings'),
                    ),
                  ],
                ),
              ),
              if (since != null)
                enter(
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'With Echo since ${_date(since)}',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              enter(
                StreakCalendar(
                  key: _calendarKey,
                  onOpen: () => _open('/you/streak'),
                ),
              ),
              enter(_Heading('This week', note: range)),
              enter(_tiles(week)),
              if (week != null && week.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Reply through Echo or tick off a to-do and this fills in.',
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      height: 1.4,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              enter(
                WeekBarChart(
                  title: 'People you got back to',
                  byDay: week?.answeredByDay ?? List.filled(7, 0),
                  from: from,
                ),
              ),
              const SizedBox(height: 12),
              enter(
                _OutlineButton(
                  label: 'Share your week',
                  icon: Symbols.ios_share_rounded,
                  onTap: week == null ? null : () => _share(week, range),
                ),
              ),
              enter(const _Heading('What Echo hears')),
              enter(_hearsCard()),
              const SizedBox(height: 12),
              enter(
                _RowCard(
                  rows: [
                    _RowData(
                      icon: Symbols.widgets_rounded,
                      title: 'Widgets',
                      value: placed > 0
                          ? '$placed on your home screen'
                          : 'None on your home screen yet',
                      onTap: () => _open('/you/widgets'),
                    ),
                    _RowData(
                      icon: Symbols.computer_rounded,
                      title: 'Echo on your computer',
                      value: _computer == null
                          ? 'Not paired'
                          : '$_computer · paired',
                      onTap: () => _open('/you/desktop'),
                    ),
                    _RowData(
                      icon: Symbols.settings_rounded,
                      title: 'Settings',
                      value: 'Voice, quiet hours, history',
                      onTap: () => _open('/settings'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              enter(
                _RowCard(
                  rows: [
                    _RowData(
                      icon: Symbols.policy_rounded,
                      title: 'Privacy policy',
                      value: 'How your data is handled',
                      external: true,
                      onTap: () =>
                          _launch('https://echo-mobileapp.vercel.app/privacy'),
                    ),
                    _RowData(
                      icon: Symbols.mail_rounded,
                      title: 'Contact the founder',
                      value: 'Questions or bug reports',
                      external: true,
                      onTap: () => _launch(
                        'mailto:chandan1204@gmail.com?subject=Echo%20feedback',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tiles(WeekStats? w) => Column(
    children: [
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Tile(
                value: w?.peopleAnswered,
                label: 'people you got back to within a day',
                accent: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(
                value: w?.todosDone,
                of: w?.todosDue,
                label: 'to-dos done',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Tile(value: w?.read, label: 'messages read for you'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(value: w?.held, label: 'held during quiet hours'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _hearsCard() {
    final c = context.colors;
    final h = _hears;
    final heard = h != null && h.signals > 0;
    return PressFeedback(
      scale: 0.98,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.dividerColor.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open('/you/hears'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                if (heard) ...[
                  _IconStack(sources: h.top),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heard ? h.title : 'Nothing heard yet',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        heard
                            ? h.busiest
                            : 'Fills in as notifications arrive. Tap to '
                                  'choose which apps Echo reads.',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          height: 1.3,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Symbols.chevron_right_rounded,
                  size: 22,
                  color: c.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The owner's name, large; a tap renames.
class _NameButton extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  const _NameButton({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.97,
      child: Semantics(
        button: true,
        label: 'Edit your name',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Symbols.edit_rounded, size: 20, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameSheet extends StatefulWidget {
  final String name;
  const _RenameSheet({required this.name});

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _controller = TextEditingController(
    text: widget.name,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom +
            20,
      ),
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
          const SizedBox(height: 4),
          Text(
            'It’s how Echo greets you, and nothing else.',
            style: GoogleFonts.nunito(fontSize: 14.5, color: c.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            cursorColor: c.primaryGreen,
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              filled: false,
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.dividerColor),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.primaryGreen, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _OutlineButton(label: 'Save', filled: true, onTap: _save),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String title;
  final String? note;
  const _Heading(this.title, {this.note});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.oldStandardTt(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: GoogleFonts.nunito(fontSize: 14, color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final int? value;
  final int? of;
  final String label;
  final bool accent;
  const _Tile({
    required this.value,
    required this.label,
    this.of,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final of = this.of;
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 13),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: (value ?? 0).toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: AppMotion.emphasized,
            builder: (context, v, _) => Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value == null ? '–' : _number(v.round())),
                  if (value != null && of != null && of > 0)
                    TextSpan(
                      text: ' of $of',
                      style: TextStyle(fontSize: 17, color: c.textSecondary),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.05,
                color: accent ? c.primaryGreen : c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final VoidCallback? onTap;
  const _OutlineButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = filled ? c.textInverse : c.textPrimary;
    return PressFeedback(
      scale: 0.98,
      enabled: onTap != null,
      child: Material(
        color: filled ? c.buttonDark : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: filled ? BorderSide.none : BorderSide(color: c.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to four app icons, overlapping.
class _IconStack extends StatelessWidget {
  final List<String> sources;
  const _IconStack({required this.sources});

  static const _size = 30.0;
  static const _step = 20.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = sources.take(4).toList();
    return SizedBox(
      width: _size + _step * (shown.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (final (i, source) in shown.indexed)
            Positioned(
              left: i * _step,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: SourceIcon(
                    source: source,
                    size: _size,
                    fallback: Icon(
                      Symbols.notifications_rounded,
                      size: 16,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RowData {
  final IconData icon;
  final String title;
  final String value;
  final bool external;
  final VoidCallback onTap;
  const _RowData({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.external = false,
  });
}

class _RowCard extends StatelessWidget {
  final List<_RowData> rows;
  const _RowCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 54,
                color: c.dividerColor.withValues(alpha: 0.6),
              ),
            InkWell(
              onTap: row.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
                child: Row(
                  children: [
                    Icon(row.icon, size: 22, color: c.textPrimary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title,
                            style: GoogleFonts.nunito(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            row.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      row.external
                          ? Symbols.open_in_new_rounded
                          : Symbols.chevron_right_rounded,
                      size: row.external ? 19 : 22,
                      color: c.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
