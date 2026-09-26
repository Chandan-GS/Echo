import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/todo/data/todo_generator.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';

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
  List<TodoItem> get tomorrow =>
      _on(DateTime(_today.year, _today.month, _today.day + 1));

  int get doneToday => today.where((i) => i.done).length;

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
class TodoCubit extends Cubit<TodoState> {
  final TodoStore _store;
  final TodoGenerator _generator;
  StreamSubscription<void>? _isarWatch;
  Timer? _recount;

  // A list made from the end of the briefing is revealed only once home is
  // back on screen, so the entrance isn't played behind the briefing.
  bool _heldArrival = false;
  Set<int> _heldAdded = const {};
  Set<int> _heldChanged = const {};

  TodoCubit({TodoStore? store, TodoGenerator? generator})
    : _store = store ?? TodoStore(),
      _generator = generator ?? TodoGenerator(store: store),
      super(TodoState(now: DateTime.now())) {
    load();
    _watchNotifications();
  }

  /// Re-reads the list (picking up items ticked off in a widget) and
  /// recounts what's new.
  Future<void> load() async {
    final now = DateTime.now();
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
    final started = DateTime.now();
    try {
      await _generator.make(started);
    } catch (e) {
      debugPrint('Making the to-do list failed: $e');
    }
    await _atLeast(started, const Duration(milliseconds: 1200));
    final (items, meta) = await _store.load();
    if (isClosed) return;
    _heldArrival = !reveal;
    emit(
      state.copyWith(
        items: items,
        meta: meta,
        now: DateTime.now(),
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
    final started = DateTime.now();
    try {
      await _generator.update(started);
    } catch (e) {
      debugPrint('Updating the to-do list failed: $e');
    }
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
        now: DateTime.now(),
        phase: TodoPhase.idle,
        pendingNew: 0,
        justAdded: reveal ? added : const {},
        justChanged: reveal ? changed : const {},
      ),
    );
    WidgetRefreshService.refresh();
  }

  /// Ticks an item on or off. Returns true when this finished today's list.
  Future<bool> toggle(int id) async {
    final wasAllDone =
        state.today.isNotEmpty && state.doneToday == state.today.length;
    final items = [
      for (final i in state.items) i.id == id ? i.copyWith(done: !i.done) : i,
    ];
    emit(state.copyWith(items: items, justAdded: {}, justChanged: {}));
    await _store.save(items, state.meta);
    WidgetRefreshService.refresh();
    final allDone =
        state.today.isNotEmpty && state.doneToday == state.today.length;
    return allDone && !wasAllDone;
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
      final now = DateTime.now();
      final fresh = await _generator.candidates(now, since: since);
      final known = state.items.map((i) => i.sourceKey).toSet();
      final count = fresh
          .where((c) => !known.contains(sourceKeyOf(c.entry)))
          .length;
      if (!isClosed) emit(state.copyWith(pendingNew: count, now: now));
    } catch (_) {}
  }

  Future<void> _atLeast(DateTime started, Duration minimum) async {
    // Keeps the drafting animation on screen long enough to read as intended
    // even when the reply is instant.
    final left = minimum - DateTime.now().difference(started);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  @override
  Future<void> close() {
    _isarWatch?.cancel();
    _recount?.cancel();
    return super.close();
  }
}
