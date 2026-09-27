import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much of the user's Gemini allowance Echo has used today, and what it
/// has learned about their limits.
///
/// Google doesn't tell an API key how much quota is left, so Echo counts its
/// own calls: every completed call and every "overloaded" error (both count
/// against the daily limit), but not calls that were refused for a limit.
/// Google's day, and so the daily limit, resets at midnight Pacific time.
///
/// The daily limit itself comes from, in order: what this user's key hit
/// before (learned from Google's error), then `gemini_rpd` in the hosted
/// config. Until either is known, only the count is shown.
class GeminiUsage {
  GeminiUsage._();
  static final GeminiUsage instance = GeminiUsage._();

  static const _usageKey = 'gemini_usage_v1';
  static const _learnedKey = 'gemini_learned_limits_v1';

  /// The latest picture, for the Settings meter and the low-limit chip.
  final ValueNotifier<GeminiUsageSnapshot?> snapshot = ValueNotifier(null);

  /// Calls in the last minute or so, to tell a per-minute limit from a
  /// daily one (Google's error text doesn't say which).
  final List<DateTime> _recent = [];

  /// The config's daily limit for the current model, if it names one.
  int? configDailyLimit;

  String? _model;
  _Day _day = _Day.empty('');
  Map<String, int> _learned = {};
  DateTime? _blockedUntil;
  GeminiLimitKind? _blockedBy;
  String? _blockedModel;

  Future<void> load({required String model, DateTime? now}) async {
    _model = model;
    await _read(now ?? DateTime.now());
    _publish(now ?? DateTime.now());
  }

