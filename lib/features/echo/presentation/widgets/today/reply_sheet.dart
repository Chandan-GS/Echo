import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/services/engine_gate.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/ask/ask_intents.dart';
import 'package:project_echo/features/echo/data/reply/reply_drafter.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_parts.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;

/// Replying from Today. Returns how it went, or null if nothing was sent.
Future<ReplyOutcome?> showReplySheet(BuildContext context, WaitingItem item) =>
    showTodaySheet<ReplyOutcome>(context, (_) => _ReplySheet(item: item));

class _ReplySheet extends StatefulWidget {
  final WaitingItem item;
  const _ReplySheet({required this.item});

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _controller = TextEditingController();
  bool _drafting = false;
  bool _hasDraft = false;
  bool _sending = false;

  /// The owner has typed, so a draft arriving late mustn't overwrite it.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _draftIfReady();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A first draft, only when an engine can already write. This never asks
  /// for one: choosing one waits for the owner to tap "Write it for me".
  Future<void> _draftIfReady() async {
    if (await EngineGate.current() == null) return;
    await _write();
  }

  Future<void> _write({String? gist}) async {
    if (_drafting) return;
    setState(() => _drafting = true);
    final text = await ReplyDrafter.draft(
      ReplyRequest(widget.item.message, gist),
    );
    if (!mounted) return;
    setState(() {
      _drafting = false;
      if (text.isEmpty) return;
      if (!_touched || gist != null) {
        _controller.text = text;
        _hasDraft = true;
        _touched = false;
      }
    });
    if (text.isEmpty && gist == null) {
      showTodayToast(context, 'Couldn’t write one here. Type your reply.');
    }
  }

  Future<void> _redraft() async {
    if (_drafting) return;
    final ready = await EngineGate.ensure(context, reason: 'draft');
    if (!ready || !mounted) return;
    final current = _controller.text.trim();
    await _write(gist: current.isEmpty ? null : current);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      showTodayToast(context, 'Write something first, or let Echo write it');
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    final outcome = await ReplySender.send(widget.item.message, text);
    if (mounted) Navigator.of(context).pop(outcome);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (mounted) showTodayToast(context, 'Copied');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final message = widget.item.message;
    return TodaySheetBody(
      children: [
        Row(
          children: [
            SourceBadge(message, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Reply to '),
                    TextSpan(
                      text: message.sender,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    TextSpan(text: ' on ${appLabel(message.source)}'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(fontSize: 14, color: c.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${message.sender}: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                TextSpan(text: '“${message.content}”'),
              ],
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 13,
              height: 1.4,
              color: c.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _touched = true,
          style: GoogleFonts.nunito(
            fontSize: 16,
            height: 1.4,
            color: c.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: _drafting ? 'Echo is writing…' : 'Write your reply…',
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AskPill(
              label: _sending ? 'Sending…' : 'Send',
              icon: Symbols.send_rounded,
              filled: true,
              onTap: _sending ? null : _send,
            ),
            AskPill(
              label: _drafting
                  ? 'Writing…'
                  : _hasDraft
                  ? 'Rewrite'
                  : 'Write it for me',
              icon: Symbols.auto_awesome_rounded,
              onTap: _drafting ? null : _redraft,
            ),
            Semantics(
              button: true,
              label: 'Copy',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _copy,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.textPrimary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(
                    Symbols.content_copy_rounded,
                    size: 20,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            'Goes out from your own ${appLabel(message.source)}, through its '
            'notification. Nothing is sent until you tap Send.',
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              height: 1.4,
              color: c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
