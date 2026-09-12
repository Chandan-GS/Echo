import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/utils/download_utils.dart';

void main() {
  group('computeDownloadProgress', () {
    test('computes a normal fraction', () {
      expect(computeDownloadProgress(50, 100), 0.5);
      expect(computeDownloadProgress(0, 100), 0.0);
      expect(computeDownloadProgress(100, 100), 1.0);
    });

    test('returns 0.0 when total is zero (no NaN)', () {
      // Regression: 0/0 == NaN broke LinearProgressIndicator and (x*100).toInt().
      final p = computeDownloadProgress(0, 0);
      expect(p.isNaN, isFalse);
      expect(p, 0.0);
    });

    test('returns 0.0 for unknown length (-1)', () {
      expect(computeDownloadProgress(1234, -1), 0.0);
    });

    test('clamps above 1.0 if received exceeds total', () {
      expect(computeDownloadProgress(150, 100), 1.0);
    });

    test('never produces a value outside [0, 1]', () {
      for (final pair in [
        [0, 0],
        [10, 0],
        [10, -1],
        [999, 1000],
        [1000, 1000],
        [2000, 1000],
      ]) {
        final p = computeDownloadProgress(pair[0], pair[1]);
        expect(p, inInclusiveRange(0.0, 1.0));
        expect(p.isNaN, isFalse);
      }
    });

    test('(progress * 100).toInt() is always a valid percent', () {
      final percent = (computeDownloadProgress(0, 0) * 100).toInt();
      expect(percent, 0);
    });
  });
}
