import 'dart:io';

import 'package:flutter/services.dart';

/// What Echo knows about its home-screen widgets (Android only).
class HomeWidgetsState {
  /// Whether the launcher lets apps add widgets (requestPinAppWidget).
  final bool canPin;

  /// How many of each widget are on the home screen, by kind
  /// (`todo`, `ring`, `brief`, `streak`).
  final Map<String, int> placed;

  /// What the Briefing and Streak widgets currently show.
  final int streak;
  final String status;

  /// Mon→Sun: 0 future, 1 missed, 2 done, 3 today (see WidgetData.kt).
  final List<int> week;

  const HomeWidgetsState({
    required this.canPin,
    required this.placed,
    required this.streak,
    required this.status,
    required this.week,
  });

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
      return HomeWidgetsState(
        canPin: raw['canPin'] as bool? ?? false,
        placed: Map<String, int>.from(raw['placed'] as Map? ?? const {}),
        streak: raw['streak'] as int? ?? 0,
        status: raw['status'] as String? ?? '',
        week: List<int>.from(raw['week'] as List? ?? const []),
      );
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
