import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/onboarding/data/first_look.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:project_echo/features/widgets/presentation/widgets/widget_previews.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The seven mornings the streak goal counts, from the first briefing on:
/// tomorrow's, or today's when the briefing time is still ahead.
List<DateTime> goalWeek(DateTime now, String briefingTime) {
  final parts = briefingTime.split(':');
  final h = int.tryParse(parts.first) ?? 7;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final first = DateTime(now.year, now.month, now.day, h, m).isAfter(now)
      ? DateTime(now.year, now.month, now.day)
      : DateTime(now.year, now.month, now.day + 1);
  return [
    for (var i = 0; i < 7; i++)
      DateTime(first.year, first.month, first.day + i),
  ];
}

/// The end of the phone's onboarding: the week ahead as a streak tracker,
/// with a small goal ([streakGoalMornings] of the first seven mornings), and
/// the Briefing widget offered for the home screen, where the launcher can
/// add one (elsewhere the offer isn't shown).
class StreakGoalScreen extends StatefulWidget {
  const StreakGoalScreen({super.key});

  @override
  State<StreakGoalScreen> createState() => _StreakGoalScreenState();
}

class _StreakGoalScreenState extends State<StreakGoalScreen> {
  List<DateTime> _week = goalWeek(DateTime.now(), '07:00');
  String _briefingTime = '07:00';
  Set<String> _heard = const {};
  HomeWidgetsState? _widgets;

  /// The Briefing widgets on the home screen before asking to add one, while
  /// Android's confirmation is up.
  int? _placedBefore;
  bool _added = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final times = prefs.getStringList('briefing_times');
    final time = times == null || times.isEmpty ? '07:00' : times.first;
    final heard = await StreakService().heardDates();
    final widgets = await HomeWidgetsService.state();
    if (!mounted) return;
    setState(() {
      _briefingTime = time;
      _week = goalWeek(DateTime.now(), time);
      _heard = heard;
      _widgets = widgets;
    });
    if (widgets?.canPin ?? false) Analytics.track('onboarding_widget_offered');
  }

  Future<void> _addWidget() async {
    HapticFeedback.lightImpact();
    _placedBefore = _widgets?.placedCount('brief') ?? 0;
    final asked = await HomeWidgetsService.pin('brief');
    if (asked) Analytics.track('onboarding_widget_requested');
    if (!asked) _placedBefore = null;
  }

  /// Back from Android's confirmation: did the widget land? The launcher can
  /// take a moment, so look a few times.
  Future<void> _onResume() async {
    final before = _placedBefore;
    if (before == null) return;
    for (var attempt = 0; attempt < 6; attempt++) {
      final s = await HomeWidgetsService.state();
      if (!mounted) return;
      if (s != null && s.placedCount('brief') > before) {
        HapticFeedback.mediumImpact();
        setState(() {
          _widgets = s;
          _added = true;
          _placedBefore = null;
        });
        Analytics.track('onboarding_widget_added');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _placedBefore = null;
  }

  String get _firstBriefing {
    final parts = _briefingTime.split(':');
    final at = DateTime(
      2000,
      1,
      1,
      int.tryParse(parts.first) ?? 7,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final today = _week.first.day == DateTime.now().day;
    return '${today ? 'today' : 'tomorrow'} at ${spokenClock(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnBoardingCubit>();
    final canPin = _widgets?.canPin ?? false;

    return OnboardingStepBody(
      title: 'Three mornings this week.',
      subtitle:
          'Your first full briefing is ready $_firstBriefing. Hear any '
          '$streakGoalMornings of your first seven mornings, and it starts '
          'to stick.',
      footer: EchoButton(
        text: 'I’m in',
        showArrow: true,
        onPressed: () {
          HapticFeedback.mediumImpact(); // milestone: setup complete
          cubit.finishOnboarding();
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeekTracker(week: _week, heard: _heard),
          if (canPin) ...[
            const SizedBox(height: 16),
            _WidgetOffer(widgets: _widgets, added: _added, onAdd: _addWidget),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The first seven mornings as a row of days, the goal's progress above.
class _WeekTracker extends StatelessWidget {
  final List<DateTime> week;
  final Set<String> heard;

  const _WeekTracker({required this.week, required this.heard});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final streak = StreakService();
    final done = week.where((d) => heard.contains(streak.dateKeyFor(d))).length;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const EchoMascot(
                state: EchoState.happy,
                size: 48,
                showRings: false,
                glow: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$done of $streakGoalMornings mornings',
                      style: GoogleFonts.oldStandardTt(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Your first week with Echo',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 0,
                end: (done / streakGoalMornings).clamp(0.0, 1.0),
              ),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.slow,
              curve: AppMotion.emphasized,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                color: colors.primaryGreen,
                backgroundColor: colors.dividerColor,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final (i, day) in week.indexed)
                Expanded(
                  child: Semantics(
                    label:
                        '${names[day.weekday - 1]}, '
                        '${heard.contains(streak.dateKeyFor(day))
                            ? 'heard'
                            : i == 0
                            ? 'first briefing'
                            : 'ahead'}',
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(
                          letters[day.weekday - 1],
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _Day(
                          heard: heard.contains(streak.dateKeyFor(day)),
                          next: i == 0,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  final bool heard;
  final bool next;

  const _Day({required this.heard, required this.next});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: heard
            ? colors.primaryGreen
            : next
            ? Colors.transparent
            : colors.dividerColor,
        border: next && !heard
            ? Border.all(color: colors.primaryGreen, width: 2.4)
            : null,
      ),
      child: heard
          ? Icon(Symbols.check_rounded, size: 18, color: colors.textInverse)
          : null,
    );
  }
}

/// The Briefing widget, offered for the home screen.
class _WidgetOffer extends StatelessWidget {
  final HomeWidgetsState? widgets;
  final bool added;
  final VoidCallback onAdd;

  const _WidgetOffer({
    required this.widgets,
    required this.added,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep the week in sight',
            style: GoogleFonts.oldStandardTt(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The Briefing widget shows your streak and plays the morning’s '
            'briefing in one tap.',
            style: GoogleFonts.nunito(
              fontSize: 14,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          ExcludeSemantics(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: BriefingWidgetPreview(data: widgets),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: added
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.check_circle_rounded,
                          size: 20,
                          fill: 1,
                          color: colors.primaryGreen,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'On your home screen',
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colors.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  )
                : TextButton.icon(
                    onPressed: onAdd,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: colors.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Symbols.add_rounded, size: 20),
                    label: Text(
                      'Add to home screen',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
