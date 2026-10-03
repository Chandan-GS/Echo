import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/features/echo/data/ask/for_you.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/todo/data/todo_generator.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/pressable.dart';

/// What Ask Echo opens with when something came in for the owner: a
/// greeting, a card for each chat that wants them, and the group chatter
/// folded into one row.
class ForYouView extends StatelessWidget {
  final ForYou forYou;
  final String? name;
  final DateTime now;
  final void Function(RawData) onReply;
  final void Function(RawData) onAdd;
  final VoidCallback onChatter;

  const ForYouView({
    super.key,
    required this.forYou,
    required this.name,
    required this.now,
    required this.onReply,
    required this.onAdd,
    required this.onChatter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final greeting = switch (now.hour) {
      >= 5 && < 12 => 'Morning',
      >= 12 && < 17 => 'Afternoon',
      _ => 'Evening',
    };
    final count = forYou.chats;
    final things = switch (count) {
      1 => 'one thing',
      2 => 'two things',
      3 => 'three things',
      _ => '$count things',
    };
    final when = forYou.sinceLastLook
        ? 'Since you last checked at ${clockLabel(forYou.since)}'
        : 'Today';
    final summary = count == 0
        ? forYou.sinceLastLook
              ? 'Nothing new for you since you last checked at '
                    '${clockLabel(forYou.since)}. Ask me anything.'
              : 'Nothing is waiting for you right now. Ask me anything.'
        : '$when, $things came in that ${count == 1 ? 'is' : 'are'} meant '
              'for you.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const EchoMascot(size: 46, showRings: false, glow: false),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name == null ? '$greeting.' : '$greeting, $name.',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          summary,
          style: GoogleFonts.nunito(
            fontSize: 14.5,
            height: 1.5,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        for (final e in forYou.items) ...[
          ForYouCard(entry: e, onReply: onReply, onAdd: onAdd),
          const SizedBox(height: 10),
        ],
        if (forYou.chatter > 0)
          _ChatterRow(count: forYou.chatter, onTap: onChatter),
      ],
    );
  }
}

/// A message meant for the owner, with what they can do about it: reply,
/// be reminded before the time it names, or put it on the list. Ask Echo
/// opens with these, and Home's "Needs you" is made of them.
class ForYouCard extends StatefulWidget {
  final RawData entry;
  final void Function(RawData) onReply;
  final void Function(RawData) onAdd;

  const ForYouCard({
    super.key,
    required this.entry,
    required this.onReply,
    required this.onAdd,
  });

  @override
  State<ForYouCard> createState() => _ForYouCardState();
}

class _ForYouCardState extends State<ForYouCard> {
  /// When "Remind me" would remind: before the time the message names.
  late final DateTime? _remindAt = reminderTimeFor(
    widget.entry,
    DateTime.now(),
  );

  /// Whether the message is on the to-do list already.
  bool _onList = false;

  @override
  void initState() {
    super.initState();
    _checkList();
    TodoStore.changed.addListener(_checkList);
  }

  @override
  void dispose() {
    TodoStore.changed.removeListener(_checkList);
    super.dispose();
  }

  Future<void> _checkList() async {
    final (items, _) = await TodoStore().load();
    final key = sourceKeyOf(widget.entry);
    final onList = items.any((i) => i.sourceKey == key);
    if (mounted && onList != _onList) setState(() => _onList = onList);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final addressed = Addressed.parse(entry.addressed) ?? Addressed.direct;
    return AskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SourceBadge(entry),
              const SizedBox(width: 10),
              Expanded(child: WhoLine(entry)),
              const SizedBox(width: 8),
              ForYouTag(addressed),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '“${entry.content}”',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (entry.thread != null)
                AskPill(
                  label: 'Reply',
                  icon: Symbols.reply_rounded,
                  filled: true,
                  onTap: () => widget.onReply(entry),
                ),
              if (_remindAt != null)
                RemindPill(entry: entry, at: _remindAt)
              // A reminder already brings it back at the right time, so Add
              // is offered only for messages without one.
              else if (_onList)
                const AskPill(
                  label: 'On your list',
                  icon: Symbols.check_rounded,
                )
              else if (looksActionable(entry))
                AskPill(
                  label: 'Add to my list',
                  icon: Symbols.checklist_rounded,
                  onTap: () => widget.onAdd(entry),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Remind me at 7:40 PM", and once tapped "Reminding at 7:40 PM" (tap again
/// to cancel). The reminder quotes [entry].
class RemindPill extends StatefulWidget {
  final RawData entry;
  final DateTime at;

  /// The reminder's title; who sent [entry] when not given.
  final String? title;
  final bool filled;

  const RemindPill({
    super.key,
    required this.entry,
    required this.at,
    this.title,
    this.filled = false,
  });

  @override
  State<RemindPill> createState() => _RemindPillState();
}

class _RemindPillState extends State<RemindPill> {
  /// When the reminder is set for, if it is.
  DateTime? _reminding;

  String get _key => sourceKeyOf(widget.entry);

  @override
  void initState() {
    super.initState();
    _read();
    // Set or changed on the to-do too: one reminder per message.
    Reminders.changed.addListener(_read);
  }

  @override
  void dispose() {
    Reminders.changed.removeListener(_read);
    super.dispose();
  }

  Future<void> _read() async {
    final at = await Reminders.setFor(_key);
    if (mounted) setState(() => _reminding = at);
  }

  Future<void> _toggle() async {
    final e = widget.entry;
    if (_reminding != null) {
      await Reminders.cancel(_key);
      return;
    }
    final title =
        widget.title ??
        (e.isGroup && (e.threadTitle?.isNotEmpty ?? false)
            ? '${e.sender} in ${e.threadTitle}'
            : e.sender);
    setState(() => _reminding = widget.at);
    Future<void> remind({int? todoId}) => Reminders.set(
      message: _key,
      at: widget.at,
      title: title,
      body: e.content,
      todoId: todoId,
      thread: e.thread,
    );
    await remind();
    // It goes on the list too, so it can be ticked off from the reminder.
    final (items, _) = await TodoStore().load();
    var todo = items.where((i) => i.sourceKey == _key).firstOrNull;
    todo ??= (await TodoGenerator().addFrom([e], DateTime.now())).firstOrNull;
    if (todo != null) await remind(todoId: todo.id);
  }

  @override
  Widget build(BuildContext context) {
    final reminding = _reminding;
    return reminding != null
        ? AskPill(
            label: 'Reminding ${whenLabel(reminding, DateTime.now())}',
            icon: Symbols.notifications_active_rounded,
            set: true,
            onTap: _toggle,
          )
        : AskPill(
            label: 'Remind me ${whenLabel(widget.at, DateTime.now())}',
            icon: Symbols.alarm_rounded,
            filled: widget.filled,
            onTap: _toggle,
          );
  }
}

/// "41 group messages · not for you ›", like Home's Regenerate row.
class _ChatterRow extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _ChatterRow({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      scale: 0.98,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.dividerColor.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Symbols.forum_rounded,
                  size: 20,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  '$count group message${count == 1 ? '' : 's'}',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  'not for you',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                  ),
                ),
                Icon(
                  Symbols.chevron_right_rounded,
                  size: 20,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
