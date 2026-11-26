import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Something the owner got out of Echo, right as it happens: the moments a
/// rating request is earned.
enum ReviewWin { briefingHeard, askAnswered, todoDone, reminderSet }

/// What [ReviewPolicy] decides on, as stored.
class ReviewHistory {
  /// Wins so far.
  final int wins;

  /// The different days wins came on (YYYY-MM-DD), the latest few.
  final List<String> winDays;

  /// When Play's review sheet was requested, oldest first.
  final List<DateTime> asked;

  const ReviewHistory({
    this.wins = 0,
    this.winDays = const [],
    this.asked = const [],
  });
}

/// When to ask for a rating, the way the better consumer apps do: only right
/// after a moment that went well, never at launch, on the first day or
/// mid-task, and rarely. Play's own sheet is asked for directly, with no
/// "Do you like Echo?" first: Play's policy forbids steering who gets it, and
/// Play decides itself whether to show it (it's quota-limited).
class ReviewPolicy {
  ReviewPolicy._();

  /// Wins before the first ask: someone who has had three good moments.
  static const minWins = 3;

  /// …on at least two different days, so it's someone who came back.
  static const minDays = 2;

  /// Asked again at most this often…
  static const gap = Duration(days: 120);

  /// …and at most this many times ever.
  static const maxAsks = 3;

  static bool shouldAsk(ReviewHistory h, DateTime now) {
    if (h.wins < minWins || h.winDays.length < minDays) return false;
    if (h.asked.length >= maxAsks) return false;
    if (h.asked.isNotEmpty && now.difference(h.asked.last) < gap) return false;
    return true;
  }
}

/// Counts wins and, when [ReviewPolicy] says so, opens Play's in-app review
/// sheet a moment after one, once the screen has settled.
class ReviewPrompt {
  ReviewPrompt._();

  static const _winsKey = 'review_wins';
  static const _daysKey = 'review_win_days';
  static const _askedKey = 'review_asked_ms';

  /// How long after a win the sheet is asked for, so it doesn't cover the
  /// moment itself.
  static const settle = Duration(milliseconds: 1500);

  static var _pending = false;

  /// Records [win] and asks for a rating if it's time.
  static Future<void> recordWin(ReviewWin win, {DateTime? now}) async {
    try {
      final at = now ?? DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final wins = (prefs.getInt(_winsKey) ?? 0) + 1;
      final today = _dateKey(at);
      final days = [...?prefs.getStringList(_daysKey)];
      if (!days.contains(today)) days.add(today);
      final kept = days.length > 5 ? days.sublist(days.length - 5) : days;
      await prefs.setInt(_winsKey, wins);
      await prefs.setStringList(_daysKey, kept);

      final history = ReviewHistory(
        wins: wins,
        winDays: kept,
        asked: [
          for (final ms in prefs.getStringList(_askedKey) ?? const <String>[])
            if (int.tryParse(ms) case final v?)
              DateTime.fromMillisecondsSinceEpoch(v),
        ],
      );
      if (_pending || !ReviewPolicy.shouldAsk(history, at)) return;
      _pending = true;
      unawaited(_ask(prefs, at, win));
    } catch (e) {
      debugPrint('Review prompt skipped: $e');
    }
  }

  static Future<void> _ask(
    SharedPreferences prefs,
    DateTime at,
    ReviewWin win,
  ) async {
    try {
      await Future<void>.delayed(settle);
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      // Counted as asked whether or not Play shows it: Play doesn't say.
      await prefs.setStringList(_askedKey, [
        ...?prefs.getStringList(_askedKey),
        '${at.millisecondsSinceEpoch}',
      ]);
      Analytics.track('review_requested', {'after': win.name});
      await review.requestReview();
    } catch (e) {
      debugPrint('Review prompt failed: $e');
    } finally {
      _pending = false;
    }
  }

  /// Opens Echo's Play listing, for a "Rate Echo" row the owner taps
  /// themselves (always works, unlike the quota-limited sheet).
  static Future<void> openListing() async {
    Analytics.track('review_listing_opened');
    await InAppReview.instance.openStoreListing();
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
