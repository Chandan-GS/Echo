import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/phone_actions.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/data/desktop_actions.dart';
import 'package:project_echo/features/desktop/presentation/today/reply_suggestions.dart';
import 'package:project_echo/features/desktop/presentation/today/today_logic.dart';
import 'package:project_echo/features/desktop/presentation/today/today_parts.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';

/// What the owner can do about the selected row, all of it done through
/// the phone.
class TodayActions {
  final ValueChanged<String> send;
  final VoidCallback remind;
  final VoidCallback addToList;

  /// "Mark handled", "Mark read", "Did it".
  final VoidCallback handle;
  final VoidCallback catchUp;

  /// Back from the reply field to the list's keys.
  final VoidCallback leaveReply;

  const TodayActions({
    required this.send,
    required this.remind,
    required this.addToList,
    required this.handle,
    required this.catchUp,
    required this.leaveReply,
  });
}

/// The middle column: the selected row's chat and what to do about it.
class TodayDetail extends StatelessWidget {
  final TriageItem item;
  final List<ChatLine> lines;
  final DateTime now;

  /// Marked handled (or read, or done) here, not by replying.
  final bool marked;

  /// The latest reply sent from here, with how it's going.
  final PhoneAction? reply;
  final ReplyRoute route;

  /// When Echo would remind, and when a reminder is already set for.
  final DateTime? remindAt;
  final DateTime? reminding;
  final bool onList;
  final String? summary;
  final FocusNode replyFocus;
  final TodayActions actions;

  const TodayDetail({
    super.key,
    required this.item,
    required this.lines,
    required this.now,
    required this.marked,
    required this.reply,
    required this.route,
    required this.remindAt,
    required this.reminding,
    required this.onList,
    required this.summary,
    required this.replyFocus,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final group = item.kind == TriageKind.group;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
      children: [
        _Header(item: item, onHandle: marked ? null : actions.handle),
        const SizedBox(height: 16),
        AskCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelLabel(
                group ? 'Latest in the group' : 'The conversation',
                trailing: group ? null : 'From Echo’s memory of this chat',
              ),
              const SizedBox(height: 12),
              _Bubbles(lines),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: AppMotion.medium,
          switchInCurve: AppMotion.emphasized,
          child: KeyedSubtree(
            key: ValueKey(
              '${item.id}·$marked·${reply?.id}·${reply?.state.name}',
            ),
            child: _action(context),
          ),
        ),
      ],
    );
  }

  Widget _action(BuildContext context) {
    final setLabel = reminding == null
        ? null
        : 'Reminding ${whenLabel(reminding!, now)}';
    final remindButton = setLabel != null
        ? DeskButton(
            label: setLabel,
            icon: Symbols.notifications_active_rounded,
            style: DeskButtonStyle.set,
          )
        : remindAt == null
        ? null
        : DeskButton(
            label: 'Remind me ${whenLabel(remindAt!, now)}',
            icon: Symbols.alarm_rounded,
            keyHint: 'H',
            onTap: actions.remind,
          );
    switch (item.kind) {
      case TriageKind.group:
        if (marked) return const _DoneCard('Marked read');
        final latest = item.entry;
        return AskCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Said(
                lead: summary == null ? null : 'Echo: ',
                text:
                    summary ??
                    (latest.sender.isEmpty
                        ? latest.content
                        : '${latest.sender}: ${latest.content}'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DeskButton(
                    label: 'Catch me up in Ask',
                    icon: Symbols.forum_rounded,
                    style: DeskButtonStyle.filled,
                    onTap: actions.catchUp,
                  ),
                  DeskButton(
                    label: 'Mark read',
                    icon: Symbols.done_all_rounded,
                    keyHint: 'E',
                    onTap: actions.handle,
                  ),
                ],
              ),
            ],
          ),
        );
      case TriageKind.promise:
        if (marked) return const _DoneCard('Done');
        return AskCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Said(text: promiseLine(item.name, item.entry.content)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ?remindButton,
                  _listButton('Add to To-do'),
                  DeskButton(
                    label: 'Did it',
                    icon: Symbols.done_rounded,
                    keyHint: 'E',
                    onTap: actions.handle,
                  ),
                ],
              ),
            ],
          ),
        );
      case TriageKind.waiting:
        final sent = reply;
        if (sent != null && sent.state != ActionState.failed) {
          return _ReplyState(sent, now: now);
        }
        if (marked) return const _DoneCard('Marked handled');
        return _Compose(
          key: ValueKey(item.id),
          item: item,
          lines: lines,
          route: route,
          failed: sent,
          focus: replyFocus,
          actions: actions,
          trailing: [?remindButton, _listButton('To-do')],
        );
    }
  }

  Widget _listButton(String label) => onList
      ? const DeskButton(
          label: 'On your list',
          icon: Symbols.checklist_rounded,
          style: DeskButtonStyle.set,
        )
      : DeskButton(
          label: label,
          icon: Symbols.checklist_rounded,
          keyHint: 'T',
          onTap: actions.addToList,
        );
}

