import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/hold_sheet.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/reply_sheet.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/why_sheet.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;

/// The icon on the reason chip.
IconData waitIcon(WaitKind kind) => switch (kind) {
  WaitKind.call => Symbols.call_rounded,
  WaitKind.request => Symbols.front_hand_rounded,
  WaitKind.mention => Symbols.alternate_email_rounded,
  WaitKind.invite => Symbols.event_available_rounded,
  WaitKind.deadline => Symbols.schedule_rounded,
  _ => Symbols.help_rounded,
};

/// How the words of a reply's outcome read.
(IconData, String) replyLine(ReplyOutcome outcome, String to, {String? what}) {
  final thing = what ?? 'Your reply';
  return switch (outcome) {
    ReplyOutcome.sent => (
      Symbols.check_circle_rounded,
      what == null ? 'Sent to $to' : 'Sent $what to $to',
    ),
    ReplyOutcome.written => (
      Symbols.edit_note_rounded,
      '$thing is typed in the chat. Tap send there.',
    ),
    ReplyOutcome.picker => (
      Symbols.edit_note_rounded,
      'Pick $to; ${what ?? 'your reply'} is typed in.',
    ),
    ReplyOutcome.copied => (
      Symbols.content_copy_rounded,
      '$thing is copied. Paste it in the chat.',
    ),
  };
}

/// One person waiting on the owner: who, how long, what they said, why it's
/// here, and what can be done about it. It says what happened to it, then
/// folds away; swiping it away means it's been dealt with some other way.
class WaitingCard extends StatefulWidget {
  final WaitingItem item;
  final int index;

  /// The card has finished leaving.
  final VoidCallback onGone;

  /// Swiped away.
  final VoidCallback onHandled;

  const WaitingCard({
    super.key,
    required this.item,
    required this.index,
    required this.onGone,
    required this.onHandled,
  });

  @override
  State<WaitingCard> createState() => _WaitingCardState();
}

