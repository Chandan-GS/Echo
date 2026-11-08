import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/presentation/widgets/echo_segmented.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/history/presentation/widgets/history_parts.dart';
import 'package:project_echo/features/quiet/data/quiet_held.dart';
import 'package:project_echo/features/quiet/data/quiet_native.dart';
import 'package:project_echo/features/quiet/data/quiet_settings.dart';
import 'package:project_echo/features/quiet/presentation/widgets/quiet_parts.dart';
import 'package:project_echo/features/quiet/presentation/widgets/quiet_people_sheet.dart';
import 'package:project_echo/features/settings/presentation/widgets/settings_kit.dart';

/// Quiet hours: the window, who gets through, and what's being held.
class QuietScreen extends StatefulWidget {
  const QuietScreen({super.key});

  @override
  State<QuietScreen> createState() => _QuietScreenState();
}

class _QuietScreenState extends State<QuietScreen> with WidgetsBindingObserver {
  /// Apps shown as their own stack; the rest share one.
  static const _ownStacks = 4;

  QuietConfig _config = const QuietConfig();
  QuietStatus _status = QuietStatus.none;
  List<RawData> _held = const [];
  bool _loaded = false;
  bool _flying = false;
  bool _bump = false;

  final _now = ValueNotifier<DateTime>(DateTime.now());
  Timer? _tick;
  Timer? _reload;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _watch();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _reload?.cancel();
    _changes?.cancel();
    _now.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  /// A new message held, or a window opening or closing, shows up here.
  void _onTick() {
    final before = _config.activeWindow(_now.value)?.end;
    _now.value = DateTime.now();
    if (_config.activeWindow(_now.value)?.end != before) _load();
  }

  Future<void> _watch() async {
    try {
      final isar = await IsarDataSource.instance;
      if (!mounted) return;
      _changes = isar.rawDatas.watchLazy().listen((_) {
        _reload?.cancel();
        _reload = Timer(const Duration(milliseconds: 500), _load);
      });
    } catch (e) {
      debugPrint('Quiet hours could not watch for changes: $e');
    }
  }

  Future<void> _load() async {
    final config = await QuietSettings.load();
    final status = await QuietNative.status();
    final session = status.session;
    final held = session == null
        ? const <RawData>[]
        : await QuietHeld.since(session.since);
    if (!mounted) return;
    setState(() {
      _config = config;
      _status = status;
      _held = held;
      _loaded = true;
    });
  }

  int get _mode => !_config.enabled ? 0 : (_config.custom ? 2 : 1);

  void _toast(String message) => settingsToast(context, message);

  Future<void> _apply(QuietConfig next) async {
    setState(() => _config = next);
    await QuietSettings.save(next);
    await _load();
  }

  Future<void> _setMode(int mode) async {
    final heldCount = _held.length;
    switch (mode) {
      case 0:
        await _apply(_config.copyWith(enabled: false));
        if (heldCount > 0) {
          _toast('Quiet hours off. Your $heldCount held notifications are coming back.');
        }
      case 1:
        await _apply(
          _config.copyWith(
            enabled: true,
            custom: false,
            startMin: QuietConfig.presetStart,
            endMin: QuietConfig.presetEnd,
          ),
        );
      case _:
        await _apply(_config.copyWith(enabled: true, custom: true));
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _config.startMin : _config.endMin;
    final picked = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _TimeSheet(start: start, current: current),
    );
    if (picked == null || !mounted) return;
    final other = start ? _config.endMin : _config.startMin;
    if (picked == other) {
      _toast('Quiet hours need a start and an end that differ');
      return;
    }
    await _apply(
      start
          ? _config.copyWith(startMin: picked)
          : _config.copyWith(endMin: picked),
    );
    _toast('${start ? 'Starts' : 'Ends'} at ${quietClockOf(picked)}');
  }

  void _toggleDay(int day) {
    final days = {..._config.days};
    if (days.contains(day)) {
      if (days.length == 1) {
        _toast('Quiet hours need at least one day');
        return;
      }
      days.remove(day);
    } else {
      days.add(day);
    }
    _apply(_config.copyWith(days: days));
  }

