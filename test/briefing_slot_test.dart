import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/utils/time_utils.dart';

void main() {
  group('dueBriefingSlot', () {
    test('runs a slot when the alarm fires on time', () {
      final slot = dueBriefingSlot(
        now: DateTime(2026, 11, 26, 7, 0, 3),
        times: ['07:00'],
      );
      expect(slot?.key, '2026-11-26_07:00');
      expect(slot?.time, const BriefingTime(7, 0));
    });

    test('runs a slot the alarm reached minutes late', () {
      final slot = dueBriefingSlot(
        now: DateTime(2026, 11, 26, 7, 6),
        times: ['07:00'],
        lastRunKey: '2026-11-25_07:00',
      );
      expect(slot?.key, '2026-11-26_07:00');
    });

    test('runs a slot the alarm reached hours late', () {
      final slot = dueBriefingSlot(
        now: DateTime(2026, 11, 26, 11, 40),
        times: ['07:00'],
        lastRunKey: '2026-11-25_07:00',
      );
      expect(slot?.key, '2026-11-26_07:00');
    });

    test('leaves a slot that is more than maxLateness old', () {
      expect(
        dueBriefingSlot(
          now: DateTime(2026, 11, 27, 3, 0),
          times: ['07:00'],
          lastRunKey: '2026-11-25_07:00',
        ),
        isNull,
      );
    });

    test('does nothing for a slot that already ran', () {
      expect(
        dueBriefingSlot(
          now: DateTime(2026, 11, 26, 7, 30),
          times: ['07:00'],
          lastRunKey: '2026-11-26_07:00',
        ),
        isNull,
      );
    });

    test('does nothing before the first slot of the day has started', () {
      expect(
        dueBriefingSlot(
          now: DateTime(2026, 11, 26, 6, 59),
          times: ['07:00'],
          lastRunKey: '2026-11-25_07:00',
        ),
        isNull,
      );
    });

    test('picks the most recent of several slots', () {
      final times = ['07:00', '13:00', '19:00'];
      expect(
        dueBriefingSlot(
          now: DateTime(2026, 11, 26, 13, 20),
          times: times,
          lastRunKey: '2026-11-26_07:00',
        )?.key,
        '2026-11-26_13:00',
      );
      // A morning alarm that arrives after the afternoon slot has started
      // runs the afternoon one; the afternoon alarm then finds it done.
      expect(
        dueBriefingSlot(
          now: DateTime(2026, 11, 26, 13, 5),
          times: times,
          lastRunKey: '2026-11-25_19:00',
        )?.key,
        '2026-11-26_13:00',
      );
      expect(
        dueBriefingSlot(
          now: DateTime(2026, 11, 26, 13, 6),
          times: times,
          lastRunKey: '2026-11-26_13:00',
        ),
        isNull,
      );
    });

    test('ignores slot order and malformed entries', () {
      expect(
        dueBriefingSlot(
          now: DateTime(2026, 11, 26, 20, 0),
          times: ['19:00', 'garbage', '07:00'],
        )?.key,
        '2026-11-26_19:00',
      );
      expect(dueBriefingSlot(now: DateTime(2026), times: ['x', '']), isNull);
    });

    test(
      'a late-night slot caught after midnight belongs to the day before',
      () {
        final slot = dueBriefingSlot(
          now: DateTime(2026, 11, 27, 0, 1),
          times: ['23:59'],
          lastRunKey: '2026-11-25_23:59',
        );
        expect(slot?.key, '2026-11-26_23:59');
        expect(
          dueBriefingSlot(
            now: DateTime(2026, 11, 27, 0, 1),
            times: ['23:59'],
            lastRunKey: '2026-11-26_23:59',
          ),
          isNull,
        );
      },
    );

    test('wraps across month and year ends', () {
      expect(
        dueBriefingSlot(
          now: DateTime(2027, 1, 1, 0, 30),
          times: ['23:30'],
        )?.key,
        '2026-12-31_23:30',
      );
    });

    test('keeps the key format earlier builds stored', () {
      // Builds before this one recorded `<ISO date>_<stored time>`, so a slot
      // that ran just before an update isn't run twice.
      final today = DateTime(2026, 11, 26, 7, 1);
      final legacyKey = '${today.toIso8601String().split('T').first}_07:00';
      expect(
        dueBriefingSlot(now: today, times: ['07:00'], lastRunKey: legacyKey),
        isNull,
      );
    });
  });
}
