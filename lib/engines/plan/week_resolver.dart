/// WeekResolver — assigns a WorkoutIntent and template to every training day,
/// then sizes each slot using ArchetypeTable.build().
///
/// CHANGE (Archetype v2): GoalMode removed entirely.
///   ArchetypeTable.build() now takes weeklyKm directly — scaling happens
///   inside the archetype, not here.
///
/// CHANGE (WeekResolver v2):
///   - isCutbackWeek now passed into _anchoredPattern() → qualityCount capped at 1.
///   - _pickFromLadder() returns (templateId, updatedIndex) record.
///   - resolve() collects all ladder index updates into updatedLadderPositions.
///   - WeekResolution exposes updatedLadderPositions for caller to persist.
///
/// CHANGE (WeekResolver v4):
///   - Cutback: archetype keeps full session count. _anchoredPattern() caps
///     qualityCount to 1 — Q2 slot becomes easy. Volume via 0.70 multiplier.
///   - Taper: no sessions dropped, no rest day forced. All selected days run.
///     Volume via race-aware progressive multiplier (_taperMultiplier).
///     5K→0.55, 10K→0.75/0.55, HM→0.78/0.55, FM→0.85/0.65/0.40 by taper week.
///
/// CHANGE (WeekResolver v5 — cyclic anchor):
///   - _anchoredPattern() now sorts non-LR days by CYCLIC distance from the
///     LR day and assigns roles by rank: Easy, Q1, Easy, Q2, Easy, …
///     This is equivalent to the user's "wrap around the long run" rule and
///     eliminates every Q-adjacency and cutback Q-count bug in one go.
///   - Intent is now always derived from the slot pattern (not the archetype
///     session type) so surplus quality archetype sessions can't bleed into
///     easy slots on cutback weeks.
library;

import '../config/workout_template_library.dart';
import '../config/archetype_table.dart';
import 'hard_day_planner.dart';
import '../../models/training_phase.dart';
import '../../models/race_plan.dart';

enum SlotType { easy, quality1, quality2, longRun, mediumLong, rest }

class DaySlot {
  final int weekday;
  final SlotType slotType;
  final WorkoutIntent? intent;
  final String? templateId;

  /// 0-based step within the current ladder rung (session-level progression).
  /// Populated from EngineMemory.sessionProgress; consumed by WorkoutResolver.
  final int progressionStep;

  final bool isRest;
  final String label;
  final double? distanceKm;

  const DaySlot({
    required this.weekday,
    required this.slotType,
    this.intent,
    this.templateId,
    this.progressionStep = 0,
    this.isRest = false,
    this.label = '',
    this.distanceKm,
  });

  DaySlot withDistance(double km) => DaySlot(
    weekday: weekday,
    slotType: slotType,
    intent: intent,
    templateId: templateId,
    progressionStep: progressionStep,
    isRest: isRest,
    label: label,
    distanceKm: km,
  );

  bool get isTraining => !isRest;
  bool get isQuality =>
      slotType == SlotType.quality1 || slotType == SlotType.quality2;

  /// The week's single longest run. A mediumLong day is endurance-intent too
  /// but is NOT the long run.
  bool get isLongRun => slotType == SlotType.longRun;
  bool get isMediumLong => slotType == SlotType.mediumLong;
  bool get isHard => isQuality || isLongRun;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String get dayName => _dayNames[weekday];

  @override
  String toString() => isRest
      ? '$dayName: REST'
      : '$dayName: ${intent?.name ?? "??"} [${templateId ?? "??"}] ($label) '
            '${distanceKm?.toStringAsFixed(1) ?? "?"}km';
}

class WeekResolution {
  final List<DaySlot> days;
  final int weekNumber;
  final TrainingPhase phase;
  final double targetKm;
  final double weekPercentageSum;

  /// Updated ladder positions after this week's template picks.
  /// Caller must persist these into EngineMemory.ladderPositions
  /// and pass them back into the next resolve() call.
  final Map<String, int> updatedLadderPositions;

  /// Updated session-progression counters (consecutive weeks per intent on the
  /// current ladder rung). Echoed unchanged today; PlanMaterializer advances
  /// them week-to-week (Phase 8).
  final Map<String, int> updatedSessionProgress;

