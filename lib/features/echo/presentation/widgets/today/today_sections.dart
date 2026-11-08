import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_parts.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/todo/presentation/widgets/reminder_sheet.dart';
import 'package:project_echo/features/todo/presentation/widgets/todo_card.dart';

/// Nobody's waiting: a small pat on the back.
class AllClearCard extends StatelessWidget {
  const AllClearCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: c.primaryGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const EchoMascot(
            size: 46,
            state: EchoState.happy,
            showRings: false,
            glow: false,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nobody’s waiting on you',
                  style: GoogleFonts.nunito(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  'Every message that needed you has an answer.',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    color: c.textSecondary,
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

/// Echo can't see notifications yet, so the list can't fill.
class NoAccessCard extends StatelessWidget {
  final VoidCallback onGrant;
  const NoAccessCard({super.key, required this.onGrant});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Echo can’t see your messages yet',
            style: GoogleFonts.nunito(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Allow notification access and whoever’s waiting on you shows '
            'up here.',
            style: GoogleFonts.nunito(
              fontSize: 13.5,
              height: 1.4,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          AskPill(
            label: 'Allow',
            icon: Symbols.notifications_active_rounded,
            filled: true,
            onTap: onGrant,
          ),
        ],
      ),
    );
  }
}

/// "N more" under the first three cards.
class WaitingMoreRow extends StatelessWidget {
  final int more;
  final bool open;
  final VoidCallback onTap;

