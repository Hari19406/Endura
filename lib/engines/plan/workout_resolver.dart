/// WorkoutResolver — the full pipeline from context to workout.
///
/// Orchestrates all four components:
///   1. SessionSelector  → picks the template + day role
///   2. VolumeCalculator → sets total workout distance (fallback only)
///   3. PaceTable        → CS × multiplier = real paces
///   4. DynamicScaler    → adjusts for readiness/RPE
///
/// Input:  SelectionContext + PaceTable + ScalingSignals
/// Output: ResolvedWorkout (ready for display) or null (rest day)
///
/// CHANGE FROM v1: PaceResolver (6 generic zones) replaced by
/// PaceTable (18 specific zones). AthletePaceProfile removed entirely —
/// the PaceTable already has CS baked in.
///
/// CHANGE (Phase 3b): when SelectionContext carries a pre-sized
/// plannedDistanceKm (from WeekResolver's absorber pass) and the session was
/// not readiness-downgraded, that distance is used directly. VolumeCalculator
/// is the fallback path only.
///
/// CHANGE (V1 Adaptation System): ScalingTier introduced.
///   green  → full (no change)
///   yellow → reduced (80% reps / 80% distance / 85% long run)
///   red    → minimum (62% reps / 60% distance / 70% long run)
///
/// Templates with supportsScaling = false (vo2_ladder, vo2_pyramid,
/// race_simulation, race_dress_rehearsal) are substituted with a simpler
/// same-intent template instead of scaled.
///
/// Minimum rep floor: 3 reps. Continuous distance floor: 2.0 km.
/// Distance rounded to practical 0.5 km increments.
library;

import '../config/workout_template_library.dart';
import 'session_selector.dart';
import 'volume_calculator.dart';
import '../core/pace_table.dart';
import '../core/vdot_calculator.dart';
import '../daily/dynamic_scaler.dart';
import '../../models/training_phase.dart';

// ============================================================================
// SCALING TIER
// ============================================================================

enum ScalingTier {
  full,     // green  — run as prescribed
  reduced,  // yellow — ~80% volume, same intent
  minimum,  // red    — ~60-65% volume, same intent
}

// ============================================================================
// RESOLVER CONTEXT — everything the resolver needs to produce a workout
// ============================================================================

class ResolverContext {
  final PaceTable paceTable;
  final PRDistance? goalRaceDistance;
  final int? goalRaceTimeSeconds;

  const ResolverContext({
    required this.paceTable,
    this.goalRaceDistance,
    this.goalRaceTimeSeconds,
  });

  bool get hasGoalPace =>
      goalRaceDistance != null &&
      goalRaceTimeSeconds != null &&
      goalRaceTimeSeconds! > 0;
}

// ============================================================================
// RESOLVER OUTPUT
// ============================================================================

class ResolverResult {
  final ResolvedWorkout? workout;
  final DayRole? dayRole;
  final bool wasDowngraded;
  final List<String> scalingAdjustments;
  final String selectionReason;

  bool get isRestDay => workout == null;

  const ResolverResult({
    this.workout,
    this.dayRole,
    this.wasDowngraded = false,
    this.scalingAdjustments = const [],
    this.selectionReason = '',
  });

  const ResolverResult.rest()
      : workout = null,
        dayRole = null,
        wasDowngraded = false,
        scalingAdjustments = const [],
        selectionReason = 'Rest day';
}

// ============================================================================
// WORKOUT RESOLVER
// ============================================================================

class WorkoutResolver {
  final SessionSelector _selector;
  final VolumeCalculator _volumeCalculator;
  final DynamicScaler _scaler;

  static const double _maxQualityFraction = 0.40;

  /// Minimum reps for any interval block after scaling.
  /// Below this the workout loses its stimulus purpose.
  static const int _minIntervalReps = 3;

  /// Minimum continuous main-block distance after scaling (km).
  static const double _minContinuousKm = 2.0;

  const WorkoutResolver({
    SessionSelector? selector,
    VolumeCalculator? volumeCalculator,
    DynamicScaler? scaler,
  })  : _selector = selector ?? const SessionSelector(),
        _volumeCalculator = volumeCalculator ?? const VolumeCalculator(),
        _scaler = scaler ?? const DynamicScaler();

