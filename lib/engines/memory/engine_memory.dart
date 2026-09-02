import '../../models/workout_type.dart';
import '../../models/training_phase.dart';
import '../../models/weekly_plan.dart';
import '../../models/race_plan.dart';
import '../config/workout_template_library.dart';
import '../core/vdot_calculator.dart';
import '../progression_decision.dart';

EngineMemory defaultSafeMemory() => const EngineMemory();

List<RpeEntry> parseRpeList(dynamic data) {
  if (data is! List) return [];

  return data
      .map((entry) {
        if (entry is int) {
          return RpeEntry(value: entry, date: DateTime.now());
        } else if (entry is Map) {
          final map = Map<String, dynamic>.from(entry);
          return RpeEntry(
            value: (map['value'] as num?)?.toInt() ?? 0,
            date: DateTime.tryParse('${map['date'] ?? ''}') ?? DateTime.now(),
          );
        } else {
          return null;
        }
      })
      .whereType<RpeEntry>()
      .toList();
}

class RpeEntry {
  final int value;
  final DateTime date;

  const RpeEntry({required this.value, required this.date});

  Map<String, dynamic> toJson() => {
    'value': value,
    'date': date.toIso8601String(),
  };

  factory RpeEntry.fromJson(Map<String, dynamic> json) {
    return RpeEntry(
      value: (json['value'] as num?)?.toInt() ?? 0,
      date: DateTime.tryParse('${json['date'] ?? ''}') ?? DateTime.now(),
    );
  }
}

class EngineMemory {
  static const int maxRecentTemplateIds = 14;

  /// Schema version — bumped to 8 for vdotAtPlanStart drift anchor.
  static const int _schemaVersion = 9;

  final int vdotScore;
  final bool vdotIsProvisional;

  /// vDOT snapshotted whenever a new race plan is saved. Anchors the
  /// per-plan drift cap in EngineRuntime so weekly nudges can't compound
  /// into an unrealistic score over the life of one plan.
  final int? vdotAtPlanStart;
  final WorkoutType lastCompletedType;
  final List<RpeEntry> recentRpeEntries;
  final int totalRunsCompleted;
  final TrainingPhase currentPhase;
  final int currentWeek;
  final WeeklyPlan? activePlan;
  final RacePlan? racePlan;
  final DateTime? firstRunDate;
  final DateTime? lastRunDate;
  final double? lastReadinessScore;
  final String? lastCompletedTemplateId;
  final WorkoutIntent? plannedIntent;
  final WorkoutIntent? lastCompletedWorkoutIntent;
  final String? plannedIntentPreviewLabel;
  final List<String> recentTemplateIds;
  final ProgressionDecision? weeklyProgressionDecision;
  final DateTime? lastProgressionEvaluationDate;
  final int pendingVdotNudge;
  final int? longRunDayIndex;

  // ── Weekly mileage system (schema v4) ────────────────────────────────────
  final double? baselineWeeklyKm;
  final double? previousWeekTargetKm;

  // ── Post-plan flow (schema v5) ────────────────────────────────────────────
  final DateTime? planCompletedAt;
  final bool isInMaintenance;

  // ── Weekly completion tracking (schema v6) ───────────────────────────────
  /// Total km actually logged this week (reset each Monday).
  final double weeklyCompletedKm;

  /// Total km planned for this week from WeekResolver slots (set at week start).
  final double weeklyPlannedKm;

  /// Number of pre-run readiness downgrades this week (yellow/red pre-checks).
  final int weeklyDowngradeCount;

  // ── Workout ladder positions (schema v7) ─────────────────────────────────
  /// Current rung index for each intent ladder, keyed by intent name.
  /// e.g. {'threshold': 1, 'vo2max': 0, 'raceSpecific': 0}
  /// Index 0 = bottom rung (easiest). Progresses/regresses with weekly signals.
  final Map<String, int> ladderPositions;

  // ── Materialised plan (schema v9) ────────────────────────────────────────
  /// Consecutive weeks spent on the current ladder rung, per intent name.
  /// Drives session-level progression (a rung's workout gets harder each week
  /// until it maxes out, then the rung advances).
  final Map<String, int> sessionProgress;

  /// planId of the MaterializedPlan in PlanStore that backs this coaching
  /// state. Null before the first materialisation.
  final String? materializedPlanId;

