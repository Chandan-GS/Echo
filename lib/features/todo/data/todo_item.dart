/// One to-do on the list Echo makes from a briefing.
///
/// Stored as JSON in shared preferences (see [TodoStore]) rather than Isar so
/// the native home-screen widgets can read it and tick items off directly.
/// Field names are part of that contract — `TodoWidgetData.kt` reads them.
class TodoItem {
  final int id;
  final String title;

  /// The calendar day the item belongs to. Items are never moved or deleted:
  /// "tomorrow" simply becomes "today" when the date comes round, and past
  /// days stay as history.
  final DateTime day;

  /// "6:30 PM", "4 PM to 6 PM", or null when no time was named.
  final String? time;

  /// Minutes into [day] used for ordering; items without a time sort last.
  final int sort;

  /// Where it came from, shown under the title and when expanded.
  final String sender;
  final String app;
  final String sourceText;

  /// Identifies the source notification so an update never adds the same
  /// notification twice.
  final String sourceKey;

  final bool done;

  /// When it was ticked off (null while not done) — "last one at 4:12 PM".
  final DateTime? doneAt;

  /// Added by the most recent update (drawn with a small dot).
  final bool isNew;

  /// The time before an update moved it ("moved from 6:30 PM").
  final String? movedFrom;

  final DateTime created;

  const TodoItem({
    required this.id,
    required this.title,
    required this.day,
    required this.time,
    required this.sort,
    required this.sender,
    required this.app,
    required this.sourceText,
    required this.sourceKey,
    required this.created,
    this.done = false,
    this.doneAt,
    this.isNew = false,
    this.movedFrom,
  });

  static const noTimeSort = 24 * 60;

  TodoItem copyWith({
    String? title,
    DateTime? day,
    String? time,
    int? sort,
    String? sourceText,
    String? sourceKey,
    bool? done,
    bool? isNew,
    String? movedFrom,
  }) => TodoItem(
    id: id,
    title: title ?? this.title,
    day: day ?? this.day,
    time: time ?? this.time,
    sort: sort ?? this.sort,
    sender: sender,
    app: app,
    sourceText: sourceText ?? this.sourceText,
    sourceKey: sourceKey ?? this.sourceKey,
    created: created,
    done: done ?? this.done,
    doneAt: doneAt,
    isNew: isNew ?? this.isNew,
    movedFrom: movedFrom ?? this.movedFrom,
  );

  /// Ticked on or off at [now].
  TodoItem withDone(bool value, DateTime now) => TodoItem(
    id: id,
    title: title,
    day: day,
    time: time,
    sort: sort,
    sender: sender,
    app: app,
    sourceText: sourceText,
    sourceKey: sourceKey,
    created: created,
    done: value,
    doneAt: value ? now : null,
    isNew: isNew,
    movedFrom: movedFrom,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'day': dayKey(day),
    'time': time,
    'sort': sort,
    'sender': sender,
    'app': app,
    'source': sourceText,
    'key': sourceKey,
    'done': done,
    'doneAt': doneAt?.millisecondsSinceEpoch,
    'new': isNew,
    'movedFrom': movedFrom,
    'created': created.millisecondsSinceEpoch,
  };

  static TodoItem fromJson(Map<String, dynamic> j) => TodoItem(
    id: j['id'] as int,
    title: j['title'] as String,
    day: parseDayKey(j['day'] as String),
    time: j['time'] as String?,
    sort: (j['sort'] as int?) ?? noTimeSort,
    sender: (j['sender'] as String?) ?? '',
    app: (j['app'] as String?) ?? '',
    sourceText: (j['source'] as String?) ?? '',
    sourceKey: (j['key'] as String?) ?? '',
    done: (j['done'] as bool?) ?? false,
    doneAt: j['doneAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(j['doneAt'] as int)
        : null,
    isNew: (j['new'] as bool?) ?? false,
    movedFrom: j['movedFrom'] as String?,
    created: DateTime.fromMillisecondsSinceEpoch((j['created'] as int?) ?? 0),
  );
}

/// Bookkeeping for the list: when it was made and last brought up to date.
/// [updatedAt] is the cut-off for "new notifications since your list".
class TodoMeta {
  final DateTime? madeAt;
  final DateTime? updatedAt;
  final int nextId;

  const TodoMeta({this.madeAt, this.updatedAt, this.nextId = 1});

  TodoMeta copyWith({DateTime? madeAt, DateTime? updatedAt, int? nextId}) =>
      TodoMeta(
        madeAt: madeAt ?? this.madeAt,
        updatedAt: updatedAt ?? this.updatedAt,
        nextId: nextId ?? this.nextId,
      );

  Map<String, dynamic> toJson() => {
    'madeAt': madeAt?.millisecondsSinceEpoch,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
    'nextId': nextId,
  };

  static TodoMeta fromJson(Map<String, dynamic> j) => TodoMeta(
    madeAt: _ms(j['madeAt']),
    updatedAt: _ms(j['updatedAt']),
    nextId: (j['nextId'] as int?) ?? 1,
  );

  static DateTime? _ms(Object? v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}
