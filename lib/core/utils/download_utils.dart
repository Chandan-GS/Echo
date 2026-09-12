/// Converts raw byte counters from a download callback into a safe progress
/// fraction in the range `[0.0, 1.0]`.
///
/// Returns `0.0` when [total] is unknown/zero (Dio reports `-1` for unknown
/// length, and some proxies send `Content-Length: 0`), which previously
/// produced `0/0 == NaN` and crashed `LinearProgressIndicator` and
/// `(progress * 100).toInt()`.
double computeDownloadProgress(int received, int total) {
  if (total <= 0) return 0.0;
  final progress = received / total;
  if (progress.isNaN || progress.isInfinite) return 0.0;
  return progress.clamp(0.0, 1.0);
}
