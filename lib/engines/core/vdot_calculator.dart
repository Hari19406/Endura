/// vDOT calculator — derives a Daniels' vDOT score from race performance
/// or easy pace, and exposes pace lookups from the static table.
///
/// All functions are pure and stateless. No I/O.
library;

import 'dart:math' as math;
import 'vdot_table.dart';

// ============================================================================
// CONFIDENCE ENUM
// ============================================================================

/// Confidence in the PR used to compute vDOT.
///
/// [high] — all-out effort run within the past 6 weeks.
/// [low]  — older or not-all-out PR; floors the computed score at 32
///          and marks the result provisional.
enum PrConfidence { high, low }

// ============================================================================
// RACE DISTANCE
// ============================================================================

/// Supported race distances for goal-pace resolution.
enum PRDistance { fiveK, tenK, halfMarathon, marathon }

extension PRDistanceX on PRDistance {
  double get distanceKm => switch (this) {
    PRDistance.fiveK => 5.0,
    PRDistance.tenK => 10.0,
    PRDistance.halfMarathon => 21.0975,
    PRDistance.marathon => 42.195,
  };
}

// ============================================================================
// VDOT FROM PR (Daniels' formula)
// ============================================================================

/// Derives a vDOT score from a race performance.
///
/// Uses Daniels' VO2 / %VO2max formula. Clamps output to [30, 85].
/// [PrConfidence.low] additionally floors the result at 32.
int vdotFromPr({
  required int prTimeSeconds,
  required double prDistanceKm,
  required PrConfidence confidence,
}) {
  if (prTimeSeconds <= 0 || prDistanceKm <= 0) return 40;
  final raw = vdotRawFromPerformance(
    timeSeconds: prTimeSeconds.toDouble(),
    distanceKm: prDistanceKm,
  );
  if (raw == null) return 40;
  final floor = confidence == PrConfidence.low ? 32 : 30;
  return raw.round().clamp(floor, 85);
}

/// Unrounded, unclamped Daniels VDOT for a performance, or null when the
/// inputs are degenerate. Continuous, so it can be inverted (see
/// [secondsForVdot]).
double? vdotRawFromPerformance({
  required double timeSeconds,
  required double distanceKm,
}) {
  if (timeSeconds <= 0 || distanceKm <= 0) return null;

  final tMin = timeSeconds / 60.0;
  final vMetersPerMin = (distanceKm * 1000) / tMin;

  final vo2 =
      -4.60 +
      0.182258 * vMetersPerMin +
      0.000104 * vMetersPerMin * vMetersPerMin;
  final pctVo2max =
      0.8 +
      0.1894393 * math.exp(-0.012778 * tMin) +
      0.2989558 * math.exp(-0.1932605 * tMin);

  if (pctVo2max <= 0) return null;

  return vo2 / pctVo2max;
}

/// The finish time (seconds) at [distanceKm] that corresponds to [vdot] —
/// the inverse of [vdotRawFromPerformance], found by bisection (VDOT falls
/// monotonically as the time grows).
int secondsForVdot(double vdot, double distanceKm) {
  var lo = distanceKm * 100; // 1:40 /km — faster than any human
  var hi = distanceKm * 1800; // 30:00 /km — slower than a walk
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    final v = vdotRawFromPerformance(timeSeconds: mid, distanceKm: distanceKm);
    if (v == null || v > vdot) {
      lo = mid; // still too fast for this VDOT → needs a longer time
    } else {
      hi = mid;
    }
  }
  return ((lo + hi) / 2).round();
}

// ============================================================================
// VDOT FROM EASY PACE (back-calculation fallback)
// ============================================================================

/// Estimates vDOT from an observed easy training pace (sec/km).
///
/// Finds the vDOT score whose E-pace range best contains [easyPaceSecPerKm].
/// Always provisional — caller should set [EngineMemory.vdotIsProvisional].
/// Floors at 32, clamps at 85.
int vdotFromEasyPace(double easyPaceSecPerKm) {
  if (easyPaceSecPerKm <= 0) return 40;

  // Walk scores from low to high; return the first vDOT whose fast-end
  // the runner meets. Lower bounds decrease as vDOT rises, so the first
  // match gives the correct (lowest plausible) vDOT for this pace.
  for (int v = 30; v <= 85; v++) {
    final paces = kVdotTable[v]!;
    if (easyPaceSecPerKm >= paces.ePaceSecPerKm.$1) {
      return v.clamp(32, 85);
    }
  }
  return 85;
}

// ============================================================================
// PACE LOOKUP
// ============================================================================

/// Returns the training paces for [vdotScore], clamped to the table range.
VdotPaces pacesFor(int vdotScore) => kVdotTable[vdotScore.clamp(30, 85)]!;
