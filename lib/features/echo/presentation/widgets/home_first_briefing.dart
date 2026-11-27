import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/gentle_nudges.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/utils/nudge_rules.dart';
import 'package:project_echo/core/utils/time_utils.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/widgets/scheduled_briefings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home on day one, before any briefing: when the first full one arrives
/// (its time changeable right here), and how much Echo has heard so far
/// today, counting up as notifications come in. Gone once a briefing has
/// been made or heard, so Home is never empty while the owner waits.
class FirstBriefingPanel extends StatefulWidget {
  /// Counts the messages saved since a time. Defaults to Isar; tests pass
  /// their own.
  final Future<int> Function(DateTime since)? countSince;

  /// Fires when new messages may have been saved. Defaults to Isar's.
  final Stream<void>? changes;

  /// The clock. Defaults to now.
  final DateTime Function()? clock;

  const FirstBriefingPanel({
    super.key,
    this.countSince,
    this.changes,
    this.clock,
  });

  @override
  State<FirstBriefingPanel> createState() => _FirstBriefingPanelState();
}

class _FirstBriefingPanelState extends State<FirstBriefingPanel>
    with WidgetsBindingObserver {
  /// Null until known, so it doesn't flash in for a returning owner.
  bool? _hadBriefing;
  int _heard = 0;
  StreamSubscription<void>? _watch;
  Timer? _recount;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    final changes = widget.changes;
    if (changes != null) {
      _watch = changes.listen((_) => _recountSoon());
    } else {
      IsarDataSource.instance
          .then((isar) {
            if (!mounted) return;
            _watch = isar.rawDatas.watchLazy().listen((_) => _recountSoon());
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.cancel();
    _recount?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  /// Several notifications often land together; count once.
  void _recountSoon() {
    _recount?.cancel();
    _recount = Timer(const Duration(milliseconds: 700), _load);
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final had = await GentleNudges.hasHadBriefing(prefs);
      final now = _now();
      final since = DateTime(now.year, now.month, now.day);
      final heard = had
          ? 0
          : await (widget.countSince ?? GentleNudges.heardSince)(since);
      if (!mounted) return;
      setState(() {
        _hadBriefing = had;
        _heard = heard;
      });
    } catch (_) {
      // Home stands without it.
    }
  }

  Future<void> _editTime(List<String> times, DateTime next) async {
    final settings = context.read<SettingsCubit>();
    final picked = await showBriefingTimePicker(
      context,
      initialTime: TimeOfDay(hour: next.hour, minute: next.minute),
    );
    if (picked == null || !mounted) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    // Replace the slot shown, keeping any others.
    final shown = times.firstWhere(
      (t) => parseBriefingTime(t) == BriefingTime(next.hour, next.minute),
      orElse: () => '',
    );
    await settings.setBriefingTimes(
      {
        for (final t in times)
          if (t != shown) t,
        value,
      }.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final times = context.select((SettingsCubit s) => s.state.briefingTimes);
    final now = _now();
    final next = nextBriefingAt(now, times);
    if (_hadBriefing != false || next == null) return const SizedBox.shrink();
    // Its own gap under the primary card, so nothing is left when hidden.
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FirstBriefingCard(
        when: briefingWhenLabel(next, now),
        heardToday: _heard,
        onEditTime: () => _editTime(times, next),
      ),
    );
  }
}

/// The card itself: "Your first full briefing arrives tomorrow at 7:00 AM",
/// the time a button that opens the briefing-time picker, and today's count.
class FirstBriefingCard extends StatelessWidget {
  /// "tomorrow at 7:00 AM" (see briefingWhenLabel).
  final String when;
  final int heardToday;
  final VoidCallback onEditTime;

  const FirstBriefingCard({
    super.key,
    required this.when,
    required this.heardToday,
    required this.onEditTime,
  });

  static String heardLine(int n) => switch (n) {
    <= 0 => 'Echo is listening. What comes in today goes into it.',
    1 => 'Echo has heard 1 message so far today.',
    _ => 'Echo has heard $n messages so far today.',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final still = MediaQuery.of(context).disableAnimations;
    final line = heardLine(heardToday);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(
              child: Icon(
                Symbols.wb_twilight_rounded,
                size: 20,
                color: c.primaryGreen,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your first full briefing arrives',
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _TimeButton(when: when, onTap: onEditTime),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    line,
                    key: ValueKey(line),
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      height: 1.35,
                      color: c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The briefing's time, as the Settings chip shows one, tappable to change.
class _TimeButton extends StatelessWidget {
  final String when;
  final VoidCallback onTap;
  const _TimeButton({required this.when, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'First briefing $when. Change time',
      excludeSemantics: true,
      child: PressFeedback(
        child: Material(
          color: c.lightGreenBackground,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              // A comfortable target even at small text sizes.
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        when,
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Symbols.edit_rounded, size: 18, color: c.textPrimary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
