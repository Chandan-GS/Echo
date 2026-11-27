import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/services/review_prompt.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/todo/data/todo_generator.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TodoPhase { idle, writing, updating }

class TodoState {
  final bool loaded;
  final List<TodoItem> items;
  final TodoMeta meta;
  final DateTime now;

  /// Relevant notifications since the list was last made or updated.
  final int pendingNew;
  final TodoPhase phase;

  /// Bumped when a list has just been made — the card plays its arrival.
  final int arrival;

  /// Items the last update added or changed, for their entrance.
  final Set<int> justAdded;
  final Set<int> justChanged;

  const TodoState({
    required this.now,
    this.loaded = false,
    this.items = const [],
    this.meta = const TodoMeta(),
    this.pendingNew = 0,
    this.phase = TodoPhase.idle,
    this.arrival = 0,
    this.justAdded = const {},
    this.justChanged = const {},
  });

  DateTime get _today => startOfDay(now);

  List<TodoItem> _on(DateTime day) =>
      items.where((i) => i.day == day).toList()
        ..sort((a, b) => a.sort.compareTo(b.sort));

  List<TodoItem> get today => _on(_today);
  List<TodoItem> get tomorrow => _on(addDays(_today, 1));

  int get doneToday => today.where((i) => i.done).length;

  /// Today's list is finished (and not mid-update).
  bool get allDoneToday =>
      phase == TodoPhase.idle && today.isNotEmpty && doneToday == today.length;

  /// When the last of today's items was ticked, if known.
  DateTime? get lastDoneToday {
    DateTime? last;
    for (final i in today) {
      final at = i.doneAt;
      if (at != null && (last == null || at.isAfter(last))) last = at;
    }
    return last;
  }

  bool get hasList {
    final made = meta.madeAt;
    return today.isNotEmpty ||
        tomorrow.isNotEmpty ||
        (made != null && startOfDay(made) == _today);
  }

  TodoState copyWith({
    bool? loaded,
    List<TodoItem>? items,
    TodoMeta? meta,
    DateTime? now,
    int? pendingNew,
    TodoPhase? phase,
    int? arrival,
    Set<int>? justAdded,
    Set<int>? justChanged,
  }) => TodoState(
    loaded: loaded ?? this.loaded,
    items: items ?? this.items,
    meta: meta ?? this.meta,
    now: now ?? this.now,
    pendingNew: pendingNew ?? this.pendingNew,
    phase: phase ?? this.phase,
    arrival: arrival ?? this.arrival,
    justAdded: justAdded ?? this.justAdded,
    justChanged: justChanged ?? this.justChanged,
  );
}

/// The to-do list shared by home and the briefing screen.
///
/// Every change is made through [TodoStore.edit] against the list as it is on
/// disk, so ticks from a home-screen widget, a reminder's Done or a paired
/// computer that landed since the last read are never overwritten.
class TodoCubit extends Cubit<TodoState> {
  final TodoStore _store;
  final TodoGenerator _generator;
  final DateTime Function() _clock;
  StreamSubscription<void>? _isarWatch;
  Timer? _recount;

  /// Moves [TodoState.now] on at midnight, so "today" is today even if the
  /// app stays open overnight.
  Timer? _dayChange;

  // Items ticked in a home-screen widget land while the app is in the
  // background; reload whenever it comes back, whichever tab is showing.
  late final AppLifecycleListener _lifecycle;

  // A list made from the end of the briefing is revealed only once home is
  // back on screen, so the entrance isn't played behind the briefing.
  bool _heldArrival = false;
  Set<int> _heldAdded = const {};
  Set<int> _heldChanged = const {};

  /// The reminders of items just deleted, so undoing puts them back.
  final Map<int, Map<String, dynamic>> _removedReminders = {};

  /// The longest making or updating the list may keep the drafting state on
  /// screen. The model call itself gives up sooner (see
  /// [TodoGenerator.askTimeout]); this covers the rest, such as waiting for
  /// notifications to be read in.
  final Duration generationTimeout;

  TodoCubit({
    TodoStore? store,
    TodoGenerator? generator,
    DateTime Function()? clock,
    this.generationTimeout = const Duration(seconds: 90),
  }) : _store = store ?? generator?.store ?? TodoStore(),
       _generator = generator ?? TodoGenerator(store: store),
       _clock = clock ?? DateTime.now,
       super(TodoState(now: (clock ?? DateTime.now)())) {
    _lifecycle = AppLifecycleListener(onResume: load);
    TodoStore.changed.addListener(load);
    load();
    _watchNotifications();
    _scheduleDayChange();
  }

  /// Re-reads the list (picking up items ticked off in a widget) and
  /// recounts what's new.
  Future<void> load() async {
    final now = _clock();
    final (items, meta) = await _store.load();
    if (isClosed) return;
    emit(state.copyWith(loaded: true, items: items, meta: meta, now: now));
    await _countNew();
  }

