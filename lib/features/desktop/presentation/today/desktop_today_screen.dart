import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/core/services/phone_actions.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/services/voice/echo_voice.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/data/desktop_actions.dart';
import 'package:project_echo/features/desktop/presentation/today/reply_suggestions.dart';
import 'package:project_echo/features/desktop/presentation/today/today_detail.dart';
import 'package:project_echo/features/desktop/presentation/today/today_list.dart';
import 'package:project_echo/features/desktop/presentation/today/today_logic.dart';
import 'package:project_echo/features/desktop/presentation/today/today_parts.dart';
import 'package:project_echo/features/desktop/presentation/today/today_rail.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/home/group_summaries.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/desktop/presentation/typing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Today on the computer: a triage inbox. Everything that wants the owner
/// on the left, the selected chat and a reply in the middle, the rest of
/// the day on the right. Keys J/K move, R replies, E marks handled, H
/// reminds, T puts it on the list; replies go out through the phone.
class DesktopTodayScreen extends StatefulWidget {
  /// Opens Ask Echo with [question] ("Catch me up on College gang").
  final void Function(String question) onAsk;

  const DesktopTodayScreen({super.key, required this.onAsk});

  @override
  State<DesktopTodayScreen> createState() => _DesktopTodayScreenState();
}

class _DesktopTodayScreenState extends State<DesktopTodayScreen> {
  final _keys = FocusNode(debugLabel: 'today keys');
  final _replyFocus = FocusNode(debugLabel: 'today reply');

  var _now = DateTime.now();
  var _items = <TriageItem>[];
  String? _selected;

  var _byThread = <String, List<RawData>>{};
  var _turns = const MyTurns({});
  var _todos = <TodoItem>[];
  var _reminders = <String, DateTime>{};
  var _reminderTitles = <String, String>{};
  var _actions = <PhoneAction>[];
  var _marked = <String>{};
  var _summaries = <String, String>{};
  String? _name;
  String? _briefing;
  DateTime? _briefingAt;
  WeekStats? _week;

  var _playing = false;
  var _playRun = 0;

  var _loading = false;
  var _again = false;
  var _summarising = false;
  Timer? _clock;
  Timer? _slow;

  late final List<Listenable> _sources = [
    EchoServerService.instance.syncTick,
    TodoStore.changed,
    Reminders.changed,
    PhoneActions.changed,
  ];

  @override
  void initState() {
    super.initState();
    for (final s in _sources) {
      s.addListener(_load);
    }
    _load();
    unawaited(EchoVoice.instance.warmUp());
    // "Now" on the rail, and what's still to come, move with the clock.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  @override
  void dispose() {
    for (final s in _sources) {
      s.removeListener(_load);
    }
    _clock?.cancel();
    _slow?.cancel();
    if (_playing) unawaited(EchoVoice.instance.stop());
    _keys.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() => _now = DateTime.now());
  }