  const WeekResolution({
    required this.days,
    required this.weekNumber,
    required this.phase,
    required this.targetKm,
    this.weekPercentageSum = 1.0,
    this.updatedLadderPositions = const {},
    this.updatedSessionProgress = const {},
  });

  DaySlot? slotFor(int weekday) {
    if (weekday < 0 || weekday > 6) return null;
    return days[weekday];
  }

  WorkoutIntent? intentForToday(DateTime now) {
    final slot = slotFor(now.weekday - 1);
    if (slot == null || slot.isRest) return null;
    return slot.intent;
  }

  String? templateIdForToday(DateTime now) {
    final slot = slotFor(now.weekday - 1);
    if (slot == null || slot.isRest) return null;
    return slot.templateId;
  }

  int get trainingDayCount => days.where((d) => d.isTraining).length;
  int get qualityCount => days.where((d) => d.isQuality).length;
  bool get hasLongRun => days.any((d) => d.isLongRun);

  List<String> get allTemplateIds => days
      .where((d) => d.templateId != null)
      .map((d) => d.templateId!)
      .toList();
}

// ============================================================================
// LADDER DEFINITIONS
// ============================================================================

const Map<WorkoutIntent, List<String>> ladderTemplateIds = {
  WorkoutIntent.endurance: [
    'long_steady', // base/build/peak/taper — all distances
    'long_progression', // base/build/peak — all distances
    'long_strides', // base/build/peak — all distances
    'long_hilly', // base/build/peak — all distances
    'long_gp_finish', // build/peak — all distances
    'long_fartlek', // build/peak — 5K/10K/HM
    'long_surges', // build/peak — HM/FM
    'long_cutdown', // build/peak — HM/FM
    'long_mid_block', // build/peak — FM only
  ],
  WorkoutIntent.threshold: [
    'cruise_intervals_400',
    'cruise_intervals_800',
    'cruise_intervals_mile',
    'cruise_intervals_2000',
    'steady_state',
    'tempo_continuous',
    'tempo_intervals',
  ],
  WorkoutIntent.vo2max: [
    'vo2_400',
    'vo2_600',
    'vo2_classic',
    'vo2_1000',
    'vo2_1200',
    'vo2_mixed',
    'vo2_thirty_thirty',
    'vo2_ladder',
    'vo2_pyramid',
  ],
  WorkoutIntent.raceSpecific: [
    'race_gp_intervals',
    'race_pace_progression',
    'race_negative_split',
    'race_simulation',
    'race_dress_rehearsal',
    'race_time_trial',
  ],
};

// ============================================================================
// WEEK RESOLVER
// ============================================================================

/// Templates kept out of the normal easy-day rotation — they exist for
/// readiness downgrades / explicit use, not week-to-week variety.
const Set<String> _rotationDenylist = {'recovery_walk_jog', 'recovery_shakeout'};

class WeekResolver {
  const WeekResolver();

