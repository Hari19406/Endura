/// MaterializedPlan — the whole training plan resolved up front: every week,
/// every day, every workout with paces. Built by PlanMaterializer at plan
/// creation and on any input change; read (not recomputed) on app open.
///
/// Storage: PlanStore (local cache + Supabase `materialized_plans`). This file
/// is pure data + JSON — no engine imports beyond the shared models.
library;

import '../../models/training_phase.dart';
import '../config/workout_template_library.dart' show ResolvedWorkout, WorkoutIntent;

/// Structural role of a training day. Superset of WeekResolver.SlotType — adds
/// `mediumLong` so the plan can distinguish a mid-week aerobic run from the
/// week's single long run.
enum MaterializedSlot { easy, quality1, quality2, longRun, mediumLong, rest }

extension MaterializedSlotX on MaterializedSlot {
  bool get isRest => this == MaterializedSlot.rest;
  bool get isQuality =>
      this == MaterializedSlot.quality1 || this == MaterializedSlot.quality2;
  bool get isLongRun => this == MaterializedSlot.longRun;
}

class DayCompletion {
  final DateTime completedAt;
  final double actualKm;
  final int? actualPaceSecPerKm;
  final double? rpe;
  final String? runId;

  const DayCompletion({
    required this.completedAt,
    required this.actualKm,
    this.actualPaceSecPerKm,
    this.rpe,
    this.runId,
  });

  Map<String, dynamic> toJson() => {
    'completedAt': completedAt.toIso8601String(),
    'actualKm': actualKm,
    if (actualPaceSecPerKm != null) 'actualPaceSecPerKm': actualPaceSecPerKm,
    if (rpe != null) 'rpe': rpe,
    if (runId != null) 'runId': runId,
  };

  factory DayCompletion.fromJson(Map<String, dynamic> j) => DayCompletion(
    completedAt: DateTime.parse(j['completedAt'] as String),
    actualKm: (j['actualKm'] as num).toDouble(),
    actualPaceSecPerKm: (j['actualPaceSecPerKm'] as num?)?.toInt(),
    rpe: (j['rpe'] as num?)?.toDouble(),
    runId: j['runId'] as String?,
  );
}

class MaterializedDay {
  /// 0 = Monday … 6 = Sunday.
  final int weekday;
  final MaterializedSlot slot;
  final WorkoutIntent? intent;
  final String? templateId;

  /// 0-based step within the current ladder rung (session-level progression).
  final int progressionStep;

  /// The fully resolved workout (blocks + paces). Null on a rest day.
  final ResolvedWorkout? workout;

  /// Set when a run is logged against this day.
  final DayCompletion? completion;

  /// Set when the athlete deliberately skips this day from the pre-run
  /// briefing screen — distinct from simply not having gotten to it yet.
  /// Mutually exclusive with [completion] in practice (`PlanStore` refuses to
  /// skip an already-completed day and vice versa).
  final DateTime? skippedAt;

  const MaterializedDay({
    required this.weekday,
    required this.slot,
    this.intent,
    this.templateId,
    this.progressionStep = 0,
    this.workout,
    this.completion,
    this.skippedAt,
  });

  bool get isRest => slot.isRest;
  bool get isCompleted => completion != null;
  bool get isSkipped => skippedAt != null;
  double get plannedKm => workout?.totalDistanceKm ?? 0;

  MaterializedDay copyWith({
    MaterializedSlot? slot,
    WorkoutIntent? intent,
    String? templateId,
    int? progressionStep,
    ResolvedWorkout? workout,
    DayCompletion? completion,
    DateTime? skippedAt,
  }) => MaterializedDay(
    weekday: weekday,
    slot: slot ?? this.slot,
    intent: intent ?? this.intent,
    templateId: templateId ?? this.templateId,
    progressionStep: progressionStep ?? this.progressionStep,
    workout: workout ?? this.workout,
    completion: completion ?? this.completion,
    skippedAt: skippedAt ?? this.skippedAt,
  );

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'slot': slot.name,
    if (intent != null) 'intent': intent!.name,
    if (templateId != null) 'templateId': templateId,
    if (progressionStep != 0) 'progressionStep': progressionStep,
    if (workout != null) 'workout': workout!.toJson(),
    if (completion != null) 'completion': completion!.toJson(),
    if (skippedAt != null) 'skippedAt': skippedAt!.toIso8601String(),
  };

  factory MaterializedDay.fromJson(Map<String, dynamic> j) => MaterializedDay(
    weekday: (j['weekday'] as num).toInt(),
    slot: MaterializedSlot.values.firstWhere(
      (e) => e.name == j['slot'],
      orElse: () => MaterializedSlot.rest,
    ),
    intent: j['intent'] == null
        ? null
        : WorkoutIntent.values.firstWhere(
            (e) => e.name == j['intent'],
            orElse: () => WorkoutIntent.aerobicBase,
          ),
    templateId: j['templateId'] as String?,
    progressionStep: (j['progressionStep'] as num?)?.toInt() ?? 0,
    workout: j['workout'] == null
        ? null
        : ResolvedWorkout.fromJson(j['workout'] as Map<String, dynamic>),
    completion: j['completion'] == null
        ? null
        : DayCompletion.fromJson(j['completion'] as Map<String, dynamic>),
    skippedAt: j['skippedAt'] == null
        ? null
        : DateTime.parse(j['skippedAt'] as String),
  );
}