  Future<void> _pickPeople() async {
    final chosen = await showQuietPeopleSheet(context, _config.through);
    if (chosen != null && mounted) {
      await _apply(_config.copyWith(through: chosen));
    }
  }

  Future<void> _deliver() async {
    if (_flying || _held.isEmpty) return;
    setState(() => _flying = true);
    await Future<void>.delayed(const Duration(milliseconds: 520));
    final asked = await QuietNative.deliverNow();
    await _load();
    if (!mounted) return;
    setState(() {
      _flying = false;
      _bump = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _bump = false);
    });
    if (asked < 0) {
      final end = _status.session?.end ?? _config.activeWindow(DateTime.now())?.end;
      _toast(
        end == null
            ? "Echo isn't connected right now. They'll come back on their own."
            : "Echo isn't connected right now. They'll come back at ${quietClock(end)} on their own.",
      );
    } else {
      _toast('Delivering $asked ${asked == 1 ? 'notification' : 'notifications'} to your shade.');
    }
  }

  Future<void> _clearDigest() async {
    await QuietNative.clearDigest();
    _toast("Cleared. They're all still in History.");
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 28;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const EchoAppBar(title: 'Quiet hours'),
      body: !_loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: EdgeInsets.fromLTRB(24, 4, 24, bottom),
              children: [
                _hero(context),
                const SizedBox(height: 20),
                FadeSlideIn(
                  delay: AppMotion.stagger,
                  child: EchoSegmented(
                    labels: [
                      'Off',
                      '${quietClockOf(QuietConfig.presetStart)}–${quietClockOf(QuietConfig.presetEnd)}',
                      'Custom',
                    ],
                    selected: _mode,
                    onSelect: _setMode,
                  ),
                ),
                AnimatedSize(
                  duration: AppMotion.medium,
                  curve: AppMotion.emphasized,
                  alignment: Alignment.topCenter,
                  child: _mode == 2
                      ? _custom(context)
                      : const SizedBox(width: double.infinity),
                ),
                if (_status.blocked || (!_status.listening && _config.enabled))
                  _warning(context),
                _section(context, 'Getting through', 'everything else waits'),
                FadeSlideIn(
                  delay: AppMotion.stagger * 2,
                  child: _gettingThrough(context),
                ),
                ..._heldSection(context),
                ..._digestSection(context),
                _footer(context),
              ],
            ),
    );
  }

  Widget _hero(BuildContext context) {
    final c = context.colors;
    return FadeSlideIn(
      child: ValueListenableBuilder<DateTime>(
        valueListenable: _now,
        builder: (context, now, _) {
          final window = _config.activeWindow(now);
          final next = _config.nextWindow(now);
          final String label;
          final String caption;
          final String state;
          final Widget sub;
          final double progress;
          if (!_config.enabled) {
            label = 'Off';
            caption = 'not holding';
            state = 'Quiet hours are off';
            progress = 0;
            sub = _subText(
              context,
              'Every notification reaches you as it comes. Pick a time to hold the ones that aren’t for you.',
            );
          } else if (window != null) {
            final total = window.end.difference(window.start).inSeconds;
            final left = window.end.difference(now);
            label = quietCountdown(left);
            caption = 'left';
            state = 'On until ${quietClock(window.end)}';
            progress = total <= 0 ? 0 : left.inSeconds / total;
            sub = _heldSub(context);
          } else {
            label = next == null ? 'Off' : quietClock(next.start);
            caption = next == null ? 'no days set' : _nextDayLabel(next, now);
            state = next == null
                ? 'No days chosen'
                : 'Starts at ${quietClock(next.start)}';
            progress = 0;
            sub = _subText(
              context,
              next == null
                  ? 'Pick at least one day for quiet hours.'
                  : 'Echo will hold what isn’t for you until ${quietClock(next.end)}.',
            );
          }
          return Column(
            children: [
              const SizedBox(height: 4),
              QuietRing(
                progress: progress,
                label: label,
                caption: caption,
                asleep: _config.enabled,
              ),
              const SizedBox(height: 16),
              Text(
                state,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontSize: 30,
                  height: 1.15,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: sub,
              ),
            ],
          );
        },
      ),
    );
  }

  String _nextDayLabel(QuietWindow next, DateTime now) {
    final day = DateTime(next.start.year, next.start.month, next.start.day);
    return historyDayLabel(day, now).toLowerCase();
  }

  Widget _subText(BuildContext context, String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: GoogleFonts.nunito(
      fontSize: 14.5,
      height: 1.45,
      color: context.colors.textSecondary,
    ),
  );

  Widget _heldSub(BuildContext context) {
    final c = context.colors;
    if (_held.isEmpty) {
      return _subText(
        context,
        'Nothing held right now. Anything that isn’t for you will wait.',
      );
    }
    final apps = QuietHeld.group(_held).length;
    return Text.rich(
      TextSpan(
        style: GoogleFonts.nunito(
          fontSize: 14.5,
          height: 1.45,
          color: c.textSecondary,
        ),
        children: [
          TextSpan(
            text: '${_held.length}',
            style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
          ),
          TextSpan(
            text:
                ' held so far from $apps ${apps == 1 ? 'app' : 'apps'}. They come back together as one notification.',
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _custom(BuildContext context) {
    final c = context.colors;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _timeChip(
                  context,
                  'Starts',
                  _config.startMin,
                  () => _pickTime(start: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _timeChip(
                  context,
                  'Ends',
                  _config.endMin,
                  () => _pickTime(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var d = 1; d <= 7; d++)
                Flexible(
                  child: Semantics(
                    button: true,
                    selected: _config.days.contains(d),
                    label: 'Day $d',
                    child: GestureDetector(
                      onTap: () => _toggleDay(d),
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _config.days.contains(d)
                              ? c.textPrimary
                              : c.surface,
                          border: Border.all(
                            color: _config.days.contains(d)
                                ? Colors.transparent
                                : c.dividerColor.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          letters[d - 1],
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _config.days.contains(d)
                                ? c.textInverse
                                : c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeChip(
    BuildContext context,
    String label,
    int minutes,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.97,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: c.dividerColor.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        quietClockOf(minutes),
                        style: GoogleFonts.nunito(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  Icon(Symbols.schedule_rounded, size: 18, color: c.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _warning(BuildContext context) {
    final c = context.colors;
    final blocked = _status.blocked;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.amberBackground,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Symbols.info_rounded, size: 20, color: context.warmAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                blocked
                    ? "This phone isn't letting Echo hold notifications right now, so they're arriving as usual. Nothing is lost, and Echo will try again next time."
                    : "Echo can't hear notifications right now, so nothing is being held. Anything already held still comes back on time.",
                style: GoogleFonts.nunito(
                  fontSize: 13.5,
                  height: 1.4,
                  color: context.warmAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String note) {
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
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 24,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            note,
            style: GoogleFonts.nunito(fontSize: 13, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _gettingThrough(BuildContext context) {
    final c = context.colors;
    final through = _status.session?.through ?? const <String>[];
    Widget toggle(bool on, ValueChanged<bool> onChanged) => Switch(
      value: on,
      activeTrackColor: c.primaryGreen,
      onChanged: onChanged,
    );
    return SettingsGroup(
      rows: [
        QuietRow(
          icon: Symbols.person_rounded,
          green: true,
          title: 'People who need you',
          value: 'Direct messages, mentions and replies to you',
          extra: through.isEmpty ? null : _throughStrip(context, through),
          onTap: () {
            final on = !_config.people;
            _apply(_config.copyWith(people: on));
            _toast(
              on
                  ? 'People who need you will get through'
                  : 'Everyone waits until the end, even people who need you',
            );
          },
          trailing: toggle(_config.people, (on) {
            _apply(_config.copyWith(people: on));
            _toast(
              on
                  ? 'People who need you will get through'
                  : 'Everyone waits until the end, even people who need you',
            );
          }),
        ),
        QuietRow(
          icon: Symbols.person_add_rounded,
          title: 'Always let through',
          value: _config.through.isEmpty
              ? 'Pick people who reach you no matter what'
              : _config.through.join(', '),
          onTap: _pickPeople,
          trailing: Icon(
            Symbols.chevron_right_rounded,
            size: 22,
            color: c.textSecondary.withValues(alpha: 0.7),
          ),
        ),
        QuietRow(
          icon: Symbols.event_rounded,
          title: 'Calendar reminders',
          value: 'Meetings still remind you on time',
          onTap: () => _apply(_config.copyWith(calendar: !_config.calendar)),
          trailing: toggle(
            _config.calendar,
            (on) => _apply(_config.copyWith(calendar: on)),
          ),
        ),
        QuietRow(
          icon: Symbols.local_shipping_rounded,
          title: 'Deliveries',
          value: 'Food and parcel updates. Off: they wait with the rest',
          onTap: () =>
              _apply(_config.copyWith(deliveries: !_config.deliveries)),
          trailing: toggle(
            _config.deliveries,
            (on) => _apply(_config.copyWith(deliveries: on)),
          ),
        ),
        const QuietRow(
          icon: Symbols.call_rounded,
          title: 'Calls and alarms',
          value: 'They ring through Android itself. Echo never touches them.',
          trailing: QuietLock(),
        ),
        const QuietRow(
          icon: Symbols.pin_rounded,
          title: 'Codes are never held',
          value:
              "Since Android 15, notifications with one-time codes reach Echo with the text hidden. Echo can't see what's inside, so it lets every one through.",
          trailing: QuietLock(),
        ),
      ],
    );
  }

  Widget _throughStrip(BuildContext context, List<String> through) {
    final c = context.colors;
    final shown = through.take(3).toList();
    return Row(
      children: [
        for (final (i, name) in shown.indexed)
          Align(
            widthFactor: i == 0 ? 1 : 0.7,
            child: PersonAvatar(name: name, size: 20),
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${through.length} got through: ${shown.join(', ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _heldSection(BuildContext context) {
    final c = context.colors;
    final groups = QuietHeld.group(_held);
    final apps = groups.length;
    final end = _config.activeWindow(DateTime.now())?.end;
    final note = _held.isEmpty
        ? 'nothing right now'
        : '${_held.length} from $apps ${apps == 1 ? 'app' : 'apps'}';
    return [
      _section(context, 'Held so far', note),
      if (_held.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.primaryGreen.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Symbols.check_circle_rounded,
                size: 22,
                fill: 1,
                color: c.primaryGreen,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  !_config.enabled
                      ? 'Nothing is held while quiet hours are off.'
                      : end == null
                      ? "Nothing held right now. When quiet hours start, anything that isn't for you waits."
                      : "Nothing held right now. Anything new that isn't for you waits until ${quietClock(end)}.",
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        )
      else ...[
        AnimatedSlide(
          offset: _flying ? const Offset(0, 0.4) : Offset.zero,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeInCubic,
          child: AnimatedOpacity(
            opacity: _flying ? 0 : 1,
            duration: const Duration(milliseconds: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in groups.take(_ownStacks))
                  HeldStack.forGroup(group),
                if (groups.length > _ownStacks)
                  _restStack(context, groups.skip(_ownStacks).toList()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        EchoButton(
          text: 'Deliver now',
          icon: Symbols.notifications_active_rounded,
          onPressed: _deliver,
        ),
      ],
    ];
  }

  Widget _restStack(BuildContext context, List<HeldGroup> rest) {
    final items = [for (final g in rest) ...g.items]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final names = rest.map((g) => g.source).take(5).join(', ');
    return HeldStack(
      title: '${rest.length} more apps',
      muted: true,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final g in rest.take(4))
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: HistoryAppIcon(source: g.source),
            ),
        ],
      ),
      count: items.length,
      who: names,
      preview: items.first.content,
      items: items,
    );
  }

  List<Widget> _digestSection(BuildContext context) {
    final session = _status.session;
    final last = _status.lastDigest;
    final closed = last?.closedAt;
    final justClosed =
        closed != null &&
        DateTime.now().difference(closed) < const Duration(minutes: 30);
    if (_held.isEmpty && session == null && !justClosed) return const [];

    final end = session?.end ?? _config.activeWindow(DateTime.now())?.end;
    final count = _held.isNotEmpty ? _held.length : (last?.count ?? 0);
    if (count == 0) return const [];
    final split = _held.isNotEmpty
        ? QuietHeld.split(_held)
        : HeldSplit(last!.groups, last.deliveries, last.other);
    final parts = [
      if (split.groups > 0) '${split.groups} group messages',
      if (split.deliveries > 0) '${split.deliveries} deliveries',
      if (split.other > 0) '${split.other} updates',
    ].join(', ');
    final pending = _held.isNotEmpty && end != null;
    return [
      _section(
        context,
        pending ? 'At ${quietClock(end)}' : 'Delivered just now',
        pending ? 'one notification' : 'in your notification shade',
      ),
      AnimatedScale(
        scale: _bump ? 1.03 : 1,
        duration: const Duration(milliseconds: 300),
        curve: AppMotion.spring,
        child: _DigestCard(
          when: pending ? quietClock(end) : 'now',
          title: 'While you were quiet: $count ${count == 1 ? 'notification' : 'notifications'}',
          body: 'Nothing else needs you. $parts.',
          onShowAll: () => context.push('/digest'),
          onClear: pending ? null : _clearDigest,
        ),
      ),
    ];
  }

  Widget _footer(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.history_rounded, size: 17, color: c.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => context.go('/history'),
              child: Text.rich(
                TextSpan(
                  text:
                      'Nothing is deleted. Everything held stays in History, marked “held”. ',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    height: 1.45,
                    color: c.textSecondary,
                  ),
                  children: [
                    TextSpan(
                      text: 'Open History',
                      style: TextStyle(
                        color: c.primaryGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DigestCard extends StatelessWidget {
  final String when;
  final String title;
  final String body;
  final VoidCallback onShowAll;
  final VoidCallback? onClear;

  const _DigestCard({
    required this.when,
    required this.title,
    required this.body,
    required this.onShowAll,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget action(String label, VoidCallback? onTap) => TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: c.primaryGreen,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(label),
    );
    return PressFeedback(
      scale: 0.985,
      haptic: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onShowAll,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const EchoMascot(
                    state: EchoState.idle,
                    size: 22,
                    showRings: false,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Echo',
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  Text(
                    ' · $when',
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.nunito(
                  fontSize: 15.5,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  height: 1.4,
                  color: c.textSecondary,
                ),
              ),
              Row(
                children: [
                  action('Show all', onShowAll),
                  if (onClear != null) action('Clear', onClear),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Starts or ends quiet hours at a common time, or any other.
class _TimeSheet extends StatelessWidget {
  final bool start;
  final int current;
  const _TimeSheet({required this.start, required this.current});

  static const _starts = [7 * 60, 8 * 60, 9 * 60, 10 * 60, 18 * 60, 22 * 60];
  static const _ends = [11 * 60, 12 * 60, 13 * 60, 14 * 60, 21 * 60, 7 * 60];

  Future<void> _other(BuildContext context) async {
    final navigator = Navigator.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked != null) navigator.pop(picked.hour * 60 + picked.minute);
  }

  IconData _icon(int minutes) {
    if (minutes >= 6 * 60 && minutes < 12 * 60) return Symbols.wb_sunny_rounded;
    if (minutes >= 18 * 60) return Symbols.dark_mode_rounded;
    return Symbols.schedule_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final options = start ? _starts : _ends;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              start ? 'Start quiet hours' : 'End quiet hours',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 4),
            Text(
              start
                  ? 'Echo starts holding what isn’t for you.'
                  : 'Everything held comes back as one notification.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            for (final minutes in options)
              _option(
                context,
                _icon(minutes),
                quietClockOf(minutes),
                minutes == current,
                () => Navigator.of(context).pop(minutes),
              ),
            _option(
              context,
              Symbols.more_time_rounded,
              options.contains(current)
                  ? 'Another time'
                  : 'Another time (${quietClockOf(current)})',
              !options.contains(current),
              () => _other(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context,
    IconData icon,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 21, color: c.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Icon(
                on
                    ? Symbols.radio_button_checked_rounded
                    : Symbols.radio_button_unchecked_rounded,
                size: 22,
                color: on ? c.primaryGreen : c.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