  WeekResolution resolve({
    required WeekTarget weekTarget,
    required List<int> trainingDayIndices,
    required RaceDistance raceDistance,
    required TrainingPhase phase,

    // Archetype inputs.
    required ExperienceLevel experienceLevel,
    required double currentWeeklyKm,

    int? longRunDayIndex,
    int weekNumber = 1,
    List<String> recentTemplateIds = const [],
    bool isCutbackWeek = false,

    /// Which taper week this is (1 = first taper week, 2 = second, etc.).
    /// Only relevant when phase == TrainingPhase.taper.
    int taperWeekNumber = 1,

    /// Ladder positions from previous week — keyed by intent name.
    /// Pass EngineMemory.ladderPositions here each call.
    Map<String, int> ladderPositions = const {},

    /// Session-progression counters (consecutive weeks per intent on the current
    /// ladder rung). Pass EngineMemory.sessionProgress. Echoed back unchanged
    /// today — PlanMaterializer advances them (Phase 8).
    Map<String, int> sessionProgress = const {},
  }) {
    final sorted = List<int>.from(trainingDayIndices)..sort();
    final n = sorted.length;

    if (n == 0) {
      return WeekResolution(
        days: List.generate(
          7,
          (i) => DaySlot(
            weekday: i,
            slotType: SlotType.rest,
            isRest: true,
            label: 'rest',
          ),
        ),
        weekNumber: weekTarget.week,
        phase: phase,
        targetKm: weekTarget.targetKm,
      );
    }

    // ── Step 1: Compute effective weekly km ───────────────────────────────
    // Cutback: 0.70 multiplier, same session count.
    // Taper: race-aware progressive multiplier, same session count.
    // Both: no sessions dropped — volume reduction only.
    final double effectiveKm;
    if (phase == TrainingPhase.taper) {
      effectiveKm =
          currentWeeklyKm * _taperMultiplier(raceDistance, taperWeekNumber);
    } else if (isCutbackWeek) {
      effectiveKm = currentWeeklyKm * 0.70;
    } else {
      effectiveKm = currentWeeklyKm;
    }

    // ── Step 2: Quality count + hard-day placement (planner first) ────────
    final lrDay = (longRunDayIndex != null && sorted.contains(longRunDayIndex))
        ? longRunDayIndex
        : sorted.last;

    final qualityCount = HardDayPlanner.qualityCountFor(
      trainingDays: n,
      phase: phase,
      isCutback: isCutbackWeek,
    );

    final placement = const HardDayPlanner().placeHardDays(
      trainingDayIndices: sorted,
      longRunDayIndex: lrDay,
      qualityCount: qualityCount,
      phase: phase,
    );

    // ── Step 3: Size the week (bounded allocation) ───────────────────────
    // Scale the skeleton's un-reduced long-run target down in step with the
    // cutback / taper reduction, then let allocate() clamp it to bounds.
    final lrScale = weekTarget.targetKm > 0
        ? (effectiveKm / weekTarget.targetKm)
        : 1.0;
    final lrTarget =
        weekTarget.longRunKm > 0 ? weekTarget.longRunKm * lrScale : null;

    final archetype = ArchetypeTable.allocate(
      effectiveKm: effectiveKm,
      days: n,
      qualityCount: placement.resolvedQualityCount,
      experience: experienceLevel,
      phase: phase,
      raceDistance: raceDistance,
      longRunKmTarget: lrTarget,
      allowMediumLong: !isCutbackWeek,
    );

    // ── Step 4: Physical slot map from the placement ────────────────────
    final slotMap = <int, SlotType>{};
    placement.roles.forEach((day, role) {
      slotMap[day] = switch (role) {
        HardDayRole.longRun => SlotType.longRun,
        HardDayRole.quality1 => SlotType.quality1,
        HardDayRole.quality2 => SlotType.quality2,
        HardDayRole.easy => SlotType.easy,
      };
    });

    // Promote the easy day furthest from the long run to mediumLong, if the
    // archetype produced one.
    if (archetype.hasMediumLong) {
      final easyDays =
          slotMap.entries
              .where((e) => e.value == SlotType.easy)
              .map((e) => e.key)
              .toList()
            ..sort(
              (a, b) => _cyclicFromLr(
                b,
                lrDay,
              ).compareTo(_cyclicFromLr(a, lrDay)),
            );
      if (easyDays.isNotEmpty) slotMap[easyDays.first] = SlotType.mediumLong;
    }

    // ── Step 5: Bind archetype session km to slots by role ──────────────
    final longKm = archetype.sessions
        .where((s) => s.type.isLong)
        .map((s) => s.effectiveKm)
        .toList();
    final mlKm = archetype.sessions
        .where((s) => s.type.isMediumLong)
        .map((s) => s.effectiveKm)
        .toList();
    final qKm = archetype.sessions
        .where((s) => s.type.isQuality)
        .map((s) => s.effectiveKm)
        .toList();
    final easyKm = archetype.sessions
        .where((s) => s.type.isEasy)
        .map((s) => s.effectiveKm)
        .toList();

    final kmForDay = <int, double>{};
    // Quality days in Q1 → Q2 order (cyclic offset from the long run).
    final qDays =
        slotMap.entries
            .where(
              (e) =>
                  e.value == SlotType.quality1 ||
                  e.value == SlotType.quality2,
            )
            .map((e) => e.key)
            .toList()
          ..sort(
            (a, b) =>
                _cyclicFromLr(a, lrDay).compareTo(_cyclicFromLr(b, lrDay)),
          );
    for (var i = 0; i < qDays.length && i < qKm.length; i++) {
      kmForDay[qDays[i]] = qKm[i];
    }
    var ei = 0;
    for (final d in sorted) {
      switch (slotMap[d]) {
        case SlotType.longRun:
          if (longKm.isNotEmpty) kmForDay[d] = longKm.first;
        case SlotType.mediumLong:
          if (mlKm.isNotEmpty) kmForDay[d] = mlKm.first;
        case SlotType.easy:
          if (ei < easyKm.length) kmForDay[d] = easyKm[ei++];
        default:
          break;
      }
    }

    // ── Step 6: Build DaySlot list, collecting ladder updates ───────────
    final mutableLadderPositions = Map<String, int>.from(ladderPositions);

    final slots = <DaySlot>[];
    for (int weekday = 0; weekday < 7; weekday++) {
      final slotType = slotMap[weekday] ?? SlotType.rest;

      if (slotType == SlotType.rest) {
        slots.add(
          DaySlot(
            weekday: weekday,
            slotType: SlotType.rest,
            isRest: true,
            label: 'rest',
          ),
        );
        continue;
      }

      final intent = _slotTypeToIntent(
        slotType,
        raceDistance,
        phase,
        experienceLevel,
      );

      // A mediumLong always uses the dedicated template; everything else goes
      // through the phase/race ladder.
      String? templateId;
      if (slotType == SlotType.mediumLong) {
        templateId = 'medium_long_run';
      } else {
        final (picked, updatedPositions) = _pickTemplate(
          intent: intent,
          slotType: slotType,
          raceDistance: raceDistance,
          phase: phase,
          weekNumber: weekNumber,
          recentTemplateIds: recentTemplateIds,
          ladderPositions: mutableLadderPositions,
          targetKm: kmForDay[weekday] ?? 0,
        );
        templateId = picked;
        mutableLadderPositions.addAll(updatedPositions);
      }

      slots.add(
        DaySlot(
          weekday: weekday,
          slotType: slotType,
          intent: intent,
          templateId: templateId,
          progressionStep: sessionProgress[intent.name] ?? 0,
          label: _labelForSlot(slotType),
          distanceKm: kmForDay[weekday],
        ),
      );
    }

    _log('WEEK RESOLVED', {
      'weekNumber': weekNumber,
      'phase': phase.name,
      'dayCount': n,
      'lrDay': lrDay,
      'isCutback': isCutbackWeek,
      'qualityCount': placement.resolvedQualityCount,
      'droppedQ2': placement.droppedQuality,
      'effectiveKm': effectiveKm.toStringAsFixed(1),
      'slots': slots
          .where((s) => s.isTraining)
          .map(
            (s) =>
                '${s.dayName}: ${s.intent?.name} [${s.templateId}] '
                '${s.distanceKm?.toStringAsFixed(1) ?? "?"}km',
          )
          .join(', '),
    });

    return WeekResolution(
      days: slots,
      weekNumber: weekTarget.week,
      phase: phase,
      targetKm: effectiveKm,
      weekPercentageSum: 1.0,
      updatedLadderPositions: Map.unmodifiable(mutableLadderPositions),
      updatedSessionProgress: Map.unmodifiable(
        Map<String, int>.from(sessionProgress),
      ),
    );
  }

