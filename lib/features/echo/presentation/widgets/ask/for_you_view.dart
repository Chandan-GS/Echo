import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/features/echo/data/ask/for_you.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';

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
          _ForYouCard(entry: e, onReply: onReply, onAdd: onAdd),
          const SizedBox(height: 10),
        ],
        if (forYou.chatter > 0)
          _ChatterRow(count: forYou.chatter, onTap: onChatter),
      ],
    );
  }
}

class _ForYouCard extends StatefulWidget {
  final RawData entry;
  final void Function(RawData) onReply;
  final void Function(RawData) onAdd;

  const _ForYouCard({
    required this.entry,
    required this.onReply,
    required this.onAdd,
  });

  @override
  State<_ForYouCard> createState() => _ForYouCardState();
}

class _ForYouCardState extends State<_ForYouCard> {
  /// When a reminder about this message is set for, if one is.
  DateTime? _reminding;

  /// When "Remind me" would remind: before the time the message names.
  late final DateTime? _remindAt = reminderTimeFor(
    widget.entry,
    DateTime.now(),
  );

  String get _key => sourceKeyOf(widget.entry);

  @override
  void initState() {
    super.initState();
    Reminders.setFor(_key).then((at) {
      if (mounted) setState(() => _reminding = at);
    });
  }

  Future<void> _toggleReminder() async {
    final e = widget.entry;
    if (_reminding != null) {
      await Reminders.cancel(_key);
      if (mounted) setState(() => _reminding = null);
      return;
    }
    final at = _remindAt!;
    await Reminders.set(
      message: _key,
      at: at,
      title: e.isGroup && (e.threadTitle?.isNotEmpty ?? false)
          ? '${e.sender} in ${e.threadTitle}'
          : e.sender,
      body: e.content,
    );
    if (mounted) setState(() => _reminding = at);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final addressed = Addressed.parse(entry.addressed) ?? Addressed.direct;
    final reminding = _reminding;
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
                  icon: Icons.reply_rounded,
                  filled: true,
                  onTap: () => widget.onReply(entry),
                ),
              if (reminding != null)
                AskPill(
                  label: 'Reminding at ${clockLabel(reminding)}',
                  icon: Icons.alarm_on_rounded,
                  onTap: _toggleReminder,
                )
              else if (_remindAt != null)
                AskPill(
                  label: 'Remind me at ${clockLabel(_remindAt)}',
                  icon: Icons.alarm_rounded,
                  onTap: _toggleReminder,
                ),
              if (looksActionable(entry))
                AskPill(
                  label: 'Add to my list',
                  icon: Icons.checklist_rounded,
                  onTap: () => widget.onAdd(entry),
                ),
            ],
          ),
        ],
      ),
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
    return Material(
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
              Icon(Icons.forum_outlined, size: 20, color: colors.textSecondary),
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
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
