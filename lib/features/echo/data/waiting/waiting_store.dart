import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
import 'package:project_echo/features/echo/data/waiting/wait_model.dart';
import 'package:project_echo/features/history/data/opened_chats.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One message that wants the owner, or that Echo left off the list.
class WaitingItem {
  final RawData message;
  final WaitReason reason;

  /// 0 today, 1 yesterday, 2 two days ago or more.
  final int ageBand;

  /// How full the ring around their face is, 0 to 1.
  final double ageProgress;

  /// "40 min", "Since yesterday", "2 days".
  final String since;

  /// When a holding reply went out, if one did.
  final DateTime? heldAt;

  /// When the owner asked to be reminded about the held reply.
  final DateTime? heldUntil;

  const WaitingItem({
    required this.message,
    required this.reason,
    required this.ageBand,
    required this.ageProgress,
    required this.since,
    this.heldAt,
    this.heldUntil,
  });

  /// This message, in the stores.
  String get key => sourceKeyOf(message);

  String get personKey => personKeyFor(message.sender, message.source);

  bool get held => heldAt != null;
}

/// Today's list, and the row of messages Echo left off it.
class WaitingFeed {
  /// Oldest first.
  final List<WaitingItem> waiting;

  /// Newest first; today's only.
  final List<WaitingItem> acks;

  /// Unclear messages the model hasn't read yet.
  final List<String> grey;

  const WaitingFeed({
    this.waiting = const [],
    this.acks = const [],
    this.grey = const [],
  });

  static const empty = WaitingFeed();
}

/// Everything the owner has told Echo about the list.
class WaitFeedback {
  /// "No reply needed", by message key: when it was said.
  final Map<String, int> off;

  /// "It does", by message key.
  final Map<String, int> on;

  /// Swiped away, by message key. Says nothing about the words in it.
  final Map<String, int> handled;

  /// Holding replies, by message key: {at, text, thread, until}.
  final Map<String, Map<String, dynamic>> held;

  /// Phrase → the people it needed no reply from.
  final Map<String, List<String>> phraseOff;

  /// Phrase → the people it did need one from.
  final Map<String, List<String>> phraseOn;

  /// Person → how many of their messages needed no reply.
  final Map<String, int> senderOff;

  WaitFeedback({
    Map<String, int>? off,
    Map<String, int>? on,
    Map<String, int>? handled,
    Map<String, Map<String, dynamic>>? held,
    Map<String, List<String>>? phraseOff,
    Map<String, List<String>>? phraseOn,
    Map<String, int>? senderOff,
  }) : off = off ?? {},
       on = on ?? {},
       handled = handled ?? {},
       held = held ?? {},
       phraseOff = phraseOff ?? {},
       phraseOn = phraseOn ?? {},
       senderOff = senderOff ?? {};

  /// After this many, the person's unclear messages stay off the list.
  static const senderLearnedAt = 3;

  /// A phrase said to need no reply by this many people counts for everyone.
  static const phraseLearnedAt = 2;

  bool phraseIsOff(String phrase, String sender) {
    final who = phraseOff[phrase];
    if (who == null) return false;
    return who.contains(sender) || who.length >= phraseLearnedAt;
  }

  bool phraseIsOn(String phrase, String sender) =>
      phraseOn[phrase]?.contains(sender) ?? false;

  bool senderIsOff(String sender) =>
      (senderOff[sender] ?? 0) >= senderLearnedAt;

  Map<String, dynamic> toJson() => {
    'off': off,
    'on': on,
    'handled': handled,
    'held': held,
    'phraseOff': phraseOff,
    'phraseOn': phraseOn,
    'senderOff': senderOff,
  };

  factory WaitFeedback.fromJson(Map<String, dynamic> j) => WaitFeedback(
    off: _ints(j['off']),
    on: _ints(j['on']),
    handled: _ints(j['handled']),
    held: {
      if (j['held'] is Map)
        for (final MapEntry(:key, :value) in (j['held'] as Map).entries)
          if (value is Map) key as String: Map<String, dynamic>.from(value),
    },
    phraseOff: _lists(j['phraseOff']),
    phraseOn: _lists(j['phraseOn']),
    senderOff: _ints(j['senderOff']),
  );

  static Map<String, int> _ints(Object? v) => {
    if (v is Map)
      for (final MapEntry(:key, :value) in v.entries)
        if (value is int) key as String: value,
  };

  static Map<String, List<String>> _lists(Object? v) => {
    if (v is Map)
      for (final MapEntry(:key, :value) in v.entries)
        if (value is List) key as String: value.whereType<String>().toList(),
  };