  static int _cyclicFromLr(int day, int lrDay) => (day - lrDay + 7) % 7;

  // ==========================================================================
  // TAPER MULTIPLIER — race-aware progressive volume reduction
  //
  // 5K:  1 taper week  → 0.55
  // 10K: 2 taper weeks → W1: 0.75, W2: 0.55
  // HM:  2 taper weeks → W1: 0.78, W2: 0.55
  // FM:  3 taper weeks → W1: 0.85, W2: 0.65, W3: 0.40
  // ==========================================================================

  static double _taperMultiplier(RaceDistance race, int taperWeekNumber) {
    return switch ((race, taperWeekNumber)) {
      (RaceDistance.fiveK, _) => 0.55,
      (RaceDistance.tenK, 1) => 0.75,
      (RaceDistance.tenK, _) => 0.55,
      (RaceDistance.halfMarathon, 1) => 0.78,
      (RaceDistance.halfMarathon, _) => 0.55,
      (RaceDistance.marathon, 1) => 0.85,
      (RaceDistance.marathon, 2) => 0.65,
      (RaceDistance.marathon, _) => 0.40,
    };
  }

  // ==========================================================================
  // INTENT MAPPING — single authority
  //
  // Merged from the former WeekResolver._primaryQualityIntent /
  // _secondaryQualityIntent AND SessionSelector._roleToIntent (which
  // disagreed). Reconciled per the rework decision:
  //   Q1 build/peak → threshold for HM & FM, vo2max for 5K & 10K.
  // ==========================================================================

