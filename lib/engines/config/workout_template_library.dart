/// Workout Template Library for Endura — Rebuild v3
///
/// Key changes from v2:
///   - Recovery is now seconds-based for all interval work (threshold, VO2, speed)
///     Meters-based recovery retained only for strides (distance is the stimulus)
///   - Threshold templates restructured into a proper ladder:
///       cruise_intervals_400  → intro threshold (8–12 × 400m, 60s)
///       cruise_intervals_800  → standard threshold (5–8 × 800m, 75s)
///       cruise_intervals_mile → advanced threshold (3–5 × 1600m, 60s)
///       tempo_continuous      → continuous tempo (build/peak only)
///       threshold_progression → progressive blocks (build/peak only)
///   - Goal pace intervals restructured to be genuinely different from cruise intervals:
///       race_gp_intervals now uses 2–4 × 2–3km blocks with longer recovery (race rehearsal)
///   - VO2 templates expanded:
///       vo2_600  added (6–8 × 600m — most common real-world VO2 prescription)
///       vo2_1000 added (5–6 × 1000m — Daniels I-pace classic)
///   - RecoveryType enum added to BlockTemplate (fixedSeconds | fixedMeters)
///   - DurationType.percentage blocks retain meters-based recovery where appropriate
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

enum RecoveryType {
  fixedSeconds,
  fixedMeters,
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

  // Recovery — one of these will be set, not both
  final int? recoverySeconds;
  final double? recoveryMeters;

  final String? label;

  const BlockTemplate({
    required this.type,
    required this.durationType,
    required this.value,
    required this.paceZone,
    this.reps,
    this.recoverySeconds,
    this.recoveryMeters,
    this.label,
  });

  // ── convenience constructors ──────────────────────────────────────────

  const BlockTemplate.main({
    required double km,
    required PaceZone zone,
    int? reps,
    int? recoverySeconds,
    double? recoveryMeters,
    String? label,
  }) : this(
          type: BlockType.main,
          durationType: DurationType.fixedKm,
          value: km,
          paceZone: zone,
          reps: reps,
          recoverySeconds: recoverySeconds,
          recoveryMeters: recoveryMeters,
          label: label,
        );

  const BlockTemplate.mainMeters({
    required double meters,
    required PaceZone zone,
    int? reps,
    int? recoverySeconds,
    double? recoveryMeters,
    String? label,
  }) : this(
          type: BlockType.main,
          durationType: DurationType.fixedKm,
          value: meters / 1000,
          paceZone: zone,
          reps: reps,
          recoverySeconds: recoverySeconds,
          recoveryMeters: recoveryMeters,
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
}

// ============================================================================
// PHASE VARIANT
// ============================================================================

class PhaseVariant {
  final int? reps;
  final double? repDistanceKm;
  final double? repDistanceMeters;
  final int? recoverySeconds;
  final double? recoveryMeters;
  final double volumeMultiplier;
  final String? note;

