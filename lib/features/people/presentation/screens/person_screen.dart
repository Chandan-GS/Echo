import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/presentation/widgets/person_photo_sheet.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/engine_gate.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/people/data/person_detail.dart';
import 'package:project_echo/features/people/data/person_loops.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart';
import 'package:project_echo/features/people/presentation/widgets/person_draft_sheet.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';

/// One person: what's open both ways, the recent conversation, and whether
/// Echo should keep an eye on them.
class PersonScreen extends StatefulWidget {
  final String personKey;

  /// Replaces reading the person, for tests.
  @visibleForTesting
  final Future<PersonDetail> Function(String key, DateTime now)? loader;

  const PersonScreen({super.key, required this.personKey, this.loader});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  PersonDetail? _d;
  int _loadId = 0;
  final Set<String> _ticked = {};

  @override
  void initState() {
    super.initState();
    PeopleStore.changed.addListener(_load);
    TodoStore.changed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    PeopleStore.changed.removeListener(_load);
    TodoStore.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    final d = await (widget.loader ?? PersonDetailStore.load)(
      widget.personKey,
      DateTime.now(),
    );
    if (!mounted || id != _loadId) return;
    setState(() => _d = d);
  }

  String _lineKey(OweLine l) =>
      l.waiting != null
          ? 'w${l.at.millisecondsSinceEpoch}'
          : l.todo != null
          ? 't${l.todo!.id}'
          : 'm${l.money!.line.key}';

  Future<void> _tick(OweLine line) async {
    final key = _lineKey(line);
    if (_ticked.contains(key)) return;
    setState(() => _ticked.add(key));
    final first = _d?.first ?? '';
    final now = DateTime.now();
    if (line.money != null) {
      await PeopleStore.markPaid(line.money!.line.key, now);
    } else if (line.todo != null) {
      await PeopleStore.tickTodo(line.todo!, now);
    } else if (line.waiting != null) {
      await WaitingStore.markHandled(line.waiting!);
      PeopleStore.changed.value++;
    }
    if (mounted) {
      showPeopleSnack(context, 'Done. That’s off your list for $first.');
    }
  }

  Future<void> _message(PersonDraftKind kind) async {
    final d = _d;
    if (d == null) return;
    final sent = await showPersonDraftSheet(
      context,
      PersonDraft(
        kind: kind,
        name: d.summary.name,
        source: d.summary.source,
        to: d.replyTo,
        context: d.timeline.isEmpty || kind == PersonDraftKind.wish
            ? null
            : _quote(d.timeline.last, d.first),
      ),
    );
    if (sent == null) return;
    if (kind == PersonDraftKind.wish) {
      await PeopleStore.markWished(d.summary.key, DateTime.now());
    }
    _load();
  }

  String _quote(TimelineLine l, String first) =>
      '${l.mine ? 'You' : first}: “${clip(l.text, 110)}”';

  Future<void> _openChat() async {
    final to = _d?.replyTo;
    if (to == null) return;
    final ok = await ReplySender.open(to);
    if (!ok && mounted) {
      showPeopleSnack(context, 'Couldn’t open ${appLabel(to.source)}.');
    }
  }

  void _askEcho() {
    final d = _d;
    if (d == null) return;
    context.push('/echo/chat', extra: 'What’s going on with ${d.first}?');
  }

  Future<void> _setDontNudge(bool on) async {
    final d = _d;
    if (d == null) return;
    await PeopleStore.setDontNudge(d.summary.key, on);
    if (!mounted) return;
    showPeopleSnack(
      context,
      on ? 'No more nudges about ${d.first}.' : 'Nudges about ${d.first} are back on.',
    );
  }

  Future<void> _setWatching(bool on) async {
    final d = _d;
    if (d == null) return;
    await PeopleStore.setWatching(d.summary.key, on);
    if (!mounted) return;
    showPeopleSnack(
      context,
      on
          ? 'Keeping an eye on ${d.first}.'
          : 'Echo won’t watch for ${d.first} going quiet.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: const EchoAppBar(title: ''),
      body: d == null
          ? const SizedBox.shrink()
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                20,
                6,
                20,
                MediaQuery.paddingOf(context).bottom + 28,
              ),
              children: [
                FadeSlideIn(child: _Hero(detail: d, onMessage: _message, onOpenChat: _openChat, onAsk: _askEcho)),
                const SizedBox(height: 22),
                FadeSlideIn(
                  delay: AppMotion.staggerDelay(1),
                  child: _Ledger(
                    detail: d,
                    ticked: _ticked,
                    keyOf: _lineKey,
                    onTick: _tick,
                  ),
                ),
                if (d.followUp != null)
                  _FollowUpCard(
                    key: ValueKey(d.followUp!.thread),
                    detail: d,
                    owed: d.followUp!,
                    onSent: _load,
                  ),
                const PeopleSection('Recently', note: 'both ways'),
                _Timeline(detail: d),
                if (d.groups.isNotEmpty) ...[
                  const PeopleSection('Groups together'),
                  for (final g in d.groups) _GroupRow(group: g),
                ],
                PeopleSection('Echo and ${d.first}'),
                _Settings(
                  detail: d,
                  onDontNudge: _setDontNudge,
                  onWatching: _setWatching,
                ),
              ],
            ),
    );
  }
}