  /// Marks are kept this long past being made, well beyond retention.
  static const _keep = Duration(days: 30);
  static const _maxPhrases = 300;
  static const _maxSenders = 400;

  void prune(DateTime now) {
    final cut = now.subtract(_keep).millisecondsSinceEpoch;
    off.removeWhere((_, t) => t < cut);
    on.removeWhere((_, t) => t < cut);
    handled.removeWhere((_, t) => t < cut);
    held.removeWhere((_, h) => ((h['at'] as int?) ?? 0) < cut);
    while (phraseOff.length > _maxPhrases) {
      phraseOff.remove(phraseOff.keys.first);
    }
    while (phraseOn.length > _maxPhrases) {
      phraseOn.remove(phraseOn.keys.first);
    }
    while (senderOff.length > _maxSenders) {
      senderOff.remove(senderOff.keys.first);
    }
  }
}

/// Who's waiting on the owner, worked out on the phone from what's retained.
///
/// Every write reloads first: other isolates write the same prefs file.
class WaitingStore {
  WaitingStore._();

  static const _key = 'waiting_store_v1';

  /// Ticks when the list changed for a reason the screen can't see: the owner
  /// said something about it, or the model finished reading.
  static final changed = ValueNotifier<int>(0);

  /// An item with no deadline ahead of it leaves the list after this long.
  static const expiresAfter = Duration(days: 3);

  /// How far back through a chat's unanswered messages to look for the ask.
  static const _walk = 10;

  /// At most this many messages Echo left off the list.
  static const _maxAcks = 30;

  static Future<WaitingFeed> load(
    DateTime now, {
    List<RawData>? entries,
    MyTurns? turns,
  }) async {
    final all =
        entries ??
        await withoutExcludedSources(await IsarDataSource.getAllEntries());
    final feed = compose(
      all,
      turns ?? await ChatContextStore.loadMyTurns(),
      now,
      feedback: await _read(),
      verdicts: await WaitModel.cached(),
      opened: await _opened(),
    );
    if (feed.grey.isNotEmpty) {
      unawaited(
        WaitModel.resolve(feed.grey).then((decided) {
          if (decided > 0) changed.value++;
        }),
      );
    }
    return feed;
  }

  static Future<Map<String, int>> _opened() async {
    try {
      return await OpenedChats.load();
    } catch (_) {
      return const {};
    }
  }

  /// The pure part of [load]. [opened] is when each thread was last opened or
  /// read in its own app, in epoch milliseconds.
  static WaitingFeed compose(
    Iterable<RawData> entries,
    MyTurns turns,
    DateTime now, {
    WaitFeedback? feedback,
    Map<String, bool> verdicts = const {},
    Map<String, int> opened = const {},
  }) {
    final fb = feedback ?? WaitFeedback();
    final byChat = <String, List<RawData>>{};
    for (final e in entries) {
      final addressed = Addressed.parse(e.addressed);
      if (addressed == null || addressed == Addressed.group) continue;
      if (e.timestamp.isAfter(now)) continue;
      (byChat[e.thread ?? e.sender] ??= []).add(e);
    }

    final today = startOfDay(now);
    final waiting = <WaitingItem>[];
    final acks = <WaitingItem>[];
    final grey = <String>{};

    for (final msgs in byChat.values) {
      msgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final thread = msgs.first.thread;
      final mine = _lastRealTurn(turns, thread, now, fb);
      final openedMs = thread == null ? null : opened[thread];
      final openedAt = openedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(openedMs);

      var walked = 0;
      WaitingItem? newestAck;
      var asked = false;
      for (final m in msgs.take(_walk)) {
        walked++;
        final key = sourceKeyOf(m);
        final held = fb.held[key];
        if (mine != null && !m.timestamp.isAfter(mine.at)) break;
        if (fb.handled.containsKey(key)) break;
        // Read in its own app since it came in; a hold stays until a real reply.
        if (held == null &&
            openedAt != null &&
            !m.timestamp.isAfter(openedAt)) {
          break;
        }
        if (fb.off.containsKey(key)) {
          if (walked == 1 && !m.timestamp.isBefore(today)) {
            acks.add(
              _item(
                m,
                _classified(m).copyWith(
                  needsReply: false,
                  label: 'You said no reply needed',
                ),
                now,
              ),
            );
          }
          break;
        }

        final reason = _judge(m, fb, verdicts, grey);
        if (reason.needsReply) {
          if (held == null && _expired(m, now)) break;
          waiting.add(
            _item(m, _withContext(reason, m, mine, now), now, held: held),
          );
          asked = true;
          break;
        }
        if (walked == 1 &&
            reason.kind != WaitKind.code &&
            !m.timestamp.isBefore(today)) {
          newestAck = _item(m, _ackReason(reason, m, mine), now);
        }
      }
      if (!asked && newestAck != null) acks.add(newestAck);
    }

    waiting.sort((a, b) => a.message.timestamp.compareTo(b.message.timestamp));
    acks.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return WaitingFeed(
      waiting: waiting,
      acks: acks.take(_maxAcks).toList(),
      grey: grey.toList(),
    );
  }

