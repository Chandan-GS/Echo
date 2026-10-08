import 'package:flutter_test/flutter_test.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Google's real replies, from the provider test on 27 Sep 2026.
const dailyError =
    'You exceeded your current quota, please check your plan and billing details. '
    'For more information on this error, head to: https://ai.google.dev/gemini-api/docs/rate-limits. '
    'To monitor your current usage, head to: https://ai.dev/rate-limit. \n'
    '* Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, '
    'limit: 20, model: gemini-3.6-flash\nPlease retry in 22.885210526s.';
const minuteError =
    'You exceeded your current quota, please check your plan and billing details. '
    '* Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, '
    'limit: 15, model: gemini-3.5-flash-lite\nPlease retry in 30.33s.';
const overloaded =
    'This model is currently experiencing high demand. Spikes in demand are usually temporary. '
    'Please try again later.';

void main() {
  group('parseQuotaError', () {
    test('reads the limit and retry time', () {
      final q = parseQuotaError(dailyError)!;
      expect(q.limit, 20);
      expect(q.retrySeconds, closeTo(22.885, 0.001));
      expect(q.saysPerDay, isFalse);
    });

    test('ignores errors that are not about quota', () {
      expect(parseQuotaError(overloaded), isNull);
      expect(parseQuotaError('Connection refused'), isNull);
    });
  });

  group('classifyLimit', () {
    test('a burst that reached the limit is per-minute', () {
      final q = parseQuotaError(minuteError)!;
      expect(classifyLimit(q, callsLastMinute: 15), GeminiLimitKind.perMinute);
      expect(classifyLimit(q, callsLastMinute: 14), GeminiLimitKind.perMinute);
    });

    test('a refusal at a normal pace is the daily limit', () {
      final q = parseQuotaError(dailyError)!;
      expect(classifyLimit(q, callsLastMinute: 1), GeminiLimitKind.perDay);
    });

    test('a known daily limit settles it', () {
      final q = parseQuotaError(dailyError)!;
      expect(
        classifyLimit(q, callsLastMinute: 19, dailyLimit: 20),
        GeminiLimitKind.perDay,
      );
    });
  });

  group("Google's day", () {
    test('turns over at midnight Pacific (IST is 12:30 PM in summer)', () {
      // 27 Sep, 10:00 IST = 26 Sep, 21:30 PDT.
      final now = DateTime.utc(2026, 9, 27, 4, 30);
      expect(pacificDay(now), '2026-09-26');
      expect(nextPacificMidnight(now).toUtc(), DateTime.utc(2026, 9, 27, 7));
    });

    test('is eight hours behind UTC in winter', () {
      final now = DateTime.utc(2026, 12, 10, 12);
      expect(pacificDay(now), '2026-12-10');
      expect(nextPacificMidnight(now).toUtc(), DateTime.utc(2026, 12, 11, 8));
    });

    test('knows the daylight-saving switch', () {
      // 8 Mar 2026 is the second Sunday of March.
      expect(pacificDay(DateTime.utc(2026, 3, 8, 9, 30)), '2026-03-08');
      expect(pacificDay(DateTime.utc(2026, 3, 8, 7, 30)), '2026-03-07');
    });
  });

  group('friendlyGeminiError', () {
    final now = DateTime(2026, 9, 27, 10);

    test('the daily limit says when it resets', () {
      final hit = GeminiLimitHit(
        kind: GeminiLimitKind.perDay,
        limit: 20,
        until: DateTime(2026, 9, 27, 12, 30),
      );
      expect(
        friendlyGeminiError(ServerException(dailyError), hit: hit, now: now),
        "Gemini's daily limit on your key is used up. It resets at 12:30 PM.",
      );
    });

    test('the per-minute limit says how long to wait', () {
      final hit = GeminiLimitHit(
        kind: GeminiLimitKind.perMinute,
        limit: 15,
        until: now.add(const Duration(seconds: 31)),
      );
      expect(
        friendlyGeminiError(ServerException(minuteError), hit: hit, now: now),
        contains('about 31 seconds'),
      );
    });

    test('overloaded, a bad key, and anything else', () {
      expect(
        friendlyGeminiError(ServerException(overloaded)),
        'Gemini is busy right now. Try again in a moment.',
      );
      expect(
        friendlyGeminiError(InvalidApiKey('API key not valid.')),
        "Your Gemini key isn't working. Check it in Settings.",
      );
      expect(
        friendlyGeminiError(Exception('socket closed')),
        contains("couldn't reach Gemini"),
      );
    });
  });

  group('GeminiUsage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('counts calls and tokens, and learns the daily limit', () async {
      final usage = GeminiUsage.instance..configDailyLimit = null;
      final t = DateTime.utc(2026, 9, 27, 4);
      await usage.load(model: 'gemini-3.5-flash-lite', now: t);
      await usage.recordCall(
        model: 'gemini-3.5-flash-lite',
        tokens: 1500,
        now: t,
      );
      await usage.recordCall(
        model: 'gemini-3.5-flash-lite',
        tokens: 1600,
        now: t.add(const Duration(minutes: 5)),
      );
      var snap = usage.snapshot.value!;
      expect(snap.requests, 2);
      expect(snap.tokens, 3100);
      expect(snap.left, isNull); // limit not known yet

      final hit = await usage.recordError(
        ServerException(dailyError.replaceAll('limit: 20', 'limit: 2')),
        model: 'gemini-3.5-flash-lite',
        now: t.add(const Duration(minutes: 30)),
      );
      expect(hit!.kind, GeminiLimitKind.perDay);
      snap = usage.snapshot.value!;
      expect(snap.dailyLimit, 2);
      expect(snap.left, 0);
      expect(snap.blockedBy, GeminiLimitKind.perDay);
    });

    test(
      "an overloaded call still counts, and a new Pacific day starts fresh",
      () async {
        final usage = GeminiUsage.instance..configDailyLimit = 100;
        final t = DateTime.utc(2026, 9, 27, 4);
        await usage.load(model: 'm', now: t);
        await usage.recordError(
          ServerException(overloaded),
          model: 'm',
          now: t,
        );
        expect(usage.snapshot.value!.requests, 1);
        expect(usage.snapshot.value!.left, 99);

        // 27 Sep, 08:00 UTC is past midnight Pacific.
        await usage.recordCall(model: 'm', now: DateTime.utc(2026, 9, 27, 8));
        expect(usage.snapshot.value!.requests, 1);
      },
    );
  });
}
