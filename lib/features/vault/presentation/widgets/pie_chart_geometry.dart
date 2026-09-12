import 'dart:math' as math;

/// Geometry for a single pie slice, independent of any rendering concern so it
/// can be unit-tested in isolation.
class PieSliceGeometry {
  final String category;
  final int count;
  final double startAngle;
  final double sweepAngle;

  const PieSliceGeometry({
    required this.category,
    required this.count,
    required this.startAngle,
    required this.sweepAngle,
  });
}

/// Computes normalized pie-slice angles for the given category counts.
///
/// Rules:
/// * The `'All'` bucket is excluded (it is the aggregate, not a slice).
/// * Returns an empty list when there are no real categories OR the total count
///   is zero — this prevents the `count / total` division-by-zero that produced
///   `NaN` sweep angles and broke `Canvas.drawArc`.
/// * Small slices are bumped to at least [minSweepDegrees] so they remain wide
///   enough to scrub, then **all** sweeps are rescaled so they sum to exactly
///   2π. Rescaling is what stops many tiny categories from overflowing past
///   360° and overlapping/hiding each other.
List<PieSliceGeometry> computePieSlices(
  Map<String, int> categoryCounts, {
  double startOffset = -math.pi / 2,
  double minSweepDegrees = 15,
}) {
  final categories =
      categoryCounts.keys.where((k) => k != 'All').toList(growable: false);
  if (categories.isEmpty) return const [];

  final total = categories.fold<int>(
    0,
    (sum, cat) => sum + (categoryCounts[cat] ?? 0),
  );
  if (total <= 0) return const [];

  const twoPi = 2 * math.pi;
  final minSweep = minSweepDegrees * (math.pi / 180.0);

  // Proportional sweep with a per-slice minimum.
  final adjusted = <double>[];
  for (final cat in categories) {
    final proportion = (categoryCounts[cat] ?? 0) / total;
    final sweep = proportion * twoPi;
    adjusted.add(sweep < minSweep ? minSweep : sweep);
  }

  // Normalize so the whole ring is exactly 2π (no overlap, no gap).
  final sum = adjusted.fold<double>(0.0, (s, v) => s + v);
  final scale = sum > 0 ? twoPi / sum : 1.0;

  final slices = <PieSliceGeometry>[];
  double current = startOffset;
  for (int i = 0; i < categories.length; i++) {
    final sweep = adjusted[i] * scale;
    slices.add(
      PieSliceGeometry(
        category: categories[i],
        count: categoryCounts[categories[i]] ?? 0,
        startAngle: current,
        sweepAngle: sweep,
      ),
    );
    current += sweep;
  }
  return slices;
}