  const WaitingMoreRow({
    super.key,
    required this.more,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              open ? 'Show fewer' : '$more more',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.primaryGreen,
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 260),
              child: Icon(
                Symbols.expand_more_rounded,
                size: 20,
                color: c.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashed row of messages Echo left off the list, opening into each one
/// and a way to put it back.
class AcksRow extends StatefulWidget {
  final List<WaitingItem> acks;
  const AcksRow({super.key, required this.acks});

  @override
  State<AcksRow> createState() => _AcksRowState();
}

class _AcksRowState extends State<AcksRow> {
  bool _open = false;
  final _added = <String>{};

  Future<void> _itDoes(WaitingItem item) async {
    final name = item.message.sender;
    setState(() => _added.add(item.key));
    showTodayToast(context, '$name is on your list. Echo will learn from this');
    await WaitingStore.markNeedsReply(item);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.acks.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final n = widget.acks.length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: CustomPaint(
              painter: DashedBorderPainter(color: c.dividerColor, radius: 18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Symbols.done_all_rounded,
                      size: 19,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$n ${n == 1 ? 'message' : 'messages'} to you '
                        'didn’t need a reply',
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: Icon(
                        Symbols.expand_more_rounded,
                        size: 20,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AskCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      child: Column(
                        children: [
                          for (final (i, item) in widget.acks.indexed)
                            _AckLine(
                              item: item,
                              last: i == n - 1,
                              added: _added.contains(item.key),
                              onItDoes: () => _itDoes(item),
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

class _AckLine extends StatelessWidget {
  final WaitingItem item;
  final bool last;
  final bool added;
  final VoidCallback onItDoes;

  const _AckLine({
    required this.item,
    required this.last,
    required this.added,
    required this.onItDoes,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final message = item.message;
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: added ? 0.4 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(
                  bottom: BorderSide(
                    color: c.dividerColor.withValues(alpha: 0.6),
                  ),
                ),
        ),
        child: Row(
          children: [
            PersonAvatar(
              name: message.sender,
              size: 32,
              source: message.source,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“${message.content}”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${message.sender} · ${item.reason.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: added ? null : onItDoes,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  added ? 'Added' : 'It does',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: c.primaryGreen,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds a typed to-do without leaving Today.
Future<void> showQuickAdd(BuildContext context) async {
  final todo = context.read<TodoCubit>();
  final text = await showTodaySheet<String>(
    context,
    (_) => const _QuickAddSheet(),
  );
  if (text == null || text.trim().isEmpty) return;
  final added = await todo.addTyped(text);
  if (added != null && context.mounted) {
    showTodayToast(context, 'Added “${added.title}”');
  }
}

class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet();

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TodaySheetBody(
      children: [
        Text('Add to your list', style: todaySheetTitle(context)),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          style: GoogleFonts.nunito(fontSize: 16, color: c.textPrimary),
          decoration: InputDecoration(
            hintText: 'Call the plumber at 11 tomorrow',
            hintStyle: GoogleFonts.nunito(fontSize: 16, color: c.textSecondary),
            filled: true,
            fillColor: c.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: AskPill(
            label: 'Add',
            icon: Symbols.add_rounded,
            filled: true,
            onTap: _add,
          ),
        ),
      ],
    );
  }
}

/// What's left today, ticked off here, with a small + so adding one doesn't
/// take two screens.
class TodoSection extends StatefulWidget {
  const TodoSection({super.key});

  static const shown = 4;

  @override
  State<TodoSection> createState() => _TodoSectionState();
}

class _TodoSectionState extends State<TodoSection> {
  Map<String, DateTime> _reminders = const {};

  @override
  void initState() {
    super.initState();
    _read();
    Reminders.changed.addListener(_read);
  }

  @override
  void dispose() {
    Reminders.changed.removeListener(_read);
    super.dispose();
  }

  Future<void> _read() async {
    final all = await Reminders.all();
    if (mounted) setState(() => _reminders = all);
  }

  Future<void> _remind(TodoItem item) async {
    final choice = await showReminderSheet(
      context,
      item,
      current: _reminders[item.sourceKey],
    );
    switch (choice) {
      case RemindAt(:final at):
        final entry = await IsarDataSource.entryForKey(item.sourceKey);
        await Reminders.set(
          message: item.sourceKey,
          at: at,
          title: item.title,
          body: item.sourceText.isEmpty
              ? 'On your list for ${item.time ?? 'today'}.'
              : '${item.sender}: “${item.sourceText}”',
          todoId: item.id,
          thread: entry?.thread,
        );
        if (mounted) {
          showTodayToast(
            context,
            'I’ll remind you ${whenLabel(at, DateTime.now())}',
          );
        }
      case RemoveReminder():
        await Reminders.cancel(item.sourceKey);
        if (mounted) showTodayToast(context, 'Reminder removed');
      case null:
        break;
    }
  }

  void _openList() => context.push('/todo');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<TodoCubit, TodoState>(
      builder: (context, todo) {
        final left = todo.today.where((i) => !i.done).toList()
          ..sort((a, b) => a.sort.compareTo(b.sort));
        final open = todo.items
            .where((i) => !i.done && !i.day.isBefore(startOfDay(todo.now)))
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TodaySectionHead(
              'To-do',
              action: open == 0 ? 'Open' : 'All $open',
              onAction: _openList,
              extra: Semantics(
                button: true,
                label: 'Add a to-do',
                child: PressFeedback(
                  scale: 0.85,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showQuickAdd(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                      child: Icon(
                        Symbols.add_rounded,
                        size: 22,
                        color: c.primaryGreen,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AskCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: AnimatedSize(
                duration: AppMotion.medium,
                curve: AppMotion.emphasized,
                alignment: Alignment.topCenter,
                child: left.isEmpty
                    ? _EmptyTodo(
                        done: todo.today.length,
                        onAdd: () => showQuickAdd(context),
                      )
                    : Column(
                        children: [
                          for (final (i, item)
                              in left.take(TodoSection.shown).indexed)
                            _TodoRow(
                              key: ValueKey(item.id),
                              item: item,
                              first: i == 0,
                              reminding: _reminders.containsKey(item.sourceKey),
                              onOpen: _openList,
                              onRemind: () => _remind(item),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyTodo extends StatelessWidget {
  final int done;
  final VoidCallback onAdd;
  const _EmptyTodo({required this.done, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              done == 0
                  ? 'Nothing on today’s list.'
                  : done == 1
                  ? 'Done for today.'
                  : 'All $done done for today.',
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AskPill(label: 'Add', icon: Symbols.add_rounded, onTap: onAdd),
        ],
      ),
    );
  }
}

/// A to-do as it reads in the list. Its circle ticks it off, and the tick
/// shows for a moment before the row leaves.
class _TodoRow extends StatefulWidget {
  final TodoItem item;
  final bool first;
  final bool reminding;
  final VoidCallback onOpen;
  final VoidCallback onRemind;

  const _TodoRow({
    super.key,
    required this.item,
    required this.first,
    required this.reminding,
    required this.onOpen,
    required this.onRemind,
  });

  @override
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  bool _ticked = false;

  Future<void> _tick() async {
    if (_ticked) return;
    setState(() => _ticked = true);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (mounted) await toggleTodo(context, widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    final from = [
      item.sender,
      item.app,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: _ticked ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
        decoration: BoxDecoration(
          border: widget.first
              ? null
              : Border(
                  top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: 'Done',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _tick,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(top: 1, right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _ticked ? c.primaryGreen : Colors.transparent,
                    border: Border.all(
                      color: _ticked
                          ? c.primaryGreen
                          : c.primaryGreen.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                  child: AnimatedScale(
                    duration: AppMotion.medium,
                    curve: AppMotion.spring,
                    scale: _ticked ? 1 : 0.4,
                    child: AnimatedOpacity(
                      duration: AppMotion.fast,
                      opacity: _ticked ? 1 : 0,
                      child: Icon(
                        Symbols.check_rounded,
                        size: 17,
                        color: context.isDarkMode
                            ? c.textInverse
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.nunito(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: c.textPrimary,
                        decoration: _ticked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: item.time ?? 'Anytime',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: c.primaryGreen,
                            ),
                          ),
                          if (from.isNotEmpty) TextSpan(text: ' · $from'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        height: 1.35,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Remind me',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onRemind,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    widget.reminding
                        ? Symbols.notifications_active_rounded
                        : Symbols.notification_add_rounded,
                    size: 21,
                    fill: widget.reminding ? 1 : 0,
                    color: widget.reminding ? c.primaryGreen : c.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chats where the owner asked and hasn't heard back. Left out when there
/// are none.
class OwedSection extends StatelessWidget {
  final List<OwedToYou> owed;
  const OwedSection({super.key, required this.owed});

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String _sub(OwedToYou o, DateTime now) {
    final t = o.turn.at;
    final days = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
    return switch (days) {
      0 => 'You asked earlier today. No reply yet.',
      1 => 'You asked yesterday. No reply yet.',
      _ => 'You asked on ${_days[t.weekday - 1]}. $days days, no reply.',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (owed.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TodaySectionHead('Owed to you', note: 'no reply yet'),
        AskCard(
          child: Column(
            children: [
              for (final (i, o) in owed.indexed) ...[
                if (i > 0) const SizedBox(height: 14),
                _owedRow(context, c, o, now),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _owedRow(
    BuildContext context,
    AppColors c,
    OwedToYou o,
    DateTime now,
  ) {
    void open() => context.push(
      '/person',
      extra: personKeyFor(o.chat.sender, o.chat.source),
    );
    return PressFeedback(
      scale: 0.98,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: Row(
          children: [
            PersonAvatar(name: o.who, size: 36, source: o.chat.source),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${o.who}, “${o.turn.text}”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _sub(o, now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AskPill(label: 'Nudge', icon: Symbols.send_rounded, onTap: open),
          ],
        ),
      ),
    );
  }
}

/// Busy groups, each with a bar showing how much it said against the
/// busiest.
class BusyGroupsSection extends StatelessWidget {
  final List<BusyGroup> groups;
  final Map<String, String> summaries;

  const BusyGroupsSection({
    super.key,
    required this.groups,
    required this.summaries,
  });

  static const shown = 4;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final busiest = groups.first.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TodaySectionHead(
          'Busy groups',
          action: 'All ${groups.length}',
          onAction: () => context.push('/groups'),
        ),
        for (final (i, g) in groups.take(shown).indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          GroupRow(group: g, busiest: busiest, summary: summaries[g.name]),
        ],
      ],
    );
  }
}

/// One group: its app, how busy it was, Echo's line about it or its latest
/// message, and the bar. Marked when someone in it wants the owner.
class GroupRow extends StatelessWidget {
  final BusyGroup group;
  final int busiest;
  final String? summary;

  const GroupRow({
    super.key,
    required this.group,
    required this.busiest,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final latest = group.latest;
    final line =
        summary ??
        (latest.sender.isEmpty
            ? latest.content
            : '${latest.sender}: ${latest.content}');
    final fg = ageColors(context, 2).fg;
    final ratio = busiest <= 0 ? 0.0 : (group.count / busiest).clamp(0.0, 1.0);
    return PressFeedback(
      scale: 0.98,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/group', extra: group.name),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
            child: Row(
              children: [
                SourceBadge(latest, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: group.name),
                            TextSpan(
                              text: ' · ${group.count} today',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (group.needs)
                              TextSpan(
                                text: 'Needs you. ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: fg,
                                ),
                              ),
                            TextSpan(text: line),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          height: 1.35,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, box) => Stack(
                          children: [
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: c.dividerColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            AnimatedContainer(
                              duration: AppMotion.medium,
                              curve: AppMotion.emphasized,
                              height: 4,
                              width: box.maxWidth * ratio,
                              decoration: BoxDecoration(
                                color: group.needs
                                    ? (context.isDarkMode
                                          ? const Color(0xFFE58C76)
                                          : const Color(0xFFC0503B))
                                    : c.textSecondary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
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
