import '../../models/workout_type.dart';
import '../../models/training_phase.dart';
import '../../models/weekly_plan.dart';
import '../../models/race_plan.dart';
import '../config/workout_template_library.dart';
import '../core/vdot_calculator.dart';

EngineMemory defaultSafeMemory() => const EngineMemory();

List<RpeEntry> parseRpeList(dynamic data) {
  if (data is! List) return [];

  return data.map((entry) {
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
  }).whereType<RpeEntry>().toList();
}

class RpeEntry {
  final int value;
  final DateTime date;

  const RpeEntry({
    required this.value,
    required this.date,
  });

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

  /// Schema version — bumped from 2→3 when vDOT replaced criticalSpeed.
  static const int _schemaVersion = 3;

  final int vdotScore;
  final bool vdotIsProvisional;
  final WorkoutType lastCompletedType;
  final WorkoutType? lastNonRecoveryType;
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

  String get lastWorkoutType => lastCompletedType.name;

  const EngineMemory({
    this.vdotScore = 40,
    this.vdotIsProvisional = true,
    this.lastCompletedType = WorkoutType.easy,
    this.lastNonRecoveryType,
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
  });

  bool get hasRacePlan => racePlan != null;

  bool get isExploreMode => racePlan == null;

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
        .where((entry) =>
            reference.difference(entry.date).inHours <= withinDays * 24)
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
        'lastCompletedType': lastCompletedType.name,
        'lastNonRecoveryType': lastNonRecoveryType?.name,
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
      };

  factory EngineMemory.fromJson(Map<String, dynamic> json) {
    try {
      List<String> parseStringList(dynamic raw) {
        if (raw is! List) return [];
        return raw.whereType<String>().toList();
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

      // ── Schema migration: criticalSpeed → vdotScore ──────────────────────
      int parsedVdot;
      bool parsedProvisional;

      if (!json.containsKey('vdotScore') && json.containsKey('criticalSpeed')) {
        final storedCs = (json['criticalSpeed'] as num?)?.toDouble() ?? 4.0;
        final easyPaceEstimate = storedCs > 0
            ? (1000 / storedCs) * 1.2
            : 360.0;
        parsedVdot = vdotFromEasyPace(easyPaceEstimate).clamp(30, 85);
        parsedProvisional = true;
      } else {
        parsedVdot = (json['vdotScore'] as num?)?.toInt() ?? 40;
        parsedProvisional = (json['vdotIsProvisional'] as bool?) ?? true;
      }

      final totalRuns = (json['totalRunsCompleted'] as num?)?.toInt() ?? 0;
      final firstRunDate = DateTime.tryParse('${json['firstRunDate'] ?? ''}');
      final lastRunDate = DateTime.tryParse('${json['lastRunDate'] ?? ''}');

      // Use calendar-based week if firstRunDate is available, otherwise fall back.
      final currentWeek = firstRunDate != null
          ? PhaseEngine.weekNumberFromDate(firstRunDate)
          : PhaseEngine.weekNumber(totalRuns);

      return EngineMemory(
        vdotScore: parsedVdot.clamp(30, 85),
        vdotIsProvisional: parsedProvisional,
        lastCompletedType: WorkoutTypeX.fromString(
          (json['lastCompletedType'] as String?) ?? 'easy',
        ),
        lastNonRecoveryType: json['lastNonRecoveryType'] is String
            ? WorkoutTypeX.fromString(json['lastNonRecoveryType'] as String)
            : null,
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
        lastCompletedWorkoutIntent:
            parseWorkoutIntent(json['lastCompletedWorkoutIntent']),
        plannedIntentPreviewLabel:
            json['plannedIntentPreviewLabel'] as String?,
        recentTemplateIds: parseStringList(json['recentTemplateIds']),
      );
    } catch (_) {
      return defaultSafeMemory();
    }
  }

  EngineMemory copyWith({
    int? vdotScore,
    bool? vdotIsProvisional,
    WorkoutType? lastCompletedType,
    WorkoutType? lastNonRecoveryType,
    bool clearLastNonRecovery = false,
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
  }) {
    final newTotalRuns = totalRunsCompleted ?? this.totalRunsCompleted;
    final newFirstRunDate = firstRunDate ?? this.firstRunDate;

    // Calendar-based if firstRunDate exists, otherwise fall back to run count.
    final newCurrentWeek = currentWeek ??
        (newFirstRunDate != null
            ? PhaseEngine.weekNumberFromDate(newFirstRunDate)
            : PhaseEngine.weekNumber(newTotalRuns));

    return EngineMemory(
      vdotScore: vdotScore ?? this.vdotScore,
      vdotIsProvisional: vdotIsProvisional ?? this.vdotIsProvisional,
      lastCompletedType: lastCompletedType ?? this.lastCompletedType,
      lastNonRecoveryType: clearLastNonRecovery
          ? null
          : (lastNonRecoveryType ?? this.lastNonRecoveryType),
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
    );
  }
}