  const PhaseVariant({
    this.reps,
    this.repDistanceKm,
    this.repDistanceMeters,
    this.recoverySeconds,
    this.recoveryMeters,
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
// RESOLVED WORKOUT
// ============================================================================

class ResolvedBlock {
  final BlockType type;
  final double distanceKm;
  final int paceMinSecondsPerKm;
  final int paceMaxSecondsPerKm;
  final bool isRpeOnly;
  final int? reps;

  // Recovery — rendered differently on run screen
  final int? recoverySeconds;
  final double? recoveryMeters;

  final String? label;

  const ResolvedBlock({
    required this.type,
    required this.distanceKm,
    required this.paceMinSecondsPerKm,
    required this.paceMaxSecondsPerKm,
    this.isRpeOnly = false,
    this.reps,
    this.recoverySeconds,
    this.recoveryMeters,
    this.label,
  });

  int get targetPace =>
      ((paceMinSecondsPerKm + paceMaxSecondsPerKm) / 2).round();

  double get totalDistanceKm {
    final repCount = reps ?? 1;
    final workDist = distanceKm * repCount;
    // Recovery distance only counted when meters-based
    final recDist = (recoveryMeters != null)
        ? (recoveryMeters! / 1000) * (repCount > 1 ? repCount - 1 : 0)
        : 0.0;
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

  String get formattedRecovery {
    if (recoverySeconds != null) {
      final m = recoverySeconds! ~/ 60;
      final s = recoverySeconds! % 60;
      return m > 0
          ? '$m:${s.toString().padLeft(2, '0')} recovery'
          : '${recoverySeconds}s recovery';
    }
    if (recoveryMeters != null) {
      return '${recoveryMeters!.round()} m jog recovery';
    }
    return '';
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
      // Add seconds-based recovery to duration estimate
      if (block.recoverySeconds != null && repCount > 1) {
        totalSeconds += block.recoverySeconds! * (repCount - 1);
      }
      // Add meters-based recovery to duration estimate (assume easy jog ~7:00/km)
      if (block.recoveryMeters != null && repCount > 1) {
        totalSeconds +=
            (block.recoveryMeters! / 1000) * 420 * (repCount - 1);
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
// ============================================================================
// ============================================================================

class WorkoutLibrary {
  static const List<WorkoutTemplate> templates = [

    // ════════════════════════════════════════════════════════════════════════
    // AEROBIC BASE
    // ════════════════════════════════════════════════════════════════════════

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
      description:
          'Steady conversational pace. Build aerobic base and aid recovery.',
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
      description:
          'Start easy, finish at steady effort. Teaches pace awareness.',
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
      description:
          'Easy run with strides at the end for turnover and form work.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.85,
          zone: PaceZone.aerobicEasy,
        ),
        // Strides: distance is the stimulus — meters-based recovery is correct here
        BlockTemplate.mainMeters(
          meters: 100,
          zone: PaceZone.strides,
          reps: 4,
          recoveryMeters: 100,
          label: 'Stride',
        ),
      ],
      phaseVariants: {
        TrainingPhase.base: PhaseVariant(
          reps: 4,
          repDistanceMeters: 100,
          recoveryMeters: 100,
          note: 'Start with 4 strides',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 6,
          repDistanceMeters: 100,
          recoveryMeters: 100,
          note: 'Progress to 6 strides',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 8,
          repDistanceMeters: 100,
          recoveryMeters: 100,
          note: 'Maintain 8 strides',
        ),
      },
    ),

    // ════════════════════════════════════════════════════════════════════════
    // ENDURANCE (LONG RUNS)
    // ════════════════════════════════════════════════════════════════════════

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
      description: 'Steady-state long run. Primary aerobic endurance stimulus.',
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
      description:
          'Long run starting easy, finishing at steady. Teaches negative splitting.',
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
      description:
          'Long run with final 20–25% at race goal pace. Simulates race fatigue.',
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
          note: 'Goal pace block = 20–25% of long run',
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
      description:
          'Long run with sustained goal-pace block in the middle. Marathon-specific.',
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
      description:
          'Midweek longer easy effort. Bridges easy runs and the long run.',
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

    // ════════════════════════════════════════════════════════════════════════
    // THRESHOLD
    //
    // Ladder from introductory → advanced:
    //   cruise_intervals_400  (base intro — short reps, incomplete rest)
    //   cruise_intervals_800  (standard — Jack Daniels T-intervals)
    //   cruise_intervals_mile (advanced — longer sustained blocks)
    //   tempo_continuous      (build/peak — continuous threshold run)
    //   threshold_progression (build/peak — ascending intensity blocks)
    // ════════════════════════════════════════════════════════════════════════

    WorkoutTemplate(
      id: 'cruise_intervals_400',
      name: 'Cruise Intervals — 400m',
      intent: WorkoutIntent.threshold,
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
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.halfMarathon: DistanceRange(minKm: 7, maxKm: 11),
        RaceDistance.marathon: DistanceRange(minKm: 8, maxKm: 12),
      },
      recommendedPercentage: 0.18,
      description:
          'Short threshold reps with 60s recovery. Entry-level T-pace work. '
          'Accumulates threshold stimulus without sustained discomfort.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.cruiseIntervals,
          reps: 8,
          recoverySeconds: 60,
          label: 'T-rep',
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
          reps: 8,
          repDistanceMeters: 400,
          recoverySeconds: 60,
          note: 'Intro: 8 × 400m, 60s recovery',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 12,
          repDistanceMeters: 400,
          recoverySeconds: 60,
          note: 'Progress to 12 × 400m',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'cruise_intervals_800',
      name: 'Cruise Intervals — 800m',
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
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 16),
      },
      recommendedPercentage: 0.18,
      description:
          'Standard T-intervals. 75s recovery keeps stimulus incomplete — '
          'core of Jack Daniels\' threshold prescription.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 800,
          zone: PaceZone.cruiseIntervals,
          reps: 5,
          recoverySeconds: 75,
          label: 'T-rep',
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
          reps: 4,
          repDistanceMeters: 800,
          recoverySeconds: 90,
          note: 'Intro: 4 × 800m, 90s recovery',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 5,
          repDistanceMeters: 800,
          recoverySeconds: 75,
          note: 'Standard: 5 × 800m, 75s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 6,
          repDistanceMeters: 800,
          recoverySeconds: 60,
          note: 'Peak: 6 × 800m, 60s recovery (tighter rest)',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'cruise_intervals_mile',
      name: 'Cruise Intervals — Mile',
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
      description:
          'Longer T-reps (1600m) with 60s recovery. Advanced threshold — '
          'approaches continuous tempo in total stress.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 1600,
          zone: PaceZone.cruiseIntervals,
          reps: 3,
          recoverySeconds: 60,
          label: 'T-rep',
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
          repDistanceMeters: 1600,
          recoverySeconds: 60,
          note: '3 × 1600m, 60s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 4,
          repDistanceMeters: 1600,
          recoverySeconds: 60,
          note: '4 × 1600m, 60s recovery',
        ),
      },
    ),

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
      description:
          'Continuous run at threshold pace. No breaks. '
          'Builds lactate clearance and mental toughness at T-pace.',
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
      description:
          'Three ascending blocks with short jog recoveries. '
          'Each block faster than the last — teaches threshold management.',
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
        BlockTemplate.recoveryJog(km: 0.4),
        BlockTemplate.main(
          km: 2.0,
          zone: PaceZone.tempo,
          label: 'Block 2 — Threshold',
        ),
        BlockTemplate.recoveryJog(km: 0.4),
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