  String get lastWorkoutType => lastCompletedType.name;

  const EngineMemory({
    this.vdotScore = 40,
    this.vdotIsProvisional = true,
    this.vdotAtPlanStart,
    this.lastCompletedType = WorkoutType.easy,
    this.recentRpeEntries = const [],
    this.totalRunsCompleted = 0,
    this.currentPhase = TrainingPhase.base,
    this.currentWeek = 1,
    this.activePlan,
    this.racePlan,
    this.firstRunDate,
    this.lastRunDate,
    this.lastReadinessScore,
    this.lastCompletedTemplateId,
    this.plannedIntent,
    this.lastCompletedWorkoutIntent,
    this.plannedIntentPreviewLabel,
    this.recentTemplateIds = const [],
    this.weeklyProgressionDecision,
    this.lastProgressionEvaluationDate,
    this.pendingVdotNudge = 0,
    this.longRunDayIndex,
    this.baselineWeeklyKm,
    this.previousWeekTargetKm,
    this.planCompletedAt,
    this.isInMaintenance = false,
    // v6
    this.weeklyCompletedKm = 0.0,
    this.weeklyPlannedKm = 0.0,
    this.weeklyDowngradeCount = 0,
    // v7
    this.ladderPositions = const {},
    // v9
    this.sessionProgress = const {},
    this.materializedPlanId,
  });

  bool get hasRacePlan => racePlan != null;

  bool get isExploreMode => racePlan == null;

  bool get isPlanComplete => planCompletedAt != null;

  int? get daysSincePlanCompletion {
    if (planCompletedAt == null) return null;
    return DateTime.now().difference(planCompletedAt!).inDays;
  }

  bool get shouldAutoEnterMaintenance {
    final days = daysSincePlanCompletion;
    return days != null && days >= 7 && !isInMaintenance;
  }

  /// Completion rate for this week: completedKm / plannedKm.
  /// Returns null if plannedKm is 0 (no data yet).
  double? get weeklyCompletionRate {
    if (weeklyPlannedKm <= 0) return null;
    return weeklyCompletedKm / weeklyPlannedKm;
  }

  /// Returns the current ladder index for [intent], defaulting to 0.
  int ladderIndexFor(WorkoutIntent intent) => ladderPositions[intent.name] ?? 0;

  /// Returns a new [ladderPositions] map with [intent] moved up one rung,
  /// clamped to [maxIndex].
  Map<String, int> advanceLadder(WorkoutIntent intent, int maxIndex) {
    final updated = Map<String, int>.from(ladderPositions);
    updated[intent.name] = (ladderIndexFor(intent) + 1).clamp(0, maxIndex);
    return updated;
  }

  /// Returns a new [ladderPositions] map with [intent] moved down one rung,
  /// clamped to 0.
  Map<String, int> regressionLadder(WorkoutIntent intent) {
    final updated = Map<String, int>.from(ladderPositions);
    updated[intent.name] = (ladderIndexFor(intent) - 1).clamp(0, 99);
    return updated;
  }

  double? averageRecentRpe([int n = 3]) {
    if (recentRpeEntries.isEmpty) return null;
    final slice = _sortedRecentRpeEntries().take(n).toList();
    return slice.map((entry) => entry.value).reduce((a, b) => a + b) /
        slice.length;
  }

