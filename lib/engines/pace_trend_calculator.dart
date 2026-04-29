// pace_trend_calculator.dart — single source of truth for pace trend.
//
// Previously there were three separate implementations:
//   • home_screen.dart       → endpoint comparison (oldest vs newest)
//   • run_screen_summary.dart → endpoint comparison (oldest vs newest)
//   • coach_engine_v2.dart   → latest vs average-of-previous
//
// All three now call this function. The endpoint comparison algorithm is
// used because it looks at the full window extremes rather than just the
// most recent run, making it more stable against single-session outliers.
//
// Input paces must be in seconds/km, newest-first order.
// 0 means "invalid" (GPS failure — not 360, which was the old sentinel).
// Invalid paces are filtered before any calculation.
class PaceTrendCalculator {
  PaceTrendCalculator._();

  /// Returns one of: 'improving' | 'declining' | 'neutral' | 'insufficient_data'
  ///
  /// [paceSecondsNewestFirst] — pace of each recent run in seconds/km,
  ///   ordered newest-first. Pass 0 for any run whose pace could not be
  ///   parsed (they will be dropped before analysis).
  ///
  /// Returns 'insufficient_data' when fewer than 3 clean paces remain after
  /// filtering, so callers can surface an honest "not enough data" message
  /// instead of silently defaulting to stable.
  static String calculate(List<int> paceSecondsNewestFirst) {
    // Drop invalid paces (0 = GPS parse failure). 360 was the old sentinel
    // and is now gone — see _paceToSeconds fix in home/summary screens.
    final validPaces = paceSecondsNewestFirst.where((p) => p > 0).toList();

    // Need at least 5 valid runs to see a meaningful trend — prevents a
    // single noisy session from flipping the label early in a user's history.
    if (validPaces.length < 5) return 'insufficient_data';

    // Cap window at 7 most recent valid runs.
    final window = validPaces.take(7).toList();

    // Median for outlier reference — robust against GPS spikes.
    final sorted = [...window]..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2.0;

    // Discard any pace that deviates more than 30 % from the median.
    // A 6 min/km runner won't jump to 9 min/km under normal conditions.
    final cleanPaces =
        window.where((p) => (p - median).abs() / median <= 0.30).toList();

    // Not enough clean data — honest "unknown" rather than a false stable.
    if (cleanPaces.length < 3) return 'insufficient_data';

    // Endpoint comparison: oldest clean entry vs newest clean entry.
    // cleanPaces[0] = most recent, cleanPaces.last = oldest in window.
    // Positive diff → runner was slower before → they have improved.
    final diff = cleanPaces.last - cleanPaces.first;
    if (diff > 15) return 'improving';
    if (diff < -15) return 'declining';
    return 'neutral';
  }
}
