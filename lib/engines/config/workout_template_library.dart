/// Workout Template Library for Endura — Rebuild v2
///
/// Architecture:
///   Intent → Template → Variant (by phase)
///
/// Templates define workout STRUCTURE with specific PaceZone references.
/// PaceTable converts zones to real paces via CS × multiplier.
/// VolumeCalculator uses [recommendedPercentage] + [distanceByRace]
/// to allocate weekly volume into concrete session distances.
///
/// CHANGE FROM v1: IntensityZone (6 generic zones) replaced by
/// PaceZone (18 specific zones) from pace_table.dart. Each block
/// now references exactly the pace zone it needs.
library;

import '../core/pace_table.dart';
import '../../models/training_phase.dart';
// ============================================================================
// ENUMS
// ============================================================================

enum WorkoutIntent {
  aerobicBase,
  endurance,
  threshold,
  vo2max,
  speed,
  raceSpecific,
  recovery,
}

enum RaceDistance {
  fiveK,
  tenK,
  halfMarathon,
  marathon,
}

enum BlockType {
  warmup,
  main,
  recovery,
  cooldown,
}

enum DurationType {
  fixedKm,
  percentage,
}

// ============================================================================
// DISTANCE RANGE
// ============================================================================

class DistanceRange {
  final double minKm;
  final double maxKm;

  const DistanceRange({required this.minKm, required this.maxKm});
}

// ============================================================================
// BLOCK TEMPLATE
// ============================================================================

class BlockTemplate {
  final BlockType type;
  final DurationType durationType;
  final double value;
  final PaceZone paceZone;
  final int? reps;
  final BlockTemplate? recoveryBlock;
  final String? label;

  const BlockTemplate({
    required this.type,
    required this.durationType,
    required this.value,
    required this.paceZone,
    this.reps,
    this.recoveryBlock,
    this.label,
  });

  const BlockTemplate.main({
    required double km,
    required PaceZone zone,
    int? reps,
    BlockTemplate? recovery,
    String? label,
  }) : this(
          type: BlockType.main,
          durationType: DurationType.fixedKm,
          value: km,
          paceZone: zone,
          reps: reps,
          recoveryBlock: recovery,
          label: label,
        );

  const BlockTemplate.mainMeters({
    required double meters,
    required PaceZone zone,
    int? reps,
    BlockTemplate? recovery,
    String? label,
  }) : this(
          type: BlockType.main,
          durationType: DurationType.fixedKm,
          value: meters / 1000,
          paceZone: zone,
          reps: reps,
          recoveryBlock: recovery,
          label: label,
        );

  const BlockTemplate.percent({
    required BlockType type,
    required double fraction,
    required PaceZone zone,
  }) : this(
          type: type,
          durationType: DurationType.percentage,
          value: fraction,
          paceZone: zone,
        );

  const BlockTemplate.recoveryJog({
    required double km,
  }) : this(
          type: BlockType.recovery,
          durationType: DurationType.fixedKm,
          value: km,
          paceZone: PaceZone.easyRecovery,
        );

  const BlockTemplate.recoveryMeters({
    required double meters,
  }) : this(
          type: BlockType.recovery,
          durationType: DurationType.fixedKm,
          value: meters / 1000,
          paceZone: PaceZone.easyRecovery,
        );
}

// ============================================================================
// PHASE VARIANT
// ============================================================================

class PhaseVariant {
  final int? reps;
  final double? repDistanceKm;
  final double? repDistanceMeters;
  final double? recoveryDistanceMeters;
  final double volumeMultiplier;
  final String? note;

  const PhaseVariant({
    this.reps,
    this.repDistanceKm,
    this.repDistanceMeters,
    this.recoveryDistanceMeters,
    this.volumeMultiplier = 1.0,
    this.note,
  });
}

// ============================================================================
// WORKOUT TEMPLATE
// ============================================================================

class WorkoutTemplate {
  final String id;
  final String name;
  final WorkoutIntent intent;
  final Set<TrainingPhase> applicablePhases;
  final Set<RaceDistance> applicableRaceDistances;
  final Map<RaceDistance, DistanceRange> distanceByRace;
  final double recommendedPercentage;
  final List<BlockTemplate> blocks;
  final Map<TrainingPhase, PhaseVariant> phaseVariants;
  final String description;

  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.intent,
    required this.applicablePhases,
    required this.applicableRaceDistances,
    required this.distanceByRace,
    required this.recommendedPercentage,
    required this.blocks,
    this.phaseVariants = const {},
    this.description = '',
  });
}

