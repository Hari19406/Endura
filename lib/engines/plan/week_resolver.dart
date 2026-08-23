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
import '../../models/training_phase.dart';
import '../../models/race_plan.dart';

enum SlotType { easy, quality1, quality2, longRun, rest }

class DaySlot {
  final int weekday;
  final SlotType slotType;
  final WorkoutIntent? intent;
  final String? templateId;
  final bool isRest;
  final String label;
  final double? distanceKm;

  const DaySlot({
    required this.weekday,
    required this.slotType,
    this.intent,
    this.templateId,
    this.isRest = false,
    this.label = '',
    this.distanceKm,
  });

  DaySlot withDistance(double km) => DaySlot(
    weekday: weekday,
    slotType: slotType,
    intent: intent,
    templateId: templateId,
    isRest: isRest,
    label: label,
    distanceKm: km,
  );

  bool get isTraining => !isRest;
  bool get isQuality =>
      intent == WorkoutIntent.vo2max ||
      intent == WorkoutIntent.threshold ||
      intent == WorkoutIntent.speed ||
      intent == WorkoutIntent.raceSpecific;
  bool get isLongRun => intent == WorkoutIntent.endurance;
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

  const WeekResolution({
    required this.days,
    required this.weekNumber,
    required this.phase,
    required this.targetKm,
    this.weekPercentageSum = 1.0,
    this.updatedLadderPositions = const {},
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

    // ── Step 2: Build archetype week ──────────────────────────────────────
    final archetype = ArchetypeTable.build(
      weeklyKm: effectiveKm,
      days: n,
      experience: experienceLevel,
      phase: phase,
    );

    // ── Step 3: Anchor pattern — physical day assignment ──────────────────
    final lrDay = (longRunDayIndex != null && sorted.contains(longRunDayIndex))
        ? longRunDayIndex
        : sorted.last;

    final slotMap = _anchoredPattern(
      sorted: sorted,
      lrDay: lrDay,
      isCutbackWeek: isCutbackWeek,
      phase: phase,
    );

    // ── Step 4: Assign archetype sessions to physical days ────────────────
    final archetypeSessions = archetype?.sessions ?? [];
    final assignedSessions = _assignArchetypeSessions(
      archetypeSessions: archetypeSessions,
      slotMap: slotMap,
      sorted: sorted,
    );

    // ── Step 5: Build DaySlot list, collecting ladder updates ─────────────
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

      final archetypeSession = assignedSessions[weekday];
      // Intent always comes from the slot pattern, never from the archetype
      // session type. The archetype only provides per-session distance.
      final intent = _slotTypeToIntent(slotType, raceDistance, phase);

      final (templateId, updatedPositions) = _pickTemplate(
        intent: intent,
        slotType: slotType,
        raceDistance: raceDistance,
        phase: phase,
        weekNumber: weekNumber,
        recentTemplateIds: recentTemplateIds,
        ladderPositions: mutableLadderPositions,
      );

      mutableLadderPositions.addAll(updatedPositions);

      slots.add(
        DaySlot(
          weekday: weekday,
          slotType: slotType,
          intent: intent,
          templateId: templateId,
          label: _labelForSlot(slotType),
          distanceKm: archetypeSession?.effectiveKm,
        ),
      );
    }

    _log('WEEK RESOLVED', {
      'weekNumber': weekNumber,
      'phase': phase.name,
      'dayCount': n,
      'lrDay': lrDay,
      'isCutback': isCutbackWeek,
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
    );
  }

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
  // ARCHETYPE SESSION ASSIGNMENT
  // ==========================================================================

  Map<int, ArchetypeSession> _assignArchetypeSessions({
    required List<ArchetypeSession> archetypeSessions,
    required Map<int, SlotType> slotMap,
    required List<int> sorted,
  }) {
    if (archetypeSessions.isEmpty) return {};

    final result = <int, ArchetypeSession>{};

    final qualitySessions = archetypeSessions
        .where((s) => s.type.isQuality)
        .toList();
    final longSessions = archetypeSessions.where((s) => s.type.isLong).toList();
    final easySessions = archetypeSessions.where((s) => s.type.isEasy).toList();

    int qualityIdx = 0;
    int longIdx = 0;
    int easyIdx = 0;

    for (final day in sorted) {
      final slotType = slotMap[day];
      if (slotType == null || slotType == SlotType.rest) continue;

      switch (slotType) {
        case SlotType.longRun:
          if (longIdx < longSessions.length) {
            result[day] = longSessions[longIdx++];
          }
          break;
        case SlotType.quality1:
        case SlotType.quality2:
          if (qualityIdx < qualitySessions.length) {
            result[day] = qualitySessions[qualityIdx++];
          }
          break;
        case SlotType.easy:
          if (easyIdx < easySessions.length) {
            result[day] = easySessions[easyIdx++];
          }
          break;
        case SlotType.rest:
          break;
      }
    }

    return result;
  }

  // ==========================================================================
  // SLOT PATTERN — V5 (cyclic anchor)
  //
  // Non-LR training days are sorted by their CYCLIC distance from the LR day
  // (i.e. how many days after the LR they fall, wrapping around the week),
  // then assigned roles by rank:
  //
  //   Rank: 0=Easy  1=Q1  2=Easy  3=Q2  4+=Easy
  //
  // This naturally gives:
  //   3-day (2 non-LR): Easy, Q1
  //   4-day (3 non-LR): Easy, Q1, Easy
  //   5-day (4 non-LR): Easy, Q1, Easy, Q2
  //   6-day (5 non-LR): Easy, Q1, Easy, Q2, Easy
  //
  // Cutback / taper: rank 3 (Q2) → Easy.  No sessions dropped.
  // Volume reduction is handled separately by effectiveKm.
  // ==========================================================================

  Map<int, SlotType> _anchoredPattern({
    required List<int> sorted,
    required int lrDay,
    required bool isCutbackWeek,
    required TrainingPhase phase,
  }) {
    final result = <int, SlotType>{};
    result[lrDay] = SlotType.longRun;

    // Sort non-LR days by cyclic offset from LR day (1..6).
    final remaining = sorted.where((d) => d != lrDay).toList()
      ..sort((a, b) => ((a - lrDay + 7) % 7).compareTo((b - lrDay + 7) % 7));

    final dropQ2 = isCutbackWeek || phase == TrainingPhase.taper;

    for (int i = 0; i < remaining.length; i++) {
      // Day immediately before LR (cyclic offset 6) must stay Easy —
      // it buffers the LR the same way offset-1 buffers recovery after it.
      final isPreLrDay = (remaining[i] - lrDay + 7) % 7 == 6;

      result[remaining[i]] = switch (i) {
        0 => SlotType.easy,
        1 => SlotType.quality1,
        2 => SlotType.easy,
        3 => (dropQ2 || isPreLrDay) ? SlotType.easy : SlotType.quality2,
        _ => SlotType.easy,
      };
    }

    return result;
  }

  // ==========================================================================
  // INTENT MAPPING
  // ==========================================================================

  WorkoutIntent _slotTypeToIntent(
    SlotType slot,
    RaceDistance raceDistance,
    TrainingPhase phase,
  ) {
    return switch (slot) {
      SlotType.easy => WorkoutIntent.aerobicBase,
      SlotType.longRun => WorkoutIntent.endurance,
      // Unreachable — resolve() short-circuits rest slots before this call.
      SlotType.rest => WorkoutIntent.aerobicBase,
      SlotType.quality1 => _primaryQualityIntent(raceDistance, phase),
      SlotType.quality2 => _secondaryQualityIntent(raceDistance, phase),
    };
  }

  WorkoutIntent _primaryQualityIntent(RaceDistance race, TrainingPhase phase) {
    if (phase == TrainingPhase.base || phase == TrainingPhase.taper) {
      return WorkoutIntent.threshold;
    }
    return switch (race) {
      RaceDistance.fiveK => WorkoutIntent.vo2max,
      RaceDistance.tenK => WorkoutIntent.vo2max,
      RaceDistance.halfMarathon => WorkoutIntent.threshold,
      RaceDistance.marathon => WorkoutIntent.vo2max,
    };
  }

  WorkoutIntent _secondaryQualityIntent(
    RaceDistance race,
    TrainingPhase phase,
  ) {
    // Base = aerobic development + economy work (Daniels' R-pace/strides
    // territory), not another interval session — vo2max belongs to build/peak.
    if (phase == TrainingPhase.base) return WorkoutIntent.speed;
    if (phase == TrainingPhase.peak) return WorkoutIntent.raceSpecific;
    return switch (race) {
      // 5K/10K keep layering R-pace/economy work through build.
      RaceDistance.fiveK => WorkoutIntent.speed,
      RaceDistance.tenK => WorkoutIntent.speed,
      RaceDistance.halfMarathon => WorkoutIntent.vo2max,
      RaceDistance.marathon => WorkoutIntent.threshold,
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