class MaterializedWeek {
  /// 1-based; matches RacePlan.weeks / WeekTarget.week.
  final int weekNumber;
  final TrainingPhase phase;

  /// Effective weekly km after cutback / taper reduction.
  final double targetKm;
  final bool isCutback;

  /// A completed week — never recomputed by PlanMaterializer.
  final bool isFrozen;

  /// Always length 7, index 0 = Monday.
  final List<MaterializedDay> days;

  const MaterializedWeek({
    required this.weekNumber,
    required this.phase,
    required this.targetKm,
    required this.isCutback,
    required this.isFrozen,
    required this.days,
  });

  Iterable<MaterializedDay> get trainingDays =>
      days.where((d) => !d.isRest);
  double get plannedKm =>
      days.fold(0.0, (s, d) => s + d.plannedKm);
  int get qualityCount =>
      days.where((d) => d.slot.isQuality).length;
  bool get hasLongRun => days.any((d) => d.slot.isLongRun);

  MaterializedWeek copyWith({
    TrainingPhase? phase,
    double? targetKm,
    bool? isCutback,
    bool? isFrozen,
    List<MaterializedDay>? days,
  }) => MaterializedWeek(
    weekNumber: weekNumber,
    phase: phase ?? this.phase,
    targetKm: targetKm ?? this.targetKm,
    isCutback: isCutback ?? this.isCutback,
    isFrozen: isFrozen ?? this.isFrozen,
    days: days ?? this.days,
  );

  Map<String, dynamic> toJson() => {
    'weekNumber': weekNumber,
    'phase': phase.name,
    'targetKm': targetKm,
    'isCutback': isCutback,
    'isFrozen': isFrozen,
    'days': days.map((d) => d.toJson()).toList(),
  };