  ResolverResult resolve({
    required SelectionContext selectionContext,
    required ResolverContext resolverContext,
    required ScalingSignals scalingSignals,
  }) {
    // ── Step 1: Derive scaling tier from readiness ────────────────────────
    final tier = _tierFromReadiness(selectionContext.readiness);

    // ── Step 2: Select template ───────────────────────────────────────────
    // If tier != full and the selected template doesn't support scaling,
    // SessionSelector still runs normally — we swap the template afterwards.
    var selection = _selector.select(selectionContext);
    if (selection == null) {
      return const ResolverResult.rest();
    }

    // ── Step 3: Substitute non-scalable templates when under-readiness ────
    final adjustments = <String>[];
    if (tier != ScalingTier.full && !selection.template.supportsScaling) {
      final substitute = _substituteTemplate(
        original: selection.template,
        selectionContext: selectionContext,
      );
      if (substitute != null) {
        adjustments.add(
          'Substituted ${selection.template.name} → ${substitute.name} '
          '(readiness: ${selectionContext.readiness.name})',
        );
        selection = SessionSelection(
          template: substitute,
          variant: WorkoutLibrary.getVariant(substitute, selectionContext.phase),
          dayRole: selection.dayRole,
          intent: selection.intent,
          wasDowngraded: true,
          reason: selection.reason,
          originalPlannedIntent: selection.originalPlannedIntent,
        );
      }
    }

    // ── Step 4: Total workout distance ────────────────────────────────────
    // Prefer the pre-sized distance from WeekResolver's absorber pass. Only
    // recompute via VolumeCalculator if there's no planned distance or the
    // session was readiness-downgraded (the planned size no longer applies).
    final usePlanned = !selection.wasDowngraded &&
        selectionContext.plannedDistanceKm != null;
    var totalDistanceKm = usePlanned
        ? selectionContext.plannedDistanceKm!
        : _volumeCalculator.calculateWorkoutDistance(
            weeklyTargetKm: selectionContext.weeklyTargetKm,
            template: selection.template,
            raceDistance: selectionContext.raceDistance,
            phase: selectionContext.phase,
            dayRole: selection.dayRole,
            variant: selection.variant,
            experienceLevel: selectionContext.experienceLevel,
            weekPercentageSum: selectionContext.weekPercentageSum,
          );

    // Apply long-run distance scaling (endurance slots only).
    // Interval/continuous scaling happens inside resolveTemplate at the
    // block level, not at the total-distance level.
    if (selection.intent == WorkoutIntent.endurance && tier != ScalingTier.full) {
      final scaled = _scaleLongRunDistance(totalDistanceKm, tier);
      if (scaled != totalDistanceKm) {
        adjustments.add(
          'Long run scaled: ${totalDistanceKm.toStringAsFixed(1)} → '
          '${scaled.toStringAsFixed(1)} km (${tier.name})',
        );
        totalDistanceKm = scaled;
      }
    }

    // ── Step 5: Resolve blocks with real paces and distances ─────────────
    final resolvedWorkout = resolveTemplate(
      template: selection.template,
      variant: selection.variant,
      totalDistanceKm: totalDistanceKm,
      resolverContext: resolverContext,
      phase: selectionContext.phase,
      intent: selection.intent,
      experienceLevel: selectionContext.experienceLevel,
      scalingTier: tier,
      scalingAdjustments: adjustments,
    );

    // ── Step 6: Scale for readiness/RPE (DynamicScaler) ──────────────────
    final scaled = _scaler.scale(resolvedWorkout, scalingSignals);

    return ResolverResult(
      workout: scaled.workout,
      dayRole: selection.dayRole,
      wasDowngraded: selection.wasDowngraded || tier != ScalingTier.full,
      scalingAdjustments: [...adjustments, ...scaled.adjustments],
      selectionReason: selection.reason,
    );
  }