  /// [reveal] false holds the entrance until [reveal] is called.
  Future<void> make({bool reveal = true}) async {
    if (state.phase != TodoPhase.idle) return;
    Analytics.track('todo_list_made');
    emit(
      state.copyWith(phase: TodoPhase.writing, justAdded: {}, justChanged: {}),
    );
    final started = _clock();
    await _generate('Making', _generator.make(started));
    await _atLeast(started, const Duration(milliseconds: 1200));
    final (items, meta) = await _store.load();
    if (isClosed) return;
    _heldArrival = !reveal;
    emit(
      state.copyWith(
        items: items,
        meta: meta,
        now: _clock(),
        phase: TodoPhase.idle,
        pendingNew: 0,
        arrival: reveal ? state.arrival + 1 : state.arrival,
      ),
    );
    WidgetRefreshService.refresh();
  }

  /// Plays a held entrance (see [make] and [update]).
  void revealHeld() {
    if (isClosed) return;
    if (_heldArrival) {
      _heldArrival = false;
      emit(state.copyWith(arrival: state.arrival + 1));
    }
    if (_heldAdded.isNotEmpty || _heldChanged.isNotEmpty) {
      emit(state.copyWith(justAdded: _heldAdded, justChanged: _heldChanged));
      _heldAdded = const {};
      _heldChanged = const {};
    }
  }

  Future<void> update({bool reveal = true}) async {
    if (state.phase != TodoPhase.idle) return;
    Analytics.track('todo_list_updated');
    final before = {for (final i in state.items) i.id: i};
    emit(
      state.copyWith(phase: TodoPhase.updating, justAdded: {}, justChanged: {}),
    );
    final started = _clock();
    await _generate('Updating', _generator.update(started));
    await _atLeast(started, const Duration(milliseconds: 1000));
    final (items, meta) = await _store.load();
    if (isClosed) return;
    final added = {
      for (final i in items)
        if (!before.containsKey(i.id)) i.id,
    };
    final changed = {
      for (final i in items)
        if (before[i.id] != null &&
            (before[i.id]!.time != i.time || before[i.id]!.day != i.day))
          i.id,
    };
    if (!reveal) {
      _heldAdded = added;
      _heldChanged = changed;
    }
    emit(
      state.copyWith(
        items: items,
        meta: meta,
        now: _clock(),
        phase: TodoPhase.idle,
        pendingNew: 0,
        justAdded: reveal ? added : const {},
        justChanged: reveal ? changed : const {},
      ),
    );
    WidgetRefreshService.refresh();
  }

  /// Waits for making or updating the list, at most [generationTimeout]. If
  /// it runs over, the drafting state ends anyway and the list is re-read
  /// once the work finishes, since what it saves is merged into the list.
  Future<void> _generate(String what, Future<void> work) async {
    try {
      await work.timeout(generationTimeout);
    } on TimeoutException {
      debugPrint('$what the to-do list is taking too long; carrying on.');
      work.then((_) => isClosed ? null : load(), onError: (_) {});
    } catch (e) {
      debugPrint('$what the to-do list failed: $e');
    }
  }

  /// Ticks an item on or off, as the owner saw it: if it's already the way
  /// they're making it (a reminder's Done ticked it a moment ago), nothing
  /// changes, rather than undoing that. Returns true when this finished
  /// today's list.
  Future<bool> toggle(int id) async {
    final shown = state.items.where((i) => i.id == id).firstOrNull;
    if (shown == null) return false;
    return setDone(id, !shown.done);
  }

  /// Marks an item done or not done. Returns true when this finished today's
  /// list.
  Future<bool> setDone(int id, bool done) async {
    final now = _clock();
    // On screen at once; the stored list follows.
    emit(
      state.copyWith(
        items: [
          for (final i in state.items)
            i.id == id && i.done != done ? i.withDone(done, now) : i,
        ],
        justAdded: {},
        justChanged: {},
      ),
    );
    var wasAllDone = false;
    final saved = await _store.edit((items, meta) {
      final target = items.where((i) => i.id == id).firstOrNull;
      if (target == null || target.done == done) return null;
      wasAllDone = _allDone(items, now);
      return (
        [for (final i in items) i.id == id ? i.withDone(done, now) : i],
        meta,
      );
    });
    if (saved == null) {
      // Already that way, gone, or unreadable: show what's really stored.
      await load();
      return false;
    }
    _show(saved, const {});
    if (done) ReviewPrompt.recordWin(ReviewWin.todoDone);
    return _allDone(saved.$1, now) && !wasAllDone;
  }

  static bool _allDone(List<TodoItem> items, DateTime now) {
    final today = startOfDay(now);
    final on = items.where((i) => i.day == today);
    return on.isNotEmpty && on.every((i) => i.done);
  }

