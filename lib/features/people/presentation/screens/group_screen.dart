import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/presentation/widgets/person_photo_sheet.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/people/data/group_page.dart';
import 'package:project_echo/features/people/data/group_rules.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/people/data/person_loops.dart';
import 'package:project_echo/features/people/data/person_tally.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart';
import 'package:project_echo/features/todo/data/todo_generator.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';

/// A group, read for the owner: money, dates and mentions by rules on the
/// phone; a line of what was decided only with a cloud engine; everything
/// else counted and set aside, one tap from the raw chat.
class GroupScreen extends StatefulWidget {
  final String threadTitle;

  /// Replaces reading the group, for tests.
  @visibleForTesting
  final Future<GroupPage> Function(String title, DateTime now)? loader;

  const GroupScreen({super.key, required this.threadTitle, this.loader});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  GroupPage? _page;
  String? _summary;
  bool _showSkipped = false;
  bool _showRaw = false;
  final Set<String> _paid = {};
  final Set<String> _added = {};
  final Set<String> _reminding = {};
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    PeopleStore.changed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    PeopleStore.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    final now = DateTime.now();
    final page = await (widget.loader ?? GroupPageStore.load)(
      widget.threadTitle,
      now,
    );
    if (!mounted || id != _loadId) return;
    setState(() => _page = page);
    final all = await Reminders.all();
    if (mounted) setState(() => _reminding..clear()..addAll(all.keys));
    final summary = await GroupPageStore.summary(page, now);
    if (mounted && summary != null) setState(() => _summary = summary);
  }

  Future<void> _markPaid(GroupNeed need) async {
    final key = need.line.key;
    setState(() => _paid.add(key));
    await PeopleStore.markPaid(key, DateTime.now());
    if (mounted) {
      showPeopleSnack(context, 'Marked paid. It’s off your to-do list.');
    }
  }

  Future<void> _remindMoney(GroupNeed need) async {
    final money = need.money!;
    final line = need.line;
    final now = DateTime.now();
    final key = 'money:${line.key}';
    final due = money.due;
    final at = _remindAt(due, now);
    final who = firstNameOf(line.sender);
    final on = await toggleReminder(
      key: key,
      at: at,
      title: '$who asked for ${money.what}',
      body: clip(line.text, 120),
      thread: line.thread,
    );
    if (!mounted) return;
    setState(() => on ? _reminding.add(key) : _reminding.remove(key));
    showPeopleSnack(context, on ? 'Reminder set.' : 'Reminder removed.');
  }

  static DateTime _remindAt(DateTime? due, DateTime now) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    if (due == null) return tomorrow;
    final day = DateTime(due.year, due.month, due.day, 9);
    if (day.isAfter(now)) return day;
    final soon = now.add(const Duration(hours: 1));
    return soon.day == now.day ? soon : tomorrow;
  }

  Future<void> _remindDate(GroupDate date) async {
    final now = DateTime.now();
    final key = 'date:${date.line.key}';
    final at = date.hasTime
        ? date.when.subtract(reminderLead)
        : DateTime(date.when.year, date.when.month, date.when.day, 9);
    final on = await toggleReminder(
      key: key,
      at: at.isAfter(now) ? at : date.when,
      title: clip(date.line.text, 60),
      body: widget.threadTitle,
      thread: date.line.thread,
    );
    if (!mounted) return;
    setState(() => on ? _reminding.add(key) : _reminding.remove(key));
    showPeopleSnack(context, on ? 'Reminder set.' : 'Reminder removed.');
  }

  Future<void> _addTodo(GroupNeed need) async {
    final key = need.line.key;
    setState(() => _added.add(key));
    final added = await TodoGenerator().addFrom([
      need.line.toEntry(),
    ], DateTime.now());
    if (!mounted) return;
    if (added.isEmpty) {
      setState(() => _added.remove(key));
      showPeopleSnack(context, 'That’s already on your list.');
      return;
    }
    TodoStore.changed.value++;
    showPeopleSnack(context, 'Added to your to-do list.');
  }

  void _reply(GroupNeed need) => context.push(
    '/person',
    extra: personKeyFor(need.line.sender, need.line.source),
  );

  Future<void> _openChat() async {
    final page = _page;
    if (page == null || page.latest == null) return;
    final ok = await ReplySender.open(page.latest!);
    if (!ok && mounted) {
      showPeopleSnack(context, 'Couldn’t open ${appLabel(page.source ?? '')}.');
    }
  }

  void _ask() =>
      context.push('/echo/chat', extra: 'Catch me up on ${widget.threadTitle}');

  Future<void> _togglePullOut(bool on) async {
    await PeopleStore.setGroupPullsOut(widget.threadTitle, on);
    if (mounted) {
      showPeopleSnack(
        context,
        on
            ? 'Pulling out what’s for you in ${widget.threadTitle}.'
            : '${widget.threadTitle} will just show a count.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Symbols.arrow_back_ios_new_rounded,
            size: 28,
            color: context.colors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            onPressed: _ask,
            icon: Icon(
              Symbols.auto_awesome_rounded,
              color: context.colors.textPrimary,
            ),
            tooltip: 'Ask Echo',
          ),
        ],
      ),
      body: page == null
          ? const SizedBox.shrink()
          : page.heardNothing
          ? _NothingHeard(page: page)
          : ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.paddingOf(context).bottom + 28,
              ),
              children: [
                FadeSlideIn(child: _Hero(page: page)),
                if (page.pullsOut) ..._digestSections(page),
                const SizedBox(height: 12),
                _ShowEverything(
                  on: _showRaw,
                  onTap: () => setState(() => _showRaw = !_showRaw),
                ),
                if (_showRaw)
                  _RawChat(page: page, onOpen: _openChat),
                const PeopleSection('For this group'),
                _GroupSwitches(
                  title: widget.threadTitle,
                  pullsOut: page.pullsOut,
                  onPullOut: _togglePullOut,
                  onAsk: _ask,
                ),
                const SizedBox(height: 14),
                _Limit(source: page.source),
              ],
            ),
    );
  }

  List<Widget> _digestSections(GroupPage page) {
    final d = page.digest;
    final needs = d.needs.where((n) => !_paid.contains(n.line.key)).toList();
    return [
      const SizedBox(height: 14),
      FadeSlideIn(
        delay: AppMotion.staggerDelay(1),
        child: needs.isEmpty
            ? const _NothingNeedsYou()
            : _NeedsCard(
                needs: needs,
                paid: _paid,
                added: _added,
                reminding: _reminding,
                onPaid: _markPaid,
                onRemind: _remindMoney,
                onReply: _reply,
                onAdd: _addTodo,
              ),
      ),
      if (page.cloud && _summary != null)
        FadeSlideIn(
          delay: AppMotion.staggerDelay(2),
          child: _DecidedCard(line: _summary!),
        )
      else if (!page.cloud)
        const _NoEngineNote(),
      if (d.dates.isNotEmpty)
        FadeSlideIn(
          delay: AppMotion.staggerDelay(3),
          child: _DatesCard(
            dates: d.dates,
            reminding: _reminding,
            onRemind: _remindDate,
          ),
        ),
      if (d.skipped.total > 0)
        FadeSlideIn(
          delay: AppMotion.staggerDelay(4),
          child: _Skipped(
            summary: d.skipped,
            on: _showSkipped,
            onTap: () => setState(() => _showSkipped = !_showSkipped),
          ),
        ),
    ];
  }
}

