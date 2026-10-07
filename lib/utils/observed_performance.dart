// lib/utils/observed_performance.dart
//
// "What does your actual recent performance suggest?" — race-time predictions
// derived ONLY from measured Best Efforts, using Daniels' VDOT mathematics.
//
// This is deliberately separate from the Training Engine. It never reads or
// writes `EngineMemory.vdotScore`, the plan, workout selection or training
// paces; the two answers may differ and that is fine. Nothing here feeds back
// into training.
//
// Method (deterministic):
//  1. Only Best Efforts at 3K or longer inside the last [windowDays] days are
//     used — shorter efforts are not aerobic-equivalence-friendly.
//  2. Each effort is turned into an observed VDOT with
//     [vdotRawFromPerformance].
//  3. A race distance is predicted from the highest observed VDOT among
//     efforts whose distance is within [minSourceRatio]..[maxSourceRatio] of
//     it (so a 5K effort is never extrapolated to a marathon). The time comes
//     from [secondsForVdot]. No supporting effort → no prediction.
library;

import '../engines/core/vdot_calculator.dart'
    show secondsForVdot, vdotRawFromPerformance;
import '../services/best_efforts_service.dart' show DistanceCategory;

/// One measured Best Effort, reduced to what the prediction needs.
class ObservedEffort {
  final DistanceCategory category;
  final int seconds;
  final DateTime date;

  const ObservedEffort({
    required this.category,
    required this.seconds,
    required this.date,
  });

  /// Daniels VDOT of this effort, or null when degenerate.
  double? get vdot => vdotRawFromPerformance(
    timeSeconds: seconds.toDouble(),
    distanceKm: category.meters / 1000,
  );
}

class RacePrediction {
  final DistanceCategory category;
  final int predictedSeconds;

  /// The effort the prediction was derived from.
  final ObservedEffort basedOn;

  /// Observed VDOT of [basedOn].
  final double observedVdot;

  const RacePrediction({
    required this.category,
    required this.predictedSeconds,
    required this.basedOn,
    required this.observedVdot,
  });
}

class ObservedPerformance {
  ObservedPerformance._();

  /// Race distances that get a prediction.
  static const List<DistanceCategory> targets = [
    DistanceCategory.k5,
    DistanceCategory.k10,
    DistanceCategory.half,
    DistanceCategory.marathon,
  ];

  /// Best Effort categories usable as evidence (3K and up).
  static const List<DistanceCategory> sourceCategories = [
    DistanceCategory.k3,
    DistanceCategory.k5,
    DistanceCategory.k10,
    DistanceCategory.half,
    DistanceCategory.marathon,
  ];

  /// Shortest effort distance usable as evidence (3K and up).
  static const double minSourceMeters = 3000;

  /// Source distance must lie in [target * min, target * max].
  static const double minSourceRatio = 0.45;
  static const double maxSourceRatio = 4.0;

  static const int windowDays = 365;

  /// The highest observed VDOT across usable efforts, or null when there is
  /// no usable effort. Informational — never applied to training.
  static double? observedVdot(List<ObservedEffort> efforts, {DateTime? now}) {
    double? best;
    for (final e in _usable(efforts, now ?? DateTime.now())) {
      final v = e.vdot;
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  /// One prediction per target distance that has supporting evidence, in
  /// [targets] order. Empty when the Best Effort data is insufficient.
  static List<RacePrediction> predict(
    List<ObservedEffort> efforts, {
    DateTime? now,
  }) {
    final usable = _usable(efforts, now ?? DateTime.now()).toList();
    final out = <RacePrediction>[];
    for (final target in targets) {
      ObservedEffort? bestSource;
      double bestVdot = 0;
      for (final e in usable) {
        final ratio = e.category.meters / target.meters;
        if (ratio < minSourceRatio || ratio > maxSourceRatio) continue;
        final v = e.vdot;
        if (v == null || v <= bestVdot) continue;
        bestVdot = v;
        bestSource = e;
      }
      if (bestSource == null) continue;
      out.add(
        RacePrediction(
          category: target,
          predictedSeconds: secondsForVdot(bestVdot, target.meters / 1000),
          basedOn: bestSource,
          observedVdot: bestVdot,
        ),
      );
    }
    return out;
  }

  static Iterable<ObservedEffort> _usable(
    List<ObservedEffort> efforts,
    DateTime now,
  ) {
    final cutoff = now.subtract(const Duration(days: windowDays));
    return efforts.where(
      (e) =>
          e.seconds > 0 &&
          e.category.meters >= minSourceMeters &&
          !e.date.isBefore(cutoff),
    );
  }
}
