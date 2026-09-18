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
/// v4: DurationType.fixedSeconds support added.
///   Hill sprints and hill repeats use time-based blocks.
///   _calculateFixedDistance estimates km at 5:30/km for budget only.
///   _resolveBlock passes durationSeconds to ResolvedBlock for display.
///   Recovery distance never counted anywhere — timing only.
library;

import '../config/workout_template_library.dart';
import '../../config/feature_flags.dart';
import 'session_selector.dart';
import 'volume_calculator.dart';
import '../core/pace_table.dart';
import '../core/vdot_calculator.dart';
import '../daily/dynamic_scaler.dart';
import '../../models/training_phase.dart';

// ============================================================================
// LADDER / PYRAMID CONFIG
// ============================================================================

class _LadderStep {
  final int meters;
  final int recoverySeconds;
  const _LadderStep(this.meters, this.recoverySeconds);
}

class _LadderConfig {
  final List<_LadderStep> steps;
  const _LadderConfig(this.steps);
  double get workKm => steps.fold(0.0, (sum, s) => sum + s.meters / 1000.0);
}

// Ascending ladders — small to large
const _ladderConfigs = [
  _LadderConfig([
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
  ]),
  _LadderConfig([
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
    _LadderStep(1000, 180),
  ]),
  _LadderConfig([
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
    _LadderStep(1000, 180),
    _LadderStep(1200, 210),
  ]),
  _LadderConfig([
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
    _LadderStep(1000, 180),
    _LadderStep(1200, 210),
    _LadderStep(1600, 270),
  ]),
];

// Pyramids — up then back down
const _pyramidConfigs = [
  _LadderConfig([
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
    _LadderStep(600, 120),
    _LadderStep(400, 90),
  ]),
  _LadderConfig([
    _LadderStep(200, 60),
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
    _LadderStep(600, 120),
    _LadderStep(400, 90),
    _LadderStep(200, 60),
  ]),
  _LadderConfig([
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
    _LadderStep(1000, 180),
    _LadderStep(800, 150),
    _LadderStep(600, 120),
    _LadderStep(400, 90),
  ]),
  _LadderConfig([
    _LadderStep(200, 60),
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
    _LadderStep(1000, 180),
    _LadderStep(800, 150),
    _LadderStep(600, 120),
    _LadderStep(400, 90),
    _LadderStep(200, 60),
  ]),
  _LadderConfig([
    _LadderStep(400, 90),
    _LadderStep(600, 120),
    _LadderStep(800, 150),
    _LadderStep(1000, 180),
    _LadderStep(1200, 210),
    _LadderStep(1000, 180),
    _LadderStep(800, 150),
    _LadderStep(600, 120),
    _LadderStep(400, 90),
  ]),
];

// ============================================================================
// SCALING TIER
// ============================================================================

enum ScalingTier {
  full, // green  — run as prescribed
  reduced, // yellow — ~80% volume, same intent
  minimum, // red    — ~60-65% volume, same intent
}

