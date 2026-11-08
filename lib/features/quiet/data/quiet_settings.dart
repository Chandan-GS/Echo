import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/quiet/data/quiet_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One run of quiet hours.
class QuietWindow {
  final DateTime start;
  final DateTime end;
  const QuietWindow(this.start, this.end);
}

/// The owner's quiet hours. Off until they turn it on. Read by the native
/// listener too (QuietHours.kt), which keeps [activeWindow]'s rules in step.
@immutable
class QuietConfig {
  final bool enabled;

  /// Minutes after midnight. An end at or before the start runs past midnight.
  final int startMin;
  final int endMin;

  /// Days a window may start on, 1 = Monday … 7 = Sunday.
  final Set<int> days;

  /// False for the 9 AM to 1 PM preset, true once the owner picks their own.
  final bool custom;

  final bool people;
  final bool calendar;
  final bool deliveries;

  /// Names of people who always get through, whatever else is on.
  final List<String> through;

  /// What the owner goes by, so the listener can spot mentions.
  final List<String> names;

  const QuietConfig({
    this.enabled = false,
    this.startMin = presetStart,
    this.endMin = presetEnd,
    this.days = weekdays,
    this.custom = false,
    this.people = true,
    this.calendar = true,
    this.deliveries = false,
    this.through = const [],
    this.names = const [],
  });

  static const presetStart = 9 * 60;
  static const presetEnd = 13 * 60;
  static const weekdays = {1, 2, 3, 4, 5};

  QuietConfig copyWith({
    bool? enabled,
    int? startMin,
    int? endMin,
    Set<int>? days,
    bool? custom,
    bool? people,
    bool? calendar,
    bool? deliveries,
    List<String>? through,
    List<String>? names,
  }) => QuietConfig(
    enabled: enabled ?? this.enabled,
    startMin: startMin ?? this.startMin,
    endMin: endMin ?? this.endMin,
    days: days ?? this.days,
    custom: custom ?? this.custom,
    people: people ?? this.people,
    calendar: calendar ?? this.calendar,
    deliveries: deliveries ?? this.deliveries,
    through: through ?? this.through,
    names: names ?? this.names,
  );

  /// The window [now] falls in: today's, or yesterday's if it runs past
  /// midnight. Null outside one, when off, or if start and end are equal.
  QuietWindow? activeWindow(DateTime now) {
    if (!enabled || startMin == endMin) return null;
    for (final back in const [0, 1]) {
      final w = _windowOn(DateTime(now.year, now.month, now.day - back));
      if (w != null && !now.isBefore(w.start) && now.isBefore(w.end)) return w;
    }
    return null;
  }

  /// The next window to start after [now], looking a week ahead.
  QuietWindow? nextWindow(DateTime now) {
    if (!enabled || startMin == endMin || days.isEmpty) return null;
    for (var ahead = 0; ahead <= 7; ahead++) {
      final w = _windowOn(DateTime(now.year, now.month, now.day + ahead));
      if (w != null && w.start.isAfter(now)) return w;
    }
    return null;
  }

  QuietWindow? _windowOn(DateTime day) {
    if (!days.contains(day.weekday)) return null;
    final endDay = endMin > startMin ? day.day : day.day + 1;
    return QuietWindow(
      DateTime(day.year, day.month, day.day, startMin ~/ 60, startMin % 60),
      DateTime(day.year, day.month, endDay, endMin ~/ 60, endMin % 60),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'startMin': startMin,
    'endMin': endMin,
    'days': days.toList()..sort(),
    'custom': custom,
    'people': people,
    'calendar': calendar,
    'deliveries': deliveries,
    'through': through,
    'names': names,
  };

  /// Unreadable or missing settings are simply off.
  static QuietConfig fromJson(String? raw) {
    if (raw == null) return const QuietConfig();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return QuietConfig(
        enabled: j['enabled'] == true,
        startMin: j['startMin'] as int? ?? presetStart,
        endMin: j['endMin'] as int? ?? presetEnd,
        days: {...?(j['days'] as List?)?.cast<int>()},
        custom: j['custom'] == true,
        people: j['people'] != false,
        calendar: j['calendar'] != false,
        deliveries: j['deliveries'] == true,
        through: [...?(j['through'] as List?)?.cast<String>()],
        names: [...?(j['names'] as List?)?.cast<String>()],
      );
    } catch (_) {
      return const QuietConfig();
    }
  }
}

/// Where the owner's quiet hours are kept.
class QuietSettings {
  QuietSettings._();

  static const key = 'quiet_config_v1';

  static Future<QuietConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return QuietConfig.fromJson(prefs.getString(key));
  }

  /// Saves [c] and has the listener act on it straight away, so turning
  /// quiet hours off hands back what's being held.
  static Future<void> save(QuietConfig c) async {
    final prefs = await SharedPreferences.getInstance();
    final names = ownerNames(
      prefs.getString('user_name'),
      await ChatContextStore.selfNames(),
    );
    await prefs.setString(
      key,
      jsonEncode(c.copyWith(names: names.toList()).toJson()),
    );
    await QuietNative.sync();
  }
}
