import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/phone_actions.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/today/reply_suggestions.dart';
import 'package:project_echo/features/desktop/presentation/today/today_logic.dart';
import 'package:project_echo/features/desktop/presentation/today/today_parts.dart';
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
    required this.remindAt,
    required this.reminding,
    required this.onList,
    required this.summary,
    required this.replyFocus,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(item: item, onHandle: marked ? null : actions.handle),
                const SizedBox(height: 22),
                _Message(_said),
                const SizedBox(height: 28),
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
            ),
          ),
        ),
      ],
    );
  }

  /// What the row is about, in a line or two: the message waiting on the
  /// owner, what they promised, or what a busy group is on about.
  String get _said => switch (item.kind) {
    TriageKind.waiting => item.entry.content,
    TriageKind.promise => promiseLine(item.name, item.entry.content),
    TriageKind.group =>
      summary ??
          (item.entry.sender.isEmpty
              ? item.entry.content
              : '${item.entry.sender}: ${item.entry.content}'),
  };

  Widget _action(BuildContext context) {
    final setLabel = reminding == null
        ? null
        : 'Reminding ${whenLabel(reminding!, now)}';
    final remindButton = setLabel != null
        ? DeskButton(label: setLabel, style: DeskButtonStyle.set)
        : remindAt == null
        ? null
        : DeskButton(
            label: 'Remind me ${whenLabel(remindAt!, now)}',
            onTap: actions.remind,
          );
    switch (item.kind) {
      case TriageKind.group:
        if (marked) return const _DoneCard('Marked read');
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DeskButton(
              label: 'Catch me up',
              style: DeskButtonStyle.green,
              onTap: actions.catchUp,
            ),
            DeskButton(label: 'Mark read', onTap: actions.handle),
          ],
        );
      case TriageKind.promise:
        if (marked) return const _DoneCard('Done');
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ?remindButton,
            _listButton('Add to To-do'),
            DeskButton(label: 'Did it', onTap: actions.handle),
          ],
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
          failed: sent,
          focus: replyFocus,
          actions: actions,
          trailing: [?remindButton, _listButton('Add to To-do')],
        );
    }
  }

  Widget _listButton(String label) => onList
      ? const DeskButton(label: 'On your list', style: DeskButtonStyle.set)
      : DeskButton(label: label, onTap: actions.addToList);
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.kind == TriageKind.promise ? 'You promised' : item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.oldStandardTt(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                group
                    ? '${item.where} today'
                    : '${item.where} · ${clockLabel(item.entry.timestamp)}',
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
          icon: Symbols.done_all_rounded,
          tooltip: group ? 'Mark read (E)' : 'Mark handled (E)',
          onTap: onHandle,
        ),
      ],
    );
  }
}

/// The message itself, set large: what the owner is here to answer.
class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) => SelectableText(
    text,
    style: GoogleFonts.nunito(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      height: 1.55,
      color: context.colors.textPrimary,
    ),
  );
}

/// Reply suggestions, an emoji, or the owner's own words, and the buttons
/// that send it or set it aside.
class _Compose extends StatefulWidget {
  final TriageItem item;
  final List<ChatLine> lines;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failed != null) ...[
          _StatusLine(failed, now: DateTime.now()),
          const SizedBox(height: 12),
        ],
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
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _send,
            const SingleActivator(LogicalKeyboardKey.escape):
                widget.actions.leaveReply,
          },
          child: TextField(
            controller: _text,
            focusNode: widget.focus,
            minLines: 2,
            maxLines: 6,
            cursorColor: c.primaryGreen,
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.5,
              color: c.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Reply…',
              hintStyle: GoogleFonts.nunito(fontSize: 15, color: context.faint),
              filled: true,
              fillColor: c.surface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
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
              label: 'Send',
              keyHint: '⌘↵',
              style: DeskButtonStyle.green,
              onTap: _send,
            ),
            ...widget.trailing,
          ],
        ),
      ],
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
  Widget build(BuildContext context) => Column(
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
    return Row(
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
    );
  }
}