  /// Re-reads the stored count. Briefings also run in the background alarm
  /// isolate, which has its own copy of preferences, so every update starts
  /// from what's actually stored rather than from memory.
  Future<void> _read(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    _learned = Map<String, int>.from(
      jsonDecode(prefs.getString(_learnedKey) ?? '{}') as Map,
    );
    final raw = prefs.getString(_usageKey);
    _day = raw == null
        ? _Day.empty(pacificDay(now))
        : _Day.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// A call that reached Gemini and counted against the limit.
  Future<void> recordCall({
    required String model,
    int tokens = 0,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    _model = model;
    _recent.add(at);
    await _read(at);
    _roll(at);
    _day = _day.add(model, tokens);
    // A successful call means any per-minute block has passed.
    if (_blockedBy == GeminiLimitKind.perMinute) {
      _blockedUntil = null;
      _blockedBy = null;
    }
    await _save();
    _publish(at);
  }

  /// Notes what a failed call says about the limits, and returns the limit
  /// that was hit, if it was one.
  Future<GeminiLimitHit?> recordError(
    Object error, {
    required String model,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    _model = model;
    final text = errorText(error);
    if (isOverloaded(text)) {
      // Overloaded calls still count against the daily limit.
      await recordCall(model: model, now: at);
      return null;
    }
    final quota = parseQuotaError(text);
    if (quota == null) return null;

    await _read(at);
    _roll(at);
    final kind = classifyLimit(
      quota,
      callsLastMinute: _callsSince(at.subtract(const Duration(seconds: 70))),
      dailyLimit: dailyLimitFor(model),
    );
    final hit = GeminiLimitHit(
      kind: kind,
      limit: quota.limit,
      until: kind == GeminiLimitKind.perDay
          ? nextPacificMidnight(at)
          : at.add(Duration(seconds: (quota.retrySeconds ?? 60).ceil())),
    );
    if (kind == GeminiLimitKind.perDay && quota.limit != null) {
      _learned[model] = quota.limit!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_learnedKey, jsonEncode(_learned));
    }
    _blockedUntil = hit.until;
    _blockedBy = kind;
    _blockedModel = model;
    _publish(at);
    return hit;
  }

  int? dailyLimitFor(String model) => _learned[model] ?? configDailyLimit;

  int _callsSince(DateTime since) {
    _recent.removeWhere((t) => t.isBefore(since));
    return _recent.length;
  }

  /// Starts a fresh count when Google's day has turned over.
  void _roll(DateTime now) {
    final today = pacificDay(now);
    if (_day.day != today) {
      _day = _Day.empty(today);
      if (_blockedBy == GeminiLimitKind.perDay) {
        _blockedUntil = null;
        _blockedBy = null;
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usageKey, jsonEncode(_day.toJson()));
  }

  void _publish(DateTime now) {
    final model = _model;
    if (model == null) return;
    _roll(now);
    final blocked =
        _blockedModel == model &&
        _blockedUntil != null &&
        now.isBefore(_blockedUntil!);
    snapshot.value = GeminiUsageSnapshot(
      model: model,
      requests: _day.requests[model] ?? 0,
      tokens: _day.tokens[model] ?? 0,
      dailyLimit: dailyLimitFor(model),
      resetsAt: nextPacificMidnight(now),
      blockedUntil: blocked ? _blockedUntil : null,
      blockedBy: blocked ? _blockedBy : null,
    );
  }
}

enum GeminiLimitKind { perMinute, perDay }

class GeminiLimitHit {
  final GeminiLimitKind kind;
  final int? limit;
  final DateTime until;
  const GeminiLimitHit({
    required this.kind,
    required this.limit,
    required this.until,
  });
}

@immutable
class GeminiUsageSnapshot {
  final String model;
  final int requests;
  final int tokens;
  final int? dailyLimit;
  final DateTime resetsAt;
  final DateTime? blockedUntil;
  final GeminiLimitKind? blockedBy;

  const GeminiUsageSnapshot({
    required this.model,
    required this.requests,
    required this.tokens,
    required this.dailyLimit,
    required this.resetsAt,
    this.blockedUntil,
    this.blockedBy,
  });

  /// Requests left today, when the limit is known.
  int? get left => dailyLimit == null
      ? null
      : blockedBy == GeminiLimitKind.perDay
      ? 0
      : (dailyLimit! - requests).clamp(0, dailyLimit!);

  /// 0..1 of today's allowance left, when the limit is known.
  double? get fractionLeft =>
      dailyLimit == null || dailyLimit == 0 ? null : left! / dailyLimit!;

  /// Worth a quiet heads-up: a fifth or less left.
  bool get isLow => (fractionLeft ?? 1) <= 0.2;
}

class _Day {
  final String day;
  final Map<String, int> requests;
  final Map<String, int> tokens;
  const _Day(this.day, this.requests, this.tokens);
  _Day.empty(this.day) : requests = const {}, tokens = const {};

  _Day add(String model, int t) => _Day(
    day,
    {...requests, model: (requests[model] ?? 0) + 1},
    {...tokens, model: (tokens[model] ?? 0) + t},
  );

  Map<String, dynamic> toJson() => {
    'day': day,
    'requests': requests,
    'tokens': tokens,
  };
  static _Day fromJson(Map<String, dynamic> j) => _Day(
    j['day'] as String? ?? '',
    Map<String, int>.from(j['requests'] as Map? ?? {}),
    Map<String, int>.from(j['tokens'] as Map? ?? {}),
  );
}

// ── Pure helpers (tested) ──────────────────────────────────────────────────

/// The text of a Gemini error, without the package's type prefix.
String errorText(Object error) =>
    error is GenerativeAIException ? error.message : error.toString();

bool isOverloaded(String text) => RegExp(
  r'high demand|overloaded|UNAVAILABLE|503',
  caseSensitive: false,
).hasMatch(text);

bool isInvalidKey(Object error, String text) =>
    error is InvalidApiKey ||
    RegExp(
      r'API key not valid|API_KEY_INVALID|invalid api key',
      caseSensitive: false,
    ).hasMatch(text);

class QuotaError {
  final int? limit;
  final double? retrySeconds;
  final bool saysPerDay;
  const QuotaError({this.limit, this.retrySeconds, this.saysPerDay = false});
}

/// Reads Google's quota error, for example:
/// "You exceeded your current quota … * Quota exceeded for metric:
/// generativelanguage.googleapis.com/generate_content_free_tier_requests,
/// limit: 20, model: gemini-3.6-flash Please retry in 22.88s."
QuotaError? parseQuotaError(String text) {
  if (!RegExp(
    r'exceeded your current quota|Quota exceeded|RESOURCE_EXHAUSTED|rate limit',
    caseSensitive: false,
  ).hasMatch(text)) {
    return null;
  }
  final limit = RegExp(r'limit:\s*(\d+)').firstMatch(text);
  final retry = RegExp(
    r'retry in\s*([\d.]+)\s*s',
    caseSensitive: false,
  ).firstMatch(text);
  return QuotaError(
    limit: limit == null ? null : int.parse(limit.group(1)!),
    retrySeconds: retry == null ? null : double.tryParse(retry.group(1)!),
    saysPerDay: RegExp(r'PerDay|per day', caseSensitive: false).hasMatch(text),
  );
}

/// Google's text doesn't say which limit ran out, and its retry time is
/// short even for the daily one. If Echo itself made about [QuotaError.limit]
/// calls in the last minute, it was the per-minute limit; otherwise the day's.
GeminiLimitKind classifyLimit(
  QuotaError q, {
  required int callsLastMinute,
  int? dailyLimit,
}) {
  if (q.saysPerDay) return GeminiLimitKind.perDay;
  final limit = q.limit;
  if (limit == null) return GeminiLimitKind.perMinute;
  if (dailyLimit != null && limit == dailyLimit) return GeminiLimitKind.perDay;
  return callsLastMinute + 1 >= limit
      ? GeminiLimitKind.perMinute
      : GeminiLimitKind.perDay;
}

/// Google's day, as a date key: "2026-09-27".
String pacificDay(DateTime now) {
  final p = _toPacific(now.toUtc());
  return '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
}

/// When Google's day next turns over, in local time.
DateTime nextPacificMidnight(DateTime now) {
  final utc = now.toUtc();
  final p = _toPacific(utc);
  final midnight = DateTime.utc(p.year, p.month, p.day + 1);
  // Midnight Pacific, expressed in UTC: add back that date's offset.
  final offset = _isPacificDst(midnight) ? 7 : 8;
  return midnight.add(Duration(hours: offset)).toLocal();
}

/// Pacific wall-clock time for a UTC instant, as a UTC-flagged DateTime.
DateTime _toPacific(DateTime utc) {
  final standard = utc.subtract(const Duration(hours: 8));
  return _isPacificDst(standard)
      ? utc.subtract(const Duration(hours: 7))
      : standard;
}

/// US daylight time: second Sunday of March, 2 AM, to first Sunday of
/// November, 2 AM (checked on Pacific standard wall time).
bool _isPacificDst(DateTime pst) {
  final y = pst.year;
  final start = _nthSunday(y, 3, 2).add(const Duration(hours: 2));
  final end = _nthSunday(y, 11, 1).add(const Duration(hours: 1));
  return !pst.isBefore(start) && pst.isBefore(end);
}

DateTime _nthSunday(int year, int month, int n) {
  final first = DateTime.utc(year, month, 1);
  final toSunday = (DateTime.sunday - first.weekday) % 7;
  return first.add(Duration(days: toSunday + 7 * (n - 1)));
}

/// "12:30 PM"
String clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// What to tell the user when a Gemini call fails.
String friendlyGeminiError(Object error, {GeminiLimitHit? hit, DateTime? now}) {
  final text = errorText(error);
  if (hit != null && hit.kind == GeminiLimitKind.perDay) {
    return "Gemini's daily limit on your key is used up. It resets at "
        '${clockTime(hit.until)}.';
  }
  if (hit != null) {
    final wait = hit.until
        .difference(now ?? DateTime.now())
        .inSeconds
        .clamp(5, 3600);
    return 'Gemini needs a short break after a burst of requests. Try again '
        'in about ${wait < 60 ? '$wait seconds' : '${(wait / 60).ceil()} minutes'}.';
  }
  if (isOverloaded(text))
    return 'Gemini is busy right now. Try again in a moment.';
  if (isInvalidKey(error, text)) {
    return "Your Gemini key isn't working. Check it in Settings.";
  }
  return "I couldn't reach Gemini. Check your connection and try again.";
}

/// "gemini-3.5-flash-lite" → "Gemini 3.5 Flash-Lite"
String modelLabel(String id) {
  final parts = id.split('-');
  if (parts.length < 2 || parts.first != 'gemini') return id;
  String cap(String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);
  final rest = parts.skip(2).map(cap).join('-');
  return 'Gemini ${parts[1]}${rest.isEmpty ? '' : ' $rest'}';
}

/// 61200 → "61,200"
String grouped(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
