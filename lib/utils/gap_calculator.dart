// lib/utils/gap_calculator.dart

import 'dart:math' as math;

/// Grade-Adjusted Pace (GAP) — the pace-equivalent-on-flat-ground for a given
/// actual pace and gradient, using the Minetti et al. (2002) cost-of-running
/// polynomial normalized to flat-ground cost. This is the same published
/// approach used by Strava/TrainingPeaks-style GAP figures. Pure function,
/// no I/O — every consumer (run_screen at save time, run_detail_screen for
/// display) goes through this so the math lives in exactly one place.
class GapCalculator {
  GapCalculator._();

  /// Cost of running (J/kg/m) as a function of gradient (fraction, e.g. 0.05
  /// = 5% uphill). Validated over roughly ±45% grade; clamp outside that.
  static double _costOfRunning(double gradient) {
    final g = gradient.clamp(-0.45, 0.45);
    return 155.4 * math.pow(g, 5) -
        30.4 * math.pow(g, 4) -
        43.3 * math.pow(g, 3) +
        46.3 * math.pow(g, 2) +
        19.5 * g +
        3.6;
  }

  /// Grade-adjusted pace in sec/km given an actual pace (sec/km) and
  /// gradient (fraction).
  static double gradeAdjustedPaceSecPerKm(double paceSecPerKm, double gradient) {
    final flatCost = _costOfRunning(0.0);
    final gradedCost = _costOfRunning(gradient);
    return paceSecPerKm * (gradedCost / flatCost);
  }

  /// Per-sample GAP series (sec/km) from track samples. Entry is null where
  /// the gradient or pace can't be derived (missing altitude/pace, or a
  /// zero-distance step against the previous sample).
  static List<double?> gapSeriesSecPerKm(
    List<Map<String, dynamic>> trackSamples,
  ) {
    final result = <double?>[];
    for (int i = 0; i < trackSamples.length; i++) {
      if (i == 0) {
        result.add(null);
        continue;
      }
      result.add(_gapForPair(trackSamples[i - 1], trackSamples[i]));
    }
    return result;
  }

  /// Distance-weighted average GAP across all consecutive sample pairs with
  /// both altitude and pace present. Null if fewer than 2 usable samples.
  static double? averageGapSecPerKm(List<Map<String, dynamic>> trackSamples) {
    double weightedSum = 0;
    double totalWeight = 0;
    for (int i = 1; i < trackSamples.length; i++) {
      final gap = _gapForPair(trackSamples[i - 1], trackSamples[i]);
      if (gap == null) continue;
      final dPrev = (trackSamples[i - 1]['d'] as num).toDouble();
      final dCur = (trackSamples[i]['d'] as num).toDouble();
      final weight = dCur - dPrev;
      if (weight <= 0) continue;
      weightedSum += gap * weight;
      totalWeight += weight;
    }
    if (totalWeight <= 0) return null;
    return weightedSum / totalWeight;
  }

  static double? _gapForPair(
    Map<String, dynamic> prev,
    Map<String, dynamic> cur,
  ) {
    final alt1 = prev['alt'] as num?;
    final alt2 = cur['alt'] as num?;
    final pace = cur['pace'] as num?;
    if (alt1 == null || alt2 == null || pace == null) return null;
    final d1 = (prev['d'] as num).toDouble();
    final d2 = (cur['d'] as num).toDouble();
    final distanceDelta = d2 - d1;
    if (distanceDelta <= 0) return null;
    final gradient = (alt2.toDouble() - alt1.toDouble()) / distanceDelta;
    return gradeAdjustedPaceSecPerKm(pace.toDouble(), gradient);
  }
}