class _NothingHeard extends StatelessWidget {
  final GroupPage page;

  const _NothingHeard({required this.page});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = page.retentionDays;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EchoMascot(
            state: EchoState.idle,
            size: 84,
            showRings: false,
            glow: false,
          ),
          const SizedBox(height: 16),
          Text(
            'Echo hasn’t heard from ${page.title}',
            textAlign: TextAlign.center,
            style: GoogleFonts.oldStandardTt(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nothing from this group reached this phone in the last $days '
            '${days == 1 ? 'day' : 'days'}. A muted group still comes through '
            'silently, but if its notifications are turned off completely in '
            'the app, Echo hears nothing from it.',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 14,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          PeoplePill(
            label: 'Apps Echo hears',
            icon: Symbols.apps_rounded,
            onTap: () => context.push('/you/hears'),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final GroupPage page;

  const _Hero({required this.page});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = page.newSinceYesterday;
    return Row(
      children: [
        if (page.source != null) ...[
          Semantics(
            button: true,
            label: 'Change picture',
            child: PressFeedback(
              child: GestureDetector(
                onTap: () => showPersonPhotoSheet(
                  context,
                  name: page.title,
                  source: page.source,
                ),
                child: PersonAvatar(
                  name: page.title,
                  size: 48,
                  source: page.source,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                page.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.oldStandardTt(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                n == 0 ? 'Nothing new since yesterday' : '$n new since yesterday',
                style: GoogleFonts.nunito(
                  fontSize: 13.5,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NothingNeedsYou extends StatelessWidget {
  const _NothingNeedsYou();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Symbols.check_circle_rounded,
                fill: 1,
                size: 18,
                color: c.primaryGreen,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Nothing here needs you',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: c.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No money or mentions for you in what Echo heard.',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedsCard extends StatelessWidget {
  final List<GroupNeed> needs;
  final Set<String> paid;
  final Set<String> added;
  final Set<String> reminding;
  final void Function(GroupNeed) onPaid;
  final void Function(GroupNeed) onRemind;
  final void Function(GroupNeed) onReply;
  final void Function(GroupNeed) onAdd;

  const _NeedsCard({
    required this.needs,
    required this.paid,
    required this.added,
    required this.reminding,
    required this.onPaid,
    required this.onRemind,
    required this.onReply,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return AskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionKicker(Symbols.priority_high_rounded, 'Needs you', warm: true),
          for (final (i, n) in needs.indexed) ...[
            if (i > 0) const _Hairline(),
            _NeedRow(
              need: n,
              added: added.contains(n.line.key),
              reminding: reminding.contains('money:${n.line.key}'),
              onPaid: () => onPaid(n),
              onRemind: () => onRemind(n),
              onReply: () => onReply(n),
              onAdd: () => onAdd(n),
            ),
          ],
        ],
      ),
    );
  }
}

class _NeedRow extends StatefulWidget {
  final GroupNeed need;
  final bool added;
  final bool reminding;
  final VoidCallback onPaid;
  final VoidCallback onRemind;
  final VoidCallback onReply;
  final VoidCallback onAdd;

  const _NeedRow({
    required this.need,
    required this.added,
    required this.reminding,
    required this.onPaid,
    required this.onRemind,
    required this.onReply,
    required this.onAdd,
  });

  @override
  State<_NeedRow> createState() => _NeedRowState();
}

class _NeedRowState extends State<_NeedRow> {
  bool _source = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = widget.need;
    final money = n.money;
    final who = firstNameOf(n.line.sender);
    final now = DateTime.now();
    final title = money != null
        ? '$who asked for ${money.what}'
              '${money.due != null ? ', by ${dayWord(money.due!, now)}' : ''}.'
        : '$who mentioned you.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.nunito(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            height: 1.4,
            color: c.textPrimary,
          ),
        ),
        if (money == null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              clip(n.line.text, 140),
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                height: 1.4,
                color: c.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: money != null
              ? [
                  PeoplePill(
                    label: 'Mark paid',
                    icon: Symbols.payments_rounded,
                    filled: true,
                    onTap: widget.onPaid,
                  ),
                  PeoplePill(
                    label: widget.reminding
                        ? 'Reminding'
                        : money.due != null
                        ? 'Remind me ${shortDay(money.due!, now)}'
                        : 'Remind me tomorrow',
                    icon: widget.reminding
                        ? Symbols.notifications_active_rounded
                        : Symbols.alarm_rounded,
                    set: widget.reminding,
                    onTap: widget.onRemind,
                  ),
                ]
              : [
                  PeoplePill(
                    label: 'Reply',
                    icon: Symbols.reply_rounded,
                    filled: true,
                    onTap: widget.onReply,
                  ),
                  PeoplePill(
                    label: widget.added ? 'On your to-do list' : 'Add to To-do',
                    icon: widget.added
                        ? Symbols.check_rounded
                        : Symbols.checklist_rounded,
                    set: widget.added,
                    onTap: widget.added ? null : widget.onAdd,
                  ),
                ],
        ),
        if (money != null) ...[
          const SizedBox(height: 8),
          _SourceToggle(
            on: _source,
            label: 'See the original message',
            onTap: () => setState(() => _source = !_source),
          ),
          if (_source)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _OriginalBox(line: n.line),
            ),
        ],
      ],
    );
  }
}

class _SourceToggle extends StatelessWidget {
  final bool on;
  final String label;
  final VoidCallback onTap;

  const _SourceToggle({
    required this.on,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedRotation(
            turns: on ? 0.5 : 0,
            duration: AppMotion.fast,
            child: Icon(
              Symbols.expand_more_rounded,
              size: 18,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              on ? 'Hide the original message' : label,
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginalBox extends StatelessWidget {
  final GroupLine line;

  const _OriginalBox({required this.line});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.dividerColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text.rich(
        TextSpan(
          style: GoogleFonts.nunito(
            fontSize: 13,
            height: 1.45,
            color: c.textSecondary,
          ),
          children: [
            TextSpan(
              text: '${line.sender}: ',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            TextSpan(text: '“${line.text}”'),
          ],
        ),
      ),
    );
  }
}

class _SectionKicker extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool warm;

  const _SectionKicker(this.icon, this.text, {this.warm = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = warm ? context.warmAccent : c.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(
      height: 1,
      color: context.colors.dividerColor.withValues(alpha: 0.6),
    ),
  );
}

class _DecidedCard extends StatelessWidget {
  final String line;

  const _DecidedCard({required this.line});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AskCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionKicker(Symbols.how_to_vote_rounded, 'In short'),
            Text(
              line,
              style: GoogleFonts.nunito(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Without a cloud engine: says plainly what still works.
class _NoEngineNote extends StatelessWidget {
  const _NoEngineNote();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 2, right: 2),
      child: Text(
        'What was decided needs the cloud engine, which isn’t on. Money, '
        'dates and mentions are read on this phone.',
        style: GoogleFonts.nunito(
          fontSize: 12.5,
          height: 1.45,
          color: c.textSecondary,
        ),
      ),
    );
  }
}

class _DatesCard extends StatelessWidget {
  final List<GroupDate> dates;
  final Set<String> reminding;
  final void Function(GroupDate) onRemind;

  const _DatesCard({
    required this.dates,
    required this.reminding,
    required this.onRemind,
  });

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AskCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionKicker(Symbols.event_rounded, 'Dates'),
            for (final (i, d) in dates.indexed) ...[
              if (i > 0) const _Hairline(),
              Row(
                children: [
                  Container(
                    width: 44,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: c.dividerColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _weekdays[d.when.weekday - 1].toUpperCase(),
                          style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: context.warmAccent,
                          ),
                        ),
                        Text(
                          '${d.when.day}',
                          style: GoogleFonts.oldStandardTt(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clip(d.line.text, 80),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          [
                            firstNameOf(d.line.sender),
                            if (d.hasTime) _time(d.when),
                          ].join(' · '),
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PressFeedback(
                    child: Tooltip(
                      message: 'Remind me',
                      child: IconButton(
                        onPressed: () => onRemind(d),
                        icon: Icon(
                          reminding.contains('date:${d.line.key}')
                              ? Symbols.notifications_active_rounded
                              : Symbols.alarm_add_rounded,
                          size: 20,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _Skipped extends StatelessWidget {
  final SkipSummary summary;
  final bool on;
  final VoidCallback onTap;

  const _Skipped({
    required this.summary,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kinds = summary.counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AskCard(
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PeopleRow(
                first: true,
                onTap: onTap,
                child: Row(
                  children: [
                    Icon(
                      Symbols.filter_alt_off_rounded,
                      size: 20,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: c.textSecondary,
                          ),
                          children: [
                            const TextSpan(text: 'Skipped for you: '),
                            TextSpan(
                              text: summary.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: on ? 0.5 : 0,
                      duration: AppMotion.fast,
                      child: Icon(
                        Symbols.expand_more_rounded,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (on)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final k in kinds)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  skipLabel(k.key),
                                  style: GoogleFonts.nunito(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '${k.value}',
                                style: GoogleFonts.nunito(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (summary.examples.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            summary.examples.map((e) => '“${clip(e, 70)}”').join(' · '),
                            style: GoogleFonts.nunito(
                              fontSize: 12.5,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                              color: c.textSecondary,
                            ),
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
}

class _ShowEverything extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const _ShowEverything({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      child: PeoplePill(
        label: on ? 'Hide the full chat' : 'Show everything',
        icon: Symbols.forum_rounded,
        onTap: onTap,
      ),
    );
  }
}

class _RawChat extends StatelessWidget {
  final GroupPage page;
  final VoidCallback onOpen;

  const _RawChat({required this.page, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = page.lines.take(rawShown).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AskCard(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: lines.length,
              itemBuilder: (context, i) => _RawLine(
                line: lines[i],
                skipped: page.digest.skippedKeys.contains(lines[i].key),
                first: i == 0,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  page.lines.length > lines.length
                      ? 'The last ${lines.length} of ${page.lines.length}'
                      : '${lines.length} messages',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: c.textSecondary,
                  ),
                ),
                PeoplePill(
                  label: pillWith('Open in', appLabel(page.source ?? '')),
                  icon: Symbols.open_in_new_rounded,
                  onTap: onOpen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RawLine extends StatelessWidget {
  final GroupLine line;
  final bool skipped;
  final bool first;

  const _RawLine({
    required this.line,
    required this.skipped,
    required this.first,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final word = dayWord(line.at, now);
    final time = _clock(line.at);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersonAvatar(name: line.sender, size: 26, source: line.source),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      firstNameOf(line.sender),
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      word == 'today' ? time : '${cap(word)} $time',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                    if (skipped) const AgeTag('skipped'),
                  ],
                ),
                Text(
                  line.text,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    height: 1.4,
                    color: skipped ? c.textSecondary : c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime at) {
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _GroupSwitches extends StatelessWidget {
  final String title;
  final bool pullsOut;
  final void Function(bool) onPullOut;
  final VoidCallback onAsk;

  const _GroupSwitches({
    required this.title,
    required this.pullsOut,
    required this.onPullOut,
    required this.onAsk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AskCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Icon(Symbols.filter_alt_rounded, size: 20, color: c.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pull out what’s for me',
                        style: GoogleFonts.nunito(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        'Money, dates, and mentions',
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: pullsOut, onChanged: onPullOut),
              ],
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: PeopleRow(
              onTap: onAsk,
              child: Row(
                children: [
                  Icon(Symbols.auto_awesome_rounded, size: 20, color: c.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ask Echo about $title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          '“What did I miss?” with the messages it used',
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const RowChevron(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Limit extends StatelessWidget {
  final String? source;

  const _Limit({required this.source});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final app = source == null ? 'the app' : appLabel(source!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Symbols.info_rounded, size: 17, color: c.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Muted groups still reach Echo silently. If you turn this group’s '
            'notifications off completely in $app, Echo hears nothing from it.',
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
