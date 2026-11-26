import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/review_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 11, 26, 9);

  group('when to ask for a rating', () {
    test('not before three good moments on two different days', () {
      expect(
        ReviewPolicy.shouldAsk(
          const ReviewHistory(wins: 5, winDays: ['2026-11-26']),
          now,
        ),
        isFalse,
        reason: 'a first day, however good',
      );
      expect(
        ReviewPolicy.shouldAsk(
          const ReviewHistory(wins: 2, winDays: ['2026-11-25', '2026-11-26']),
          now,
        ),
        isFalse,
      );
      expect(
        ReviewPolicy.shouldAsk(
          const ReviewHistory(wins: 3, winDays: ['2026-11-25', '2026-11-26']),
          now,
        ),
        isTrue,
      );
    });

    test('again only after 120 days, and three times at most', () {
      const days = ['2026-11-25', '2026-11-26'];
      expect(
        ReviewPolicy.shouldAsk(
          ReviewHistory(
            wins: 9,
            winDays: days,
            asked: [now.subtract(const Duration(days: 30))],
          ),
          now,
        ),
        isFalse,
      );
      expect(
        ReviewPolicy.shouldAsk(
          ReviewHistory(
            wins: 9,
            winDays: days,
            asked: [now.subtract(const Duration(days: 121))],
          ),
          now,
        ),
        isTrue,
      );
      expect(
        ReviewPolicy.shouldAsk(
          ReviewHistory(
            wins: 30,
            winDays: days,
            asked: [
              for (final d in [500, 360, 200]) now.subtract(Duration(days: d)),
            ],
          ),
          now,
        ),
        isFalse,
      );
    });
  });

  test('wins are counted with the days they came on', () async {
    SharedPreferences.setMockInitialValues({});
    await ReviewPrompt.recordWin(ReviewWin.briefingHeard, now: now);
    await ReviewPrompt.recordWin(ReviewWin.askAnswered, now: now);
    await ReviewPrompt.recordWin(
      ReviewWin.todoDone,
      now: now.add(const Duration(days: 1)),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('review_wins'), 3);
    expect(prefs.getStringList('review_win_days'), [
      '2026-11-26',
      '2026-11-27',
    ]);
  });
}
