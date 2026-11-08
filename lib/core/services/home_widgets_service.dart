import 'dart:io';

import 'package:flutter/services.dart';

/// One face on the Waiting widget, as the widget draws it.
class WidgetFace {
  final String name, since;
  final String source;

  /// 0 fresh, 1 since yesterday, 2 two days or more.
  final int age;
  final double progress;

  const WidgetFace({
    required this.name,
    required this.since,
    required this.source,
    required this.age,
    required this.progress,
  });
}

/// What the Next to-do widget is showing.
class WidgetNextTodo {
  final String title;
  final String? due, countdown;
  final String app;

  const WidgetNextTodo({
    required this.title,
    required this.due,
    required this.countdown,
    required this.app,
  });
}

/// What Echo knows about its home-screen widgets (Android only).
class HomeWidgetsState {
  /// Whether the launcher lets apps add widgets (requestPinAppWidget).
  final bool canPin;

  /// How many of each widget are on the home screen, by kind
  /// (`todo` Next to-do, `ring` Waiting on you, `brief` Today, `streak` Echo).
  final Map<String, int> placed;

  /// What the Briefing and Streak widgets currently show.
  final int streak;
  final String status;

  /// Mon→Sun: 0 future, 1 missed, 2 done, 3 today (see WidgetData.kt).
  final List<int> week;

  /// What the widgets show, read the same way they read it (WidgetData.kt).
  final String date;
  final bool ready;

  /// Whether the morning briefing is on; off means none is on its way.
  final bool briefingOn;
  final bool listening;

  /// False until Echo has heard anything to say who's waiting.
  final bool waitingKnown;
  final List<WidgetFace> waiting;
  final int waitingCount;
  final int oldestDays;
  final bool hasList;
  final int dueToday;
  final int todosToday;
  final int tomorrow;
  final WidgetNextTodo? next;
  final String? tomorrowTitle;
  final int owesYou;

  const HomeWidgetsState({
    required this.canPin,
    required this.placed,
    required this.streak,
    required this.status,
    required this.week,
    this.date = '',
    this.ready = false,
    this.briefingOn = true,
    this.listening = false,
    this.waitingKnown = false,
    this.waiting = const [],
    this.waitingCount = 0,
    this.oldestDays = 0,
    this.hasList = false,
    this.dueToday = 0,
    this.todosToday = 0,
    this.tomorrow = 0,
    this.next,
    this.tomorrowTitle,
    this.owesYou = 0,
  });

  /// Reads the `state` call's answer (MainActivity + WidgetData.previewState).
  factory HomeWidgetsState.fromNative(Map<String, dynamic> raw) {
    final next = raw['next'] as Map?;
    return HomeWidgetsState(
      canPin: raw['canPin'] as bool? ?? false,
      placed: Map<String, int>.from(raw['placed'] as Map? ?? const {}),
      streak: raw['streak'] as int? ?? 0,
      status: raw['status'] as String? ?? '',
      week: List<int>.from(raw['week'] as List? ?? const []),
      date: raw['date'] as String? ?? '',
      ready: raw['ready'] as bool? ?? false,
      briefingOn: raw['briefingOn'] as bool? ?? true,
      listening: raw['listening'] as bool? ?? false,
      waitingKnown: raw['waitingKnown'] as bool? ?? false,
      waiting: [
        for (final f in raw['waiting'] as List? ?? const [])
          WidgetFace(
            name: (f as Map)['name'] as String? ?? '',
            since: f['since'] as String? ?? '',
            source: f['source'] as String? ?? '',
            age: f['age'] as int? ?? 0,
            progress: (f['progress'] as num? ?? 0).toDouble(),
          ),
      ],
      waitingCount: raw['waitingCount'] as int? ?? 0,
      oldestDays: raw['oldestDays'] as int? ?? 0,
      hasList: raw['hasList'] as bool? ?? false,
      dueToday: raw['dueToday'] as int? ?? 0,
      todosToday: raw['todosToday'] as int? ?? 0,
      tomorrow: raw['tomorrow'] as int? ?? 0,
      next: next == null
          ? null
          : WidgetNextTodo(
              title: next['title'] as String? ?? '',
              due: next['due'] as String?,
              countdown: next['countdown'] as String?,
              app: next['app'] as String? ?? '',
            ),
      tomorrowTitle: raw['tomorrowTitle'] as String?,
      owesYou: raw['owesYou'] as int? ?? 0,
    );
  }

  int placedCount(String kind) => placed[kind] ?? 0;
  int get totalPlaced => placed.values.fold(0, (a, b) => a + b);
  int get kindsPlaced => placed.values.where((n) => n > 0).length;
}

/// Adds Echo's widgets to the home screen from inside the app.
class HomeWidgetsService {
  static const _channel = MethodChannel('project_echo/widget');

  static bool get supported => Platform.isAndroid;

  static Future<HomeWidgetsState?> state() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('state');
      if (raw == null) return null;
      return HomeWidgetsState.fromNative(raw);
    } catch (_) {
      return null;
    }
  }

  /// Asks the launcher to add a widget. True means Android is showing its
  /// confirmation — not that the user said yes; compare [state] afterwards.
  static Future<bool> pin(String kind) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('pin', {'kind': kind}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
