import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/vault/presentation/widgets/pie_chart_geometry.dart';

const double _twoPi = 2 * math.pi;

double _sumOfSweeps(List<PieSliceGeometry> slices) =>
    slices.fold(0.0, (s, slice) => s + slice.sweepAngle);

void main() {
  group('computePieSlices', () {
    test('excludes the aggregate "All" bucket', () {
      final slices = computePieSlices({'All': 10, 'Slack': 6, 'SMS': 4});
      expect(slices.map((s) => s.category), containsAll(['Slack', 'SMS']));
      expect(slices.any((s) => s.category == 'All'), isFalse);
    });

    test('returns empty when there are no real categories', () {
      expect(computePieSlices({'All': 0}), isEmpty);
      expect(computePieSlices({}), isEmpty);
    });

    test('returns empty (no NaN) when total count is zero', () {
      // Regression: count/total was 0/0 == NaN, producing NaN sweep angles.
      final slices = computePieSlices({'All': 0, 'Slack': 0, 'SMS': 0});
      expect(slices, isEmpty);
    });

    test('sweeps always sum to exactly 2π for a normal distribution', () {
      final slices = computePieSlices({'A': 5, 'B': 3, 'C': 2});
      expect(_sumOfSweeps(slices), closeTo(_twoPi, 1e-9));
      for (final s in slices) {
        expect(s.sweepAngle.isNaN, isFalse);
        expect(s.sweepAngle, greaterThan(0));
      }
    });

    test('many tiny categories never overflow past 2π (no overlap)', () {
      // 25 senders each with a single notification. Each raw proportion is
      // below the 15° minimum, which previously summed to 375° > 360° and made
      // slices overlap. Normalization must keep the total at exactly 2π.
      final counts = <String, int>{'All': 25};
      for (int i = 0; i < 25; i++) {
        counts['sender_$i'] = 1;
      }
      final slices = computePieSlices(counts);
      expect(slices.length, 25);
      expect(_sumOfSweeps(slices), closeTo(_twoPi, 1e-9));
    });

    test('slices are contiguous (each starts where the previous ended)', () {
      final slices = computePieSlices({'A': 7, 'B': 2, 'C': 1});
      for (int i = 1; i < slices.length; i++) {
        final prevEnd = slices[i - 1].startAngle + slices[i - 1].sweepAngle;
        expect(slices[i].startAngle, closeTo(prevEnd, 1e-9));
      }
    });

    test('first slice starts at the configured offset (top of circle)', () {
      final slices = computePieSlices({'A': 1, 'B': 1});
      expect(slices.first.startAngle, closeTo(-math.pi / 2, 1e-9));
    });

    test('a single category fills the whole ring', () {
      final slices = computePieSlices({'All': 4, 'Solo': 4});
      expect(slices.length, 1);
      expect(slices.first.sweepAngle, closeTo(_twoPi, 1e-9));
      expect(slices.first.count, 4);
    });

    test('larger categories get proportionally larger sweeps', () {
      final slices = computePieSlices({'Big': 90, 'Small': 10});
      final big = slices.firstWhere((s) => s.category == 'Big');
      final small = slices.firstWhere((s) => s.category == 'Small');
      expect(big.sweepAngle, greaterThan(small.sweepAngle));
    });
  });
}