  bool hasHighRpe({
    int n = 2,
    int threshold = 8,
    int withinDays = 3,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    return _sortedRecentRpeEntries()
        .where(
          (entry) =>
              reference.difference(entry.date).inHours <= withinDays * 24,
        )
        .take(n)
        .any((entry) => entry.value >= threshold);
  }

  List<RpeEntry> _sortedRecentRpeEntries() {
    final entries = List<RpeEntry>.from(recentRpeEntries);
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  List<String> appendTemplateId(String templateId) {
    final updated = [templateId, ...recentTemplateIds];
    if (updated.length > maxRecentTemplateIds) {
      return updated.sublist(0, maxRecentTemplateIds);
    }
    return updated;
  }

  Map<String, dynamic> toJson() => {
    '_schemaVersion': _schemaVersion,
    'vdotScore': vdotScore,
    'vdotIsProvisional': vdotIsProvisional,
    'vdotAtPlanStart': vdotAtPlanStart,
    'lastCompletedType': lastCompletedType.name,
    'recentRpeValues': recentRpeEntries.map((e) => e.toJson()).toList(),
    'totalRunsCompleted': totalRunsCompleted,
    'currentPhase': currentPhase.name,
    'currentWeek': currentWeek,
    'activePlan': activePlan?.toJson(),
    'racePlan': racePlan?.toJson(),
    'firstRunDate': firstRunDate?.toIso8601String(),
    'lastRunDate': lastRunDate?.toIso8601String(),
    'lastReadinessScore': lastReadinessScore,
    'lastCompletedTemplateId': lastCompletedTemplateId,
    'plannedIntent': plannedIntent?.name,
    'lastCompletedWorkoutIntent': lastCompletedWorkoutIntent?.name,
    'plannedIntentPreviewLabel': plannedIntentPreviewLabel,
    'recentTemplateIds': recentTemplateIds,
    'weeklyProgressionDecision': weeklyProgressionDecision?.name,
    'lastProgressionEvaluationDate': lastProgressionEvaluationDate
        ?.toIso8601String(),
    'pendingVdotNudge': pendingVdotNudge,
    'longRunDayIndex': longRunDayIndex,
    'baselineWeeklyKm': baselineWeeklyKm,
    'previousWeekTargetKm': previousWeekTargetKm,
    // v5
    'planCompletedAt': planCompletedAt?.toIso8601String(),
    'isInMaintenance': isInMaintenance,
    // v6
    'weeklyCompletedKm': weeklyCompletedKm,
    'weeklyPlannedKm': weeklyPlannedKm,
    'weeklyDowngradeCount': weeklyDowngradeCount,
    // v7
    'ladderPositions': ladderPositions,
    // v9
    'sessionProgress': sessionProgress,
    'materializedPlanId': materializedPlanId,
  };

  factory EngineMemory.fromJson(Map<String, dynamic> json) {
    try {
      List<String> parseStringList(dynamic raw) {
        if (raw is! List) return [];
        return raw.whereType<String>().toList();
      }

      Map<String, int> parseLadderPositions(dynamic raw) {
        if (raw is! Map) return {};
        return raw.map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
        );
      }

      TrainingPhase parsePhase(dynamic raw) {
        if (raw is! String) return TrainingPhase.base;
        return TrainingPhase.values.firstWhere(
          (p) => p.name == raw,
          orElse: () => TrainingPhase.base,
        );
      }

      WeeklyPlan? parseWeeklyPlan(dynamic raw) {
        if (raw is! Map) return null;
        try {
          return WeeklyPlan.fromJson(Map<String, dynamic>.from(raw));
        } catch (_) {
          return null;
        }
      }

      RacePlan? parseRacePlan(dynamic raw) {
        if (raw is! Map) return null;
        try {
          return RacePlan.fromJson(Map<String, dynamic>.from(raw));
        } catch (_) {
          return null;
        }
      }

      WorkoutIntent? parseWorkoutIntent(dynamic raw) {
        if (raw is! String) return null;
        try {
          return WorkoutIntent.values.firstWhere((e) => e.name == raw);
        } catch (_) {
          return null;
        }
      }

      ProgressionDecision? parseProgressionDecision(dynamic raw) {
        if (raw is! String) return null;
        try {
          return ProgressionDecision.values.firstWhere(
            (e) => e.name == raw,
            orElse: () => ProgressionDecision.hold,
          );
        } catch (_) {
          return null;
        }
      }

      // ── Schema migration: criticalSpeed → vdotScore ──────────────────────
      int parsedVdot;
      bool parsedProvisional;

      if (!json.containsKey('vdotScore') && json.containsKey('criticalSpeed')) {
        final storedCs = (json['criticalSpeed'] as num?)?.toDouble() ?? 4.0;
        final easyPaceEstimate = storedCs > 0 ? (1000 / storedCs) * 1.2 : 360.0;
        parsedVdot = vdotFromEasyPace(easyPaceEstimate).clamp(30, 85);
        parsedProvisional = true;
      } else {
        parsedVdot = (json['vdotScore'] as num?)?.toInt() ?? 40;
        parsedProvisional = (json['vdotIsProvisional'] as bool?) ?? true;
      }

      final totalRuns = (json['totalRunsCompleted'] as num?)?.toInt() ?? 0;
      final firstRunDate = DateTime.tryParse('${json['firstRunDate'] ?? ''}');
      final lastRunDate = DateTime.tryParse('${json['lastRunDate'] ?? ''}');

      final currentWeek = firstRunDate != null
          ? PhaseEngine.weekNumberFromDate(firstRunDate)
          : PhaseEngine.weekNumber(totalRuns);

      return EngineMemory(
        vdotScore: parsedVdot.clamp(30, 85),
        vdotIsProvisional: parsedProvisional,
        vdotAtPlanStart: (json['vdotAtPlanStart'] as num?)?.toInt(),
        lastCompletedType: WorkoutTypeX.fromString(
          (json['lastCompletedType'] as String?) ?? 'easy',
        ),
        recentRpeEntries: parseRpeList(json['recentRpeValues']),
        totalRunsCompleted: totalRuns,
        currentPhase: parsePhase(json['currentPhase']),
        currentWeek: currentWeek,
        activePlan: parseWeeklyPlan(json['activePlan']),
        racePlan: parseRacePlan(json['racePlan']),
        firstRunDate: firstRunDate,
        lastRunDate: lastRunDate,
        lastReadinessScore: (json['lastReadinessScore'] as num?)?.toDouble(),
        lastCompletedTemplateId: json['lastCompletedTemplateId'] as String?,
        plannedIntent: parseWorkoutIntent(json['plannedIntent']),
        lastCompletedWorkoutIntent: parseWorkoutIntent(
          json['lastCompletedWorkoutIntent'],
        ),
        plannedIntentPreviewLabel: json['plannedIntentPreviewLabel'] as String?,
        recentTemplateIds: parseStringList(json['recentTemplateIds']),
        weeklyProgressionDecision: parseProgressionDecision(
          json['weeklyProgressionDecision'],
        ),
        lastProgressionEvaluationDate: DateTime.tryParse(
          '${json['lastProgressionEvaluationDate'] ?? ''}',
        ),
        pendingVdotNudge: (json['pendingVdotNudge'] as num?)?.toInt() ?? 0,
        longRunDayIndex: (json['longRunDayIndex'] as num?)?.toInt(),
        baselineWeeklyKm: (json['baselineWeeklyKm'] as num?)?.toDouble(),
        previousWeekTargetKm: (json['previousWeekTargetKm'] as num?)
            ?.toDouble(),
        planCompletedAt: DateTime.tryParse('${json['planCompletedAt'] ?? ''}'),
        isInMaintenance: (json['isInMaintenance'] as bool?) ?? false,
        // v6 — null-safe for users migrating from v5
        weeklyCompletedKm:
            (json['weeklyCompletedKm'] as num?)?.toDouble() ?? 0.0,
        weeklyPlannedKm: (json['weeklyPlannedKm'] as num?)?.toDouble() ?? 0.0,
        weeklyDowngradeCount:
            (json['weeklyDowngradeCount'] as num?)?.toInt() ?? 0,
        // v7 — null-safe for users migrating from v6
        ladderPositions: parseLadderPositions(json['ladderPositions']),
        // v9 — null-safe for users migrating from v8
        sessionProgress: parseLadderPositions(json['sessionProgress']),
        materializedPlanId: json['materializedPlanId'] as String?,
      );
    } catch (_) {
      return defaultSafeMemory();
    }
  }

  EngineMemory copyWith({
    int? vdotScore,
    bool? vdotIsProvisional,
    int? vdotAtPlanStart,
    bool clearVdotAtPlanStart = false,
    WorkoutType? lastCompletedType,
    List<RpeEntry>? recentRpeEntries,
    int? totalRunsCompleted,
    TrainingPhase? currentPhase,
    int? currentWeek,
    WeeklyPlan? activePlan,
    bool clearActivePlan = false,
    RacePlan? racePlan,
    bool clearRacePlan = false,
    DateTime? firstRunDate,
    DateTime? lastRunDate,
    double? lastReadinessScore,
    String? lastCompletedTemplateId,
    bool clearLastCompletedTemplateId = false,
    WorkoutIntent? plannedIntent,
    bool clearPlannedIntent = false,
    WorkoutIntent? lastCompletedWorkoutIntent,
    bool clearLastCompletedWorkoutIntent = false,
    String? plannedIntentPreviewLabel,
    bool clearPlannedIntentPreviewLabel = false,
    List<String>? recentTemplateIds,
    ProgressionDecision? weeklyProgressionDecision,
    bool clearWeeklyProgressionDecision = false,
    DateTime? lastProgressionEvaluationDate,
    int? pendingVdotNudge,
    int? longRunDayIndex,
    double? baselineWeeklyKm,
    double? previousWeekTargetKm,
    // v5
    DateTime? planCompletedAt,
    bool clearPlanCompletedAt = false,
    bool? isInMaintenance,
    // v6
    double? weeklyCompletedKm,
    double? weeklyPlannedKm,
    int? weeklyDowngradeCount,
    // v7
    Map<String, int>? ladderPositions,
    // v9
    Map<String, int>? sessionProgress,
    String? materializedPlanId,
    bool clearMaterializedPlanId = false,
  }) {
    final newTotalRuns = totalRunsCompleted ?? this.totalRunsCompleted;
    final newFirstRunDate = firstRunDate ?? this.firstRunDate;

    final newCurrentWeek =
        currentWeek ??
        (newFirstRunDate != null
            ? PhaseEngine.weekNumberFromDate(newFirstRunDate)
            : PhaseEngine.weekNumber(newTotalRuns));

    return EngineMemory(
      vdotScore: vdotScore ?? this.vdotScore,
      vdotIsProvisional: vdotIsProvisional ?? this.vdotIsProvisional,
      vdotAtPlanStart: clearVdotAtPlanStart
          ? null
          : (vdotAtPlanStart ?? this.vdotAtPlanStart),
      lastCompletedType: lastCompletedType ?? this.lastCompletedType,
      recentRpeEntries: recentRpeEntries ?? this.recentRpeEntries,
      totalRunsCompleted: newTotalRuns,
      currentPhase: currentPhase ?? this.currentPhase,
      currentWeek: newCurrentWeek,
      activePlan: clearActivePlan ? null : (activePlan ?? this.activePlan),
      racePlan: clearRacePlan ? null : (racePlan ?? this.racePlan),
      firstRunDate: newFirstRunDate,
      lastRunDate: lastRunDate ?? this.lastRunDate,
      lastReadinessScore: lastReadinessScore ?? this.lastReadinessScore,
      lastCompletedTemplateId: clearLastCompletedTemplateId
          ? null
          : (lastCompletedTemplateId ?? this.lastCompletedTemplateId),
      plannedIntent: clearPlannedIntent
          ? null
          : (plannedIntent ?? this.plannedIntent),
      lastCompletedWorkoutIntent: clearLastCompletedWorkoutIntent
          ? null
          : (lastCompletedWorkoutIntent ?? this.lastCompletedWorkoutIntent),
      plannedIntentPreviewLabel: clearPlannedIntentPreviewLabel
          ? null
          : (plannedIntentPreviewLabel ?? this.plannedIntentPreviewLabel),
      recentTemplateIds: recentTemplateIds ?? this.recentTemplateIds,
      weeklyProgressionDecision: clearWeeklyProgressionDecision
          ? null
          : (weeklyProgressionDecision ?? this.weeklyProgressionDecision),
      lastProgressionEvaluationDate:
          lastProgressionEvaluationDate ?? this.lastProgressionEvaluationDate,
      pendingVdotNudge: pendingVdotNudge ?? this.pendingVdotNudge,
      longRunDayIndex: longRunDayIndex ?? this.longRunDayIndex,
      baselineWeeklyKm: baselineWeeklyKm ?? this.baselineWeeklyKm,
      previousWeekTargetKm: previousWeekTargetKm ?? this.previousWeekTargetKm,
      // v5
      planCompletedAt: clearPlanCompletedAt
          ? null
          : (planCompletedAt ?? this.planCompletedAt),
      isInMaintenance: isInMaintenance ?? this.isInMaintenance,
      // v6
      weeklyCompletedKm: weeklyCompletedKm ?? this.weeklyCompletedKm,
      weeklyPlannedKm: weeklyPlannedKm ?? this.weeklyPlannedKm,
      weeklyDowngradeCount: weeklyDowngradeCount ?? this.weeklyDowngradeCount,
      // v7
      ladderPositions: ladderPositions ?? this.ladderPositions,
      // v9
      sessionProgress: sessionProgress ?? this.sessionProgress,
      materializedPlanId: clearMaterializedPlanId
          ? null
          : (materializedPlanId ?? this.materializedPlanId),
    );
  }
}
