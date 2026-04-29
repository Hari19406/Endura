/// WeekResolver — assigns a WorkoutIntent and template to every day of the week.
///
/// The week structure is FIXED based on how many days the runner trains:
///   3 days: E – Q – L
///   4 days: E – Q – E – L
///   5 days: E – Q – E – Q – L
///   6 days: E – Q – E – Q – E – L
///   7 days: E – Q – E – Q – E – L – E
///
/// These slots are mapped onto the runner's chosen training days
/// (e.g., Mon/Tue/Thu/Fri/Sat for a 5-day runner).
///
/// Quality sessions are always split:
///   1 quality slot  → threshold OR vo2max (race-distance dependent)
///   2 quality slots → one threshold + one vo2max (always)
///
/// Rotation: tracks recently used template IDs per category.
/// A template won't repeat within 2 weeks unless all templates
/// in that category have been used.
///
/// Cutback weeks:
///   - Drop from 2 quality to 1 quality (lighter)
///   - Freed quality slot becomes easy
///   - Volume drops to ~70% of build week (handled by progression layer)
library;

import '../config/workout_template_library.dart';
import '../../models/training_phase.dart';
import '../../models/race_plan.dart';

// ============================================================================
// SLOT TYPE — the structural role of each day
// ============================================================================

enum SlotType { easy, quality1, quality2, longRun, rest }

// ============================================================================
// DAY SLOT — one day in the resolved week
// ============================================================================

class DaySlot {
  final int weekday;
  final SlotType slotType;
  final WorkoutIntent? intent;
  final String? templateId;
  final bool isRest;
  final String label;

  const DaySlot({
    required this.weekday,
    required this.slotType,
    this.intent,
    this.templateId,
    this.isRest = false,
    this.label = '',
  });

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
      : '$dayName: ${intent?.name ?? "??"} [${templateId ?? "??"}] ($label)';
}

// ============================================================================
// WEEK RESOLUTION RESULT
// ============================================================================

class WeekResolution {
  final List<DaySlot> days;
  final int weekNumber;
  final TrainingPhase phase;
  final double targetKm;

