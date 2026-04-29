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

  final tMin = prTimeSeconds / 60.0;
  final vMetersPerMin = (prDistanceKm * 1000) / tMin;

  final vo2 = -4.60 + 0.182258 * vMetersPerMin + 0.000104 * vMetersPerMin * vMetersPerMin;
  final pctVo2max = 0.8
      + 0.1894393 * math.exp(-0.012778 * tMin)
      + 0.2989558 * math.exp(-0.1932605 * tMin);

  if (pctVo2max <= 0) return 40;

  final raw = vo2 / pctVo2max;
  final floor = confidence == PrConfidence.low ? 32 : 30;
  return raw.round().clamp(floor, 85);
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

  // Walk scores from high to low; return the first whose E range covers the pace.
  for (int v = 85; v >= 30; v--) {
    final paces = kVdotTable[v]!;
    if (easyPaceSecPerKm >= paces.ePaceSecPerKm.$1) {
      return v.clamp(32, 85);
    }
  }
  return 32;
}

// ============================================================================
// PACE LOOKUP
// ============================================================================

/// Returns the training paces for [vdotScore], clamped to the table range.
VdotPaces pacesFor(int vdotScore) =>
    kVdotTable[vdotScore.clamp(30, 85)]!;