// ============================================================================
// RESOLVED WORKOUT — what the athlete actually sees
// ============================================================================

class ResolvedBlock {
  final BlockType type;
  final double distanceKm;
  final int paceMinSecondsPerKm;
  final int paceMaxSecondsPerKm;
  final bool isRpeOnly;
  final int? reps;
  final ResolvedBlock? recovery;
  final String? label;

  const ResolvedBlock({
    required this.type,
    required this.distanceKm,
    required this.paceMinSecondsPerKm,
    required this.paceMaxSecondsPerKm,
    this.isRpeOnly = false,
    this.reps,
    this.recovery,
    this.label,
  });

  int get targetPace =>
      ((paceMinSecondsPerKm + paceMaxSecondsPerKm) / 2).round();

  double get totalDistanceKm {
    final repCount = reps ?? 1;
    final workDist = distanceKm * repCount;
    final recDist =
        (recovery?.distanceKm ?? 0) * (repCount > 1 ? repCount - 1 : 0);
    return workDist + recDist;
  }

  String get formattedPace {
    if (isRpeOnly) return 'RPE 9';
    return '${_fmt(paceMinSecondsPerKm)}–${_fmt(paceMaxSecondsPerKm)}/km';
  }

  String formattedPaceForIntent(WorkoutIntent intent) {
    if (isRpeOnly) return 'RPE 9';
    final isEasy = (intent == WorkoutIntent.aerobicBase ||
        intent == WorkoutIntent.recovery ||
        intent == WorkoutIntent.endurance) &&
        paceMaxSecondsPerKm - paceMinSecondsPerKm >= 30;
    if (isEasy) {
      final ceiling = (paceMinSecondsPerKm / 5).round() * 5;
      return '≤ ${_fmt(ceiling)}/km';
    }
    final lo = (paceMinSecondsPerKm / 5).round() * 5;
    final hi = (paceMaxSecondsPerKm / 5).round() * 5;
    return lo == hi ? '${_fmt(lo)}/km' : '${_fmt(lo)}–${_fmt(hi)}/km';
  }

  String get formattedDistance {
    if (distanceKm >= 1.0) return '${distanceKm.toStringAsFixed(1)} km';
    return '${(distanceKm * 1000).round()} m';
  }

  static String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

class ResolvedWorkout {
  final String templateId;
  final String name;
  final WorkoutIntent intent;
  final List<ResolvedBlock> blocks;
  final TrainingPhase phase;
  final String? coachNote;

  const ResolvedWorkout({
    required this.templateId,
    required this.name,
    required this.intent,
    required this.blocks,
    required this.phase,
    this.coachNote,
  });

  double get totalDistanceKm =>
      blocks.fold(0.0, (sum, b) => sum + b.totalDistanceKm);

  Duration get estimatedDuration {
    double totalSeconds = 0;
    for (final block in blocks) {
      final repCount = block.reps ?? 1;
      totalSeconds += block.distanceKm * block.targetPace * repCount;
      if (block.recovery != null && repCount > 1) {
        totalSeconds +=
            block.recovery!.distanceKm * block.recovery!.targetPace *
                (repCount - 1);
      }
    }
    return Duration(seconds: totalSeconds.round());
  }