class _WaitingCardState extends State<WaitingCard>
    with TickerProviderStateMixin {
  /// Notification buttons are kept for six hours; until the phone says
  /// otherwise, a fresh message is assumed to have one.
  static const _freshFor = Duration(hours: 6);

  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: 1,
  );

  bool _reacting = false;
  late bool _live = _assumeLive;
  (IconData, String)? _line;
  bool _leaving = false;
  Timer? _timer;

  bool get _assumeLive =>
      DateTime.now().difference(widget.item.message.timestamp) < _freshFor;

  String get _name => widget.item.message.sender;

  @override
  void initState() {
    super.initState();
    _checkRoute();
  }

  @override
  void didUpdateWidget(covariant WaitingCard old) {
    super.didUpdateWidget(old);
    if (old.item.key != widget.item.key) {
      _live = _assumeLive;
    }
    _checkRoute();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _leave.dispose();
    super.dispose();
  }

  /// Reply is offered only while the notification's own button is alive.
  Future<void> _checkRoute() async {
    final route = await ReplySender.routeFor(widget.item.message);
    final live = route == ReplyRoute.send;
    if (mounted && live != _live) setState(() => _live = live);
  }

  void _show((IconData, String) line, {bool thenLeave = true}) {
    setState(() {
      _line = line;
      _reacting = false;
      _leaving = thenLeave;
    });
    _timer?.cancel();
    if (thenLeave) {
      _timer = Timer(const Duration(milliseconds: 1100), () async {
        if (!mounted) return;
        await _leave.reverse();
        if (mounted) widget.onGone();
      });
    } else {
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _line = null);
      });
    }
  }

  void _afterReply(ReplyOutcome outcome, {String? what}) {
    _show(
      replyLine(outcome, _name, what: what),
      thenLeave: outcome == ReplyOutcome.sent,
    );
  }

  Future<void> _reply() async {
    final outcome = await showReplySheet(context, widget.item);
    if (outcome != null && mounted) _afterReply(outcome);
  }

  Future<void> _open({required bool call}) async {
    final name = _name;
    final opened = await ReplySender.open(widget.item.message);
    if (!mounted) return;
    showTodayToast(
      context,
      !opened
          ? 'Couldn’t open that chat'
          : call
          ? 'Opening the chat with $name to call'
          : 'Opening the chat with $name',
    );
  }

  Future<void> _react(String emoji) async {
    setState(() => _reacting = false);
    final outcome = await ReplySender.send(widget.item.message, emoji);
    if (mounted) _afterReply(outcome, what: emoji);
  }

  Future<void> _hold() async {
    final item = widget.item;
    final choice = await showHoldSheet(context, item);
    if (choice == null || !mounted) return;
    final outcome = await ReplySender.send(item.message, choice.text);
    await WaitingStore.markHeld(
      item,
      text: choice.text,
      until: choice.remindAt,
    );
    final at = choice.remindAt;
    if (at != null) {
      await Reminders.set(
        message: item.key,
        at: at,
        title: 'Reply to $_name',
        body: item.message.content,
        thread: item.message.thread,
      );
    }
    if (mounted) {
      showTodayToast(context, holdToast(_name, outcome == ReplyOutcome.sent));
    }
  }

  Future<void> _why() async {
    final item = widget.item;
    final noReply = await showWhySheet(context, item);
    if (noReply != true || !mounted) return;
    await WaitingStore.markNoReplyNeeded(item, notify: false);
    if (mounted) {
      _show((
        Symbols.check_circle_rounded,
        'Off your list. Echo will learn from this',
      ));
    }
  }

  void _openPerson() => context.push('/person', extra: widget.item.personKey);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    final message = item.message;
    final age = ageColors(context, item.ageBand);
    final where = [
      if (message.isGroup && (message.threadTitle?.isNotEmpty ?? false))
        message.threadTitle!,
      appLabel(message.source),
    ].join(' · ');

    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _leave, curve: AppMotion.standard),
      child: FadeTransition(
        opacity: _leave,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(_leave),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: ValueKey('swipe-${item.key}'),
              direction: _leaving
                  ? DismissDirection.none
                  : DismissDirection.horizontal,
              background: const _SwipeHint(alignment: Alignment.centerLeft),
              secondaryBackground: const _SwipeHint(
                alignment: Alignment.centerRight,
              ),
              onDismissed: (_) => widget.onHandled(),
              child: AskCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openPerson,
                      child: Row(
                        children: [
                          PersonAvatar(
                            name: message.sender,
                            size: 40,
                            source: message.source,
                            ring: (
                              age: item.ageBand,
                              progress: item.ageProgress,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.sender,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.nunito(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  where,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.nunito(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                            ),
                            child: item.held
                                ? AgeTag(
                                    text: heldTag(
                                      item.heldUntil,
                                      DateTime.now(),
                                    ),
                                    background: context.selectionFill,
                                    foreground: context.onSelection,
                                  )
                                : AgeTag(
                                    text: item.since,
                                    background: age.bg,
                                    foreground: age.fg,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openPerson,
                      child: Text(
                        '“${message.content}”',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _WhyLine(reason: item.reason, onTap: _why),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topLeft,
                        children: [...previous, ?current],
                      ),
                      child: _line != null
                          ? _SentLine(key: const ValueKey('sent'), line: _line!)
                          : _reacting
                          ? _Reactions(
                              key: const ValueKey('reacting'),
                              onClose: () => setState(() => _reacting = false),
                              onPick: _react,
                            )
                          : _actions(item),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(WaitingItem item) {
    final call = item.reason.kind == WaitKind.call;
    final (primary, icon, tap) = call
        ? ('Call', Symbols.call_rounded, () => _open(call: true))
        : _live
        ? ('Reply', Symbols.reply_rounded, _reply)
        : ('Open chat', Symbols.open_in_new_rounded, () => _open(call: false));
    return Wrap(
      key: const ValueKey('actions'),
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AskPill(label: primary, icon: icon, filled: true, onTap: tap),
        if (_live)
          _RoundIcon(
            icon: Symbols.add_reaction_rounded,
            label: 'React',
            onTap: () => setState(() => _reacting = true),
          ),
        if (_live)
          AskPill(
            label: item.held ? 'Held' : 'Hold reply',
            icon: Symbols.schedule_send_rounded,
            set: item.held,
            onTap: item.held ? null : _hold,
          ),
      ],
    );
  }
}

/// The reason chip, left-aligned and only as wide as its words: icon, reason,
/// and "Why?" behind a hairline.
class _WhyLine extends StatefulWidget {
  final WaitReason reason;
  final VoidCallback onTap;
  const _WhyLine({required this.reason, required this.onTap});

  @override
  State<_WhyLine> createState() => _WhyLineState();
}

class _WhyLineState extends State<_WhyLine> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = GoogleFonts.nunito(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: c.textSecondary,
    );
    return Semantics(
      button: true,
      label: '${widget.reason.label}. Why?',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
          decoration: BoxDecoration(
            color: c.textPrimary.withValues(alpha: _down ? 0.10 : 0.05),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                waitIcon(widget.reason.kind),
                size: 15,
                color: c.primaryGreen,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  widget.reason.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: c.dividerColor)),
                ),
                child: Text(
                  'Why?',
                  style: style.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.primaryGreen,
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

class _SentLine extends StatelessWidget {
  final (IconData, String) line;
  const _SentLine({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(line.$1, size: 18, fill: 1, color: c.primaryGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line.$2,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: c.primaryGreen,
            ),
          ),
        ),
      ],
    );
  }
}

class _Reactions extends StatelessWidget {
  final VoidCallback onClose;
  final ValueChanged<String> onPick;
  const _Reactions({super.key, required this.onClose, required this.onPick});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundIcon(icon: Symbols.close_rounded, label: 'Close', onTap: onClose),
        const SizedBox(width: 8),
        QuickReactions(onPick: onPick),
      ],
    ),
  );
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoundIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: PressFeedback(
        scale: 0.85,
        child: Material(
          color: Colors.transparent,
          shape: CircleBorder(
            side: BorderSide(color: c.textPrimary.withValues(alpha: 0.35)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 20, color: c.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  final Alignment alignment;
  const _SwipeHint({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: context.selectionFill.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.check_rounded, size: 18, color: c.primaryGreen),
          const SizedBox(width: 6),
          Text(
            'Handled',
            style: GoogleFonts.nunito(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: c.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}
