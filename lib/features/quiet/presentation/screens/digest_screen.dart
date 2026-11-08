import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/presentation/widgets/header_icon_button.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/history/presentation/widgets/history_parts.dart';
import 'package:project_echo/features/quiet/data/quiet_held.dart';
import 'package:project_echo/features/quiet/data/quiet_native.dart';
import 'package:project_echo/features/quiet/presentation/widgets/quiet_parts.dart';
import 'package:project_echo/features/settings/presentation/widgets/settings_kit.dart';

/// What the notification at the end of quiet hours opens: whether any of it
/// needs the owner, then everything that was held, by app.
class DigestScreen extends StatefulWidget {
  const DigestScreen({super.key});

  @override
  State<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends State<DigestScreen> {
  static const _ownCards = 4;

  QuietSession? _session;
  List<RawData> _rows = const [];
  bool _loaded = false;
  bool _cleared = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await QuietNative.status();
    final session = status.lastDigest;
    final rows = session == null
        ? const <RawData>[]
        : await QuietHeld.since(session.since, until: session.closedAt);
    if (!mounted) return;
    setState(() {
      _session = session;
      _rows = rows;
      _loaded = true;
    });
  }

  Future<void> _clearAll() async {
    await QuietNative.clearDigest();
    if (!mounted) return;
    setState(() => _cleared = true);
    settingsToast(context, "Cleared. They're all still in History.");
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom + 28;
    return Scaffold(
      backgroundColor: c.background,
      appBar: const EchoAppBar(title: ''),
      body: !_loaded
          ? const SizedBox.shrink()
          : _session == null || _rows.isEmpty
          ? _empty(context)
          : ListView(
              padding: EdgeInsets.fromLTRB(24, 4, 24, bottom),
              children: _content(context, _session!),
            ),
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EchoMascot(
              state: EchoState.idle,
              size: 84,
              showRings: false,
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing was held',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.displayMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 6),
            Text(
              _session == null
                  ? 'When quiet hours end, what they held shows up here.'
                  : "What was held has passed the time you keep things for.",
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 14,
                height: 1.45,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            EchoButton(
              text: 'Set quiet hours',
              icon: Symbols.bedtime_rounded,
              onPressed: () => context.pushReplacement('/quiet'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, QuietSession session) {
    final c = context.colors;
    final split = QuietHeld.split(_rows);
    final groups = QuietHeld.group(_rows);
    final parts = [
      ('group messages', split.groups, c.primaryGreen),
      ('deliveries', split.deliveries, context.warmAccent),
      ('updates', split.other, c.textPrimary.withValues(alpha: 0.3)),
    ].where((p) => p.$2 > 0).toList();
    return [
      Align(
        alignment: Alignment.centerRight,
        child: HeaderIconButton(
          icon: Symbols.auto_awesome_rounded,
          label: 'Ask Echo',
          onTap: () => context.push(
            '/echo/chat',
            extra: 'What did I miss while I was quiet?',
          ),
        ),
      ),
      FadeSlideIn(
        child: Text(
          _dateLine(session),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19),
        ),
      ),
      const SizedBox(height: 6),
      FadeSlideIn(
        delay: AppMotion.stagger,
        child: Text(
          'While you were quiet: ${_rows.length} ${_rows.length == 1 ? 'notification' : 'notifications'}',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            fontSize: 30,
            height: 1.15,
          ),
        ),
      ),
      const SizedBox(height: 18),
      FadeSlideIn(delay: AppMotion.stagger * 2, child: _ok(context, session)),
      if (session.restarted) ...[
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: AppMotion.stagger * 2,
          child: Text(
            "Your phone restarted while these were held, so Android can't put them back in your shade. Everything is here and in History.",
            style: GoogleFonts.nunito(
              fontSize: 13.5,
              height: 1.45,
              color: context.warmAccent,
            ),
          ),
        ),
      ],
      const SizedBox(height: 18),
      FadeSlideIn(
        delay: AppMotion.stagger * 3,
        child: _split(context, parts),
      ),
      for (final (i, group) in groups.take(_ownCards).indexed)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FadeSlideIn(
            delay: AppMotion.staggerDelay(4 + i),
            child: _AppCard(
              icon: HistoryAppIcon(source: group.source, size: 26),
              title: group.source,
              note: '${group.count} ${_kindOf(group)}',
              items: group.items,
            ),
          ),
        ),
      if (groups.length > _ownCards)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _restCard(groups.skip(_ownCards).toList()),
        ),
      const SizedBox(height: 22),
      if (!_cleared)
        EchoButton(
          text: 'Clear all ${_rows.length}',
          icon: Symbols.done_all_rounded,
          onPressed: _clearAll,
        ),
      const SizedBox(height: 10),
      PressFeedback(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.go('/history'),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Symbols.inbox_rounded, size: 20, color: c.textPrimary),
                const SizedBox(width: 8),
                Text(
                  'See them in History',
                  style: GoogleFonts.nunito(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  String _kindOf(HeldGroup group) {
    final s = QuietHeld.split(group.items);
    if (s.groups == s.total) return s.total == 1 ? 'group message' : 'group messages';
    if (s.deliveries == s.total) return s.total == 1 ? 'delivery' : 'deliveries';
    return s.total == 1 ? 'update' : 'updates';
  }

  Widget _restCard(List<HeldGroup> rest) {
    final items = [for (final g in rest) ...g.items]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _AppCard(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final g in rest.take(4))
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: HistoryAppIcon(source: g.source, size: 20),
            ),
        ],
      ),
      title: '${items.length} more',
      note: 'offers and updates',
      items: items,
      withIcons: true,
    );
  }