  String get formattedSummary {
    final dist = totalDistanceKm.toStringAsFixed(1);
    final min = estimatedDuration.inMinutes;
    return '$dist km · ~$min min';
  }
}

// ============================================================================
// ============================================================================
//
//   W O R K O U T   L I B R A R Y
//
//   PaceZone references (from pace_table.dart):
//     shakeout, easyRecovery, aerobicEasy, progressiveStart, progressiveEnd,
//     tempo, cruiseIntervals, thresholdProgStart, thresholdProgEnd,
//     vo2Intervals, shortShort, fourHundredRepeats, ladderPyramid,
//     strides, speedReps, hillSprints, goalPace, raceSimulation,
//     dressRehearsal
//
// ============================================================================
// ============================================================================

class WorkoutLibrary {
  static const List<WorkoutTemplate> templates = [
    // ── AEROBIC BASE ──────────────────────────────────────────────────────

    WorkoutTemplate(
      id: 'easy_steady',
      name: 'Easy Run',
      intent: WorkoutIntent.aerobicBase,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
        TrainingPhase.taper,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.tenK: DistanceRange(minKm: 4, maxKm: 8),
        RaceDistance.halfMarathon: DistanceRange(minKm: 5, maxKm: 10),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 12),
      },
      recommendedPercentage: 0.20,
      description: 'Steady conversational pace. Build aerobic base and recovery.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 1.0,
          zone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'easy_progressive',
      name: 'Progressive Easy',
      intent: WorkoutIntent.aerobicBase,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.tenK: DistanceRange(minKm: 4, maxKm: 8),
        RaceDistance.halfMarathon: DistanceRange(minKm: 5, maxKm: 10),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 12),
      },
      recommendedPercentage: 0.18,
      description: 'Start easy, finish at steady effort. Teaches pace awareness.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.65,
          zone: PaceZone.progressiveStart,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.35,
          zone: PaceZone.progressiveEnd,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'easy_strides',
      name: 'Easy + Strides',
      intent: WorkoutIntent.aerobicBase,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.tenK: DistanceRange(minKm: 4, maxKm: 8),
        RaceDistance.halfMarathon: DistanceRange(minKm: 5, maxKm: 10),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 12),
      },
      recommendedPercentage: 0.18,
      description: 'Easy run with strides at the end for turnover and form.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.85,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 100,
          zone: PaceZone.strides,
          reps: 5,
          recovery: BlockTemplate.recoveryMeters(meters: 100),
          label: 'Strides',
        ),
      ],
      phaseVariants: {
        TrainingPhase.base: PhaseVariant(
          reps: 4,
          repDistanceMeters: 100,
          recoveryDistanceMeters: 100,
          note: 'Start with 4 strides',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 6,
          repDistanceMeters: 100,
          recoveryDistanceMeters: 100,
          note: 'Progress to 6 strides',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 8,
          repDistanceMeters: 100,
          recoveryDistanceMeters: 100,
          note: 'Maintain 8 strides',
        ),
      },
    ),

    // ── ENDURANCE (LONG RUNS) ─────────────────────────────────────────────

    WorkoutTemplate(
      id: 'long_steady',
      name: 'Long Run',
      intent: WorkoutIntent.endurance,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
        TrainingPhase.taper,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.tenK: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 20),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 32),
      },
      recommendedPercentage: 0.30,
      description: 'Steady-state long run for aerobic endurance.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 1.0,
          zone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.base: PhaseVariant(
          volumeMultiplier: 0.85,
          note: 'Conservative long run distance',
        ),
        TrainingPhase.build: PhaseVariant(
          volumeMultiplier: 1.0,
          note: 'Full long run distance',
        ),
        TrainingPhase.peak: PhaseVariant(
          volumeMultiplier: 1.10,
          note: 'Peak long run — longest of the plan',
        ),
        TrainingPhase.taper: PhaseVariant(
          volumeMultiplier: 0.65,
          note: 'Reduced taper long run',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'long_progression',
      name: 'Long Run — Progression',
      intent: WorkoutIntent.endurance,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.tenK: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 20),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 32),
      },
      recommendedPercentage: 0.30,
      description: 'Long run starting easy, finishing at steady. Teaches negative splitting.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.70,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.30,
          zone: PaceZone.progressiveEnd,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'long_gp_finish',
      name: 'Long Run — Goal Pace Finish',
      intent: WorkoutIntent.endurance,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 20),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 32),
      },
      recommendedPercentage: 0.30,
      description: 'Long run with final segment at race goal pace. Simulates race fatigue.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.warmup,
          fraction: 0.15,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.60,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.25,
          zone: PaceZone.goalPace,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          volumeMultiplier: 1.0,
          note: 'Goal pace block = 20-25% of long run',
        ),
        TrainingPhase.peak: PhaseVariant(
          volumeMultiplier: 1.10,
          note: 'Longer goal pace block at peak',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'long_mid_block',
      name: 'Long Run — Mid-Race Block',
      intent: WorkoutIntent.endurance,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {RaceDistance.marathon},
      distanceByRace: {
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 32),
      },
      recommendedPercentage: 0.30,
      description: 'Long run with a sustained goal-pace block in the middle. Marathon-specific.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.warmup,
          fraction: 0.20,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.20,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.30,
          zone: PaceZone.goalPace,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.20,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.cooldown,
          fraction: 0.10,
          zone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'medium_long_run',
      name: 'Medium Long Run',
      intent: WorkoutIntent.endurance,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      recommendedPercentage: 0.20,
      description: 'Midweek longer effort. Bridges easy runs and the long run.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 1.0,
          zone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.base: PhaseVariant(
          volumeMultiplier: 0.85,
          note: 'Conservative medium long',
        ),
        TrainingPhase.build: PhaseVariant(
          volumeMultiplier: 1.0,
          note: 'Standard medium long',
        ),
        TrainingPhase.peak: PhaseVariant(
          volumeMultiplier: 1.05,
          note: 'Slight bump at peak',
        ),
      },
    ),

    // ── THRESHOLD ─────────────────────────────────────────────────────────

    WorkoutTemplate(
      id: 'tempo_continuous',
      name: 'Tempo Run',
      intent: WorkoutIntent.threshold,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      recommendedPercentage: 0.18,
      description: 'Continuous run at threshold pace. Builds lactate clearance.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.warmup,
          fraction: 0.20,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.60,
          zone: PaceZone.tempo,
        ),
        BlockTemplate.percent(
          type: BlockType.cooldown,
          fraction: 0.20,
          zone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          volumeMultiplier: 0.90,
          note: 'Moderate tempo volume in build',
        ),
        TrainingPhase.peak: PhaseVariant(
          volumeMultiplier: 1.0,
          note: 'Full tempo volume at peak',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'cruise_intervals',
      name: 'Cruise Intervals',
      intent: WorkoutIntent.threshold,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      recommendedPercentage: 0.18,
      description: 'Threshold-pace reps with short recovery. Gentler intro to threshold.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.main(
          km: 1.5,
          zone: PaceZone.cruiseIntervals,
          reps: 4,
          recovery: BlockTemplate.recoveryMeters(meters: 400),
          label: 'Cruise',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.base: PhaseVariant(
          reps: 3,
          repDistanceKm: 1.0,
          recoveryDistanceMeters: 500,
          note: 'Intro: shorter reps, longer recovery',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 4,
          repDistanceKm: 1.5,
          recoveryDistanceMeters: 400,
          note: 'Standard cruise intervals',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 3,
          repDistanceKm: 2.0,
          recoveryDistanceMeters: 400,
          note: 'Longer reps, maintain quality',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'threshold_progression',
      name: 'Threshold Progression',
      intent: WorkoutIntent.threshold,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      recommendedPercentage: 0.18,
      description: 'Blocks that get progressively harder. Teaches threshold management.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.main(
          km: 2.0,
          zone: PaceZone.thresholdProgStart,
          label: 'Block 1 — Steady',
        ),
        BlockTemplate.recoveryJog(km: 0.5),
        BlockTemplate.main(
          km: 2.0,
          zone: PaceZone.tempo,
          label: 'Block 2 — Threshold',
        ),
        BlockTemplate.recoveryJog(km: 0.5),
        BlockTemplate.main(
          km: 1.0,
          zone: PaceZone.thresholdProgEnd,
          label: 'Block 3 — Hard',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    // ── VO₂MAX ────────────────────────────────────────────────────────────

    WorkoutTemplate(
      id: 'vo2_classic',
      name: 'VO₂ Intervals',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.halfMarathon: DistanceRange(minKm: 7, maxKm: 11),
        RaceDistance.marathon: DistanceRange(minKm: 8, maxKm: 12),
      },
      recommendedPercentage: 0.15,
      description: 'Classic VO₂max intervals. Primary high-intensity session.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.main(
          km: 1.0,
          zone: PaceZone.vo2Intervals,
          reps: 5,
          recovery: BlockTemplate.recoveryMeters(meters: 400),
          label: 'VO₂',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          reps: 4,
          repDistanceKm: 0.8,
          recoveryDistanceMeters: 400,
          note: 'Build into VO₂ with shorter reps',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 5,
          repDistanceKm: 1.0,
          recoveryDistanceMeters: 400,
          note: 'Full VO₂ dose at peak',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_short_short',
      name: 'Short-Short Intervals',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
      },
      recommendedPercentage: 0.15,
      description: 'Alternating fast/slow in short bursts. High VO₂ time with less strain.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 200,
          zone: PaceZone.shortShort,
          reps: 12,
          recovery: BlockTemplate.recoveryMeters(meters: 200),
          label: 'Short-Short',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          reps: 10,
          repDistanceMeters: 200,
          recoveryDistanceMeters: 200,
          note: 'Start with 10 reps',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 14,
          repDistanceMeters: 200,
          recoveryDistanceMeters: 200,
          note: 'Progress to 14 reps',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_ladder',
      name: 'Ladder Intervals',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.halfMarathon: DistanceRange(minKm: 7, maxKm: 11),
      },
      recommendedPercentage: 0.15,
      description: 'Ascending ladder: 200-400-600-800-1000. Builds and releases.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 200, zone: PaceZone.ladderPyramid, label: '200m'),
        BlockTemplate.recoveryMeters(meters: 200),
        BlockTemplate.mainMeters(
          meters: 400, zone: PaceZone.ladderPyramid, label: '400m'),
        BlockTemplate.recoveryMeters(meters: 200),
        BlockTemplate.mainMeters(
          meters: 600, zone: PaceZone.ladderPyramid, label: '600m'),
        BlockTemplate.recoveryMeters(meters: 300),
        BlockTemplate.mainMeters(
          meters: 800, zone: PaceZone.ladderPyramid, label: '800m'),
        BlockTemplate.recoveryMeters(meters: 300),
        BlockTemplate.mainMeters(
          meters: 1000, zone: PaceZone.ladderPyramid, label: '1000m'),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'vo2_pyramid',
      name: 'Pyramid Intervals',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
      },
      recommendedPercentage: 0.15,
      description: 'Pyramid: 200-400-600-800-600-400-200. Peak-phase variety.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 200, zone: PaceZone.strides, label: '200m'),
        BlockTemplate.recoveryMeters(meters: 200),
        BlockTemplate.mainMeters(
          meters: 400, zone: PaceZone.ladderPyramid, label: '400m'),
        BlockTemplate.recoveryMeters(meters: 200),
        BlockTemplate.mainMeters(
          meters: 600, zone: PaceZone.ladderPyramid, label: '600m'),
        BlockTemplate.recoveryMeters(meters: 300),
        BlockTemplate.mainMeters(
          meters: 800, zone: PaceZone.vo2Intervals, label: '800m'),
        BlockTemplate.recoveryMeters(meters: 300),
        BlockTemplate.mainMeters(
          meters: 600, zone: PaceZone.ladderPyramid, label: '600m'),
        BlockTemplate.recoveryMeters(meters: 200),
        BlockTemplate.mainMeters(
          meters: 400, zone: PaceZone.ladderPyramid, label: '400m'),
        BlockTemplate.recoveryMeters(meters: 200),
        BlockTemplate.mainMeters(
          meters: 200, zone: PaceZone.strides, label: '200m'),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    // ── SPEED / NEUROMUSCULAR ─────────────────────────────────────────────

    WorkoutTemplate(
      id: 'speed_hills',
      name: 'Hill Sprints',
      intent: WorkoutIntent.speed,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 4, maxKm: 7),
        RaceDistance.tenK: DistanceRange(minKm: 5, maxKm: 8),
      },
      recommendedPercentage: 0.12,
      description: 'Short max-effort hill reps. Builds power and running economy.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 80,
          zone: PaceZone.hillSprints,
          reps: 8,
          recovery: BlockTemplate.recoveryMeters(meters: 200),
          label: 'Hill Sprint',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.base: PhaseVariant(
          reps: 6,
          repDistanceMeters: 80,
          recoveryDistanceMeters: 200,
          note: 'Start with 6 hills',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 10,
          repDistanceMeters: 80,
          recoveryDistanceMeters: 200,
          note: 'Progress to 10 hills',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'speed_reps',
      name: 'Speed Reps',
      intent: WorkoutIntent.speed,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 4, maxKm: 7),
        RaceDistance.tenK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.halfMarathon: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 10),
      },
      recommendedPercentage: 0.12,
      description: 'Short fast reps for leg speed and turnover.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 300,
          zone: PaceZone.speedReps,
          reps: 6,
          recovery: BlockTemplate.recoveryMeters(meters: 300),
          label: 'Speed Rep',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          reps: 5,
          repDistanceMeters: 200,
          recoveryDistanceMeters: 300,
          note: 'Start with 200m reps',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 6,
          repDistanceMeters: 400,
          recoveryDistanceMeters: 300,
          note: 'Progress to 400m reps',
        ),
      },
    ),

    // ── RACE SPECIFIC ─────────────────────────────────────────────────────

    WorkoutTemplate(
      id: 'race_gp_intervals',
      name: 'Goal Pace Intervals',
      intent: WorkoutIntent.raceSpecific,
      applicablePhases: {
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 16),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 24),
      },
      recommendedPercentage: 0.15,
      description: 'Reps at goal race pace. Locks in target rhythm.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.main(
          km: 1.5,
          zone: PaceZone.goalPace,
          reps: 4,
          recovery: BlockTemplate.recoveryMeters(meters: 500),
          label: 'Goal Pace',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          reps: 3,
          repDistanceKm: 1.0,
          recoveryDistanceMeters: 500,
          note: 'Shorter reps, finding the pace',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 4,
          repDistanceKm: 2.0,
          recoveryDistanceMeters: 400,
          note: 'Longer reps, race simulation',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'race_simulation',
      name: 'Race Simulation',
      intent: WorkoutIntent.raceSpecific,
      applicablePhases: {TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 16),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 24),
      },
      recommendedPercentage: 0.18,
      description: 'Extended race-pace effort. Mental and physical dress rehearsal.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.60,
          zone: PaceZone.raceSimulation,
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'race_dress_rehearsal',
      name: 'Dress Rehearsal',
      intent: WorkoutIntent.raceSpecific,
      applicablePhases: {TrainingPhase.taper},
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 16),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 24),
      },
      recommendedPercentage: 0.12,
      description: 'Short race-pace effort in taper week. Confidence builder.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.main(
          km: 2.0,
          zone: PaceZone.dressRehearsal,
          label: 'Race Pace',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    // ── RECOVERY ──────────────────────────────────────────────────────────

    WorkoutTemplate(
      id: 'recovery_shakeout',
      name: 'Shake-Out Run',
      intent: WorkoutIntent.recovery,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
        TrainingPhase.taper,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 3, maxKm: 5),
        RaceDistance.tenK: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.halfMarathon: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.marathon: DistanceRange(minKm: 3, maxKm: 8),
      },
      recommendedPercentage: 0.08,
      description: 'Short easy jog to flush legs after hard sessions.',
      blocks: [
        BlockTemplate(
          type: BlockType.main,
          durationType: DurationType.fixedKm,
          value: 3.0,
          paceZone: PaceZone.shakeout,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'recovery_walk_jog',
      name: 'Walk/Jog',
      intent: WorkoutIntent.recovery,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
        TrainingPhase.taper,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 3, maxKm: 5),
        RaceDistance.tenK: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.halfMarathon: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.marathon: DistanceRange(minKm: 3, maxKm: 8),
      },
      recommendedPercentage: 0.08,
      description: 'Alternating walk and easy jog. For return from illness/injury or very high fatigue.',
      blocks: [
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.easyRecovery,
          reps: 6,
          recovery: BlockTemplate.recoveryMeters(meters: 200),
          label: 'Jog',
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'rest_day',
      name: 'Rest Day',
      intent: WorkoutIntent.recovery,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
        TrainingPhase.taper,
      },
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 0, maxKm: 0),
        RaceDistance.tenK: DistanceRange(minKm: 0, maxKm: 0),
        RaceDistance.halfMarathon: DistanceRange(minKm: 0, maxKm: 0),
        RaceDistance.marathon: DistanceRange(minKm: 0, maxKm: 0),
      },
      recommendedPercentage: 0.0,
      description: 'Full rest. No running. Recovery is training.',
      blocks: [],
    ),
  ];

  // ========================================================================
  // QUERY METHODS
  // ========================================================================

  static List<WorkoutTemplate> byIntent(WorkoutIntent intent) {
    return templates.where((t) => t.intent == intent).toList();
  }

  static List<WorkoutTemplate> forContext({
    required RaceDistance distance,
    required TrainingPhase phase,
  }) {
    return templates
        .where((t) =>
            t.applicableRaceDistances.contains(distance) &&
            t.applicablePhases.contains(phase))
        .toList();
  }

  static List<WorkoutTemplate> forSlot({
    required WorkoutIntent intent,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
  }) {
    return templates
        .where((t) =>
            t.intent == intent &&
            t.applicableRaceDistances.contains(raceDistance) &&
            t.applicablePhases.contains(phase))
        .toList();
  }

  static WorkoutTemplate? byId(String id) {
    try {
      return templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static PhaseVariant? getVariant(
      WorkoutTemplate template, TrainingPhase phase) {
    return template.phaseVariants[phase];
  }

  static Map<WorkoutIntent, int> get templateCountByIntent {
    final counts = <WorkoutIntent, int>{};
    for (final intent in WorkoutIntent.values) {
      counts[intent] = templates.where((t) => t.intent == intent).length;
    }
    return counts;
  }

  static Map<RaceDistance, int> get templateCountByDistance {
    final counts = <RaceDistance, int>{};
    for (final dist in RaceDistance.values) {
      counts[dist] =
          templates.where((t) => t.applicableRaceDistances.contains(dist)).length;
    }
    return counts;
  }
}