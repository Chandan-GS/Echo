import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/history/presentation/widgets/history_parts.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';

/// The full message and what can be done with it.
Future<void> showHistoryItemSheet(BuildContext context, RawData entry) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 460),
      curve: Cubic(0.2, 0.9, 0.25, 1),
      reverseDuration: Duration(milliseconds: 240),
      reverseCurve: Curves.easeInCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (_) => _HistoryItemSheet(
      entry: entry,
      messenger: ScaffoldMessenger.of(context),
      router: GoRouter.of(context),
      todos: context.read<TodoCubit>(),
    ),
  );
}

class _HistoryItemSheet extends StatefulWidget {
  final RawData entry;
  final ScaffoldMessengerState messenger;
  final GoRouter router;
  final TodoCubit todos;

  const _HistoryItemSheet({
    required this.entry,
    required this.messenger,
    required this.router,
    required this.todos,
  });

  @override
  State<_HistoryItemSheet> createState() => _HistoryItemSheetState();
}

class _HistoryItemSheetState extends State<_HistoryItemSheet> {
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  bool _replying = false;
  bool _sending = false;
  int? _todoId;

  RawData get _e => widget.entry;

  bool get _canOpen => packageOfThread(_e.thread) != null;
  bool get _canReply => _e.addressed != null && _e.sent != true;

  String get _firstName =>
      _e.sender.split(' · ').first.replaceFirst('You to ', '');

  String get _question {
    if (_e.isGroup && (_e.threadTitle?.isNotEmpty ?? false)) {
      return 'Catch me up on ${_e.threadTitle}';
    }
    if (_e.sent == true) return 'Did $_firstName answer me?';
    if (_e.addressed == null) return 'What did ${appLabel(_e.source)} send me this week?';
    return 'What else did $_firstName say this week?';
  }

  @override
  void dispose() {
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _toast(String message) => widget.messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _open() async {
    final opened = await ReplySender.open(_e);
    if (!opened) _toast("Couldn't open ${appLabel(_e.source)}");
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleReply() {
    setState(() => _replying = !_replying);
    if (_replying) _replyFocus.requestFocus();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) {
      _replyFocus.requestFocus();
      _toast('Type a reply first');
      return;
    }
    setState(() => _sending = true);
    final outcome = await ReplySender.send(_e, text);
    if (!mounted) return;
    Navigator.of(context).pop();
    _toast(switch (outcome) {
      ReplyOutcome.sent => 'Sent to $_firstName',
      ReplyOutcome.written => 'Written in ${appLabel(_e.source)}. Tap send there.',
      ReplyOutcome.picker => 'Pick the chat in ${appLabel(_e.source)} to send it.',
      ReplyOutcome.copied => 'Copied. Paste it in ${appLabel(_e.source)}.',
    });
  }

  Future<void> _toggleTodo() async {
    final id = _todoId;
    if (id != null) {
      setState(() => _todoId = null);
      await widget.todos.remove(id);
      _toast('Taken off your to-do list');
      return;
    }
    final item = await widget.todos.addTyped(_e.content);
    if (!mounted || item == null) return;
    setState(() => _todoId = item.id);
    _toast('Added to your to-do list');
  }

  void _ask() {
    Navigator.of(context).pop();
    widget.router.push('/echo/chat', extra: _question);
  }

  String _dayText() {
    final now = DateTime.now();
    final day = DateTime(_e.timestamp.year, _e.timestamp.month, _e.timestamp.day);
    final label = historyDayLabel(day, now);
    final prefix = label == 'Today' || label == 'Yesterday' ? '' : 'On ';
    return '$prefix$label, ${clockTime(_e.timestamp)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tags = historyTags(context, _e);
    final addressed = Addressed.parse(_e.addressed);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    HistoryAppIcon(source: _e.source, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appLabel(_e.source),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: c.primaryGreen,
                        ),
                      ),
                    ),
                    Text(
                      clockTime(_e.timestamp),
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_e.who, style: Theme.of(context).textTheme.displayMedium),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: tags),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SelectableText(
                    _e.content,
                    style: GoogleFonts.nunito(
                      fontSize: 17,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _Fact(Symbols.schedule_rounded, _dayText(), strong: true),
                if (addressed != null && addressed != Addressed.group)
                  _Fact(
                    Symbols.alternate_email_rounded,
                    addressed == Addressed.mentioned
                        ? 'Addressed to you by name, so it was on Today.'
                        : 'Addressed to you, so it was on Today.',
                  ),
                if (_e.heldAt != null)
                  const _Fact(
                    Symbols.bedtime_rounded,
                    'Held by quiet hours, then given back when they ended.',
                  ),
                if (_e.swipedAt != null)
                  _Fact(
                    Symbols.swipe_left_rounded,
                    'You swiped it away at ${clockTime(_e.swipedAt!)}. Echo kept a copy.',
                  ),
                if (_e.sent == true)
                  const _Fact(
                    Symbols.north_east_rounded,
                    'You sent this through Echo.',
                  ),
                if (_canOpen) ...[
                  const SizedBox(height: 14),
                  _SolidButton(
                    icon: Symbols.open_in_new_rounded,
                    label: 'Open in ${appLabel(_e.source)}',
                    onTap: _open,
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_canReply)
                      _Pill(
                        icon: Symbols.reply_rounded,
                        label: 'Reply',
                        on: _replying,
                        onTap: _toggleReply,
                      ),
                    _Pill(
                      icon: _todoId != null
                          ? Symbols.check_rounded
                          : Symbols.checklist_rounded,
                      label: _todoId != null
                          ? 'On your to-do list'
                          : 'Add to my to-do list',
                      on: _todoId != null,
                      onTap: _toggleTodo,
                    ),
                    _Pill(
                      icon: Symbols.auto_awesome_rounded,
                      label: 'Ask Echo about this',
                      onTap: _ask,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _replying
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _replyBox(context),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (_canReply && _e.swipedAt != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'This notification is gone from your shade, so ${appLabel(_e.source)} '
                    "may not take a reply from it any more. If not, Echo copies "
                    'your reply and opens the chat.',
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      height: 1.45,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _replyBox(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _reply,
            focusNode: _replyFocus,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: c.primaryGreen,
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Your reply',
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Send',
          child: PressFeedback(
            child: GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.arrow_upward_rounded,
                  size: 20,
                  color: c.textInverse,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool strong;
  const _Fact(this.icon, this.text, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? c.textPrimary : c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolidButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SolidButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: c.buttonDark,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: c.textInverse),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: c.textInverse,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.on = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = on ? context.onSelection : c.textPrimary;
    return PressFeedback(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: on ? context.selectionFill : c.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: on
                  ? Colors.transparent
                  : c.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