  static WaitReason _classified(RawData m) =>
      classifyWait(m.content, isGroup: m.isGroup, addressed: m.addressed);

  /// The rules, then what the model said, then what the owner taught Echo.
  static WaitReason _judge(
    RawData m,
    WaitFeedback fb,
    Map<String, bool> verdicts,
    Set<String> grey,
  ) {
    var reason = _classified(m);
    final phrase = waitPhrase(m.content);
    final sender = personKeyFor(m.sender, m.source);

    if (fb.on.containsKey(sourceKeyOf(m))) {
      return reason.copyWith(
        needsReply: true,
        label: 'You said this needs a reply',
      );
    }
    if (phrase.isNotEmpty && fb.phraseIsOff(phrase, sender)) {
      return reason.copyWith(
        needsReply: false,
        label: 'You said things like this need no reply',
      );
    }
    if (phrase.isNotEmpty && fb.phraseIsOn(phrase, sender)) {
      return reason.copyWith(
        needsReply: true,
        label: 'You said this needs a reply',
      );
    }
    if (isGreyZone(reason.kind)) {
      if (fb.senderIsOff(sender)) {
        return reason.copyWith(
          needsReply: false,
          label: 'You rarely need to answer these',
        );
      }
      final verdict = verdicts[WaitModel.keyFor(m.content)];
      if (verdict == null) {
        if (phrase.isNotEmpty) grey.add(m.content);
        reason = reason.copyWith(
          signals: [
            ...reason.signals,
            'Echo can’t tell, so it stays on your list',
          ],
        );
      } else if (verdict) {
        reason = reason.copyWith(
          label: 'Looks like it needs a reply',
          signals: [...reason.signals, 'Reads like it wants an answer'],
        );
      } else {
        reason = reason.copyWith(
          kind: WaitKind.closer,
          needsReply: false,
          label: 'Doesn’t ask you anything',
        );
      }
    }
    return reason;
  }

  /// The owner's latest message in [thread], not counting holding replies.
  static MyTurn? _lastRealTurn(
    MyTurns turns,
    String? thread,
    DateTime now,
    WaitFeedback fb,
  ) {
    if (thread == null) return null;
    final holds = {
      for (final h in fb.held.values)
        if (h['thread'] == thread) h['text'],
    };
    MyTurn? best;
    for (final t in turns.byThread[thread] ?? const <MyTurn>[]) {
      if (t.at.isAfter(now) || holds.contains(t.text)) continue;
      if (best == null || t.at.isAfter(best.at)) best = t;
    }
    return best;
  }

  /// Too old to bring up, unless what it's about is still to come.
  static bool _expired(RawData m, DateTime now) {
    if (now.difference(m.timestamp) < expiresAfter) return false;
    return !relevanceWindows(
      m.content,
      m.timestamp,
    ).any((w) => w.explicit && w.end.isAfter(now));
  }

  static WaitingItem _item(
    RawData m,
    WaitReason reason,
    DateTime now, {
    Map<String, dynamic>? held,
  }) {
    final until = held?['until'] as int?;
    return WaitingItem(
      message: m,
      reason: reason,
      ageBand: ageBandOf(m.timestamp, now),
      ageProgress: ageProgressOf(m.timestamp, now),
      since: sinceLabel(m.timestamp, now),
      heldAt: held == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((held['at'] as int?) ?? 0),
      heldUntil: until == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(until),
    );
  }

  static WaitReason _withContext(
    WaitReason reason,
    RawData m,
    MyTurn? mine,
    DateTime now,
  ) {
    final signals = [...reason.signals];
    if (signals.isNotEmpty && signals.first == 'A one-to-one chat') {
      signals[0] = 'A one-to-one chat on ${m.source}';
    }
    signals.add(
      mine == null
          ? 'You haven’t written there since'
          : 'You haven’t written there since ${_whenWords(mine.at, now)}',
    );
    return reason.copyWith(signals: signals);
  }