// ============================================================================
// RESOLVER CONTEXT
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
  static const int _minIntervalReps = 3;
  static const double _minContinuousKm = 2.0;

  /// Conservative hill pace for budget estimation: 5:30/km = 330 s/km.
  /// Used only for fixedSeconds blocks — display always shows seconds.
  static const double _hillPaceSecPerKm = 330.0;

  const WorkoutResolver({
    SessionSelector? selector,
    VolumeCalculator? volumeCalculator,
    DynamicScaler? scaler,
  }) : _selector = selector ?? const SessionSelector(),
       _volumeCalculator = volumeCalculator ?? const VolumeCalculator(),
       _scaler = scaler ?? const DynamicScaler();

  ResolverResult resolve({
    required SelectionContext selectionContext,
    required ResolverContext resolverContext,
    required ScalingSignals scalingSignals,
  }) {
    final tier = _tierFromReadiness(selectionContext.readiness);

    var selection = _selector.select(selectionContext);
    if (selection == null) return const ResolverResult.rest();

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
          variant: WorkoutLibrary.getVariant(
            substitute,
            selectionContext.phase,
          ),
          dayRole: selection.dayRole,
          intent: selection.intent,
          wasDowngraded: true,
          reason: selection.reason,
          originalPlannedIntent: selection.originalPlannedIntent,
        );
      }
    }

    final usePlanned =
        !selection.wasDowngraded && selectionContext.plannedDistanceKm != null;
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

    if (selection.intent == WorkoutIntent.endurance &&
        tier != ScalingTier.full) {
      final scaled = _scaleLongRunDistance(totalDistanceKm, tier);
      if (scaled != totalDistanceKm) {
        adjustments.add(
          'Long run scaled: ${totalDistanceKm.toStringAsFixed(1)} → '
          '${scaled.toStringAsFixed(1)} km (${tier.name})',
        );
        totalDistanceKm = scaled;
      }
    }

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

    final scaled = _scaler.scale(resolvedWorkout, scalingSignals);

    return ResolverResult(
      workout: scaled.workout,
      dayRole: selection.dayRole,
      wasDowngraded: selection.wasDowngraded || tier != ScalingTier.full,
      scalingAdjustments: [...adjustments, ...scaled.adjustments],
      selectionReason: selection.reason,
    );
  }

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

    /// Weeks spent on the current ladder rung (session-level progression).
    /// Each step adds a rep to interval work; the quality cap still applies.
    int progressionStep = 0,
  }) {
    // Ladder and pyramid are resolved dynamically — skip standard block path.
    if (template.id == 'vo2_ladder' || template.id == 'vo2_pyramid') {
      return _resolveDynamicLadder(
        template: template,
        totalDistanceKm: totalDistanceKm,
        resolverContext: resolverContext,
        phase: phase,
        intent: intent,
      );
    }

    final fixedDistanceKm = _calculateFixedDistance(template.blocks, variant);
    final flexibleBudgetKm = (totalDistanceKm - fixedDistanceKm).clamp(
      1.0,
      double.infinity,
    );

    final percentSum = template.blocks
        .where((b) => b.durationType == DurationType.percentage)
        .fold(0.0, (sum, b) => sum + b.value);

    // For interval templates, compute reps from the allocated budget so the
    // workout fills close to totalDistanceKm instead of always resolving to
    // the same fixed structure regardless of what the planner assigned.
    var dynamicReps = _computeDynamicReps(
      template: template,
      variant: variant,
      totalDistanceKm: totalDistanceKm,
      scalingAdjustments: scalingAdjustments,
    );

    // Session-level progression: same rung, one more rep each week (max +2).
    // Only for interval-style quality — continuous work progresses by rung.
    final stepBump = progressionStep.clamp(0, 2);
    if (dynamicReps != null &&
        stepBump > 0 &&
        (intent == WorkoutIntent.threshold ||
            intent == WorkoutIntent.vo2max ||
            intent == WorkoutIntent.speed ||
            intent == WorkoutIntent.raceSpecific)) {
      dynamicReps += stepBump;
      scalingAdjustments?.add(
        'Progression: +$stepBump reps (week ${progressionStep + 1} on this rung)',
      );
    }

    final resolvedBlocks = <ResolvedBlock>[];
    for (final block in template.blocks) {
      final isRepBlock =
          block.type == BlockType.main &&
          block.reps != null &&
          block.durationType == DurationType.fixedKm;
      resolvedBlocks.add(
        _resolveBlock(
          block: block,
          variant: variant,
          flexibleBudgetKm: flexibleBudgetKm,
          percentSum: percentSum,
          resolverContext: resolverContext,
          experienceLevel: experienceLevel,
          intent: intent,
          scalingTier: scalingTier,
          scalingAdjustments: scalingAdjustments,
          overrideReps: isRepBlock ? dynamicReps : null,
        ),
      );
    }

    _enforceQualityCap(resolvedBlocks, totalDistanceKm);
    _fitAerobicVolume(resolvedBlocks, totalDistanceKm, intent, scalingTier);

    return ResolvedWorkout(
      templateId: template.id,
      name: template.name,
      intent: intent,
      blocks: resolvedBlocks,
      phase: phase,
      coachNote: variant?.note,
    );
  }

  /// Aerobic templates (easy / long / medium-long) must actually reach the
  /// distance the planner budgeted for the day. Some templates have a fixed
  /// structure (recovery_shakeout = 6×400 m) that ignores the budget entirely;
  /// stretch or trim the largest distance-based, non-warmup block to close the
  /// gap. Only runs at full scaling — a readiness cut is meant to fall short.
  void _fitAerobicVolume(
    List<ResolvedBlock> blocks,
    double totalDistanceKm,
    WorkoutIntent intent,
    ScalingTier tier,
  ) {
    if (tier != ScalingTier.full) return;
    if (intent != WorkoutIntent.aerobicBase &&
        intent != WorkoutIntent.endurance) {
      return;
    }
    if (totalDistanceKm <= 0 || blocks.isEmpty) return;

    double total() => blocks.fold(0.0, (s, b) => s + b.totalDistanceKm);
    final current = total();
    if (current >= totalDistanceKm * 0.92 &&
        current <= totalDistanceKm * 1.12) {
      return;
    }

    // Pick the block to adjust: the largest by total distance that isn't a
    // warmup and isn't RPE-only.
    var idx = -1;
    var best = -1.0;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.type == BlockType.warmup || b.isRpeOnly) continue;
      if (b.totalDistanceKm > best) {
        best = b.totalDistanceKm;
        idx = i;
      }
    }
    if (idx < 0) return;

    final b = blocks[idx];
    final reps = b.reps ?? 1;
    final delta = (totalDistanceKm - current) / reps;
    final newPerRep = _roundSmart((b.distanceKm + delta).clamp(0.4, 60.0));
    blocks[idx] = ResolvedBlock(
      type: b.type,
      distanceKm: newPerRep,
      durationSeconds: b.durationSeconds,
      paceMinSecondsPerKm: b.paceMinSecondsPerKm,
      paceMaxSecondsPerKm: b.paceMaxSecondsPerKm,
      isRpeOnly: b.isRpeOnly,
      reps: b.reps,
      recoverySeconds: b.recoverySeconds,
      recoveryMeters: b.recoveryMeters,
      label: b.label,
    );
  }

  // ============================================================================
  // SCALING TIER HELPERS
  // ============================================================================

  ScalingTier _tierFromReadiness(SelectorReadiness readiness) =>
      !enableReadinessPaceAdjustment
      ? ScalingTier.full
      : switch (readiness) {
        SelectorReadiness.green => ScalingTier.full,
        SelectorReadiness.yellow => ScalingTier.reduced,
        SelectorReadiness.red => ScalingTier.minimum,
      };

  int _scaleReps(int reps, ScalingTier tier) {
    final scaled = switch (tier) {
      ScalingTier.full => reps,
      ScalingTier.reduced => (reps * 0.80).round(),
      ScalingTier.minimum => (reps * 0.62).round(),
    };
    return scaled.clamp(_minIntervalReps, reps);
  }

  double _scaleContinuousDistance(double km, ScalingTier tier) {
    if (tier == ScalingTier.full) return km;
    final scaled = switch (tier) {
      ScalingTier.full => km,
      ScalingTier.reduced => km * 0.80,
      ScalingTier.minimum => km * 0.60,
    };
    return _roundToPractical(scaled).clamp(_minContinuousKm, km);
  }

  double _scaleLongRunDistance(double km, ScalingTier tier) {
    if (tier == ScalingTier.full) return km;
    final scaled = switch (tier) {
      ScalingTier.full => km,
      ScalingTier.reduced => km * 0.85,
      ScalingTier.minimum => km * 0.70,
    };
    return _roundToPractical(scaled);
  }

  double _roundToPractical(double km) {
    final rounded = (km * 2).round() / 2.0;
    return rounded < _minContinuousKm ? _minContinuousKm : rounded;
  }

  bool _templateIsIntervalBased(WorkoutTemplate template) =>
      template.blocks.any((b) => b.type == BlockType.main && b.reps != null);

  WorkoutTemplate? _substituteTemplate({
    required WorkoutTemplate original,
    required SelectionContext selectionContext,
  }) {
    final preferredIds = switch (original.id) {
      'vo2_ladder' => ['vo2_classic', 'vo2_600'],
      'vo2_pyramid' => ['vo2_classic', 'vo2_600'],
      'race_simulation' => ['race_gp_intervals'],
      'race_dress_rehearsal' => ['race_gp_intervals'],
      'race_time_trial' => ['race_gp_intervals'],
      _ => <String>[],
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

  ResolvedPace _resolvePaceZone(
    PaceZone zone,
    ResolverContext context,
    WorkoutIntent intent,
  ) {
    if (_isGoalPaceZone(zone)) {
      if (context.hasGoalPace) {
        return context.paceTable.resolveGoalPace(
          raceDistance: context.goalRaceDistance!,
          targetTimeSeconds: context.goalRaceTimeSeconds!,
        );
      }
      if (intent == WorkoutIntent.endurance) {
        return context.paceTable.resolve(PaceZone.marathonPace);
      }
      return context.paceTable.resolve(PaceZone.tempo);
    }
    return context.paceTable.resolve(zone);
  }

  bool _isGoalPaceZone(PaceZone zone) =>
      zone == PaceZone.goalPace ||
      zone == PaceZone.raceSimulation ||
      zone == PaceZone.dressRehearsal;

  // ========================================================================
  // QUALITY CAP
  // ========================================================================

  void _enforceQualityCap(List<ResolvedBlock> blocks, double totalDistanceKm) {
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
        durationSeconds: b.durationSeconds,
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
            durationSeconds: blocks[i].durationSeconds,
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
    List<BlockTemplate> blocks,
    PhaseVariant? variant,
  ) {
    var total = 0.0;

    for (final block in blocks) {
      if (block.durationType == DurationType.percentage) continue;

      // fixedSeconds: estimate km from duration at conservative hill pace.
      // Budget only — display shows seconds not km.
      if (block.durationType == DurationType.fixedSeconds) {
        final seconds = variant?.repDurationSeconds ?? block.value;
        final reps = block.reps != null ? (variant?.reps ?? block.reps!) : 1;
        total += (seconds / _hillPaceSecPerKm) * reps;
        // No recovery distance — jog-down captured in recoverySeconds only.
        continue;
      }

      // fixedKm path.
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
      // Recovery distance intentionally excluded — timing only.
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
    int? overrideReps,
  }) {
    // ── Distance ─────────────────────────────────────────────────────────
    double distanceKm;
    int? durationSeconds;

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

      case DurationType.fixedSeconds:
        // Time-based block. Store seconds for display; estimate km for budget.
        final seconds = (variant?.repDurationSeconds ?? block.value).round();
        durationSeconds = seconds;
        distanceKm = seconds / _hillPaceSecPerKm;

      case DurationType.percentage:
        final normalizedFraction = percentSum > 0
            ? block.value / percentSum
            : 1.0;
        distanceKm = flexibleBudgetKm * normalizedFraction;
    }

    // ── Pace ─────────────────────────────────────────────────────────────
    final resolvedPace = _resolvePaceZone(
      block.paceZone,
      resolverContext,
      intent,
    );

    // ── Reps ─────────────────────────────────────────────────────────────
    int? reps;
    if (block.reps != null) {
      final raw = overrideReps ?? variant?.reps ?? block.reps!;
      final experienceClamped = _clampRepsForExperience(raw, experienceLevel);

      if (block.type == BlockType.main && scalingTier != ScalingTier.full) {
        final beforeScale = experienceClamped;
        reps = _scaleReps(experienceClamped, scalingTier);
        if (reps != beforeScale) {
          final label = durationSeconds != null
              ? '${durationSeconds}s rep'
              : '${(distanceKm * 1000).round()}m';
          scalingAdjustments?.add(
            'Reps scaled: $beforeScale → $reps × $label (${scalingTier.name})',
          );
        }
      } else {
        reps = experienceClamped;
      }
    }

    // ── Continuous block scaling (no reps, not time-based) ────────────────
    if (block.type == BlockType.main &&
        reps == null &&
        durationSeconds == null &&
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
    // recoveryMeters kept for formattedRecovery conversion (→ seconds at 360s/km).
    // Never contributes to any distance calculation.
    final int? resolvedRecoverySeconds =
        variant?.recoverySeconds ?? block.recoverySeconds;
    final double? resolvedRecoveryMeters =
        variant?.recoveryMeters ?? block.recoveryMeters;

    return ResolvedBlock(
      type: block.type,
      distanceKm: _roundSmart(distanceKm),
      durationSeconds: durationSeconds,
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
  // DYNAMIC LADDER / PYRAMID
  // ========================================================================

  ResolvedWorkout _resolveDynamicLadder({
    required WorkoutTemplate template,
    required double totalDistanceKm,
    required ResolverContext resolverContext,
    required TrainingPhase phase,
    required WorkoutIntent intent,
  }) {
    final isPyramid = template.id == 'vo2_pyramid';
    final configs = isPyramid ? _pyramidConfigs : _ladderConfigs;

    const wuKm = 2.0;
    const minCdKm = 1.0;
    final availableForWork = totalDistanceKm - wuKm - minCdKm;

    // Pick the largest config whose work km fits the available budget.
    final chosen = configs.lastWhere(
      (c) => c.workKm <= availableForWork,
      orElse: () => configs.first,
    );

    final cdKm = (totalDistanceKm - wuKm - chosen.workKm).clamp(
      minCdKm,
      double.infinity,
    );

    final easyPace = resolverContext.paceTable.resolve(PaceZone.aerobicEasy);
    final workPace = resolverContext.paceTable.resolve(PaceZone.ladderPyramid);

    final blocks = <ResolvedBlock>[];

    // Warmup
    blocks.add(
      ResolvedBlock(
        type: BlockType.warmup,
        distanceKm: wuKm,
        paceMinSecondsPerKm: easyPace.minSecondsPerKm,
        paceMaxSecondsPerKm: easyPace.maxSecondsPerKm,
      ),
    );

    // Work steps — each gets its own distance, pace, and recovery seconds
    for (final step in chosen.steps) {
      blocks.add(
        ResolvedBlock(
          type: BlockType.main,
          distanceKm: step.meters / 1000.0,
          paceMinSecondsPerKm: workPace.minSecondsPerKm,
          paceMaxSecondsPerKm: workPace.maxSecondsPerKm,
          recoverySeconds: step.recoverySeconds,
          label: '${step.meters}m',
        ),
      );
    }

    // Cooldown — absorbs remaining budget
    blocks.add(
      ResolvedBlock(
        type: BlockType.cooldown,
        distanceKm: _roundSmart(cdKm),
        paceMinSecondsPerKm: easyPace.minSecondsPerKm,
        paceMaxSecondsPerKm: easyPace.maxSecondsPerKm,
      ),
    );

    return ResolvedWorkout(
      templateId: template.id,
      name: template.name,
      intent: intent,
      blocks: blocks,
      phase: phase,
    );
  }

  // ========================================================================
  // DYNAMIC REPS
  // ========================================================================

  // Computes how many reps fit in the allocated budget for interval templates.
  // Returns null when not applicable (percentage-based, multi-block, time-based).
  int? _computeDynamicReps({
    required WorkoutTemplate template,
    required PhaseVariant? variant,
    required double totalDistanceKm,
    List<String>? scalingAdjustments,
  }) {
    if (template.intent != WorkoutIntent.threshold &&
        template.intent != WorkoutIntent.vo2max &&
        template.intent != WorkoutIntent.speed &&
        template.intent != WorkoutIntent.raceSpecific)
      return null;

    // Only applies to templates with exactly one fixedKm main block with reps.
    final repBlocks = template.blocks
        .where(
          (b) =>
              b.type == BlockType.main &&
              b.reps != null &&
              b.durationType == DurationType.fixedKm,
        )
        .toList();
    if (repBlocks.length != 1) return null;

    final mainBlock = repBlocks.first;

    final repKm =
        variant?.repDistanceKm ??
        (variant?.repDistanceMeters != null
            ? variant!.repDistanceMeters! / 1000.0
            : null) ??
        mainBlock.value;
    if (repKm <= 0) return null;

    // Overhead = WU + CD + recovery jog blocks (all non-main fixedKm blocks).
    var overheadKm = 0.0;
    for (final b in template.blocks) {
      if (b.type == BlockType.main) continue;
      if (b.durationType != DurationType.fixedKm) continue;
      overheadKm += b.value;
    }

    final availableKm = totalDistanceKm - overheadKm;
    if (availableKm <= 0) return null;

    final baseReps = variant?.reps ?? mainBlock.reps!;
    final rawDynamic = (availableKm / repKm).floor();

    // If budget allows more reps, use them. If budget is tight, keep base —
    // but never demand more than baseReps as the floor (some templates have a
    // base of 2, below _minIntervalReps).
    final tightFloor = _minIntervalReps < baseReps ? _minIntervalReps : baseReps;
    final dynamic = rawDynamic >= baseReps
        ? rawDynamic
        : rawDynamic.clamp(tightFloor, baseReps);

    if (dynamic != baseReps) {
      scalingAdjustments?.add(
        'Dynamic reps: $baseReps → $dynamic × '
        '${(repKm * 1000).round()}m '
        '(budget: ${totalDistanceKm.toStringAsFixed(1)} km)',
      );
    }

    return dynamic;
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
      'beginner' => (reps * 0.65).round().clamp(2, reps).toInt(),
      'intermediate' => (reps * 0.85).round().clamp(2, reps).toInt(),
      'advanced' => reps,
      _ => (reps * 0.85).round().clamp(2, reps).toInt(),
    };
  }
}