  /// Resolve a template + variant into a ResolvedWorkout.
  ///
  /// Public so WeekProjectionService can call it directly without
  /// going through the full resolve() pipeline.
  ///
  /// Budget-first distance allocation:
  ///   1. Calculate total fixed distance (fixedKm blocks + reps + recovery)
  ///   2. Subtract from totalDistanceKm → flexible budget
  ///   3. Percentage blocks split the flexible budget
  ResolvedWorkout resolveTemplate({
    required WorkoutTemplate template,
    required PhaseVariant? variant,
    required double totalDistanceKm,
    required ResolverContext resolverContext,
    required TrainingPhase phase,
    required WorkoutIntent intent,
    String experienceLevel = 'intermediate',
    ScalingTier scalingTier = ScalingTier.full,
    List<String>? scalingAdjustments,
  }) {
    final fixedDistanceKm = _calculateFixedDistance(template.blocks, variant);
    final flexibleBudgetKm =
        (totalDistanceKm - fixedDistanceKm).clamp(1.0, double.infinity);

    final percentSum = template.blocks
        .where((b) => b.durationType == DurationType.percentage)
        .fold(0.0, (sum, b) => sum + b.value);

    final resolvedBlocks = <ResolvedBlock>[];

    for (final block in template.blocks) {
      resolvedBlocks.add(_resolveBlock(
        block: block,
        variant: variant,
        flexibleBudgetKm: flexibleBudgetKm,
        percentSum: percentSum,
        resolverContext: resolverContext,
        experienceLevel: experienceLevel,
        intent: intent,
        scalingTier: scalingTier,
        scalingAdjustments: scalingAdjustments,
      ));
    }

    _enforceQualityCap(resolvedBlocks, totalDistanceKm);

    return ResolvedWorkout(
      templateId: template.id,
      name: template.name,
      intent: intent,
      blocks: resolvedBlocks,
      phase: phase,
      coachNote: variant?.note,
    );
  }

  // ============================================================================
  // SCALING TIER HELPERS
  // ============================================================================

  ScalingTier _tierFromReadiness(SelectorReadiness readiness) =>
      switch (readiness) {
        SelectorReadiness.green  => ScalingTier.full,
        SelectorReadiness.yellow => ScalingTier.reduced,
        SelectorReadiness.red    => ScalingTier.minimum,
      };

  /// Scale interval reps according to tier.
  /// Never goes below [_minIntervalReps].
  int _scaleReps(int reps, ScalingTier tier) {
    final scaled = switch (tier) {
      ScalingTier.full    => reps,
      ScalingTier.reduced => (reps * 0.80).round(),
      ScalingTier.minimum => (reps * 0.62).round(),
    };
    return scaled.clamp(_minIntervalReps, reps);
  }

  /// Scale a continuous main-block distance according to tier.
  /// Rounds to 0.5 km increments and floors at [_minContinuousKm].
  double _scaleContinuousDistance(double km, ScalingTier tier) {
    if (tier == ScalingTier.full) return km;
    final scaled = switch (tier) {
      ScalingTier.full    => km,
      ScalingTier.reduced => km * 0.80,
      ScalingTier.minimum => km * 0.60,
    };
    return _roundToPractical(scaled).clamp(_minContinuousKm, km);
  }

  /// Scale a long-run total distance according to tier.
  double _scaleLongRunDistance(double km, ScalingTier tier) {
    if (tier == ScalingTier.full) return km;
    final scaled = switch (tier) {
      ScalingTier.full    => km,
      ScalingTier.reduced => km * 0.85,
      ScalingTier.minimum => km * 0.70,
    };
    return _roundToPractical(scaled);
  }

  /// Round to the nearest 0.5 km, minimum 2.0 km.
  double _roundToPractical(double km) {
    final rounded = (km * 2).round() / 2.0;
    return rounded < _minContinuousKm ? _minContinuousKm : rounded;
  }

  /// Detect whether a template's main block is interval-based (has reps)
  /// or continuous (percentage / fixed distance without reps).
  bool _templateIsIntervalBased(WorkoutTemplate template) =>
      template.blocks.any((b) => b.type == BlockType.main && b.reps != null);