  static WaitReason _ackReason(WaitReason reason, RawData m, MyTurn? mine) {
    final afterReply =
        reason.kind == WaitKind.ack &&
        mine != null &&
        m.timestamp.difference(mine.at) <= const Duration(minutes: 20);
    return afterReply
        ? reason.copyWith(label: 'An ok, right after your reply')
        : reason;
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _whenWords(DateTime t, DateTime now) {
    final days = _daysBetween(t, now);
    if (days == 0) return 'today, ${_clock(t)}';
    if (days == 1) return 'yesterday, ${_clock(t)}';
    const week = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return week[t.weekday - 1];
  }

  /// Calendar days from [t] to [now], whatever the clocks did in between.
  static int _daysBetween(DateTime t, DateTime now) => DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(t.year, t.month, t.day)).inDays;

  static int ageBandOf(DateTime t, DateTime now) =>
      _daysBetween(t, now).clamp(0, 2);

  /// Fills quickly at first and slowly later: a third in an hour, nearly all
  /// of it in two days.
  static double ageProgressOf(DateTime t, DateTime now) {
    final hours = now.difference(t).inMinutes / 60;
    if (hours <= 0) return 0.06;
    return (0.3 * math.pow(hours, 0.29)).clamp(0.06, 1.0).toDouble();
  }

  static String sinceLabel(DateTime t, DateTime now) {
    final days = _daysBetween(t, now);
    if (days == 1) return 'Since yesterday';
    if (days >= 2) return '$days days';
    final minutes = now.difference(t).inMinutes;
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    return hours == 1 ? '1 hr' : '$hours hrs';
  }

  // ── What the owner says about the list ──────────────────────────────────

  /// "No reply needed": gone for good, and Echo learns from it.
  static Future<void> markNoReplyNeeded(
    WaitingItem i, {
    bool notify = true,
  }) async {
    await _write((fb, now) {
      fb.off[i.key] = now;
      fb.on.remove(i.key);
      fb.held.remove(i.key);
      final phrase = waitPhrase(i.message.content);
      if (phrase.isNotEmpty) {
        final who = fb.phraseOff[phrase] ?? const [];
        fb.phraseOff[phrase] = {...who, i.personKey}.toList();
        fb.phraseOn[phrase]?.remove(i.personKey);
      }
      fb.senderOff[i.personKey] = (fb.senderOff[i.personKey] ?? 0) + 1;
    }, notify);
  }

  /// "It does": back on the list, and Echo learns from it.
  static Future<void> markNeedsReply(
    WaitingItem i, {
    bool notify = true,
  }) async {
    await _write((fb, now) {
      fb.on[i.key] = now;
      fb.off.remove(i.key);
      final phrase = waitPhrase(i.message.content);
      if (phrase.isNotEmpty) {
        final who = fb.phraseOn[phrase] ?? const [];
        fb.phraseOn[phrase] = {...who, i.personKey}.toList();
        final was = fb.phraseOff[phrase];
        if (was != null) {
          was.remove(i.personKey);
          if (was.isEmpty) fb.phraseOff.remove(phrase);
        }
      }
      final count = fb.senderOff[i.personKey];
      if (count != null) {
        count <= 1
            ? fb.senderOff.remove(i.personKey)
            : fb.senderOff[i.personKey] = count - 1;
      }
    }, notify);
  }

  /// Swiped away: dealt with some other way. Teaches Echo nothing.
  static Future<void> markHandled(WaitingItem i, {bool notify = true}) =>
      _write((fb, now) => fb.handled[i.key] = now, notify);

  static Future<void> undoHandled(WaitingItem i) =>
      _write((fb, _) => fb.handled.remove(i.key), true);

  /// A holding reply went out; the person stays until a real one does.
  static Future<void> markHeld(
    WaitingItem i, {
    required String text,
    DateTime? until,
  }) => _write((fb, now) {
    fb.held[i.key] = {
      'at': now,
      'text': text,
      'thread': i.message.thread,
      'until': ?until?.millisecondsSinceEpoch,
    };
  }, true);

  static Future<WaitFeedback> _read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _decode(prefs.getString(_key));
  }

  static WaitFeedback _decode(String? raw) {
    try {
      final json = jsonDecode(raw ?? '{}');
      return json is Map<String, dynamic>
          ? WaitFeedback.fromJson(json)
          : WaitFeedback();
    } catch (_) {
      return WaitFeedback();
    }
  }

  static Future<void> _write(
    void Function(WaitFeedback fb, int nowMs) change,
    bool notify,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final fb = _decode(prefs.getString(_key));
    final now = DateTime.now();
    change(fb, now.millisecondsSinceEpoch);
    fb.prune(now);
    await prefs.setString(_key, jsonEncode(fb.toJson()));
    if (notify) changed.value++;
    // The home-screen widget shows this list too.
    unawaited(WidgetRefreshService.refresh().catchError((_) {}));
  }

  /// What's been said so far, for tests.
  @visibleForTesting
  static Future<WaitFeedback> feedback() => _read();
}