  const WeekResolution({
    required this.days,
    required this.weekNumber,
    required this.phase,
    required this.targetKm,
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

  List<String> get allTemplateIds =>
      days.where((d) => d.templateId != null).map((d) => d.templateId!).toList();
}

// ============================================================================
// WEEK RESOLVER
// ============================================================================

class WeekResolver {
  const WeekResolver();

  /// Resolve a full week of workout slots.
  ///
  /// [weekTarget] — volume/phase/quality info from RacePlanBuilder
  /// [trainingDayIndices] — which days the runner trains (0=Mon..6=Sun)
  /// [raceDistance] — goal race for quality intent selection
  /// [phase] — current training phase
  /// [weekNumber] — current week in training cycle
  /// [recentTemplateIds] — template IDs used in the last 2 weeks (for rotation)
  /// [isCutbackWeek] — if true, drop to 1 quality + reduce structure
  WeekResolution resolve({
    required WeekTarget weekTarget,
    required List<int> trainingDayIndices,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
    int weekNumber = 1,
    List<String> recentTemplateIds = const [],
    bool isCutbackWeek = false,
  }) {
    final sorted = List<int>.from(trainingDayIndices)..sort();
    final n = sorted.length;

    if (n == 0) {
      return WeekResolution(
        days: List.generate(7, (i) => DaySlot(
          weekday: i, slotType: SlotType.rest, isRest: true, label: 'rest',
        )),
        weekNumber: weekTarget.week,
        phase: phase,
        targetKm: weekTarget.targetKm,
      );
    }

    // ── 1. Get the structural pattern for this day count ─────────────────
    final pattern = _weekPattern(n, isCutbackWeek: isCutbackWeek);

    // ── 2. Determine quality intents ─────────────────────────────────────
    final qualityIntents = _qualityIntents(
      raceDistance: raceDistance,
      phase: phase,
    );

    // ── 3. Map pattern onto training days, pick templates ────────────────
    final slots = <DaySlot>[];
    int patternIdx = 0;

    for (int weekday = 0; weekday < 7; weekday++) {
      if (!sorted.contains(weekday)) {
        slots.add(DaySlot(
          weekday: weekday, slotType: SlotType.rest,
          isRest: true, label: 'rest',
        ));
        continue;
      }

      final slotType = pattern[patternIdx];
      patternIdx++;

      final intent = _intentForSlot(slotType, qualityIntents);
      final templateId = _pickTemplate(
        intent: intent,
        slotType: slotType,
        raceDistance: raceDistance,
        phase: phase,
        weekNumber: weekNumber,
        recentTemplateIds: recentTemplateIds,
      );

      slots.add(DaySlot(
        weekday: weekday,
        slotType: slotType,
        intent: intent,
        templateId: templateId,
        label: _labelForSlot(slotType),
      ));
    }

    _log('WEEK RESOLVED', {
      'weekNumber': weekNumber,
      'phase': phase.name,
      'dayCount': n,
      'isCutback': isCutbackWeek,
      'pattern': pattern.map((s) => s.name).join(' – '),
      'slots': slots.where((s) => s.isTraining).map((s) =>
          '${s.dayName}: ${s.intent?.name} [${s.templateId}]').join(', '),
    });

    return WeekResolution(
      days: slots,
      weekNumber: weekTarget.week,
      phase: phase,
      targetKm: weekTarget.targetKm,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // WEEK PATTERNS
  // ════════════════════════════════════════════════════════════════════════════

  /// Fixed structural pattern based on training day count.
  ///
  /// 3 days: E – Q1 – L
  /// 4 days: E – Q1 – E – L
  /// 5 days: E – Q1 – E – Q2 – L
  /// 6 days: E – Q1 – E – Q2 – E – L
  /// 7 days: E – Q1 – E – Q2 – E – L – E
  ///
  /// Cutback: Q2 becomes E (drop to 1 quality).
  List<SlotType> _weekPattern(int dayCount, {bool isCutbackWeek = false}) {
    final pattern = switch (dayCount) {
      3 => [SlotType.easy, SlotType.quality1, SlotType.longRun],
      4 => [SlotType.easy, SlotType.quality1, SlotType.easy, SlotType.longRun],
      5 => [
          SlotType.easy, SlotType.quality1, SlotType.easy,
          SlotType.quality2, SlotType.longRun,
        ],
      6 => [
          SlotType.easy, SlotType.quality1, SlotType.easy,
          SlotType.quality2, SlotType.easy, SlotType.longRun,
        ],
      7 => [
          SlotType.easy, SlotType.quality1, SlotType.easy,
          SlotType.quality2, SlotType.easy, SlotType.longRun,
          SlotType.easy,
        ],
      _ => dayCount < 3
          ? List.filled(dayCount, SlotType.easy)
          : [SlotType.easy, SlotType.quality1, SlotType.longRun],
    };

    if (!isCutbackWeek) return pattern;

    // Cutback: replace quality2 with easy, keep quality1.
    return pattern.map((s) => s == SlotType.quality2 ? SlotType.easy : s).toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // QUALITY INTENT MAPPING
  // ════════════════════════════════════════════════════════════════════════════

  /// Determines which intent each quality slot gets.
  ///
  /// Always split: Q1 and Q2 are from different categories.
  ///   5K / 10K:  Q1 = vo2max,    Q2 = threshold
  ///   HM / FM:   Q1 = threshold, Q2 = vo2max
  ///
  /// Base phase: both quality slots use threshold (lighter).
  /// Taper phase: single quality uses threshold.
  ({WorkoutIntent q1, WorkoutIntent q2}) _qualityIntents({
    required RaceDistance raceDistance,
    required TrainingPhase phase,
  }) {
    if (phase == TrainingPhase.base) {
      return (q1: WorkoutIntent.threshold, q2: WorkoutIntent.threshold);
    }

    if (phase == TrainingPhase.taper) {
      return (q1: WorkoutIntent.threshold, q2: WorkoutIntent.threshold);
    }

    // Build / Peak: race-specific split.
    return switch (raceDistance) {
      RaceDistance.fiveK => (
          q1: WorkoutIntent.vo2max,
          q2: WorkoutIntent.threshold,
        ),
      RaceDistance.tenK => (
          q1: WorkoutIntent.vo2max,
          q2: WorkoutIntent.threshold,
        ),
      RaceDistance.halfMarathon => (
          q1: WorkoutIntent.threshold,
          q2: WorkoutIntent.vo2max,
        ),
      RaceDistance.marathon => (
          q1: WorkoutIntent.threshold,
          q2: WorkoutIntent.vo2max,
        ),
    };
  }

  WorkoutIntent _intentForSlot(
    SlotType slot,
    ({WorkoutIntent q1, WorkoutIntent q2}) qualityIntents,
  ) {
    return switch (slot) {
      SlotType.easy     => WorkoutIntent.aerobicBase,
      SlotType.quality1 => qualityIntents.q1,
      SlotType.quality2 => qualityIntents.q2,
      SlotType.longRun  => WorkoutIntent.endurance,
      SlotType.rest     => WorkoutIntent.recovery,
    };
  }

  String _labelForSlot(SlotType slot) {
    return switch (slot) {
      SlotType.easy     => 'easy',
      SlotType.quality1 => 'quality 1',
      SlotType.quality2 => 'quality 2',
      SlotType.longRun  => 'long run',
      SlotType.rest     => 'rest',
    };
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TEMPLATE ROTATION
  // ════════════════════════════════════════════════════════════════════════════

  /// Pick a template for this slot, avoiding recently used ones.
  ///
  /// Strategy:
  ///   1. Get all templates matching the intent + race + phase
  ///   2. Exclude any template used in last 2 weeks (recentTemplateIds)
  ///   3. If all excluded, pick the least recently used one
  ///   4. Use weekNumber + slotType as seed for deterministic variety
  String? _pickTemplate({
    required WorkoutIntent intent,
    required SlotType slotType,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
    required int weekNumber,
    required List<String> recentTemplateIds,
  }) {
    final candidates = WorkoutLibrary.forSlot(
      intent: intent,
      raceDistance: raceDistance,
      phase: phase,
    );

    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first.id;

    // Filter out recently used templates.
    final fresh = candidates
        .where((t) => !recentTemplateIds.contains(t.id))
        .toList();

    if (fresh.isNotEmpty) {
      // Deterministic pick: weekNumber ensures different picks each week,
      // slotType.index ensures Q1 and Q2 don't collide.
      final seed = weekNumber * 7 + slotType.index;
      return fresh[seed % fresh.length].id;
    }

    // All templates used recently — pick the one used longest ago.
    // Earlier in recentTemplateIds = used longer ago.
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

  // ════════════════════════════════════════════════════════════════════════════
  // DEBUG LOGGING
  // ════════════════════════════════════════════════════════════════════════════

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