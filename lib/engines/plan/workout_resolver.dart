/// WorkoutResolver — the full pipeline from context to workout.
///
/// Orchestrates all four components:
///   1. SessionSelector  → picks the template + day role
///   2. VolumeCalculator → sets total workout distance
///   3. PaceTable        → CS × multiplier = real paces
///   4. DynamicScaler    → adjusts for readiness/RPE
///
/// Input:  SelectionContext + PaceTable + ScalingSignals
/// Output: ResolvedWorkout (ready for display) or null (rest day)
///
/// CHANGE FROM v1: PaceResolver (6 generic zones) replaced by
/// PaceTable (18 specific zones). AthletePaceProfile removed entirely —
/// the PaceTable already has CS baked in.
library;

import '../config/workout_template_library.dart';
import 'session_selector.dart';
import 'volume_calculator.dart';
import '../core/pace_table.dart';
import '../core/vdot_calculator.dart';
import '../daily/dynamic_scaler.dart';
import '../../models/training_phase.dart';

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
    double? longestRecentRunKm,
  }) {
    // ── Step 1: Select template ──────────────────────────────────────────
    final selection = _selector.select(selectionContext);
    if (selection == null) {
      return const ResolverResult.rest();
    }

    // ── Step 2: Calculate total workout distance ─────────────────────────
    final totalDistanceKm = _volumeCalculator.calculateWorkoutDistance(
      weeklyTargetKm: selectionContext.weeklyTargetKm,
      template: selection.template,
      raceDistance: selectionContext.raceDistance,
      phase: selectionContext.phase,
      dayRole: selection.dayRole,
      variant: selection.variant,
      longestRecentRunKm: longestRecentRunKm,
      experienceLevel: selectionContext.experienceLevel,
    );

    // ── Step 3: Resolve blocks with real paces and distances ─────────────
    final resolvedWorkout = resolveTemplate(
      template: selection.template,
      variant: selection.variant,
      totalDistanceKm: totalDistanceKm,
      resolverContext: resolverContext,
      phase: selectionContext.phase,
      intent: selection.intent,
    );

    // ── Step 4: Scale for readiness/RPE ──────────────────────────────────
    final scaled = _scaler.scale(resolvedWorkout, scalingSignals);

    return ResolverResult(
      workout: scaled.workout,
      dayRole: selection.dayRole,
      wasDowngraded: selection.wasDowngraded,
      scalingAdjustments: scaled.adjustments,
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

  // ========================================================================
  // PACE RESOLUTION
  // ========================================================================

  /// Resolve a PaceZone to a ResolvedPace, handling the special
  /// goal-pace zones that need target race time.
  ResolvedPace _resolvePaceZone(
      PaceZone zone, ResolverContext context) {
    if (_isGoalPaceZone(zone)) {
      if (context.hasGoalPace) {
        return context.paceTable.resolveGoalPace(
          raceDistance: context.goalRaceDistance!,
          targetTimeSeconds: context.goalRaceTimeSeconds!,
        );
      }
      // Fallback: if no goal time set, use tempo pace.
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
        recovery: b.recovery,
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

      if (block.recoveryBlock != null && reps > 1) {
        double recoveryKm;
        if (variant?.recoveryDistanceMeters != null) {
          recoveryKm = variant!.recoveryDistanceMeters! / 1000.0;
        } else {
          recoveryKm = block.recoveryBlock!.value;
        }
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
    final resolvedPace =
        _resolvePaceZone(block.paceZone, resolverContext);

    // ── Reps ─────────────────────────────────────────────────────────────
    int? reps;
    if (block.reps != null) {
      reps = variant?.reps ?? block.reps;
    }

    // ── Recovery ─────────────────────────────────────────────────────────
    ResolvedBlock? resolvedRecovery;
    if (block.recoveryBlock != null) {
      double recoveryKm;
      if (variant?.recoveryDistanceMeters != null) {
        recoveryKm = variant!.recoveryDistanceMeters! / 1000.0;
      } else {
        recoveryKm = block.recoveryBlock!.value;
      }

      final recoveryPace =
          _resolvePaceZone(block.recoveryBlock!.paceZone, resolverContext);

      resolvedRecovery = ResolvedBlock(
        type: BlockType.recovery,
        distanceKm: _roundSmart(recoveryKm),
        paceMinSecondsPerKm: recoveryPace.minSecondsPerKm,
        paceMaxSecondsPerKm: recoveryPace.maxSecondsPerKm,
      );
    }

    return ResolvedBlock(
      type: block.type,
      distanceKm: _roundSmart(distanceKm),
      paceMinSecondsPerKm: resolvedPace.minSecondsPerKm,
      paceMaxSecondsPerKm: resolvedPace.maxSecondsPerKm,
      isRpeOnly: resolvedPace.isRpeOnly,
      reps: reps,
      recovery: resolvedRecovery,
      label: block.label,
    );
  }

  // ========================================================================
  // ROUNDING
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