  /// Find a simpler scalable substitute in the same intent pool.
  ///
  /// Fallback map (spec §3 "unsupported workouts"):
  ///   vo2_ladder   / vo2_pyramid   → vo2_classic (800m) or vo2_600
  ///   race_simulation              → race_gp_intervals
  ///   race_dress_rehearsal         → race_gp_intervals
  WorkoutTemplate? _substituteTemplate({
    required WorkoutTemplate original,
    required SelectionContext selectionContext,
  }) {
    // Preferred substitute ids by original id.
    final preferredIds = switch (original.id) {
      'vo2_ladder'           => ['vo2_classic', 'vo2_600'],
      'vo2_pyramid'          => ['vo2_classic', 'vo2_600'],
      'race_simulation'      => ['race_gp_intervals'],
      'race_dress_rehearsal' => ['race_gp_intervals'],
      _                      => <String>[],
    };

    for (final id in preferredIds) {
      final t = WorkoutLibrary.byId(id);
      if (t != null &&
          t.supportsScaling &&
          t.applicableRaceDistances.contains(selectionContext.raceDistance) &&
          t.applicablePhases.contains(selectionContext.phase)) {
        return t;
      }
    }

    // Generic fallback: any scalable template in the same intent pool.
    final pool = WorkoutLibrary.forSlot(
      intent: original.intent,
      raceDistance: selectionContext.raceDistance,
      phase: selectionContext.phase,
    ).where((t) => t.supportsScaling && t.id != original.id).toList();

    return pool.isNotEmpty ? pool.first : null;
  }

  // ========================================================================
  // PACE RESOLUTION
  // ========================================================================

  ResolvedPace _resolvePaceZone(PaceZone zone, ResolverContext context, WorkoutIntent intent) {
    if (_isGoalPaceZone(zone)) {
      if (context.hasGoalPace) {
        return context.paceTable.resolveGoalPace(
          raceDistance: context.goalRaceDistance!,
          targetTimeSeconds: context.goalRaceTimeSeconds!,
        );
      }
      // Long run goal pace blocks fall back to marathon pace, not tempo
      if (intent == WorkoutIntent.endurance) {
        return context.paceTable.resolve(PaceZone.marathonPace);
      }
      return context.paceTable.resolve(PaceZone.tempo);
    }
    return context.paceTable.resolve(zone);
  }

  bool _isGoalPaceZone(PaceZone zone) {
    return zone == PaceZone.goalPace ||
        zone == PaceZone.raceSimulation ||
        zone == PaceZone.dressRehearsal;
  }

  // ========================================================================
  // QUALITY CAP
  // ========================================================================