class _Hero extends StatelessWidget {
  final PersonDetail detail;
  final void Function(PersonDraftKind) onMessage;
  final VoidCallback onOpenChat;
  final VoidCallback onAsk;

  const _Hero({
    required this.detail,
    required this.onMessage,
    required this.onOpenChat,
    required this.onAsk,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = detail.summary;
    final birthday = s.birthday != null;
    final wished = s.birthday?.wishedAt != null;
    return Column(
      children: [
        Semantics(
          button: true,
          label: 'Change picture',
          child: PressFeedback(
            child: GestureDetector(
              onTap: () =>
                  showPersonPhotoSheet(context, name: s.name, source: s.source),
              child: PersonAvatar(name: s.name, size: 88, source: s.source),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          s.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.oldStandardTt(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        if (s.sources.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcons(s.sources, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  [
                    appNames(s.sources),
                    if (s.rhythm.isNotEmpty) s.rhythm.toLowerCase(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        if (detail.lastLine.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            [
              detail.lastLine,
              if (birthday) 'birthday today 🎂',
            ].join(' · '),
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 13, color: c.textSecondary),
          ),
        ],
        if (s.drifting) ...[
          const SizedBox(height: 8),
          const AgeTag(
            'Fewer messages than usual',
            age: 1,
            icon: Symbols.trending_down_rounded,
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            PeoplePill(
              label: birthday && !wished
                  ? pillWith('Wish', detail.first)
                  : 'Message',
              icon: birthday && !wished
                  ? Symbols.cake_rounded
                  : Symbols.chat_bubble_rounded,
              filled: true,
              onTap: () => onMessage(
                birthday && !wished
                    ? PersonDraftKind.wish
                    : PersonDraftKind.message,
              ),
            ),
            if (detail.replyTo != null)
              PeoplePill(
                label: 'Open chat',
                icon: Symbols.open_in_new_rounded,
                onTap: onOpenChat,
              ),
            PeoplePill(
              label: 'Ask Echo',
              icon: Symbols.auto_awesome_rounded,
              onTap: onAsk,
            ),
          ],
        ),
      ],
    );
  }
}

/// You owe them, and, only when there's something to show, they owe you:
/// that side only fills from replies sent through Echo, so an empty column
/// would look broken.
class _Ledger extends StatelessWidget {
  final PersonDetail detail;
  final Set<String> ticked;
  final String Function(OweLine) keyOf;
  final void Function(OweLine) onTick;

  const _Ledger({
    required this.detail,
    required this.ticked,
    required this.keyOf,
    required this.onTick,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = detail;
    final owes = d.summary.loops.owes;
    final owe = d.summary.loops.owe;
    final left = owe.where((l) => !ticked.contains(keyOf(l))).length;
    final oweColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Count('$left'),
        _ColumnLabel('You owe ${d.first}'),
        if (owe.isEmpty)
          _NoneLine('Nothing. You’re square.')
        else
          for (final line in owe)
            _OweRow(
              line: line,
              ticked: ticked.contains(keyOf(line)),
              onTick: () => onTick(line),
            ),
      ],
    );
    return AskCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: owes.isEmpty
          ? oweColumn
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: oweColumn),
                  VerticalDivider(
                    width: 24,
                    color: c.dividerColor.withValues(alpha: 0.6),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Count('${owes.length}'),
                        _ColumnLabel('${d.first} owes you'),
                        for (final o in owes)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.asked,
                                  style: GoogleFonts.nunito(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  o.meta,
                                  style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Count extends StatelessWidget {
  final String n;
  const _Count(this.n);

  @override
  Widget build(BuildContext context) => Text(
    n,
    style: GoogleFonts.oldStandardTt(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      height: 1,
      color: context.colors.textPrimary,
    ),
  );
}

class _ColumnLabel extends StatelessWidget {
  final String text;
  const _ColumnLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.nunito(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        height: 1.3,
        color: context.colors.textSecondary,
      ),
    ),
  );
}

class _NoneLine extends StatelessWidget {
  final String text;
  const _NoneLine(this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              text,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OweRow extends StatelessWidget {
  final OweLine line;
  final bool ticked;
  final VoidCallback onTick;

  const _OweRow({
    required this.line,
    required this.ticked,
    required this.onTick,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: line.money != null ? 'Mark paid' : 'Done',
            child: PressFeedback(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTick,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 1),
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ticked ? context.selectionFill : Colors.transparent,
                      border: Border.all(
                        color: ticked
                            ? Colors.transparent
                            : c.textSecondary.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: ticked
                        ? Icon(
                            Symbols.check_rounded,
                            size: 15,
                            color: context.onSelection,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.title,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: c.textPrimary.withValues(alpha: ticked ? 0.5 : 1),
                    decoration: ticked ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line.meta,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    height: 1.35,
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

/// A short follow-up on a question left hanging. Templates to start with;
/// "Write it for me" uses the writing engine, the first time asking which.
class _FollowUpCard extends StatefulWidget {
  final PersonDetail detail;
  final OwesLine owed;
  final VoidCallback onSent;

  const _FollowUpCard({
    super.key,
    required this.detail,
    required this.owed,
    required this.onSent,
  });

  @override
  State<_FollowUpCard> createState() => _FollowUpCardState();
}

class _FollowUpCardState extends State<_FollowUpCard> {
  late final PersonDraft _draft = PersonDraft(
    kind: PersonDraftKind.followUp,
    name: widget.detail.summary.name,
    source: widget.detail.summary.source,
    to: widget.detail.replyTo,
    context: widget.owed.asked,
  );
  late final _text = TextEditingController(text: _draft.templates.first);
  bool _editing = false;
  bool _writing = false;
  bool _written = false;
  bool _gone = false;
  String? _sentLine;
  ReplyRoute _route = ReplyRoute.send;

  @override
  void initState() {
    super.initState();
    final to = widget.detail.replyTo;
    if (to == null) {
      _route = ReplyRoute.copy;
    } else {
      ReplySender.routeFor(to).then((r) {
        if (mounted) setState(() => _route = r);
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _writeForMe() async {
    final to = widget.detail.replyTo;
    if (_writing || to == null) return;
    final ready = await EngineGate.ensure(context, reason: 'draft');
    if (!ready || !mounted) return;
    setState(() => _writing = true);
    final source = RawData()
      ..source = to.source
      ..sender = to.sender
      ..content = widget.owed.asked
      ..timestamp = to.timestamp
      ..thread = to.thread
      ..threadTitle = to.threadTitle
      ..isGroup = false
      ..addressed = 'direct';
    final written = await writeDraft(source, _draft.gist);
    if (!mounted) return;
    setState(() {
      _writing = false;
      if (written != null) {
        _text.text = written;
        _written = true;
      }
    });
    if (written == null) {
      showPeopleSnack(
        context,
        'Echo couldn’t write this one, so here are short templates.',
      );
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final to = widget.detail.replyTo;
    if (text.isEmpty || to == null) return;
    final source = widget.detail.summary.source;
    final outcome = await ReplySender.send(to, text);
    if (!mounted) return;
    setState(() {
      _editing = false;
      _sentLine = outcomeLine(outcome, source, widget.detail.first);
    });
    showPeopleSnack(context, _sentLine!);
    widget.onSent();
  }

  Future<void> _notNow() async {
    setState(() => _gone = true);
    await PeopleStore.followUpNotNow(widget.owed.thread, DateTime.now());
    if (mounted) {
      showPeopleSnack(context, 'Okay. Echo will bring this up again on Monday.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = widget.detail;
    final o = widget.owed;
    if (_gone) return const SizedBox.shrink();
    final days = DateTime.now().difference(o.askedAt).inDays;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AskCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Symbols.auto_awesome_rounded,
                  fill: 1,
                  size: 18,
                  color: c.primaryGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Follow-up',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                AgeTag('$days ${days == 1 ? 'day' : 'days'}', age: 1),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.dividerColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: _editing
                    ? Border.all(color: c.primaryGreen, width: 1.5)
                    : null,
              ),
              child: _editing
                  ? TextField(
                      controller: _text,
                      autofocus: true,
                      maxLines: 4,
                      minLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Your message',
                      ),
                    )
                  : Text(
                      _text.text,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: c.textPrimary,
                      ),
                    ),
            ),
            if (!_written && _sentLine == null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (i, t) in _draft.templates.indexed)
                    GestureDetector(
                      onTap: () => setState(() {
                        _text.text = t;
                        _editing = false;
                      }),
                      child: AgeTag(
                        const ['Plain', 'Polite', 'Light'][i],
                        age: _text.text == t ? 0 : null,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            if (_sentLine != null)
              Row(
                children: [
                  Icon(
                    Symbols.check_circle_rounded,
                    fill: 1,
                    size: 19,
                    color: c.primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sentLine!,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: c.primaryGreen,
                      ),
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  PeoplePill(
                    label: sendLabel(_route, d.summary.source),
                    icon: Symbols.send_rounded,
                    filled: true,
                    onTap: d.replyTo == null ? null : _send,
                  ),
                  PeoplePill(
                    label: _editing ? 'Done' : 'Edit',
                    icon: _editing ? Symbols.check_rounded : Symbols.edit_rounded,
                    onTap: () => setState(() => _editing = !_editing),
                  ),
                  if (d.replyTo != null)
                    PeoplePill(
                      label: _writing ? 'Writing…' : 'Write it for me',
                      icon: Symbols.auto_awesome_rounded,
                      onTap: _writing ? null : _writeForMe,
                    ),
                  PeoplePill(label: 'Not now', onTap: _notNow),
                ],
              ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  height: 1.4,
                  color: c.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: 'Nothing from ${d.first} since you asked '
                        '${dayWord(o.askedAt, DateTime.now())}: ',
                  ),
                  TextSpan(
                    text: '“${o.asked}”',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final PersonDetail detail;

  const _Timeline({required this.detail});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = detail;
    final primary = d.summary.source.isEmpty
        ? 'the app'
        : appLabel(d.summary.source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.timeline.isEmpty)
          Text(
            'Nothing in the last ${d.retentionDays} '
            '${d.retentionDays == 1 ? 'day' : 'days'}.',
            style: GoogleFonts.nunito(fontSize: 14, color: c.textSecondary),
          )
        else
          for (final l in d.timeline) _Bubble(line: l, first: d.first),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Symbols.info_rounded, size: 17, color: c.textSecondary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your own lines show only when you replied through Echo, or '
                'when $primary kept them in its notification. What you type '
                'inside the app itself stays between you and ${d.first}.',
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  height: 1.45,
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final TimelineLine line;
  final String first;

  const _Bubble({required this.line, required this.first});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = line.mine;
    final who = mine ? 'You' : first;
    final when = _clock(line.at);
    final where = line.where == null ? '' : ' in ${line.where}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
          ),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: mine ? context.selectionFill : c.surface,
                  border: mine
                      ? null
                      : Border.all(
                          color: c.dividerColor.withValues(alpha: 0.5),
                        ),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 18),
                  ),
                ),
                child: Text(
                  line.text,
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: mine ? context.onSelection : c.textPrimary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 5,
                  children: [
                    AppIcons([line.source], size: 13),
                    Text(
                      '$who$where · $when',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                    if (line.via != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: c.dividerColor.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          line.via!,
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
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

  static String _clock(DateTime at) {
    final now = DateTime.now();
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final time = '$h:${at.minute.toString().padLeft(2, '0')} '
        '${at.hour < 12 ? 'AM' : 'PM'}';
    final word = dayWord(at, now);
    return word == 'today' ? time : '${cap(word)} $time';
  }
}

class _GroupRow extends StatelessWidget {
  final SharedGroup group;

  const _GroupRow({required this.group});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = group;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AskCard(
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(24),
          child: PeopleRow(
            first: true,
            onTap: () => context.push('/group', extra: g.title),
            child: Row(
              children: [
                AppIcons([g.source], size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.newToday > 0
                            ? '${g.title} · ${g.newToday} new'
                            : g.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      if (g.lastLine != null)
                        Text(
                          g.lastLine!,
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
                const RowChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Settings extends StatelessWidget {
  final PersonDetail detail;
  final void Function(bool) onDontNudge;
  final void Function(bool) onWatching;

  const _Settings({
    required this.detail,
    required this.onDontNudge,
    required this.onWatching,
  });

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final first = d.first;
    return AskCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _SwitchRow(
            first: true,
            icon: Symbols.visibility_rounded,
            title: 'Keep an eye on $first',
            subtitle: 'Tell me if $first goes quiet or leaves a question of mine hanging',
            value: d.choices.watching && !d.choices.dontNudge,
            onChanged: d.choices.dontNudge ? null : onWatching,
          ),
          _SwitchRow(
            icon: Symbols.notifications_off_rounded,
            title: 'Don’t nudge me about $first',
            subtitle: 'No drift or follow-up reminders. $first still shows on Today when they write to you.',
            value: d.choices.dontNudge,
            onChanged: onDontNudge,
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final bool first;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool)? onChanged;

  const _SwitchRow({
    this.first = false,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
              ),
            ),
      child: Opacity(
        opacity: onChanged == null ? 0.45 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 20, color: c.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      height: 1.35,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