  factory MaterializedWeek.fromJson(Map<String, dynamic> j) => MaterializedWeek(
    weekNumber: (j['weekNumber'] as num).toInt(),
    phase: TrainingPhase.values.firstWhere(
      (e) => e.name == j['phase'],
      orElse: () => TrainingPhase.base,
    ),
    targetKm: (j['targetKm'] as num).toDouble(),
    isCutback: j['isCutback'] as bool? ?? false,
    isFrozen: j['isFrozen'] as bool? ?? false,
    days: (j['days'] as List)
        .map((e) => MaterializedDay.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class MaterializedPlan {
  /// Schema version of this payload — bump on any breaking shape change.
  static const int schemaVersion = 1;

  final String planId;
  final DateTime builtAt;

  /// vDOT the paces were baked from.
  final int builtFromVdot;

  /// Hash of the inputs the plan was built from (race, date, days, long-run
  /// day, experience, goal time). A mismatch on load ⇒ the plan is stale ⇒
  /// re-materialise.
  final String inputsFingerprint;

  final List<MaterializedWeek> weeks;

  /// Ladder index per intent after the last materialised week.
  final Map<String, int> ladderState;

  /// Consecutive weeks per intent on the current ladder rung.
  final Map<String, int> sessionProgress;

  /// Append-only receipt of every adaptation the closed-loop engine has applied
  /// (missed-session shifts, volume scaling, pace recalibration). Surfaced in
  /// the "how we built your plan" / plan-overview UI.
  final List<AdaptationLogEntry> adaptationLog;

  const MaterializedPlan({
    required this.planId,
    required this.builtAt,
    required this.builtFromVdot,
    required this.inputsFingerprint,
    required this.weeks,
    this.ladderState = const {},
    this.sessionProgress = const {},
    this.adaptationLog = const [],
  });

  MaterializedWeek? weekByNumber(int n) {
    for (final w in weeks) {
      if (w.weekNumber == n) return w;
    }
    return null;
  }

  int get totalWeeks => weeks.length;

  /// The week + day at [weekNumber] / [weekdayIndex] (0 = Monday … 6 = Sunday),
  /// bundled for a caller that just wants "today". Null when the week is not in
  /// the plan or the day is missing. Pure — no I/O.
  MaterializedDayContext? contextForWeekday({
    required int weekNumber,
    required int weekdayIndex,
  }) {
    final week = weekByNumber(weekNumber);
    if (week == null) return null;
    for (final d in week.days) {
      if (d.weekday == weekdayIndex) {
        return MaterializedDayContext(plan: this, week: week, day: d);
      }
    }
    return null;
  }

  MaterializedPlan copyWith({
    List<MaterializedWeek>? weeks,
    DateTime? builtAt,
    int? builtFromVdot,
    String? inputsFingerprint,
    Map<String, int>? ladderState,
    Map<String, int>? sessionProgress,
    List<AdaptationLogEntry>? adaptationLog,
  }) => MaterializedPlan(
    planId: planId,
    builtAt: builtAt ?? this.builtAt,
    builtFromVdot: builtFromVdot ?? this.builtFromVdot,
    inputsFingerprint: inputsFingerprint ?? this.inputsFingerprint,
    weeks: weeks ?? this.weeks,
    ladderState: ladderState ?? this.ladderState,
    sessionProgress: sessionProgress ?? this.sessionProgress,
    adaptationLog: adaptationLog ?? this.adaptationLog,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'planId': planId,
    'builtAt': builtAt.toIso8601String(),
    'builtFromVdot': builtFromVdot,
    'inputsFingerprint': inputsFingerprint,
    'ladderState': ladderState,
    'sessionProgress': sessionProgress,
    if (adaptationLog.isNotEmpty)
      'adaptationLog': adaptationLog.map((e) => e.toJson()).toList(),
    'weeks': weeks.map((w) => w.toJson()).toList(),
  };

  factory MaterializedPlan.fromJson(Map<String, dynamic> j) => MaterializedPlan(
    planId: j['planId'] as String,
    builtAt: DateTime.parse(j['builtAt'] as String),
    builtFromVdot: (j['builtFromVdot'] as num).toInt(),
    inputsFingerprint: j['inputsFingerprint'] as String,
    ladderState: _intMap(j['ladderState']),
    sessionProgress: _intMap(j['sessionProgress']),
    adaptationLog: (j['adaptationLog'] as List?)
            ?.map((e) => AdaptationLogEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    weeks: (j['weeks'] as List)
        .map((e) => MaterializedWeek.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  static Map<String, int> _intMap(dynamic raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k as String, (v as num).toInt()));
  }
}

/// A single training day resolved against its parent week + plan — what the
/// Coach tab reads for "Today's Workout". Produced by
/// [MaterializedPlan.contextForWeekday] / [PlanStore.getTodayDayContext].
class MaterializedDayContext {
  final MaterializedPlan plan;
  final MaterializedWeek week;
  final MaterializedDay day;

  const MaterializedDayContext({
    required this.plan,
    required this.week,
    required this.day,
  });

  /// True when there is nothing to run today (explicit rest slot, or a slot
  /// with no resolved workout).
  bool get isRest => day.isRest || day.workout == null;

  /// Effective weekly volume for this week (post cutback / taper).
  double get weeklyTargetKm => week.targetKm;

  /// Whether the athlete has already logged a run against today.
  bool get isCompleted => day.isCompleted;
}

/// One line of the adaptation receipt — what the closed-loop engine changed and
/// why. Pure data.
class AdaptationLogEntry {
  final DateTime at;

  /// Machine key, e.g. `missed_key_shifted`, `volume_shortfall_scaled`,
  /// `missed_long_dropped_taper`, `pace_recalibrated`.
  final String reason;

  /// Human-readable one-liner for the receipt UI.
  final String summary;

  /// Plan week the change landed in (0 when plan-wide, e.g. pace recal).
  final int weekNumber;

  const AdaptationLogEntry({
    required this.at,
    required this.reason,
    required this.summary,
    this.weekNumber = 0,
  });

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'reason': reason,
    'summary': summary,
    if (weekNumber != 0) 'weekNumber': weekNumber,
  };

  factory AdaptationLogEntry.fromJson(Map<String, dynamic> j) =>
      AdaptationLogEntry(
        at: DateTime.parse(j['at'] as String),
        reason: j['reason'] as String,
        summary: j['summary'] as String,
        weekNumber: (j['weekNumber'] as num?)?.toInt() ?? 0,
      );
}