  void _enforceQualityCap(
      List<ResolvedBlock> blocks, double totalDistanceKm) {
    var qualityKm = 0.0;
    final qualityIndices = <int>[];

    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.type == BlockType.main && b.label != null && b.reps == null) {
        qualityKm += b.totalDistanceKm;
        qualityIndices.add(i);
      }
    }

    if (qualityKm <= 0 || totalDistanceKm <= 0) return;

    final qualityFraction = qualityKm / totalDistanceKm;
    if (qualityFraction <= _maxQualityFraction) return;

    final targetQualityKm = totalDistanceKm * _maxQualityFraction;
    final scaleFactor = targetQualityKm / qualityKm;
    var excessKm = 0.0;

    for (final i in qualityIndices) {
      final b = blocks[i];
      final newDistance = _roundSmart(b.distanceKm * scaleFactor);
      excessKm += b.distanceKm - newDistance;
      blocks[i] = ResolvedBlock(
        type: b.type,
        distanceKm: newDistance,
        paceMinSecondsPerKm: b.paceMinSecondsPerKm,
        paceMaxSecondsPerKm: b.paceMaxSecondsPerKm,
        isRpeOnly: b.isRpeOnly,
        reps: b.reps,
        recoverySeconds: b.recoverySeconds,
        recoveryMeters: b.recoveryMeters,
        label: b.label,
      );
    }

    if (excessKm > 0.1) {
      for (var i = blocks.length - 1; i >= 0; i--) {
        if (blocks[i].type == BlockType.cooldown) {
          blocks[i] = ResolvedBlock(
            type: blocks[i].type,
            distanceKm: _roundSmart(blocks[i].distanceKm + excessKm),
            paceMinSecondsPerKm: blocks[i].paceMinSecondsPerKm,
            paceMaxSecondsPerKm: blocks[i].paceMaxSecondsPerKm,
            label: blocks[i].label,
          );
          break;
        }
      }
    }
  }

  // ========================================================================
  // FIXED DISTANCE CALCULATION
  // ========================================================================

  double _calculateFixedDistance(
      List<BlockTemplate> blocks, PhaseVariant? variant) {
    var total = 0.0;

    for (final block in blocks) {
      if (block.durationType == DurationType.percentage) continue;

      double blockKm;
      if (block.type == BlockType.main && variant?.repDistanceKm != null) {
        blockKm = variant!.repDistanceKm!;
      } else if (block.type == BlockType.main &&
          variant?.repDistanceMeters != null) {
        blockKm = variant!.repDistanceMeters! / 1000.0;
      } else {
        blockKm = block.value;
      }

      final reps = (block.reps != null) ? (variant?.reps ?? block.reps!) : 1;
      total += blockKm * reps;

      if (block.recoveryMeters != null && reps > 1) {
        final recoveryKm =
            (variant?.recoveryMeters ?? block.recoveryMeters!) / 1000.0;
        total += recoveryKm * (reps - 1);
      }
    }

    return total;
  }

  // ========================================================================
  // BLOCK RESOLUTION
  // ========================================================================

  ResolvedBlock _resolveBlock({
    required BlockTemplate block,
    required PhaseVariant? variant,
    required double flexibleBudgetKm,
    required double percentSum,
    required ResolverContext resolverContext,
    required String experienceLevel,
    required WorkoutIntent intent,
    ScalingTier scalingTier = ScalingTier.full,
    List<String>? scalingAdjustments,
  }) {
    // ── Distance ─────────────────────────────────────────────────────────
    double distanceKm;
    switch (block.durationType) {
      case DurationType.fixedKm:
        if (block.type == BlockType.main && variant?.repDistanceKm != null) {
          distanceKm = variant!.repDistanceKm!;
        } else if (block.type == BlockType.main &&
            variant?.repDistanceMeters != null) {
          distanceKm = variant!.repDistanceMeters! / 1000.0;
        } else {
          distanceKm = block.value;
        }
        break;
      case DurationType.percentage:
        final normalizedFraction =
            percentSum > 0 ? block.value / percentSum : 1.0;
        distanceKm = flexibleBudgetKm * normalizedFraction;
        break;
    }

    // ── Pace ─────────────────────────────────────────────────────────────
    final resolvedPace = _resolvePaceZone(block.paceZone, resolverContext, intent);

    // ── Reps ─────────────────────────────────────────────────────────────
    int? reps;
    if (block.reps != null) {
      final raw = variant?.reps ?? block.reps!;
      final experienceClamped = _clampRepsForExperience(raw, experienceLevel);

      // Apply scaling tier to rep-based main blocks only.
      if (block.type == BlockType.main && scalingTier != ScalingTier.full) {
        final beforeScale = experienceClamped;
        reps = _scaleReps(experienceClamped, scalingTier);
        if (reps != beforeScale) {
          scalingAdjustments?.add(
            'Reps scaled: $beforeScale → $reps '
            '× ${(distanceKm * 1000).round()}m (${scalingTier.name})',
          );
        }
      } else {
        reps = experienceClamped;
      }
    }

    // ── Continuous block scaling (percentage / fixed main, no reps) ───────
    // Applied to warmup/cooldown intentionally excluded — only main blocks.
    if (block.type == BlockType.main &&
        reps == null &&
        scalingTier != ScalingTier.full) {
      final beforeScale = distanceKm;
      distanceKm = _scaleContinuousDistance(distanceKm, scalingTier);
      if (distanceKm != beforeScale) {
        scalingAdjustments?.add(
          'Distance scaled: ${beforeScale.toStringAsFixed(1)} → '
          '${distanceKm.toStringAsFixed(1)} km (${scalingTier.name})',
        );
      }
    }

    // ── Recovery ─────────────────────────────────────────────────────────
    final int? resolvedRecoverySeconds =
        variant?.recoverySeconds ?? block.recoverySeconds;
    final double? resolvedRecoveryMeters =
        variant?.recoveryMeters ?? block.recoveryMeters;

    return ResolvedBlock(
      type: block.type,
      distanceKm: _roundSmart(distanceKm),
      paceMinSecondsPerKm: resolvedPace.minSecondsPerKm,
      paceMaxSecondsPerKm: resolvedPace.maxSecondsPerKm,
      isRpeOnly: resolvedPace.isRpeOnly,
      reps: reps,
      recoverySeconds: resolvedRecoverySeconds,
      recoveryMeters: resolvedRecoveryMeters,
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

  int _clampRepsForExperience(int reps, String level) {
    return switch (level) {
      'beginner'     => (reps * 0.65).round().clamp(2, reps).toInt(),
      'intermediate' => (reps * 0.85).round().clamp(2, reps).toInt(),
      'advanced'     => reps,
      _              => (reps * 0.85).round().clamp(2, reps).toInt(),
    };
  }
}