  WorkoutIntent _slotTypeToIntent(
    SlotType slot,
    RaceDistance raceDistance,
    TrainingPhase phase,
    ExperienceLevel experience,
  ) {
    return switch (slot) {
      SlotType.easy => WorkoutIntent.aerobicBase,
      SlotType.longRun => WorkoutIntent.endurance,
      SlotType.mediumLong => WorkoutIntent.endurance,
      // Unreachable — resolve() short-circuits rest slots before this call.
      SlotType.rest => WorkoutIntent.aerobicBase,
      SlotType.quality1 => _primaryQualityIntent(raceDistance, phase, experience),
      SlotType.quality2 =>
        _secondaryQualityIntent(raceDistance, phase, experience),
    };
  }

  WorkoutIntent _primaryQualityIntent(
    RaceDistance race,
    TrainingPhase phase,
    ExperienceLevel experience,
  ) {
    // Beginners never do VO2max/speed intervals — threshold work only.
    if (experience == ExperienceLevel.beginner) return WorkoutIntent.threshold;
    if (phase == TrainingPhase.base || phase == TrainingPhase.taper) {
      return WorkoutIntent.threshold;
    }
    // build / peak / maintenance.
    return switch (race) {
      RaceDistance.fiveK => WorkoutIntent.vo2max,
      RaceDistance.tenK => WorkoutIntent.vo2max,
      RaceDistance.halfMarathon => WorkoutIntent.threshold,
      RaceDistance.marathon => WorkoutIntent.threshold,
    };
  }

  WorkoutIntent _secondaryQualityIntent(
    RaceDistance race,
    TrainingPhase phase,
    ExperienceLevel experience,
  ) {
    if (experience == ExperienceLevel.beginner) return WorkoutIntent.threshold;
    // Base = economy / R-pace work, not a second interval session.
    if (phase == TrainingPhase.base) return WorkoutIntent.speed;
    // Peak = race-specific sharpening.
    if (phase == TrainingPhase.peak) return WorkoutIntent.raceSpecific;
    // build / maintenance.
    return switch (race) {
      RaceDistance.fiveK => WorkoutIntent.speed,
      RaceDistance.tenK => WorkoutIntent.speed,
      RaceDistance.halfMarathon => WorkoutIntent.vo2max,
      RaceDistance.marathon => WorkoutIntent.vo2max,
    };
  }

  // ==========================================================================
  // TEMPLATE PICKING — LADDER-AWARE
  // ==========================================================================