  /// Adds what the owner typed ("call the plumber at 11 tomorrow"). Returns
  /// the new item.
  Future<TodoItem?> addTyped(String text) async {
    if (text.trim().isEmpty) return null;
    final now = _clock();
    TodoItem? item;
    final saved = await _store.edit((items, meta) {
      item = typedItem(text, freeId(items, meta), now);
      return ([...items, item!], meta);
    });
    if (saved == null) return null;
    _show(saved, {item!.id});
    return item;
  }

  /// Moves an item to [day] (Today ⇄ Tomorrow).
  Future<void> moveTo(int id, DateTime day) async {
    final saved = await _store.edit(
      (items, meta) => (
        [for (final i in items) i.id == id ? i.copyWith(day: day) : i],
        meta,
      ),
    );
    if (saved != null) _show(saved, {id});
  }

  /// Deletes an item and its reminder. Returns it, for undoing.
  Future<TodoItem?> remove(int id) async {
    TodoItem? gone;
    final saved = await _store.edit((items, meta) {
      gone = items.where((i) => i.id == id).firstOrNull;
      if (gone == null) return null;
      return (
        [
          for (final i in items)
            if (i.id != id) i,
        ],
        meta,
      );
    });
    if (saved == null || gone == null) return null;
    final reminder = await _reminderFor(gone!.sourceKey);
    if (reminder != null) {
      _removedReminders[id] = reminder;
      await Reminders.cancel(gone!.sourceKey);
    }
    _show(saved, const {});
    return gone;
  }

  /// Puts back an item [remove] took away, with its reminder if that's still
  /// to come.
  Future<void> restore(TodoItem item) async {
    var back = item;
    final saved = await _store.edit((items, meta) {
      if (items.any((i) => i.sourceKey == item.sourceKey)) return null;
      // Its id may have been given to something added since.
      if (items.any((i) => i.id == item.id)) {
        back = item.copyWith(id: freeId(items, meta));
      }
      return ([...items, back], meta);
    });
    final reminder = _removedReminders.remove(item.id);
    if (saved == null) return;
    _show(saved, {back.id});
    final at = reminder?['at'];
    if (reminder != null &&
        at is int &&
        DateTime.fromMillisecondsSinceEpoch(at).isAfter(_clock())) {
      await Reminders.set(
        message: back.sourceKey,
        at: DateTime.fromMillisecondsSinceEpoch(at),
        title: (reminder['title'] as String?) ?? back.title,
        body: (reminder['body'] as String?) ?? '',
        todoId: back.id,
        thread: reminder['thread'] as String?,
        byOwner: false,
      );
    }
  }

  /// The stored reminder about [key], as Reminders keeps it.
  static Future<Map<String, dynamic>?> _reminderFor(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final all = jsonDecode(prefs.getString(Reminders.storeKey) ?? '{}');
      final r = all is Map ? all[key] : null;
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null;
    }
  }

  void _show((List<TodoItem>, TodoMeta) saved, Set<int> added) {
    if (isClosed) return;
    final (items, meta) = saved;
    emit(
      state.copyWith(
        items: items,
        meta: meta,
        now: _clock(),
        justAdded: added,
        justChanged: {},
      ),
    );
    WidgetRefreshService.refresh();
  }

  void _scheduleDayChange() {
    _dayChange?.cancel();
    final now = _clock();
    final midnight = addDays(startOfDay(now), 1);
    _dayChange = Timer(
      midnight.difference(now) + const Duration(seconds: 1),
      () {
        if (isClosed) return;
        emit(state.copyWith(now: _clock()));
        _countNew();
        _scheduleDayChange();
      },
    );
  }

  void _watchNotifications() {
    IsarDataSource.instance
        .then((isar) {
          if (isClosed) return;
          _isarWatch = isar.rawDatas.watchLazy().listen((_) {
            // Several notifications often land together; count once.
            _recount?.cancel();
            _recount = Timer(const Duration(milliseconds: 600), _countNew);
          });
        })
        .catchError((_) {});
  }

  Future<void> _countNew() async {
    if (!state.hasList || state.phase != TodoPhase.idle) return;
    final since = state.meta.updatedAt ?? state.meta.madeAt;
    if (since == null) return;
    try {
      final now = _clock();
      final fresh = await _generator.candidates(now, since: since);
      final known = state.items.expand((i) => i.keys).toSet();
      final count = fresh
          .where((c) => !known.contains(sourceKeyOf(c.entry)))
          .length;
      if (!isClosed) emit(state.copyWith(pendingNew: count, now: now));
    } catch (_) {}
  }

  Future<void> _atLeast(DateTime started, Duration minimum) async {
    // Keeps the drafting animation on screen long enough to read as intended
    // even when the reply is instant.
    final left = minimum - _clock().difference(started);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  @override
  Future<void> close() {
    _isarWatch?.cancel();
    _recount?.cancel();
    _dayChange?.cancel();
    _lifecycle.dispose();
    TodoStore.changed.removeListener(load);
    return super.close();
  }
}
