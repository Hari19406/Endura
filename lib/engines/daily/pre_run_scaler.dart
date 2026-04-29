/// PreRunScaler — adjusts today's workout based on pre-run check answers.
///
/// Separate from DynamicScaler (which handles post-run RPE history).
/// This runs ONCE per session, immediately before the run starts.
///
/// Reduction matrix:
///   Feeling off only          → 85% volume, reps -15%
///   Bad sleep only            → 85% volume, reps -15%
///   Both                      → 75% volume, reps -25%
///   Leg pain only             → 80% volume, reps -20%
///   Leg pain + off/sleep      → 75% volume, reps -25%
///   Upper body pain           → no change
///   Chest pain                → block workout (handled at UI layer)
///   Need rest                 → handled at UI layer (shakeout or rest)
library;

import '../config/workout_template_library.dart';

// ============================================================================
// PRE-RUN INPUTS
// ============================================================================

enum PreRunFeeling { great, normal, tired }

enum PreRunSleep { good, poor }

enum PainLocation { none, upperBody, leg, chest }

class PreRunInputs {
  final PreRunFeeling feeling;
  final PreRunSleep sleep;
  final PainLocation pain;

  const PreRunInputs({
    required this.feeling,
    required this.sleep,
    required this.pain,
  });

  const PreRunInputs.allGood()
      : feeling = PreRunFeeling.great,
        sleep = PreRunSleep.good,
        pain = PainLocation.none;

  bool get feelingOff => feeling == PreRunFeeling.tired;
  bool get sleepPoor => sleep == PreRunSleep.poor;
  bool get hasLegPain => pain == PainLocation.leg;
  bool get hasChestPain => pain == PainLocation.chest;
  bool get hasUpperBodyPain => pain == PainLocation.upperBody;

  bool get needsReduction =>
      feelingOff || sleepPoor || hasLegPain;

  bool get isFullGo =>
      !feelingOff && !sleepPoor && pain != PainLocation.leg;
}

// ============================================================================
// SCALE RESULT
// ============================================================================

class PreRunScaleResult {
  final ResolvedWorkout workout;
  final String? coachNote;
  final bool wasReduced;

  const PreRunScaleResult({
    required this.workout,
    this.coachNote,
    this.wasReduced = false,
  });
}

// ============================================================================
// PRE-RUN SCALER
// ============================================================================

class PreRunScaler {
  const PreRunScaler();

  PreRunScaleResult scale(ResolvedWorkout workout, PreRunInputs inputs) {
    // Upper body pain or fully green → no change.
    if (inputs.isFullGo || inputs.hasUpperBodyPain) {
      return PreRunScaleResult(workout: workout);
    }

    final factors = _resolveFactors(inputs);
    final scaledBlocks = workout.blocks.map((b) => _scaleBlock(b, factors)).toList();
    final note = _buildNote(inputs);

    return PreRunScaleResult(
      workout: ResolvedWorkout(
        templateId: workout.templateId,
        name: workout.name,
        intent: workout.intent,
        blocks: scaledBlocks,
        phase: workout.phase,
        coachNote: note,
      ),
      coachNote: note,
      wasReduced: true,
    );
  }

  // ========================================================================
  // FACTOR RESOLUTION
  // ========================================================================

  _Factors _resolveFactors(PreRunInputs inputs) {
    final bothOffAndSleep = inputs.feelingOff && inputs.sleepPoor;
    final legPainWithOther = inputs.hasLegPain && (inputs.feelingOff || inputs.sleepPoor);

    // Worst applicable case wins (lowest multiplier).
    if (bothOffAndSleep || legPainWithOther) {
      return const _Factors(volumeScale: 0.75, repScale: 0.75);
    }
    if (inputs.hasLegPain) {
      return const _Factors(volumeScale: 0.80, repScale: 0.80);
    }
    // Feeling off or poor sleep (either alone).
    return const _Factors(volumeScale: 0.85, repScale: 0.85);
  }

  // ========================================================================
  // BLOCK SCALING
  // ========================================================================

  ResolvedBlock _scaleBlock(ResolvedBlock block, _Factors factors) {
    if (block.reps != null) {
      // Interval block — reduce reps, preserve rep distance.
      final newReps = (block.reps! * factors.repScale).round().clamp(2, block.reps!);
      return ResolvedBlock(
        type: block.type,
        distanceKm: block.distanceKm,
        paceMinSecondsPerKm: block.paceMinSecondsPerKm,
        paceMaxSecondsPerKm: block.paceMaxSecondsPerKm,
        isRpeOnly: block.isRpeOnly,
        reps: newReps,
        recovery: block.recovery,
        label: block.label,
      );
    }

    // Continuous block — scale distance.
    final newDistance = _roundSmart(block.distanceKm * factors.volumeScale);
    return ResolvedBlock(
      type: block.type,
      distanceKm: newDistance,
      paceMinSecondsPerKm: block.paceMinSecondsPerKm,
      paceMaxSecondsPerKm: block.paceMaxSecondsPerKm,
      isRpeOnly: block.isRpeOnly,
      reps: block.reps,
      recovery: block.recovery,
      label: block.label,
    );
  }

  // ========================================================================
  // COACH NOTE
  // ========================================================================

  String _buildNote(PreRunInputs inputs) {
    final reasons = <String>[];
    if (inputs.feelingOff) reasons.add('tiredness');
    if (inputs.sleepPoor) reasons.add('poor sleep');
    if (inputs.hasLegPain) reasons.add('leg pain');
    final reasonStr = reasons.join(' + ');
    return "Adjusted for $reasonStr. Intent unchanged — just dialling back the dose.";
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

class _Factors {
  final double volumeScale;
  final double repScale;
  const _Factors({required this.volumeScale, required this.repScale});
}