  (String?, Map<String, int>) _pickTemplate({
    required WorkoutIntent intent,
    required SlotType slotType,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
    required int weekNumber,
    required List<String> recentTemplateIds,
    required Map<String, int> ladderPositions,
    double targetKm = 0,
  }) {
    var candidates = WorkoutLibrary.forSlot(
      intent: intent,
      raceDistance: raceDistance,
      phase: phase,
    );

    if (candidates.isEmpty && phase == TrainingPhase.maintenance) {
      candidates = WorkoutLibrary.forSlot(
        intent: intent,
        raceDistance: raceDistance,
        phase: TrainingPhase.base,
      );
    }

    if (candidates.isEmpty) return (null, const {});
    if (candidates.length == 1) return (candidates.first.id, const {});

    final ladder = ladderTemplateIds[intent];
    if (ladder != null) {
      final (picked, updatedIndex) = _pickFromLadder(
        ladder: ladder,
        candidates: candidates,
        ladderPositions: ladderPositions,
        intent: intent,
        phase: phase,
        raceDistance: raceDistance,
      );
      return (picked, {intent.name: updatedIndex});
    }

    // Rotation path (aerobicBase / speed). Two guards, each applied only if it
    // doesn't empty the pool:
    //   1. special-purpose templates (walk/jog, shakeout) are for readiness
    //      substitution, never the normal rotation;
    //   2. a template whose max distance is below the slot's budget can't cover
    //      the day (e.g. recovery_walk_jog on a 12 km easy run).
    final rotatable = candidates
        .where((t) => !_rotationDenylist.contains(t.id))
        .toList();
    if (rotatable.isNotEmpty) candidates = rotatable;

    if (targetKm > 0) {
      final fit = candidates.where((t) {
        final max = t.distanceByRace[raceDistance]?.maxKm;
        return max == null || max >= targetKm * 0.9;
      }).toList();
      if (fit.isNotEmpty) candidates = fit;
    }

    final picked = _pickByRotation(
      candidates: candidates,
      recentTemplateIds: recentTemplateIds,
      weekNumber: weekNumber,
      slotType: slotType,
      intent: intent,
    );
    return (picked, const {});
  }

  (String, int) _pickFromLadder({
    required List<String> ladder,
    required List<WorkoutTemplate> candidates,
    required Map<String, int> ladderPositions,
    required WorkoutIntent intent,
    required TrainingPhase phase,
    required RaceDistance raceDistance,
  }) {
    final candidateIds = candidates.map((t) => t.id).toSet();
    final orderedRungs = ladder
        .where((id) => candidateIds.contains(id))
        .toList();

    if (orderedRungs.isEmpty) return (candidates.first.id, 0);

    final storedIndex = ladderPositions[intent.name] ?? 0;
    final clampedIndex = storedIndex.clamp(0, orderedRungs.length - 1);
    final picked = orderedRungs[clampedIndex];
    final nextIndex = (clampedIndex + 1) % orderedRungs.length;

    assert(() {
      // ignore: avoid_print
      print(
        '[WeekResolver] LADDER_PICK'
        '\n  intent: ${intent.name}'
        '\n  phase: ${phase.name}'
        '\n  race: ${raceDistance.name}'
        '\n  storedIndex: $storedIndex'
        '\n  clampedIndex: $clampedIndex'
        '\n  nextIndex: $nextIndex'
        '\n  orderedRungs: $orderedRungs'
        '\n  → picked: $picked',
      );
      return true;
    }());

    return (picked, nextIndex);
  }

  String _pickByRotation({
    required List<WorkoutTemplate> candidates,
    required List<String> recentTemplateIds,
    required int weekNumber,
    required SlotType slotType,
    required WorkoutIntent intent,
  }) {
    final fresh = candidates
        .where((t) => !recentTemplateIds.contains(t.id))
        .toList();

    if (fresh.isNotEmpty) {
      final seed = weekNumber * 7 + slotType.index;
      return fresh[seed % fresh.length].id;
    }

    final ranked = List<WorkoutTemplate>.from(candidates);
    ranked.sort((a, b) {
      final idxA = recentTemplateIds.indexOf(a.id);
      final idxB = recentTemplateIds.indexOf(b.id);
      if (idxA == -1) return -1;
      if (idxB == -1) return 1;
      return idxA.compareTo(idxB);
    });

    return ranked.first.id;
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  String _labelForSlot(SlotType slot) => switch (slot) {
    SlotType.easy => 'easy',
    SlotType.quality1 => 'quality 1',
    SlotType.quality2 => 'quality 2',
    SlotType.longRun => 'long run',
    SlotType.mediumLong => 'medium-long',
    SlotType.rest => 'rest',
  };

  void _log(String tag, Map<String, dynamic> data) {
    assert(() {
      final entries = data.entries
          .map((e) => '  ${e.key}: ${e.value}')
          .join('\n');
      // ignore: avoid_print
      print('[WeekResolver] $tag\n$entries');
      return true;
    }());
  }
}