class _Header extends StatelessWidget {
  final TriageItem item;
  final VoidCallback? onHandle;
  const _Header({required this.item, required this.onHandle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final group = item.kind == TriageKind.group;
    return Row(
      children: [
        SourceBadge(item.entry, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: item.kind == TriageKind.promise ? 'You' : item.name,
                    ),
                    if (!group)
                      TextSpan(
                        text: ' · ${item.where}',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: c.textSecondary,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                group
                    ? '${item.where} today'
                    : 'Today at ${clockLabel(item.entry.timestamp)}',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
        DeskIconButton(
          icon: Symbols.smartphone_rounded,
          tooltip: 'Open on phone',
          onTap: () {
            DesktopActions.openChat(item.entry);
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                width: 420,
                content: Text('Tap the notification on your phone to open it.'),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
        DeskIconButton(
          icon: Symbols.done_all_rounded,
          tooltip: group ? 'Mark read (E)' : 'Mark handled (E)',
          onTap: onHandle,
        ),
      ],
    );
  }
}

/// The chat as bubbles: the owner's on the right in ink, the selected
/// message ringed in green.
class _Bubbles extends StatelessWidget {
  final List<ChatLine> lines;
  const _Bubbles(this.lines);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, l) in lines.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          Align(
            alignment: l.mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.78),
              child: _Bubble(l),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  final ChatLine line;
  const _Bubble(this.line);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = line.mine && !line.picked;
    final bg = line.picked
        ? Color.alphaBlend(
            context.selectionFill.withValues(alpha: 0.45),
            c.surface,
          )
        : mine
        ? c.textPrimary
        : c.background;
    final fg = mine ? c.surface : c.textPrimary;
    const r = Radius.circular(16), tail = Radius.circular(6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: line.mine
            ? const BorderRadius.only(
                topLeft: r,
                topRight: r,
                bottomLeft: r,
                bottomRight: tail,
              )
            : const BorderRadius.only(
                topLeft: r,
                topRight: r,
                bottomLeft: tail,
                bottomRight: r,
              ),
        border: Border.all(
          color: line.picked
              ? c.primaryGreen
              : mine
              ? c.textPrimary
              : c.dividerColor,
          width: line.picked ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.who,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: mine ? c.surface.withValues(alpha: 0.7) : c.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            line.text,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.45,
              color: fg,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            clockLabel(line.at),
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: mine ? c.surface.withValues(alpha: 0.6) : context.faint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reply suggestions, an emoji, or the owner's own words, and the buttons
/// that send it or set it aside.
class _Compose extends StatefulWidget {
  final TriageItem item;
  final List<ChatLine> lines;
  final ReplyRoute route;

  /// The last reply, when the phone couldn't send it.
  final PhoneAction? failed;
  final FocusNode focus;
  final TodayActions actions;

  /// Remind and To-do, after Send.
  final List<Widget> trailing;

  const _Compose({
    super.key,
    required this.item,
    required this.lines,
    required this.route,
    required this.failed,
    required this.focus,
    required this.actions,
    required this.trailing,
  });

  @override
  State<_Compose> createState() => _ComposeState();
}

class _ComposeState extends State<_Compose> {
  late final _text = TextEditingController(
    text: widget.failed?.body['text']?.toString() ?? '',
  )..addListener(() => setState(() {}));
  late final _suggestions = ReplySuggestions.forEntry(
    widget.item.entry,
    widget.lines,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      widget.focus.requestFocus();
      return;
    }
    widget.actions.send(text);
  }

  void _pick(String s) {
    _text.value = TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
    widget.focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final failed = widget.failed;
    return AskCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed != null) ...[
            _StatusLine(failed, now: DateTime.now()),
            const SizedBox(height: 12),
          ],
          const PanelLabel('Reply'),
          const SizedBox(height: 12),
          FutureBuilder<List<String>>(
            future: _suggestions,
            builder: (context, snap) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in snap.data ?? const ['…', '…', '…'])
                  _Suggestion(
                    text: s,
                    on: s == _text.text,
                    onTap: snap.hasData ? () => _pick(s) : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Or just send',
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              QuickReactions(onPick: widget.actions.send),
            ],
          ),
          const SizedBox(height: 12),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _send,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _send,
              const SingleActivator(LogicalKeyboardKey.escape):
                  widget.actions.leaveReply,
            },
            child: TextField(
              controller: _text,
              focusNode: widget.focus,
              minLines: 3,
              maxLines: 6,
              cursorColor: c.primaryGreen,
              style: GoogleFonts.nunito(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                height: 1.5,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Write a reply, or pick one above…',
                hintStyle: GoogleFonts.nunito(
                  fontSize: 14.5,
                  color: context.faint,
                ),
                filled: true,
                fillColor: c.background,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.primaryGreen),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DeskButton(
                label: 'Send through phone',
                icon: Symbols.send_rounded,
                keyHint: '⌘↵',
                style: DeskButtonStyle.green,
                onTap: _send,
              ),
              ...widget.trailing,
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Symbols.smartphone_rounded,
                size: 16,
                color: c.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.route == ReplyRoute.send
                      ? 'Sends through the notification on your phone'
                      : 'Shows on your phone, ready to send',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
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

class _Suggestion extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback? onTap;
  const _Suggestion({required this.text, required this.on, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final waiting = onTap == null;
    return PressFeedback(
      haptic: false,
      enabled: !waiting,
      child: Material(
        color: on
            ? Color.alphaBlend(
                context.selectionFill.withValues(alpha: 0.4),
                c.surface,
              )
            : c.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: on ? c.primaryGreen : c.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              text,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: waiting ? context.faint : c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A reply sent from here: how it's going, and what was said.
class _ReplyState extends StatelessWidget {
  final PhoneAction reply;
  final DateTime now;
  const _ReplyState(this.reply, {required this.now});

  @override
  Widget build(BuildContext context) => AskCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusLine(reply, now: now),
        const SizedBox(height: 6),
        Text(
          '“${reply.body['text']}”',
          style: GoogleFonts.nunito(
            fontSize: 14,
            height: 1.45,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _StatusLine extends StatelessWidget {
  final PhoneAction action;
  final DateTime now;
  const _StatusLine(this.action, {required this.now});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (stage, text) = replyStatus(action, now);
    final color = switch (stage) {
      ReplyStage.sent || ReplyStage.ready => c.primaryGreen,
      ReplyStage.failed => context.warmAccent,
      _ => c.textSecondary,
    };
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: switch (stage) {
            ReplyStage.going => Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
            ),
            ReplyStage.slow => Icon(
              Symbols.wifi_rounded,
              size: 20,
              color: color,
            ),
            ReplyStage.sent => Icon(
              Symbols.check_circle_rounded,
              size: 20,
              fill: 1,
              color: color,
            ),
            ReplyStage.ready => Icon(
              Symbols.smartphone_rounded,
              size: 20,
              color: color,
            ),
            ReplyStage.failed => Icon(
              Symbols.error_rounded,
              size: 20,
              color: color,
            ),
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _DoneCard extends StatelessWidget {
  final String text;
  const _DoneCard(this.text);

  @override
  Widget build(BuildContext context) {
    final green = context.colors.primaryGreen;
    return AskCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Symbols.check_circle_rounded, size: 20, fill: 1, color: green),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: green,
            ),
          ),
        ],
      ),
    );
  }
}

/// A line Echo or the owner said, with an optional green lead ("Echo: ").
class _Said extends StatelessWidget {
  final String? lead;
  final String text;
  const _Said({this.lead, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          if (lead != null)
            TextSpan(
              text: lead,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.primaryGreen,
              ),
            ),
          TextSpan(text: text),
        ],
      ),
      style: GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: c.textPrimary,
      ),
    );
  }
}
