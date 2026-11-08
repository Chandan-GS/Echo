import 'dart:convert';

import 'package:flutter/services.dart';

/// What one run of quiet hours has held, as the listener tells it.
class QuietSession {
  /// When the first message was held; History's marks start here.
  final DateTime since;
  final DateTime start;
  final DateTime end;
  final int count;
  final int groups;
  final int deliveries;
  final int other;
  final List<String> through;

  /// The phone restarted while these were held, so they won't reappear.
  final bool restarted;

  final DateTime? closedAt;

  const QuietSession({
    required this.since,
    required this.start,
    required this.end,
    required this.count,
    required this.groups,
    required this.deliveries,
    required this.other,
    required this.through,
    required this.restarted,
    required this.closedAt,
  });

  static DateTime _time(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch((ms as num?)?.toInt() ?? 0);

  static QuietSession? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return QuietSession(
      since: _time(json['since']),
      start: _time(json['start']),
      end: _time(json['end']),
      count: (json['count'] as num?)?.toInt() ?? 0,
      groups: (json['groups'] as num?)?.toInt() ?? 0,
      deliveries: (json['deliveries'] as num?)?.toInt() ?? 0,
      other: (json['other'] as num?)?.toInt() ?? 0,
      through: [...?(json['through'] as List?)?.cast<String>()],
      restarted: json['restarted'] == true,
      closedAt: json['closedAt'] == null ? null : _time(json['closedAt']),
    );
  }
}

/// How quiet hours stand right now.
class QuietStatus {
  final QuietSession? session;
  final QuietSession? lastDigest;

  /// This phone isn't letting Echo hold notifications, so they keep arriving.
  final bool blocked;

  /// Whether Echo can currently hear notifications at all.
  final bool listening;

  const QuietStatus({
    this.session,
    this.lastDigest,
    this.blocked = false,
    this.listening = false,
  });

  static const none = QuietStatus();

  static QuietStatus parse(String? raw) {
    if (raw == null) return none;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return QuietStatus(
        session: QuietSession.fromJson(j['session']),
        lastDigest: QuietSession.fromJson(j['lastDigest']),
        blocked: j['blocked'] == true,
        listening: j['listening'] == true,
      );
    } catch (_) {
      return none;
    }
  }
}

/// The bridge to QuietHours.kt. Everything here is a no-op on a computer.
class QuietNative {
  QuietNative._();

  static const _channel = MethodChannel('project_echo/quiet');

  static Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<QuietStatus> status() async =>
      QuietStatus.parse(await _call<String>('status'));

  /// Tells the listener the settings changed.
  static Future<QuietStatus> sync() async =>
      QuietStatus.parse(await _call<String>('sync'));

  /// Asks for everything held back now. How many were asked for, or -1 when
  /// Echo isn't listening and can't.
  static Future<int> deliverNow() async =>
      await _call<int>('deliverNow') ?? -1;

  /// Clears the digest, and what came back with it, from the shade.
  static Future<void> clearDigest() => _call<void>('clearDigest');
}