  String _dateLine(QuietSession session) {
    final day = historyDayLabel(
      DateTime(session.start.year, session.start.month, session.start.day),
      DateTime.now(),
    );
    return '$day, ${quietClock(session.start)} to ${quietClock(session.end)}';
  }

  Widget _ok(BuildContext context, QuietSession session) {
    final c = context.colors;
    final through = session.through;
    final names = through.take(3).join(', ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          c.primaryGreen.withValues(alpha: 0.12),
          c.surface,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primaryGreen.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EchoMascot(state: EchoState.happy, size: 46, showRings: false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nothing here needs you',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  through.isEmpty
                      ? "Nobody asking for you came through while you were quiet."
                      : '${through.length == 1 ? 'One person' : '${through.length} people'} got through as they wrote: $names. '
                            "They're waiting on Today, not in here.",
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    height: 1.45,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.go('/echo'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Go to Today',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: c.primaryGreen,
                        ),
                      ),
                      Icon(
                        Symbols.chevron_right_rounded,
                        size: 18,
                        color: c.primaryGreen,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _split(BuildContext context, List<(String, int, Color)> parts) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (final (i, p) in parts.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(flex: p.$2, child: ColoredBox(color: p.$3)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final p in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.$3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${p.$2}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        TextSpan(text: ' ${p.$1}'),
                      ],
                    ),
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// An app's held messages: the first three, and the rest on request.
class _AppCard extends StatefulWidget {
  final Widget icon;
  final String title;
  final String note;
  final List<RawData> items;
  final bool withIcons;

  const _AppCard({
    required this.icon,
    required this.title,
    required this.note,
    required this.items,
    this.withIcons = false,
  });

  @override
  State<_AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<_AppCard> {
  static const _preview = 3;
  static const _expanded = 30;

  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = widget.items;
    final shown = _open ? items.take(_expanded).toList() : items.take(_preview).toList();
    final inHistory = items.length - _expanded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
            child: Row(
              children: [
                widget.icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: widget.title),
                        TextSpan(
                          text: '  ${widget.note}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    style: GoogleFonts.nunito(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in shown)
                  HeldLine(entry: item, withIcon: widget.withIcons),
              ],
            ),
          ),
          if (items.length > _preview)
            _moreButton(context, inHistory),
          if (items.length <= _preview) const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _moreButton(BuildContext context, int inHistory) {
    final c = context.colors;
    final toHistory = _open && inHistory > 0;
    final label = toHistory
        ? '$inHistory more in History'
        : _open
        ? 'Show less'
        : 'Show ${widget.items.length - _preview} more';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (toHistory) {
          context.go('/history');
        } else {
          setState(() => _open = !_open);
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              toHistory
                  ? Symbols.inbox_rounded
                  : _open
                  ? Symbols.expand_less_rounded
                  : Symbols.expand_more_rounded,
              size: 18,
              color: c.primaryGreen,
            ),
            const SizedBox(width: 2),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: c.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
