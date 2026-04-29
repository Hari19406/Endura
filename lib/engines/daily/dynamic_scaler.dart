/// DynamicScaler — adjusts resolved workouts based on RPE signals.
///
/// RPE thresholds (rolling avg of last 3 runs, values 3/5/7/9):
///   - avgRpe >= 7.0 → scale back
///   - avgRpe >= 6.5 → mild caution
///   "Just right" (5) stays fully below both thresholds — no false caution.
library;

import '../config/workout_template_library.dart';

// ============================================================================
// SCALING SIGNALS
// ============================================================================

class ScalingSignals {
  final double? avgRpe;
  final bool lastEasyRunTooHard;

  const ScalingSignals({
    this.avgRpe,
    this.lastEasyRunTooHard = false,
  });
}

// ============================================================================
// SCALING RESULT
// ============================================================================

class ScalingResult {
  final ResolvedWorkout workout;
  final List<String> adjustments;

  const ScalingResult({
    required this.workout,
    this.adjustments = const [],
  });
}

// ============================================================================
// DYNAMIC SCALER
// ============================================================================

class DynamicScaler {
  const DynamicScaler();

  ScalingResult scale(ResolvedWorkout workout, ScalingSignals signals) {
    final factors = _calculateFactors(signals, workout.intent);

    if (factors.isNeutral) {
      return ScalingResult(workout: workout);
    }

    final adjustments = <String>[];
    if (factors.repReduction > 0) adjustments.add('Fewer reps');
    if (factors.volumeScale < 1.0) adjustments.add('Volume reduced');
    if (factors.recoveryExtension > 1.0) adjustments.add('Extended recovery');

    final scaledBlocks = workout.blocks.map((block) {
      return _scaleBlock(block, factors);
    }).toList();

    return ScalingResult(
      workout: ResolvedWorkout(
        templateId: workout.templateId,
        name: workout.name,
        intent: workout.intent,
        blocks: scaledBlocks,
        phase: workout.phase,
        coachNote: adjustments.isEmpty
            ? workout.coachNote
            : '${workout.coachNote ?? ''} [${adjustments.join(', ')}]'.trim(),
      ),
      adjustments: adjustments,
    );
  }

  // ========================================================================
  // FACTOR CALCULATION
  // ========================================================================

  _ScaleFactors _calculateFactors(
      ScalingSignals signals, WorkoutIntent intent) {
    var repReduction = 0;
    var volumeScale = 1.0;
    var recoveryExtension = 1.0;

    // ── RPE history overlay ──────────────────────────────────────────────
    // avgRpe uses values 3/5/7/9 from the 4-card RPE picker.
    // "Just right" = 5, safely below both thresholds.
    if (signals.avgRpe != null) {
      if (signals.avgRpe! >= 7.0) {
        // Consistently hard — scale back meaningfully.
        repReduction = repReduction.clamp(2, 3);
        volumeScale = (volumeScale * 0.90).clamp(0.70, 1.0);
        recoveryExtension *= 1.10;
      } else if (signals.avgRpe! >= 6.5) {
        // Trending hard — mild caution.
        repReduction = repReduction.clamp(1, 3);
        volumeScale = (volumeScale * 0.95).clamp(0.75, 1.0);
      }
    }

    if (signals.lastEasyRunTooHard) {
      volumeScale = (volumeScale * 0.92).clamp(0.70, 1.0);
    }

    repReduction = repReduction.clamp(0, 3);
    recoveryExtension = recoveryExtension.clamp(1.0, 1.3);

    return _ScaleFactors(
      repReduction: repReduction,
      volumeScale: volumeScale,
      recoveryExtension: recoveryExtension,
    );
  }

  // ========================================================================
  // BLOCK SCALING
  // ========================================================================

  ResolvedBlock _scaleBlock(ResolvedBlock block, _ScaleFactors factors) {
    if (block.isRpeOnly) return block;

    final newReps = block.reps != null
        ? (block.reps! - factors.repReduction).clamp(2, block.reps!)
        : null;

    // Volume scale applies to continuous blocks only.
    final newDistance = block.reps == null
        ? _roundSmart(block.distanceKm * factors.volumeScale)
        : block.distanceKm;

    ResolvedBlock? newRecovery;
    if (block.recovery != null && factors.recoveryExtension > 1.0) {
      final extendedKm =
          _roundSmart(block.recovery!.distanceKm * factors.recoveryExtension);
      newRecovery = ResolvedBlock(
        type: block.recovery!.type,
        distanceKm: extendedKm,
        paceMinSecondsPerKm: block.recovery!.paceMinSecondsPerKm,
        paceMaxSecondsPerKm: block.recovery!.paceMaxSecondsPerKm,
      );
    } else {
      newRecovery = block.recovery;
    }

    return ResolvedBlock(
      type: block.type,
      distanceKm: newDistance,
      paceMinSecondsPerKm: block.paceMinSecondsPerKm,
      paceMaxSecondsPerKm: block.paceMaxSecondsPerKm,
      isRpeOnly: block.isRpeOnly,
      reps: newReps,
      recovery: newRecovery,
      label: block.label,
    );
  }

  // ========================================================================
  // HELPERS
  // ========================================================================

  double _roundSmart(double v) {
    if (v <= 0) return 0;
    if (v < 1.0) {
      final rounded = (v * 100).round() / 100;
      return rounded > 0 ? rounded : 0.01;
    }
    return (v * 2).round() / 2;
  }
}

// ============================================================================
// INTERNAL
// ============================================================================

class _ScaleFactors {
  final int repReduction;
  final double volumeScale;
  final double recoveryExtension;

  const _ScaleFactors({
    required this.repReduction,
    required this.volumeScale,
    required this.recoveryExtension,
  });

  bool get isNeutral =>
      repReduction == 0 &&
      volumeScale >= 1.0 &&
      recoveryExtension <= 1.0;
}