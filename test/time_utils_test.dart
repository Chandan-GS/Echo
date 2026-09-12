import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/utils/time_utils.dart';

void main() {
  group('parseBriefingTime', () {
    test('parses a valid HH:mm string', () {
      final t = parseBriefingTime('07:30');
      expect(t, isNotNull);
      expect(t!.hour, 7);
      expect(t.minute, 30);
      expect(t.minutesOfDay, 7 * 60 + 30);
    });

    test('parses boundary times midnight and end-of-day', () {
      expect(parseBriefingTime('00:00'), const BriefingTime(0, 0));
      expect(parseBriefingTime('23:59'), const BriefingTime(23, 59));
    });

    test('trims surrounding whitespace', () {
      expect(parseBriefingTime('  9:05 '), const BriefingTime(9, 5));
    });

    test('returns null when the colon is missing', () {
      expect(parseBriefingTime('7'), isNull);
      expect(parseBriefingTime('0700'), isNull);
    });

    test('returns null for empty or blank input', () {
      expect(parseBriefingTime(''), isNull);
      expect(parseBriefingTime('   '), isNull);
      expect(parseBriefingTime(':'), isNull);
    });

    test('returns null for non-numeric parts', () {
      expect(parseBriefingTime('ab:cd'), isNull);
      expect(parseBriefingTime('07:xx'), isNull);
    });

    test('returns null for out-of-range hour or minute', () {
      expect(parseBriefingTime('24:00'), isNull);
      expect(parseBriefingTime('-1:00'), isNull);
      expect(parseBriefingTime('12:60'), isNull);
      expect(parseBriefingTime('12:-5'), isNull);
    });

    test('returns null when there are too many segments', () {
      expect(parseBriefingTime('07:30:00'), isNull);
    });

    test('value equality and toString are stable', () {
      expect(const BriefingTime(7, 5), const BriefingTime(7, 5));
      expect(const BriefingTime(7, 5).toString(), '07:05');
    });
  });
}
