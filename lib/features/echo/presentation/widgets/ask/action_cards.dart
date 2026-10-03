import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What Echo put on the to-do list: the same rows as on Home, under a
/// heading saying which list, with an undo.
class AddedCard extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onUndo;
  const AddedCard({super.key, required this.message, required this.onUndo});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (message.undone || message.added.isEmpty) {
      return Text(
        message.undone ? 'Taken off your list again.' : message.text,
        style: GoogleFonts.nunito(
          fontSize: 15.5,
          height: 1.5,
          color: colors.textPrimary,
        ),
      );
    }
    return AskCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AddedHeading(
            list: addedTo(message.added, DateTime.now()),
            onUndo: onUndo,
          ),
          for (var i = 0; i < message.added.length; i++)
            TodoLine(message.added[i], first: i == 0),
        ],
      ),
    );
  }
}

/// "Added to tomorrow", with Echo's happy face and an undo.
class AddedHeading extends StatelessWidget {
  final String list;
  final VoidCallback onUndo;
  const AddedHeading({super.key, required this.list, required this.onUndo});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const EchoMascot(
            state: EchoState.happy,
            size: 26,
            showRings: false,
            glow: false,
          ),
          const SizedBox(width: 8),
          Text(
            'Added to $list',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onUndo,
            child: Text(
              'Undo',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: colors.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A reply Echo drafted: the message in the to-do card's recessed box, and
/// how it would go out. Nothing is sent until Send is tapped.
class DraftCard extends StatefulWidget {
  final ReplyDraft draft;
  final VoidCallback onSend;
  final ValueChanged<String> onEdit;

  /// "Not now", offered in voice mode where there's no other way to say no.
  final VoidCallback? onDismiss;

  const DraftCard({
    super.key,
    required this.draft,
    required this.onSend,
    required this.onEdit,
    this.onDismiss,
  });

  @override
  State<DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<DraftCard> {
  late final _text = TextEditingController(text: widget.draft.text);
  final _focus = FocusNode();
  var _editing = false;

  @override
  void didUpdateWidget(covariant DraftCard old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.draft.text != _text.text) {
      _text.text = widget.draft.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    if (_editing) widget.onEdit(_text.text.trim());
    setState(() => _editing = !_editing);
    if (_editing) _focus.requestFocus();
  }

  String get _sendLabel => switch (widget.draft.route) {
    ReplyRoute.send => 'Send',
    ReplyRoute.write || ReplyRoute.pick => 'Open in ${_app()}',
    ReplyRoute.copy => 'Copy and open chat',
  };

  /// "WhatsApp", "Slack": the app the chat is in.
  String _app() {
    final source = widget.draft.to.source;
    return source.toLowerCase() == 'whatsapp' ? 'WhatsApp' : source;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final d = widget.draft;
    final body = GoogleFonts.nunito(
      fontSize: 15,
      height: 1.4,
      color: colors.textPrimary,
    );
    return AskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SourceBadge(d.to),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: d.to.isGroup ? 'Reply in ' : 'Reply to '),
                      TextSpan(
                        text: d.chatName,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Color.lerp(colors.background, colors.surface, 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: d.status == DraftStatus.writing
                ? Text(
                    'Writing a reply…',
                    style: body.copyWith(
                      fontStyle: FontStyle.italic,
                      color: colors.textSecondary,
                    ),
                  )
                : _editing
                ? TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 6,
                    style: body,
                    cursorColor: colors.primaryGreen,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Your reply',
                    ),
                  )
                : Text(
                    d.text.isEmpty ? 'Tap Edit to write it' : d.text,
                    style: body,
                  ),
          ),
          const SizedBox(height: 10),
          _status(context),
        ],
      ),
    );
  }

  Widget _status(BuildContext context) {
    final colors = context.colors;
    final d = widget.draft;
    Widget note(IconData icon, String text) => Row(
      children: [
        Icon(
          icon,
          size: 18,
          fill: icon == Symbols.check_circle_rounded ? 1 : 0,
          color: colors.primaryGreen,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: colors.primaryGreen,
            ),
          ),
        ),
      ],
    );
    return switch (d.status) {
      DraftStatus.writing => const SizedBox.shrink(),
      DraftStatus.ready => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AskPill(
            label: _sendLabel,
            icon: Symbols.send_rounded,
            filled: true,
            onTap: d.text.trim().isEmpty && !_editing
                ? null
                : () {
                    if (_editing) _toggleEdit();
                    widget.onSend();
                  },
          ),
          AskPill(
            label: _editing ? 'Done' : 'Edit',
            icon: _editing ? Symbols.check_rounded : Symbols.edit_rounded,
            onTap: _toggleEdit,
          ),
          if (widget.onDismiss != null)
            AskPill(label: 'Not now', onTap: widget.onDismiss),
          // The copy buttons already copy; the others get a copy of their own.
          if (!_editing &&
              d.text.trim().isNotEmpty &&
              d.route != ReplyRoute.copy)
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Symbols.content_copy_rounded,
                size: 19,
                color: colors.textSecondary,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: d.text));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Copied')));
              },
            ),
        ],
      ),
      DraftStatus.sending => note(Symbols.schedule_rounded, 'Sending…'),
      DraftStatus.sent => note(
        Symbols.check_circle_rounded,
        'Sent to ${d.chatName}'
        '${d.doneAt == null ? '' : ' · ${clockLabel(d.doneAt!)}'}',
      ),
      DraftStatus.written => note(
        Symbols.edit_note_rounded,
        'Written in ${d.chatName} in ${_app()}. Tap send there.',
      ),
      DraftStatus.picker => note(
        Symbols.edit_note_rounded,
        'Pick ${d.chatName} in ${_app()}; your reply is written in.',
      ),
      DraftStatus.copied => note(
        Symbols.content_copy_rounded,
        'Copied. Paste it in the chat.',
      ),
      DraftStatus.dismissed => Text(
        'Not sent.',
        style: GoogleFonts.nunito(fontSize: 14, color: colors.textSecondary),
      ),
    };
  }
}