    // ════════════════════════════════════════════════════════════════════════
    // VO₂MAX
    //
    // Ladder from accessible → demanding:
    //   vo2_600        (600m — most common real-world prescription)
    //   vo2_classic    (800m–1000m — Daniels I-pace standard)
    //   vo2_1000       (1000m — longer I-pace reps)
    //   vo2_short_short (200m alternating — high VO2 time, lower strain)
    //   vo2_ladder     (ascending 200→1000m)
    //   vo2_pyramid    (peak-phase only — full pyramid)
    // ════════════════════════════════════════════════════════════════════════

    WorkoutTemplate(
      id: 'vo2_600',
      name: 'VO₂ Intervals — 600m',
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
      description:
          '600m reps at I-pace with ~3 min recovery. '
          'Most accessible VO₂ session — high quality time without blowing up.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 600,
          zone: PaceZone.vo2Intervals,
          reps: 6,
          recoverySeconds: 180,
          label: 'I-rep',
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
          reps: 6,
          repDistanceMeters: 600,
          recoverySeconds: 180,
          note: '6 × 600m, 3 min recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 8,
          repDistanceMeters: 600,
          recoverySeconds: 180,
          note: '8 × 600m, 3 min recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_classic',
      name: 'VO₂ Intervals — 800m',
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
      description:
          'Classic 800m I-pace intervals. ~3–4 min recovery ensures '
          'quality is maintained every rep.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 800,
          zone: PaceZone.vo2Intervals,
          reps: 5,
          recoverySeconds: 210,
          label: 'I-rep',
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
          repDistanceMeters: 800,
          recoverySeconds: 240,
          note: '4 × 800m, 4 min recovery — build into VO₂',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 5,
          repDistanceMeters: 800,
          recoverySeconds: 210,
          note: '5 × 800m, 3:30 recovery — full VO₂ dose',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_1000',
      name: 'VO₂ Intervals — 1000m',
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
      description:
          '1000m I-pace reps — longer sustained effort at VO₂max intensity. '
          'Demands more mental control than 800s.',
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
          recoverySeconds: 240,
          label: 'I-rep',
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
          repDistanceKm: 1.0,
          recoverySeconds: 270,
          note: '4 × 1000m, 4:30 recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 5,
          repDistanceKm: 1.0,
          recoverySeconds: 240,
          note: '5 × 1000m, 4 min recovery',
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
      description:
          'Alternating 200m fast / 200m float. High VO₂ time in legs with '
          'less perceived strain than longer reps.',
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
          // Float 200m recovery — meters is appropriate here (it's a running float)
          recoveryMeters: 200,
          label: 'Fast',
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
          recoveryMeters: 200,
          note: '10 × 200m/200m float',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 14,
          repDistanceMeters: 200,
          recoveryMeters: 200,
          note: '14 × 200m/200m float',
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
      description:
          'Ascending ladder: 400–600–800–1000m. Recovery scales with rep distance.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.ladderPyramid,
          recoverySeconds: 120,
          label: '400m',
        ),
        BlockTemplate.mainMeters(
          meters: 600,
          zone: PaceZone.ladderPyramid,
          recoverySeconds: 150,
          label: '600m',
        ),
        BlockTemplate.mainMeters(
          meters: 800,
          zone: PaceZone.ladderPyramid,
          recoverySeconds: 180,
          label: '800m',
        ),
        BlockTemplate.mainMeters(
          meters: 1000,
          zone: PaceZone.ladderPyramid,
          recoverySeconds: 240,
          label: '1000m',
        ),
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
      description:
          'Full pyramid: 400–600–800–600–400m. Peak-phase variety session.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.ladderPyramid,
          recoverySeconds: 120,
          label: '400m',
        ),
        BlockTemplate.mainMeters(
          meters: 600,
          zone: PaceZone.ladderPyramid,
          recoverySeconds: 150,
          label: '600m',
        ),
        BlockTemplate.mainMeters(
          meters: 800,
          zone: PaceZone.vo2Intervals,
          recoverySeconds: 210,
          label: '800m',
        ),
        BlockTemplate.mainMeters(
          meters: 600,
          zone: PaceZone.ladderPyramid,
          recoverySeconds: 150,
          label: '600m',
        ),
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.ladderPyramid,
          recoverySeconds: 120,
          label: '400m',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    // ════════════════════════════════════════════════════════════════════════
    // SPEED / NEUROMUSCULAR
    // ════════════════════════════════════════════════════════════════════════

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
      description:
          'Short max-effort hill reps. Full recovery between each. '
          'Builds power and running economy — not a fitness session.',
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
          recoverySeconds: 120,
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
          recoverySeconds: 120,
          note: 'Start with 6 hills, full 2 min recovery',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 10,
          repDistanceMeters: 80,
          recoverySeconds: 120,
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
      description:
          'Short fast reps for leg speed and turnover. '
          'Full recovery — quality over quantity.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 200,
          zone: PaceZone.speedReps,
          reps: 6,
          recoverySeconds: 120,
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
          recoverySeconds: 120,
          note: '5 × 200m, 2 min recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 6,
          repDistanceMeters: 400,
          recoverySeconds: 150,
          note: '6 × 400m, 2:30 recovery',
        ),
      },
    ),

    // ════════════════════════════════════════════════════════════════════════
    // RACE SPECIFIC
    //
    // race_gp_intervals: long sustained blocks at goal pace (2–3km each)
    //                    genuinely different from cruise_intervals in both
    //                    zone and structure — race rehearsal, not T-work
    // race_simulation:   extended race-pace effort, peak only
    // race_dress_rehearsal: taper confidence builder
    // ════════════════════════════════════════════════════════════════════════

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
      description:
          'Long sustained blocks at goal race pace with generous recovery. '
          'Purpose is rhythm and race feel — not lactate stress. '
          'Structurally distinct from cruise intervals: longer reps, longer rest.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.main(
          km: 2.0,
          zone: PaceZone.goalPace,
          reps: 3,
          recoverySeconds: 180,
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
          repDistanceKm: 2.0,
          recoverySeconds: 180,
          note: '3 × 2km @ goal pace, 3 min recovery — finding the rhythm',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 3,
          repDistanceKm: 3.0,
          recoverySeconds: 180,
          note: '3 × 3km @ goal pace, 3 min recovery — race simulation',
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
      description:
          'Extended continuous race-pace effort. Mental and physical dress rehearsal.',
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
      description:
          'Short race-pace effort in taper week. Low volume, confidence-building.',
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

    // ════════════════════════════════════════════════════════════════════════
    // RECOVERY
    // ════════════════════════════════════════════════════════════════════════

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
      description:
          'Alternating jog and walk. For return from illness/injury or very high fatigue.',
      blocks: [
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.easyRecovery,
          reps: 6,
          // Walk recovery — meters is correct here
          recoveryMeters: 200,
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

  // ════════════════════════════════════════════════════════════════════════
  // QUERY METHODS
  // ════════════════════════════════════════════════════════════════════════

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
      counts[dist] = templates
          .where((t) => t.applicableRaceDistances.contains(dist))
          .length;
    }
    return counts;
  }
}