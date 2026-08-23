/// Workout Template Library for Endura — Rebuild v6
///
/// Changes from v5:
///   - long_progression : extended to TrainingPhase.base — base pool now has
///                        3 long-run templates (steady, progression, strides).
///   - long_strides     : Easy long run with neuromuscular strides at finish.
///                        Applicable: base/build/peak, all distances.
///   - long_fartlek     : Easy long run with 5–6 × 2min @tempo fartlek bursts.
///                        Applicable: build/peak, 5K/10K/HM only.
///   - WeekResolver     : WorkoutIntent.endurance ladder added, cycling all
///                        long-run templates by phase/distance context.
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
}

enum RaceDistance { fiveK, tenK, halfMarathon, marathon }

enum BlockType { warmup, main, recovery, cooldown }

enum DurationType { fixedKm, fixedSeconds, percentage }

enum RecoveryType { fixedSeconds, fixedMeters }

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

  /// km when fixedKm or percentage; seconds when fixedSeconds.
  final double value;

  final PaceZone paceZone;
  final int? reps;
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

  const BlockTemplate.mainSeconds({
    required double seconds,
    required PaceZone zone,
    int? reps,
    int? recoverySeconds,
    String? label,
  }) : this(
         type: BlockType.main,
         durationType: DurationType.fixedSeconds,
         value: seconds,
         paceZone: zone,
         reps: reps,
         recoverySeconds: recoverySeconds,
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

  const BlockTemplate.recoveryJog({required double km})
    : this(
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
  final double? repDurationSeconds;
  final int? recoverySeconds;
  final double? recoveryMeters;
  final double volumeMultiplier;
  final String? note;

  const PhaseVariant({
    this.reps,
    this.repDistanceKm,
    this.repDistanceMeters,
    this.repDurationSeconds,
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
  final List<BlockTemplate> blocks;
  final Map<TrainingPhase, PhaseVariant> phaseVariants;
  final String description;
  final bool supportsScaling;

  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.intent,
    required this.applicablePhases,
    required this.applicableRaceDistances,
    required this.distanceByRace,
    required this.blocks,
    this.phaseVariants = const {},
    this.description = '',
    this.supportsScaling = true,
  });
}

// ============================================================================
// RESOLVED BLOCK
// ============================================================================

class ResolvedBlock {
  final BlockType type;
  final double distanceKm;

  /// Only set for fixedSeconds blocks (hill sprints / hill repeats).
  /// Null for all distance-based blocks.
  final int? durationSeconds;

  final int paceMinSecondsPerKm;
  final int paceMaxSecondsPerKm;
  final bool isRpeOnly;
  final int? reps;
  final int? recoverySeconds;
  final double? recoveryMeters;
  final String? label;

  const ResolvedBlock({
    required this.type,
    required this.distanceKm,
    required this.paceMinSecondsPerKm,
    required this.paceMaxSecondsPerKm,
    this.durationSeconds,
    this.isRpeOnly = false,
    this.reps,
    this.recoverySeconds,
    this.recoveryMeters,
    this.label,
  });

  int get targetPace =>
      ((paceMinSecondsPerKm + paceMaxSecondsPerKm) / 2).round();

  /// Recovery distance is never counted.
  /// Total = work interval distance × reps only.
  double get totalDistanceKm => distanceKm * (reps ?? 1);

  String get formattedPace {
    if (isRpeOnly) return 'RPE effort';
    return '${_fmt(paceMinSecondsPerKm)}–${_fmt(paceMaxSecondsPerKm)}/km';
  }

  String formattedPaceForIntent(WorkoutIntent intent) {
    if (isRpeOnly) return 'RPE effort';
    final isEasy =
        (intent == WorkoutIntent.aerobicBase ||
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
    if (durationSeconds != null) {
      return '${durationSeconds}s';
    }
    if (distanceKm >= 1.0) return '${distanceKm.toStringAsFixed(1)} km';
    return '${(distanceKm * 1000).round()} m';
  }

  /// Always shows plain seconds — 60s, 90s, 120s, 180s etc.
  /// recoveryMeters converted at 6:00/km (360 s/km).
  String get formattedRecovery {
    final totalSeconds =
        recoverySeconds ??
        (recoveryMeters != null
            ? ((recoveryMeters! / 1000) * 360).round()
            : null);
    if (totalSeconds == null) return '';
    return '${totalSeconds}s recovery';
  }

  static String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// RESOLVED WORKOUT
// ============================================================================

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
      if (block.durationSeconds != null) {
        totalSeconds += block.durationSeconds! * repCount;
      } else {
        totalSeconds += block.distanceKm * block.targetPace * repCount;
      }
      // Recovery as time only — recoveryMeters never counted for duration.
      if (block.recoverySeconds != null && repCount > 1) {
        totalSeconds += block.recoverySeconds! * (repCount - 1);
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
// WORKOUT LIBRARY
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
        RaceDistance.tenK: DistanceRange(minKm: 4, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 5, maxKm: 12),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 14),
      },
      description:
          'Conversational pace. Builds aerobic base and aids recovery.',
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
      applicablePhases: {TrainingPhase.base, TrainingPhase.build},
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.tenK: DistanceRange(minKm: 4, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 5, maxKm: 12),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 14),
      },
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
        RaceDistance.tenK: DistanceRange(minKm: 4, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 5, maxKm: 12),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 14),
      },
      description:
          'Easy run with strides at the end for turnover and form work.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.85,
          zone: PaceZone.aerobicEasy,
        ),
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
        TrainingPhase.taper: PhaseVariant(
          reps: 4,
          repDistanceMeters: 100,
          recoveryMeters: 100,
          note: 'Light strides — stay sharp before race',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'easy_aerobic',
      name: 'Aerobic Run',
      intent: WorkoutIntent.aerobicBase,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 14),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 16),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      description:
          'Upper end of easy — M-pace effort. Honest aerobic work, not junk miles. '
          'Third easy-day variant in HM/FM weeks and high-volume 10K plans.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 1.0,
          zone: PaceZone.marathonPace,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'easy_hilly',
      name: 'Hilly Easy Run',
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
        RaceDistance.tenK: DistanceRange(minKm: 4, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 5, maxKm: 12),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 14),
      },
      description:
          'Easy run on rolling or hilly terrain. Effort stays easy — '
          'let pace drift slower on the climbs, strength work is the bonus.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 1.0,
          zone: PaceZone.aerobicEasy,
        ),
      ],
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
        RaceDistance.fiveK: DistanceRange(minKm: 6, maxKm: 16),
        RaceDistance.tenK: DistanceRange(minKm: 8, maxKm: 20),
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 28),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 35),
      },
      description:
          'Steady-state long run at easy pace. Primary aerobic endurance stimulus.',
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
        RaceDistance.fiveK: DistanceRange(minKm: 6, maxKm: 16),
        RaceDistance.tenK: DistanceRange(minKm: 8, maxKm: 20),
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 28),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 35),
      },
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
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 6, maxKm: 16),
        RaceDistance.tenK: DistanceRange(minKm: 8, maxKm: 20),
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 28),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 35),
      },
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
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {RaceDistance.marathon},
      distanceByRace: {
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 35),
      },
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
      id: 'long_cutdown',
      name: 'Long Run — Cutdown',
      intent: WorkoutIntent.endurance,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 28),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 35),
      },
      description:
          '3-segment cutdown: easy → marathon pace → comfortably hard. '
          'Each third gets progressively faster. Harder than long_progression — '
          'final block pushes past M-pace, teaching runners to move on tired legs.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.40,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.35,
          zone: PaceZone.marathonPace,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.25,
          zone: PaceZone.progressiveEnd,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          volumeMultiplier: 1.0,
          note: 'Cutdown — each third faster than the last',
        ),
        TrainingPhase.peak: PhaseVariant(
          volumeMultiplier: 1.05,
          note: 'Peak cutdown — push the final block',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'long_surges',
      name: 'Long Run — Surges',
      intent: WorkoutIntent.endurance,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 28),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 35),
      },
      description:
          'Easy long run with 5 × 1-minute surges at HM effort scattered through '
          'the middle miles. Low perceived cost, high neuromuscular return. '
          'Teaches gear changes on tired legs without blowing up the session.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.warmup,
          fraction: 0.30,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainSeconds(
          seconds: 60,
          zone: PaceZone.progressiveEnd,
          reps: 5,
          recoverySeconds: 120,
          label: 'Surge',
        ),
        BlockTemplate.percent(
          type: BlockType.cooldown,
          fraction: 0.70,
          zone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          reps: 5,
          repDurationSeconds: 60,
          recoverySeconds: 120,
          note: '5 × 1min surges, 2min float recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 7,
          repDurationSeconds: 60,
          recoverySeconds: 90,
          note: '7 × 1min surges, 90s float recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'long_strides',
      name: 'Long Run — Strides',
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
        RaceDistance.fiveK: DistanceRange(minKm: 6, maxKm: 16),
        RaceDistance.tenK: DistanceRange(minKm: 8, maxKm: 20),
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 28),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 35),
      },
      description:
          'Easy long run with neuromuscular strides at the finish. '
          'Low cost, high turnover return — appropriate from base phase onward.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.85,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 100,
          zone: PaceZone.strides,
          reps: 6,
          recoveryMeters: 100,
          label: 'Stride',
        ),
      ],
      phaseVariants: {
        TrainingPhase.base: PhaseVariant(
          reps: 4,
          repDistanceMeters: 100,
          recoveryMeters: 100,
          note: '4 × 100m strides to finish the long run',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 6,
          repDistanceMeters: 100,
          recoveryMeters: 100,
          note: '6 × 100m strides to finish the long run',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 6,
          repDistanceMeters: 100,
          recoveryMeters: 100,
          note: '6 × 100m strides to finish the long run',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'long_fartlek',
      name: 'Long Run — Fartlek',
      intent: WorkoutIntent.endurance,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 6, maxKm: 16),
        RaceDistance.tenK: DistanceRange(minKm: 8, maxKm: 20),
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 28),
      },
      description:
          'Easy long run with tempo fartlek bursts through the middle miles. '
          '5K/10K/HM — teaches gear changes at threshold without trashing the session.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.warmup,
          fraction: 0.25,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainSeconds(
          seconds: 120,
          zone: PaceZone.tempo,
          reps: 5,
          recoverySeconds: 120,
          label: 'Fartlek',
        ),
        BlockTemplate.percent(
          type: BlockType.cooldown,
          fraction: 0.75,
          zone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.build: PhaseVariant(
          reps: 5,
          repDurationSeconds: 120,
          recoverySeconds: 120,
          note: '5 × 2min @tempo, 2min float recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 6,
          repDurationSeconds: 120,
          recoverySeconds: 90,
          note: '6 × 2min @tempo, 90s float recovery',
        ),
      },
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
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      description:
          'Midweek longer easy effort (HM/marathon only). Bridges easy runs and long run.',
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

    WorkoutTemplate(
      id: 'long_hilly',
      name: 'Long Run — Hilly',
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
        RaceDistance.fiveK: DistanceRange(minKm: 6, maxKm: 16),
        RaceDistance.tenK: DistanceRange(minKm: 8, maxKm: 20),
        RaceDistance.halfMarathon: DistanceRange(minKm: 12, maxKm: 28),
        RaceDistance.marathon: DistanceRange(minKm: 16, maxKm: 35),
      },
      description:
          'Long run on hilly terrain at the same easy effort as a standard long run. '
          'Expect a slower average pace — the climbs are the extra strength stimulus.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 1.0,
          zone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    // ════════════════════════════════════════════════════════════════════════
    // THRESHOLD
    // ════════════════════════════════════════════════════════════════════════
    WorkoutTemplate(
      id: 'cruise_intervals_400',
      name: 'Cruise Intervals — 400m',
      intent: WorkoutIntent.threshold,
      applicablePhases: {TrainingPhase.base, TrainingPhase.build},
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
      description:
          'Short threshold reps with 60s recovery. Entry-level T-pace work.',
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
      description:
          "Standard T-intervals. 75s recovery keeps stimulus incomplete — core of Jack Daniels' threshold prescription.",
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
          note: 'Peak: 6 × 800m, 60s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'cruise_intervals_mile',
      name: 'Cruise Intervals — Mile',
      intent: WorkoutIntent.threshold,
      applicablePhases: {
        TrainingPhase.base,
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
      description:
          'Longer T-reps (1600m) with 60s recovery. Advanced threshold.',
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
        TrainingPhase.base: PhaseVariant(
          reps: 2,
          repDistanceMeters: 1600,
          recoverySeconds: 90,
          note: 'Base intro: 2 × 1600m, 90s recovery',
        ),
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
      id: 'cruise_intervals_2000',
      name: 'Cruise Intervals — 2km',
      intent: WorkoutIntent.threshold,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      description:
          'Longer T-reps (2km) with short recovery — a step beyond mile '
          'repeats, closer to continuous tempo. For HM/marathon runners '
          'advancing past cruise_intervals_mile.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 2000,
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
          reps: 2,
          repDistanceMeters: 2000,
          recoverySeconds: 75,
          note: '2 × 2km, 75s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 3,
          repDistanceMeters: 2000,
          recoverySeconds: 60,
          note: '3 × 2km, 60s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'cruise_intervals_taper',
      name: 'Taper Sharpener — Cruise Intervals',
      intent: WorkoutIntent.threshold,
      applicablePhases: {TrainingPhase.taper},
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
      description:
          'Short cruise intervals to stay sharp in taper without adding '
          'fatigue. Broken format with generous recovery — lower risk than a '
          'sustained tempo, confidence work rather than conditioning.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 1000,
          zone: PaceZone.cruiseIntervals,
          reps: 3,
          recoverySeconds: 120,
          label: 'T-rep',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.0,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'tempo_continuous',
      name: 'Tempo Run',
      intent: WorkoutIntent.threshold,
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
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 14),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      description: 'Continuous run at threshold pace. No breaks.',
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
        TrainingPhase.base: PhaseVariant(
          volumeMultiplier: 0.75,
          note: 'Introductory continuous tempo — base phase',
        ),
        TrainingPhase.build: PhaseVariant(
          volumeMultiplier: 0.90,
          note: 'Moderate tempo volume in build',
        ),
        TrainingPhase.peak: PhaseVariant(
          volumeMultiplier: 1.0,
          note: 'Full tempo volume at peak',
        ),
        TrainingPhase.taper: PhaseVariant(
          volumeMultiplier: 0.65,
          note: 'Short taper tempo — sharpening only',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'threshold_progression',
      name: 'Threshold Progression',
      intent: WorkoutIntent.threshold,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
      description: 'Three ascending blocks with short jog recoveries.',
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

    WorkoutTemplate(
      id: 'steady_state',
      name: 'Steady State Run',
      intent: WorkoutIntent.threshold,
      applicablePhases: {
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
      },
      applicableRaceDistances: {
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 16),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 20),
      },
      description:
          'Continuous sustained run between easy and threshold — M-pace effort. '
          'The whole run is the stimulus. Replaces junk miles with meaningful aerobic work.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.warmup,
          fraction: 0.10,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.80,
          zone: PaceZone.steadyState,
        ),
        BlockTemplate.percent(
          type: BlockType.cooldown,
          fraction: 0.10,
          zone: PaceZone.aerobicEasy,
        ),
      ],
      phaseVariants: {
        TrainingPhase.base: PhaseVariant(
          volumeMultiplier: 0.85,
          note: 'Intro steady state — keep it honest, not hard',
        ),
        TrainingPhase.build: PhaseVariant(
          volumeMultiplier: 1.0,
          note: 'Standard steady state — sustained M-pace',
        ),
        TrainingPhase.peak: PhaseVariant(
          volumeMultiplier: 1.10,
          note: 'Peak steady state — longest of the plan',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'tempo_intervals',
      name: 'Broken Tempo',
      intent: WorkoutIntent.threshold,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
      description:
          'Tempo effort split into two blocks with a short jog recovery. '
          'Same time at threshold as a continuous tempo — easier to hold pace on tired legs.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.main(
          km: 2.5,
          zone: PaceZone.tempo,
          reps: 2,
          recoverySeconds: 150,
          label: 'Tempo Block',
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
          reps: 2,
          repDistanceKm: 2.5,
          recoverySeconds: 150,
          note: '2 × 2.5km @ tempo, 150s jog recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 2,
          repDistanceKm: 3.0,
          recoverySeconds: 120,
          note: '2 × 3km @ tempo, 120s jog recovery',
        ),
      },
    ),

    // ════════════════════════════════════════════════════════════════════════
    // VO₂MAX
    // ════════════════════════════════════════════════════════════════════════
    WorkoutTemplate(
      id: 'vo2_600',
      name: 'VO₂ Intervals — 600m',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
      description: '600m reps at I-pace with ~3 min recovery.',
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
          note: '6 × 600m, 180s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 8,
          repDistanceMeters: 600,
          recoverySeconds: 180,
          note: '8 × 600m, 180s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_classic',
      name: 'VO₂ Intervals — 800m',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
      description: 'Classic 800m I-pace intervals. ~3–4 min recovery.',
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
          note: '4 × 800m, 240s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 5,
          repDistanceMeters: 800,
          recoverySeconds: 210,
          note: '5 × 800m, 210s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_1000',
      name: 'VO₂ Intervals — 1000m',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
      description: '1000m I-pace reps — longer sustained VO₂max effort.',
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
          note: '4 × 1000m, 270s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 5,
          repDistanceKm: 1.0,
          recoverySeconds: 240,
          note: '5 × 1000m, 240s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_1200',
      name: 'VO₂ Intervals — 1200m',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {RaceDistance.tenK, RaceDistance.halfMarathon},
      distanceByRace: {
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 7, maxKm: 13),
      },
      description:
          '1200m reps at 10K pace. Fills the ladder gap between 1000m and mile repeats.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 1200,
          zone: PaceZone.tenKPace,
          reps: 4,
          recoverySeconds: 180,
          label: '10K rep',
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
          repDistanceMeters: 1200,
          recoverySeconds: 180,
          note: '4 × 1200m @ 10K pace, 180s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 5,
          repDistanceMeters: 1200,
          recoverySeconds: 180,
          note: '5 × 1200m @ 10K pace, 180s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_mixed',
      name: 'Mixed Intervals',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
      description:
          'Varying rep lengths at the same I-pace — 1000m, then 2×600m, then '
          '2×400m. Intensity stays constant; only the distance changes, '
          'breaking up the monotony of same-length reps.',
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
          recoverySeconds: 240,
          label: '1000m',
        ),
        BlockTemplate.mainMeters(
          meters: 600,
          zone: PaceZone.vo2Intervals,
          reps: 2,
          recoverySeconds: 150,
          label: '600m',
        ),
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.vo2Intervals,
          reps: 2,
          recoverySeconds: 90,
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

    WorkoutTemplate(
      id: 'vo2_short_short',
      name: 'Short-Short Intervals',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {RaceDistance.fiveK, RaceDistance.tenK},
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
      },
      description:
          'Alternating 200m fast / 200m float. High VO₂ time with less strain than longer reps.',
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
      supportsScaling: false,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 10),
        RaceDistance.tenK: DistanceRange(minKm: 5, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 6, maxKm: 13),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 14),
      },
      description: 'Ascending ladder — structure and length scale with budget.',
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
      supportsScaling: false,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.fiveK,
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 10),
        RaceDistance.tenK: DistanceRange(minKm: 5, maxKm: 12),
        RaceDistance.halfMarathon: DistanceRange(minKm: 6, maxKm: 13),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 14),
      },
      description:
          'Pyramid up and back — structure and length scale with budget.',
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

    WorkoutTemplate(
      id: 'vo2_400',
      name: 'VO₂ Intervals — 400m',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
      description:
          'Classic 400m reps at I-pace with short recovery. High rep count for VO₂max stimulus.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.vo2Intervals,
          reps: 10,
          recoverySeconds: 90,
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
          reps: 8,
          repDistanceMeters: 400,
          recoverySeconds: 90,
          note: '8 × 400m, 90s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 12,
          repDistanceMeters: 400,
          recoverySeconds: 75,
          note: '12 × 400m, 75s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'vo2_thirty_thirty',
      name: '30/30 Intervals',
      intent: WorkoutIntent.vo2max,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {RaceDistance.fiveK, RaceDistance.tenK},
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
      },
      description:
          '30 seconds hard / 30 seconds easy float, repeated. Classic VO₂max '
          'session — minimal joint stress, high time-at-VO₂max.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainSeconds(
          seconds: 30,
          zone: PaceZone.vo2Intervals,
          reps: 16,
          recoverySeconds: 30,
          label: 'Hard',
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
          reps: 12,
          repDurationSeconds: 30,
          recoverySeconds: 30,
          note: '12 × 30s hard/30s float',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 18,
          repDurationSeconds: 30,
          recoverySeconds: 30,
          note: '18 × 30s hard/30s float',
        ),
      },
    ),

    // ════════════════════════════════════════════════════════════════════════
    // SPEED / NEUROMUSCULAR
    // ════════════════════════════════════════════════════════════════════════
    WorkoutTemplate(
      id: 'speed_hills',
      name: 'Hill Sprints',
      intent: WorkoutIntent.speed,
      applicablePhases: {TrainingPhase.base, TrainingPhase.build},
      applicableRaceDistances: {RaceDistance.fiveK, RaceDistance.tenK},
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 4, maxKm: 7),
        RaceDistance.tenK: DistanceRange(minKm: 5, maxKm: 8),
      },
      description:
          '8–12s max-effort hill reps. Builds power and running economy.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainSeconds(
          seconds: 10,
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
          repDurationSeconds: 10,
          recoverySeconds: 120,
          note: '6 × 10s hill sprints, 120s recovery',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 10,
          repDurationSeconds: 10,
          recoverySeconds: 120,
          note: '10 × 10s hill sprints, 120s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'hill_repeats',
      name: 'Hill Repeats',
      intent: WorkoutIntent.speed,
      applicablePhases: {TrainingPhase.base, TrainingPhase.build},
      applicableRaceDistances: {RaceDistance.fiveK, RaceDistance.tenK},
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 5, maxKm: 9),
      },
      description:
          '30–90s uphill reps at controlled hard effort. Full jog-down recovery. '
          'Builds strength endurance. Distinct from hill sprints — longer, controlled, not all-out.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainSeconds(
          seconds: 45,
          zone: PaceZone.hillRepeats,
          reps: 8,
          recoverySeconds: 90,
          label: 'Hill Rep',
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
          repDurationSeconds: 45,
          recoverySeconds: 90,
          note: '6 × 45s uphill, 90s recovery',
        ),
        TrainingPhase.build: PhaseVariant(
          reps: 10,
          repDurationSeconds: 60,
          recoverySeconds: 90,
          note: '10 × 60s uphill, 90s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'speed_reps',
      name: 'Speed Reps',
      intent: WorkoutIntent.speed,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
      description:
          'Short fast reps for leg speed and turnover. Full recovery — quality over quantity.',
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
          note: '5 × 200m, 120s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 6,
          repDistanceMeters: 400,
          recoverySeconds: 150,
          note: '6 × 400m, 150s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'speed_reps_intro',
      name: 'Speed Reps — Intro',
      intent: WorkoutIntent.speed,
      applicablePhases: {TrainingPhase.base},
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
      description:
          'Short, controlled fast reps to introduce leg speed in base phase, '
          'ahead of the harder quality work in build.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 150,
          zone: PaceZone.speedReps,
          reps: 5,
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
    ),

    WorkoutTemplate(
      id: 'speed_hills_endurance',
      name: 'Hill Sprints — Endurance Runners',
      intent: WorkoutIntent.speed,
      // Base only: secondaryQuality never resolves to `speed` for HM/marathon
      // in build (see week_resolver._secondaryQualityIntent) — those distances
      // keep vo2max/threshold as their build secondary quality instead.
      applicablePhases: {TrainingPhase.base},
      applicableRaceDistances: {
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.halfMarathon: DistanceRange(minKm: 5, maxKm: 9),
        RaceDistance.marathon: DistanceRange(minKm: 6, maxKm: 10),
      },
      description:
          'Short max-effort hill sprints for HM/marathon runners. Builds power '
          'and running economy without the impact cost of dedicated speed work.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainSeconds(
          seconds: 10,
          zone: PaceZone.hillSprints,
          reps: 5,
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
    ),

    WorkoutTemplate(
      id: 'speed_flying_sprints',
      name: 'Flying Sprints',
      intent: WorkoutIntent.speed,
      // Base, not peak: peak's secondaryQuality always resolves to
      // raceSpecific (see week_resolver._secondaryQualityIntent), so `speed`
      // is never requested in peak. Base is where 5K/10K R-pace work lives.
      applicablePhases: {TrainingPhase.base},
      applicableRaceDistances: {RaceDistance.fiveK, RaceDistance.tenK},
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 4, maxKm: 7),
        RaceDistance.tenK: DistanceRange(minKm: 5, maxKm: 8),
      },
      description:
          '30m acceleration into a 20m flying sprint at max controlled speed. '
          'Full recovery — pure neuromuscular power, not conditioning.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.mainMeters(
          meters: 50,
          zone: PaceZone.speedReps,
          reps: 6,
          recoverySeconds: 150,
          label: 'Flying Sprint',
        ),
        BlockTemplate(
          type: BlockType.cooldown,
          durationType: DurationType.fixedKm,
          value: 1.5,
          paceZone: PaceZone.aerobicEasy,
        ),
      ],
    ),

    // speed_strides_taper removed — duplicated easy_strides' existing
    // TrainingPhase.taper phaseVariant ("Light strides — stay sharp before
    // race"), and taper has no secondary-quality slot to place it in anyway
    // (WeekResolver drops Q2 to easy for every taper week).

    // ════════════════════════════════════════════════════════════════════════
    // RACE SPECIFIC
    // ════════════════════════════════════════════════════════════════════════
    WorkoutTemplate(
      id: 'race_gp_intervals',
      name: 'Goal Pace Intervals',
      intent: WorkoutIntent.raceSpecific,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 16),
      },
      description:
          'Sustained blocks at goal race pace. Purpose is rhythm and race feel.',
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
          note: '3 × 2km @ goal pace, 180s recovery',
        ),
        TrainingPhase.peak: PhaseVariant(
          reps: 3,
          repDistanceKm: 3.0,
          recoverySeconds: 180,
          note: '3 × 3km @ goal pace, 180s recovery',
        ),
      },
    ),

    WorkoutTemplate(
      id: 'race_simulation',
      name: 'Race Simulation',
      intent: WorkoutIntent.raceSpecific,
      supportsScaling: false,
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
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
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
      supportsScaling: false,
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
        RaceDistance.halfMarathon: DistanceRange(minKm: 6, maxKm: 10),
        RaceDistance.marathon: DistanceRange(minKm: 8, maxKm: 12),
      },
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

    WorkoutTemplate(
      id: 'race_negative_split',
      name: 'Negative Split Run',
      intent: WorkoutIntent.raceSpecific,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
      applicableRaceDistances: {
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      },
      distanceByRace: {
        RaceDistance.halfMarathon: DistanceRange(minKm: 8, maxKm: 16),
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 18),
      },
      description:
          'First half at easy/steady effort, second half at goal pace. '
          'Trains the discipline to hold back early and finish strong.',
      blocks: [
        BlockTemplate.percent(
          type: BlockType.warmup,
          fraction: 0.10,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.45,
          zone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.percent(
          type: BlockType.main,
          fraction: 0.45,
          zone: PaceZone.goalPace,
        ),
      ],
    ),

    WorkoutTemplate(
      id: 'race_pace_progression',
      name: 'Goal Pace Progression',
      intent: WorkoutIntent.raceSpecific,
      applicablePhases: {TrainingPhase.build, TrainingPhase.peak},
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
        RaceDistance.marathon: DistanceRange(minKm: 10, maxKm: 16),
      },
      description:
          'Three ascending blocks finishing at goal race pace. Builds '
          'confidence in closing fast on tired legs.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate.main(
          km: 1.5,
          zone: PaceZone.steadyState,
          label: 'Block 1 — Steady',
        ),
        BlockTemplate.recoveryJog(km: 0.3),
        BlockTemplate.main(
          km: 1.5,
          zone: PaceZone.tempo,
          label: 'Block 2 — Threshold',
        ),
        BlockTemplate.recoveryJog(km: 0.3),
        BlockTemplate.main(
          km: 1.5,
          zone: PaceZone.goalPace,
          label: 'Block 3 — Goal Pace',
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
      id: 'race_time_trial',
      name: 'Fitness Time Trial',
      intent: WorkoutIntent.raceSpecific,
      supportsScaling: false,
      applicablePhases: {TrainingPhase.peak},
      applicableRaceDistances: {RaceDistance.fiveK, RaceDistance.tenK},
      distanceByRace: {
        RaceDistance.fiveK: DistanceRange(minKm: 5, maxKm: 8),
        RaceDistance.tenK: DistanceRange(minKm: 6, maxKm: 10),
      },
      description:
          'Hard continuous effort at close to race intensity — a fitness '
          'checkpoint, not to be run more than once or twice a cycle.',
      blocks: [
        BlockTemplate(
          type: BlockType.warmup,
          durationType: DurationType.fixedKm,
          value: 2.0,
          paceZone: PaceZone.aerobicEasy,
        ),
        BlockTemplate(
          type: BlockType.main,
          durationType: DurationType.fixedKm,
          value: 3.0,
          // tenKPace, not vo2Intervals: I-pace is only meant to be sustained
          // in 3-5min reps with rest, not as one continuous unbroken block —
          // a slower runner would spend 15-20+ min at that intensity here.
          paceZone: PaceZone.tenKPace,
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
    // EASY (very light — shakeout / return-from-layoff)
    // ════════════════════════════════════════════════════════════════════════
    WorkoutTemplate(
      id: 'recovery_shakeout',
      name: 'Shake-Out Run',
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
        RaceDistance.fiveK: DistanceRange(minKm: 3, maxKm: 5),
        RaceDistance.tenK: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.halfMarathon: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.marathon: DistanceRange(minKm: 3, maxKm: 8),
      },
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
        RaceDistance.fiveK: DistanceRange(minKm: 3, maxKm: 5),
        RaceDistance.tenK: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.halfMarathon: DistanceRange(minKm: 3, maxKm: 6),
        RaceDistance.marathon: DistanceRange(minKm: 3, maxKm: 8),
      },
      description:
          'Alternating jog and walk. For return from illness/injury or very high fatigue.',
      blocks: [
        BlockTemplate.mainMeters(
          meters: 400,
          zone: PaceZone.easyRecovery,
          reps: 6,
          recoveryMeters: 200,
          label: 'Jog',
        ),
      ],
    ),
  ];

  // ════════════════════════════════════════════════════════════════════════
  // QUERY METHODS
  // ════════════════════════════════════════════════════════════════════════

  static List<WorkoutTemplate> byIntent(WorkoutIntent intent) =>
      templates.where((t) => t.intent == intent).toList();

  static List<WorkoutTemplate> forContext({
    required RaceDistance distance,
    required TrainingPhase phase,
  }) => templates
      .where(
        (t) =>
            t.applicableRaceDistances.contains(distance) &&
            t.applicablePhases.contains(phase),
      )
      .toList();

  static List<WorkoutTemplate> forSlot({
    required WorkoutIntent intent,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
  }) => templates
      .where(
        (t) =>
            t.intent == intent &&
            t.applicableRaceDistances.contains(raceDistance) &&
            t.applicablePhases.contains(phase),
      )
      .toList();

  static WorkoutTemplate? byId(String id) {
    try {
      return templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static PhaseVariant? getVariant(
    WorkoutTemplate template,
    TrainingPhase phase,
  ) => template.phaseVariants[phase];

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