  /// Reads everything again; a call made while reading runs once more after.
  Future<void> _load() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      do {
        _again = false;
        await _read();
      } while (_again && mounted);
    } finally {
      _loading = false;
    }
  }

  Future<void> _read() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final feed = await HomeFeed.load(now);
    final entries = await IsarDataSource.getAllEntries();
    final turns = await ChatContextStore.loadMyTurns();
    final (todos, _) = await TodoStore().load();
    final reminders = await Reminders.all();
    final actions = await PhoneActions.all();
    final marked = await HandledMarks.load(now);
    final summaries = await GroupSummaries.cached();
    final items = TriageItem.fromFeed(feed);
    WeekStats? week;
    try {
      week = await WeekStats.load(now);
    } catch (_) {
      // The tiles are left out.
    }
    final briefing = prefs.getString('cached_briefing_text')?.trim();
    final briefingAt = DateTime.tryParse(
      prefs.getString('cached_briefing_time') ?? '',
    );
    final byThread = <String, List<RawData>>{};
    for (final e in entries) {
      if (e.thread != null) (byThread[e.thread!] ??= []).add(e);
    }
    if (!mounted) return;
    // Marked a moment ago, while this was reading, still counts.
    final sameDay = startOfDay(_now) == startOfDay(now);
    setState(() {
      _now = now;
      _byThread = byThread;
      _turns = turns;
      _todos = todos;
      _reminders = reminders;
      _reminderTitles = reminderTitles(prefs.getString(Reminders.storeKey));
      _actions = actions;
      _marked = sameDay ? {...marked, ..._marked} : marked;
      _summaries = {..._summaries, ...summaries};
      _name = prefs.getString('user_name')?.trim();
      _briefing = (briefing?.isEmpty ?? true) ? null : briefing;
      _briefingAt =
          briefingAt != null && startOfDay(briefingAt) == startOfDay(now)
          ? briefingAt
          : null;
      _week = week;
      _selected = _keepSelection(items);
      _items = items;
    });
    _watchSlowReplies();
    unawaited(_summarise(feed.busyGroups, now));
  }

  /// The same row as before if it's still there; otherwise the one now in
  /// its place, so finishing a row moves on to the next.
  String? _keepSelection(List<TriageItem> items) {
    if (items.isEmpty) return null;
    if (items.any((i) => i.id == _selected)) return _selected;
    final was = _items.indexWhere((i) => i.id == _selected);
    final at = was < 0 ? 0 : was.clamp(0, items.length - 1);
    final next = items.skip(at).where((i) => !_isHandled(i)).firstOrNull;
    return (next ?? items[at]).id;
  }

  /// Asks for new group lines when they've moved on, one ask at a time.
  Future<void> _summarise(List<BusyGroup> groups, DateTime now) async {
    if (groups.isEmpty || _summarising) return;
    _summarising = true;
    try {
      final lines = await GroupSummaries.refresh(groups, now);
      if (mounted) setState(() => _summaries = {..._summaries, ...lines});
    } finally {
      _summarising = false;
    }
  }

  /// Rebuilds when a reply has waited long enough to say the phone may be
  /// away.
  void _watchSlowReplies() {
    _slow?.cancel();
    final due = [
      for (final a in _actions)
        if (a.kind == 'reply' &&
            (a.state == ActionState.waiting ||
                a.state == ActionState.collected))
          a.at.add(phoneSlow),
    ].where((t) => t.isAfter(DateTime.now())).toList()..sort();
    if (due.isEmpty) return;
    _slow = Timer(
      due.first.difference(DateTime.now()) + const Duration(seconds: 1),
      () {
        _tick();
        _watchSlowReplies();
      },
    );
  }

  PhoneAction? _replyFor(TriageItem item) =>
      item.kind == TriageKind.waiting ? replyTo(_actions, item.entry) : null;

  /// Replied to from here (and not failed), or marked.
  bool _isHandled(TriageItem item) {
    if (_marked.contains(item.id)) return true;
    final r = _replyFor(item);
    return r != null && r.state != ActionState.failed;
  }

  TriageItem? get _current =>
      _items.where((i) => i.id == _selected).firstOrNull;

  List<ChatLine> _linesFor(TriageItem item) {
    final e = item.entry;
    if (item.kind == TriageKind.group) {
      return [
        for (final m in item.group!.messages.take(6).toList().reversed)
          ChatLine(
            who: m.sender.isEmpty ? m.source : m.sender,
            text: m.content,
            at: m.timestamp,
          ),
      ];
    }
    final thread = e.thread;
    return conversation(
      thread == null
          ? [if (item.kind == TriageKind.waiting) e]
          : _byThread[thread] ?? const [],
      thread == null ? const [] : _turns.byThread[thread] ?? const [],
      picked: e,
      pickedMine: item.kind == TriageKind.promise,
    );
  }

  void _select(TriageItem item) {
    setState(() => _selected = item.id);
    // The next chat's replies are ready by the time J gets there.
    final at = _items.indexOf(item);
    final next = _items
        .skip(at + 1)
        .where((i) => i.kind == TriageKind.waiting && !_isHandled(i))
        .firstOrNull;
    if (next != null) {
      unawaited(ReplySuggestions.forEntry(next.entry, _linesFor(next)));
    }
  }

  void _move(int by) {
    if (_items.isEmpty) return;
    final at = _items.indexWhere((i) => i.id == _selected);
    _select(_items[(at + by).clamp(0, _items.length - 1)]);
  }

  /// After [id] is dealt with, on to the next row still open: below it,
  /// else from the top.
  void _advanceFrom(String id, Duration after) {
    Future.delayed(after, () {
      if (!mounted || _selected != id) return;
      final at = _items.indexWhere((i) => i.id == id);
      final open = [
        ..._items.skip(at + 1),
        ..._items.take(at < 0 ? 0 : at),
      ].where((i) => !_isHandled(i));
      if (open.isNotEmpty) _select(open.first);
    });
  }

  // ── Actions, all through the phone ─────────────────────────────────────

  Future<void> _send(String text) async {
    final item = _current;
    if (item == null || item.kind != TriageKind.waiting) return;
    _keys.requestFocus();
    await DesktopActions.reply(item.entry, text);
    _advanceFrom(item.id, const Duration(milliseconds: 1200));
  }

  Future<void> _remind() async {
    final item = _current;
    if (item == null || item.kind == TriageKind.group) return;
    final e = item.entry;
    final key = item.id;
    final at = reminderTimeFor(e, DateTime.now());
    if (at == null || _reminders.containsKey(key)) return;
    // It goes on the list too, so the reminder's Done ticks it off.
    final todo =
        _todos.where((t) => t.sourceKey == key).firstOrNull ??
        await DesktopActions.addMessage(e);
    await DesktopActions.remind(
      key: key,
      at: at,
      title: switch (item.kind) {
        TriageKind.promise => 'You told ${item.name}',
        _ =>
          e.isGroup && (e.threadTitle?.isNotEmpty ?? false)
              ? '${e.sender} in ${e.threadTitle}'
              : e.sender,
      },
      body: e.content,
      todoId: todo.id,
      thread: e.thread,
    );
  }

  Future<void> _addToList() async {
    final item = _current;
    if (item == null || item.kind == TriageKind.group) return;
    if (_onList(item)) return;
    await DesktopActions.addMessage(item.entry);
  }

  Future<void> _handle() async {
    final item = _current;
    if (item == null || _marked.contains(item.id)) return;
    setState(() => _marked = {..._marked, item.id});
    if (item.promise case final p?) await HomeFeed.markDone(p);
    await HandledMarks.add(item.id, DateTime.now());
    _advanceFrom(item.id, const Duration(milliseconds: 300));
  }

  void _catchUp() {
    final group = _current?.group;
    if (group != null) widget.onAsk('Catch me up on ${group.name}');
  }

  void _playBriefing() {
    final voice = EchoVoice.instance;
    final run = ++_playRun;
    if (_playing) {
      unawaited(voice.stop());
      setState(() => _playing = false);
      return;
    }
    final text = _briefing;
    if (text == null) return;
    voice.sayAll(text);
    setState(() => _playing = true);
    voice.finished.then((_) {
      if (mounted && run == _playRun) setState(() => _playing = false);
    });
  }

  bool _onList(TriageItem item) => _todos.any((t) => t.sourceKey == item.id);

  // ── Keys ───────────────────────────────────────────────────────────────

  /// Whether the owner is typing somewhere, when letters are letters.
  bool get _typing => typingInAField();

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (_typing ||
        keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final repeat = event is KeyRepeatEvent;
    final VoidCallback? run = switch (event.logicalKey) {
      LogicalKeyboardKey.keyJ => () => _move(1),
      LogicalKeyboardKey.keyK => () => _move(-1),
      LogicalKeyboardKey.keyR when !repeat => _replyFocus.requestFocus,
      LogicalKeyboardKey.keyE when !repeat => _handle,
      LogicalKeyboardKey.keyH when !repeat => _remind,
      LogicalKeyboardKey.keyT when !repeat => _addToList,
      _ => null,
    };
    if (run == null) return KeyEventResult.ignored;
    run();
    return KeyEventResult.handled;
  }

  // ── Layout ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hairline = BorderSide(color: c.dividerColor);
    final waiting = _items
        .where((i) => i.kind == TriageKind.waiting && !_isHandled(i))
        .length;
    final reminders = [
      for (final MapEntry(:key, :value) in _reminders.entries)
        (
          value,
          _reminderTitles[key] ??
              _todos.where((t) => t.sourceKey == key).firstOrNull?.title ??
              'Reminder',
        ),
    ];
    return Material(
      color: c.background,
      // A click anywhere but the reply field hands the keys back to the
      // list (a click away from the field has already left it).
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) {
          if (!_typing && !_keys.hasPrimaryFocus) _keys.requestFocus();
        },
        child: Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(border: Border(bottom: hairline)),
                child: _Header(
                  now: _now,
                  name: _name,
                  waiting: waiting,
                  next: _nextTodo(),
                  briefing: _briefing,
                  playing: _playing,
                  onPlay: _playBriefing,
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Narrow windows give the middle the room: the rail goes
                    // first, then the list slims down.
                    final rail = box.maxWidth >= 1060;
                    final list = box.maxWidth >= 960 ? 380.0 : 320.0;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: list,
                          decoration: BoxDecoration(
                            border: Border(right: hairline),
                          ),
                          child: TodayList(
                            items: _items,
                            selected: _selected,
                            handled: {
                              for (final i in _items)
                                if (_isHandled(i)) i.id,
                            },
                            summaries: _summaries,
                            onSelect: (item) {
                              _keys.requestFocus();
                              _select(item);
                            },
                          ),
                        ),
                        Expanded(child: _detail()),
                        if (rail)
                          Container(
                            width: 300,
                            decoration: BoxDecoration(
                              border: Border(left: hairline),
                            ),
                            child: TodayRail(
                              events: restOfToday(_todos, reminders, _now),
                              now: _now,
                              briefing: _briefing,
                              briefingAt: _briefingAt,
                              playing: _playing,
                              onPlay: _playBriefing,
                              week: _week,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail() {
    final item = _current;
    if (item == null) {
      return Center(
        child: Text(
          _items.isEmpty
              ? 'You’re all caught up.'
              : 'Pick something on the left.',
          style: GoogleFonts.oldStandardTt(
            fontSize: 22,
            color: context.colors.textSecondary,
          ),
        ),
      );
    }
    return FadeSlideIn(
      key: ValueKey(item.id),
      offsetY: 6,
      duration: AppMotion.fast,
      child: TodayDetail(
        item: item,
        lines: _linesFor(item),
        now: _now,
        marked: _marked.contains(item.id),
        reply: _replyFor(item),
        remindAt: item.kind == TriageKind.group
            ? null
            : reminderTimeFor(item.entry, _now),
        reminding: _reminders[item.id],
        onList: _onList(item),
        summary: item.group == null ? null : _summaries[item.group!.name],
        replyFocus: _replyFocus,
        actions: TodayActions(
          send: _send,
          remind: _remind,
          addToList: _addToList,
          handle: _handle,
          catchUp: _catchUp,
          leaveReply: _keys.requestFocus,
        ),
      ),
    );
  }

  /// Today's next to-do with a time, for the header.
  TodoItem? _nextTodo() {
    final today = startOfDay(_now);
    final left = [
      for (final t in _todos)
        if (!t.done && t.day == today && (t.startsAt?.isAfter(_now) ?? false))
          t,
    ]..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
    return left.firstOrNull;
  }
}

/// The date, who's waiting and what's next, and the briefing button.
class _Header extends StatelessWidget {
  final DateTime now;
  final String? name;
  final int waiting;
  final TodoItem? next;
  final String? briefing;
  final bool playing;
  final VoidCallback onPlay;

  const _Header({
    required this.now,
    required this.name,
    required this.waiting,
    required this.next,
    required this.briefing,
    required this.playing,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final green = TextStyle(fontWeight: FontWeight.w800, color: c.primaryGreen);
    final (who, rest) = peopleWaiting(waiting);
    final name = this.name;
    final next = this.next;
    final briefing = this.briefing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  longDate(now),
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name == null || name.isEmpty
                            ? '${greetingAt(now.hour)}. '
                            : '${greetingAt(now.hour)}, $name. ',
                      ),
                      TextSpan(text: who, style: waiting > 0 ? green : null),
                      TextSpan(text: rest),
                      if (next != null) ...[
                        TextSpan(
                          text: next.sender.trim().isNotEmpty
                              ? '; next is ${next.sender} at '
                              : '; next is “${next.title}” at ',
                        ),
                        TextSpan(
                          text: clockLabel(next.startsAt!),
                          style: green,
                        ),
                      ],
                      const TextSpan(text: '.'),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (briefing != null) ...[
            const SizedBox(width: 18),
            DeskButton(
              label: playing
                  ? 'Stop briefing'
                  : 'Play briefing · ${briefingMinutes(briefing)} min',
              icon: playing ? Symbols.stop_rounded : Symbols.play_arrow_rounded,
              style: DeskButtonStyle.filled,
              onTap: onPlay,
            ),
          ],
        ],
      ),
    );
  }
}
