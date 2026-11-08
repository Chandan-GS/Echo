import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/utils/time_utils.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/home_glance.dart';
import 'package:project_echo/features/settings/data/schedule_prefs.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
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

/// "Friday  7 November" and the small Quiet pill.
class TodayHeader extends StatelessWidget {
  final DateTime now;
  final bool quietOn;
  final VoidCallback onQuiet;

  const TodayHeader({
    super.key,
    required this.now,
    required this.quietOn,
    required this.onQuiet,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = quietOn ? context.onSelection : c.textPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _weekdays[now.weekday - 1],
                    style: GoogleFonts.oldStandardTt(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      height: 1,
                      color: c.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: '  ${now.day} ${_months[now.month - 1]}',
                    style: GoogleFonts.oldStandardTt(
                      fontSize: 17,
                      fontStyle: FontStyle.italic,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Quiet hours',
            child: PressFeedback(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onQuiet,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                  decoration: BoxDecoration(
                    color: quietOn ? context.selectionFill : c.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: quietOn
                          ? Colors.transparent
                          : c.dividerColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.bedtime_rounded,
                        size: 17,
                        fill: 1,
                        color: quietOn ? fg : c.primaryGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Quiet',
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                    ],
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

/// The swipeable top of Today: the briefing and evening wrap, the day in a
/// sentence, then what's next on a line. Each page keeps its own height.
class TodayGlance extends StatefulWidget {
  final DateTime now;
  final int waiting;
  final String? name;

  const TodayGlance({
    super.key,
    required this.now,
    required this.waiting,
    required this.name,
  });

  @override
  State<TodayGlance> createState() => _TodayGlanceState();
}

class _TodayGlanceState extends State<TodayGlance> {
  static const _pages = 3;

  int _page = 0;
  double _drag = 0;
  bool _dragging = false;
  final _heights = <double?>[null, null, null];

  /// A swipe further than this moves a page.
  static const _flick = 40.0;

  void _go(int page) => setState(() {
    _page = page.clamp(0, _pages - 1);
    _drag = 0;
    _dragging = false;
  });

  void _onHeight(int page, double h) {
    if (_heights[page] != h && mounted) setState(() => _heights[page] = h);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final height =
            _heights[_page] ??
            _heights.whereType<double>().fold<double>(
              120,
              (a, b) => a > b ? a : b,
            );
        return Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragUpdate: (d) =>
                  setState(() => _drag += d.delta.dx),
              onHorizontalDragEnd: (_) {
                final moved = _drag.abs() > _flick ? (_drag < 0 ? 1 : -1) : 0;
                _go(_page + moved);
              },
              onHorizontalDragCancel: () => _go(_page),
              child: ClipRect(
                child: AnimatedContainer(
                  duration: AppMotion.medium,
                  curve: Curves.easeOutCubic,
                  height: height,
                  width: w,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: w * _pages,
                    maxWidth: w * _pages,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: AnimatedContainer(
                      duration: _dragging
                          ? Duration.zero
                          : const Duration(milliseconds: 420),
                      curve: AppMotion.emphasized,
                      transform: Matrix4.translationValues(
                        -_page * w + _drag,
                        0,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < _pages; i++)
                            SizedBox(
                              width: w,
                              child: ExcludeSemantics(
                                excluding: i != _page,
                                child: IgnorePointer(
                                  ignoring: i != _page,
                                  child: _SizeReporter(
                                    onHeight: (h) => _onHeight(i, h),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      child: _pageAt(i),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Dots(count: _pages, current: _page, onTap: _go),
          ],
        );
      },
    );
  }

  Widget _pageAt(int i) => switch (i) {
    0 => BriefingPage(now: widget.now),
    1 => _GreetingPage(
      now: widget.now,
      name: widget.name,
      waiting: widget.waiting,
    ),
    _ => const DayLine(),
  };
}

/// Reports its child's laid-out height after the frame.
class _SizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _SizeReporter({required this.onHeight, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderSizeReporter extends RenderProxyBox {
  ValueChanged<double> onHeight;
  double? _last;
  _RenderSizeReporter(this.onHeight);

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int current;
  final ValueChanged<int> onTap;

  const _Dots({
    required this.count,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: i == current ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == current ? c.textPrimary : c.dividerColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Good morning, Chandan." then who's waiting and what's next.
class _GreetingPage extends StatelessWidget {
  final DateTime now;
  final String? name;
  final int waiting;

  const _GreetingPage({
    required this.now,
    required this.name,
    required this.waiting,
  });

  static const _counts = [
    '',
    'One person is',
    'Two people are',
    'Three people are',
    'Four people are',
  ];

  String get _greeting => switch (now.hour) {
    >= 5 && < 12 => 'Good morning',
    >= 12 && < 17 => 'Good afternoon',
    >= 17 && < 22 => 'Good evening',
    _ => 'Good night',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final who = waiting == 0
        ? 'Nobody is'
        : waiting < _counts.length
        ? _counts[waiting]
        : '$waiting people are';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: name == null || name!.isEmpty
                    ? _greeting
                    : '$_greeting, ',
              ),
              if (name != null && name!.isNotEmpty)
                TextSpan(
                  text: name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              const TextSpan(text: '.'),
            ],
          ),
          style: GoogleFonts.nunito(
            fontSize: 16,
            height: 1.4,
            color: c.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        BlocBuilder<TodoCubit, TodoState>(
          builder: (context, todo) {
            final minutes = now.hour * 60 + now.minute;
            final next =
                (todo.today.where((i) => !i.done).toList()
                      ..sort((a, b) => a.sort.compareTo(b.sort)))
                    .where((i) => i.time != null && i.sort >= minutes)
                    .firstOrNull;
            return Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$who waiting on you. '),
                  if (next == null)
                    const TextSpan(
                      text: 'Nothing with a time left on your list.',
                    )
                  else ...[
                    TextSpan(text: 'Next on your list is ${next.title}, by '),
                    TextSpan(
                      text: _startTime(next.time!),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: c.primaryGreen,
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ],
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 16,
                height: 1.45,
                color: c.textPrimary,
              ),
            );
          },
        ),
      ],
    );
  }

  /// "8:00 PM" → "8 PM"; "4 PM to 6 PM" → "4 PM".
  static String _startTime(String time) =>
      time.split(' to ').first.replaceFirst(':00 ', ' ');
}

/// The dark briefing card, and the evening wrap's line under it.
class BriefingPage extends StatefulWidget {
  final DateTime now;
  const BriefingPage({super.key, required this.now});

  @override
  State<BriefingPage> createState() => _BriefingPageState();
}

class _BriefingPageState extends State<BriefingPage> {
  DateTime? _madeAt;
  List<BriefingTime> _times = const [];

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(covariant BriefingPage old) {
    super.didUpdateWidget(old);
    if (old.now.day != widget.now.day) _read();
  }

  Future<void> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_briefing_time');
    final times = [
      for (final t in prefs.getStringList('briefing_times') ?? const ['07:00'])
        ?parseBriefingTime(t),
    ]..sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
    if (mounted) {
      setState(() {
        _madeAt = raw == null ? null : DateTime.tryParse(raw);
        _times = times;
      });
    }
  }

  static String _length(String tts) {
    final words = tts.trim().split(RegExp(r'\s+')).length;
    final seconds = (words / 2.5).round();
    if (seconds < 60) return '$seconds s';
    final m = seconds ~/ 60, s = seconds % 60;
    return s == 0 ? '$m min' : '$m min $s s';
  }

  static String _clock(int minutesOfDay) {
    final hour = minutesOfDay ~/ 60, minute = minutesOfDay % 60;
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute == 0 ? '' : ':${minute.toString().padLeft(2, '0')}';
    return '$h$m ${hour < 12 ? 'AM' : 'PM'}';
  }

  static String _untilWords(int minutes) {
    if (minutes < 60) return 'in $minutes min';
    final m = minutes % 60;
    return 'in ${minutes ~/ 60} h${m == 0 ? '' : ' $m min'}';
  }

  /// The evening wrap while it's still ahead, otherwise the next briefing.
  (IconData, String)? _wrapLine(SettingsState settings) {
    final nowMinutes = widget.now.hour * 60 + widget.now.minute;
    final wrap = settings.eveningWrapEnabled
        ? parseBriefingTime(eveningWrapTimeOrDefault(settings.eveningWrapTime))
        : null;
    if (wrap != null && wrap.minutesOfDay > nowMinutes) {
      return (
        Symbols.nights_stay_rounded,
        'Evening wrap at ${_clock(wrap.minutesOfDay)}, '
            '${_untilWords(wrap.minutesOfDay - nowMinutes)}',
      );
    }
    if (!settings.briefingEnabled || _times.isEmpty) return null;
    final next = _times.where((t) => t.minutesOfDay > nowMinutes).firstOrNull;
    if (next != null) {
      return (
        Symbols.schedule_rounded,
        'Next briefing at ${_clock(next.minutesOfDay)}, ${_untilWords(next.minutesOfDay - nowMinutes)}',
      );
    }
    return (
      Symbols.schedule_rounded,
      'Next briefing tomorrow at ${_clock(_times.first.minutesOfDay)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<BriefingCubit, BriefingState>(
      builder: (context, state) {
        final writing = state is BriefingGenerating;
        final wrap = _wrapLine(context.watch<SettingsCubit>().state);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            if (state is BriefingError && state.limitReached)
              _LimitCard(message: state.message)
            else
              _card(context, state, writing),
            if (wrap != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
                child: Row(
                  children: [
                    Icon(wrap.$1, size: 17, color: c.primaryGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        wrap.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, BriefingState state, bool writing) {
    final cubit = context.read<BriefingCubit>();
    void generate() {
      if (!writing) cubit.generateBriefing();
    }

    final String? tts = switch (state) {
      BriefingCached(:final ttsText) => ttsText,
      BriefingReady(:final ttsText) => ttsText,
      _ => null,
    };
    final made = _madeAt;
    final today = made != null && _sameDay(made, widget.now);
    final evening = today && made.hour >= 15;

    final (title, subtitle, onTap) = switch (state) {
      BriefingGenerating() => (
        'Writing your briefing…',
        'Echo will say when it’s ready',
        null,
      ),
      BriefingError(:final message) => ('Try again', message, generate),
      _ when tts != null => (
        evening ? 'This evening’s wrap' : 'This morning’s briefing',
        [
          _length(tts),
          if (today) 'made at ${_clock(made.hour * 60 + made.minute)}',
        ].join(', '),
        () => context.push('/briefing', extra: evening ? 'evening' : 'morning'),
      ),
      _ => (
        'Make today’s briefing',
        'Everything that’s come in, read to you',
        generate,
      ),
    };
    return _BriefCard(
      title: title,
      subtitle: subtitle,
      writing: writing,
      onTap: onTap,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// The inverted card: a round play button and two lines.
class _BriefCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool writing;
  final VoidCallback? onTap;

  const _BriefCard({
    required this.title,
    required this.subtitle,
    required this.writing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = c.background;
    return PressFeedback(
      scale: 0.98,
      enabled: onTap != null,
      child: Material(
        color: c.textPrimary,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                  child: writing
                      ? Padding(
                          padding: const EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: c.textPrimary,
                          ),
                        )
                      : Icon(
                          Symbols.play_arrow_rounded,
                          fill: 1,
                          size: 26,
                          color: c.textPrimary,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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

/// Gemini's daily limit stopped the briefing: say when it's back, and offer
/// the on-device engine when its model is already downloaded.
class _LimitCard extends StatefulWidget {
  final String message;
  const _LimitCard({required this.message});

  @override
  State<_LimitCard> createState() => _LimitCardState();
}

class _LimitCardState extends State<_LimitCard> {
  bool _onDeviceReady = false;

  @override
  void initState() {
    super.initState();
    createOfflineModelRepository().downloadedPathOrNull().then((path) {
      if (mounted && path != null) setState(() => _onDeviceReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget button(String label, VoidCallback onTap, {bool filled = true}) =>
        Material(
          color: filled ? c.textPrimary : Colors.transparent,
          shape: StadiumBorder(
            side: filled
                ? BorderSide.none
                : BorderSide(color: c.textPrimary.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: filled ? c.background : c.textPrimary,
                ),
              ),
            ),
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: c.amberBackground,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today’s briefing couldn’t be written',
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.message,
            style: GoogleFonts.nunito(
              fontSize: 14.5,
              height: 1.4,
              color: c.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_onDeviceReady)
                button('Use on-device AI', () async {
                  final briefing = context.read<BriefingCubit>();
                  await context.read<SettingsCubit>().setAiEngine(
                    isOffline: true,
                  );
                  briefing.generateBriefing();
                }),
              button(
                'OK',
                () => context.read<BriefingCubit>().goBack(),
                filled: !_onDeviceReady,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
