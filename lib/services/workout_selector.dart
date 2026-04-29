import '../models/coaching_types.dart';
import '../models/training_phase.dart';
import '../models/workout_type.dart';
import '../models/workout_sequence.dart';
import '../engines/planner/weekly_budget.dart';
import '../engines/planner/absence_detector.dart';
import '../engines/memory/engine_memory.dart' show RpeEntry;

export '../models/coaching_types.dart';

enum WorkoutId {
  easyRun,
  easyStrides,
  tempoRun,
  intervalWorkout,
  longEasy,
  recoveryRun,
  restDay,
}

enum _FatigueDecision { none, downgrade, recovery }

class WorkoutSelector {
  static const double _minimumLongRunCapKm = 6.0;

  WorkoutId selectWorkout({
    required Readiness readiness,
    required WorkoutId? lastWorkoutType,
    required int daysSinceLastQuality,
    required double weeklyVolume,
    RunAnalysis? fatigueAnalysis,
    required int daysSinceLastLongRun,
    required double? lastLongRunDistance,
    required double? proposedLongRunDistance,
    String goalRace = 'fitness',
    WorkoutType? lastCompletedType,
    DateTime? lastRunDate,
    WorkoutType? lastNonRecoveryType,
    TrainingPhase phase = TrainingPhase.base,
    List<RpeEntry> recentRpeEntries = const [],
    WeeklyBudget? budget,
    AbsenceResult? absence,
    List<int> trainingDayIndices = const [],
    WorkoutId? plannedWorkoutId,
  }) {
    if (plannedWorkoutId == null && trainingDayIndices.isNotEmpty) {
      final todayIdx = DateTime.now().weekday - 1;
      if (!trainingDayIndices.contains(todayIdx)) {
        return WorkoutId.restDay;
      }
    }

    final analysis = fatigueAnalysis ?? const RunAnalysis();
    final fatigueDecision = _resolveFatigueDecision(analysis);

    if (absence != null && absence.forceEasyReturn) {
      return WorkoutId.easyRun;
    }

    if (readiness == Readiness.red) return WorkoutId.recoveryRun;
    final highRpeOverride = _postHighRpeOverride(
      recentRpeEntries,
      readiness: readiness,
    );
    if (highRpeOverride != null) return highRpeOverride;
    if (fatigueDecision == _FatigueDecision.recovery) {
      return WorkoutId.recoveryRun;
    }

    final lastType = lastCompletedType ?? _toWorkoutType(lastWorkoutType);
    final nextSequenceType = WorkoutSequence.next(last: lastType);
    final backToBackHardOverride = _preventBackToBackHardRun(
      workoutId: plannedWorkoutId ?? _toWorkoutId(nextSequenceType),
      readiness: readiness,
      lastCompletedType: lastType,
      lastRunDate: lastRunDate,
    );
    if (backToBackHardOverride != null) {
      return backToBackHardOverride;
    }

    final effectiveType = plannedWorkoutId != null
        ? (_toWorkoutType(plannedWorkoutId) ?? WorkoutType.easy)
        : nextSequenceType;
    if (budget != null && budget.volumeGateFired && effectiveType.isHard) {
      return WorkoutId.easyRun;
    }

    if (plannedWorkoutId != null) {
      return plannedWorkoutId;
    }

    if (budget != null) {
      if (nextSequenceType == WorkoutType.quality && budget.qualityExhausted) {
        return _resolveEasySlot(readiness: readiness, lastType: lastType);
      }
      if (nextSequenceType == WorkoutType.long && budget.longRunDone) {
        return _resolveEasySlot(readiness: readiness, lastType: lastType);
      }
      if (budget.daysRemaining <= 1 &&
          !budget.longRunDone &&
          budget.longRunPlanned &&
          !budget.qualityExhausted) {
        final priorityWorkout = _pickPrioritySession(goalRace, phase);
        return _preventBackToBackHardRun(
              workoutId: priorityWorkout,
              readiness: readiness,
              lastCompletedType: lastType,
              lastRunDate: lastRunDate,
            ) ??
            priorityWorkout;
      }
    }

    if (nextSequenceType == WorkoutType.long) {
      final longRunOk = _longRunEligible(
        daysSinceLastLongRun: daysSinceLastLongRun,
        analysis: analysis,
        readiness: readiness,
        weeklyVolume: weeklyVolume,
        lastLongRunDistance: lastLongRunDistance,
        proposedLongRunDistance: proposedLongRunDistance,
        goalRace: goalRace,
      );
      if (!longRunOk) return WorkoutId.easyRun;
      return _applyFatigueAdjustment(WorkoutId.longEasy, fatigueDecision);
    }

    if (nextSequenceType == WorkoutType.quality) {
      final workout = _resolveQualitySlot(
        phase: phase,
        readiness: readiness,
        daysSinceLastQuality: daysSinceLastQuality,
        lastNonRecoveryType: lastNonRecoveryType,
        goalRace: goalRace,
      );
      return _applyFatigueAdjustment(workout, fatigueDecision);
    }

    if (nextSequenceType == WorkoutType.easy) {
      final workout = _resolveEasySlot(readiness: readiness, lastType: lastType);
      return _applyFatigueAdjustment(workout, fatigueDecision);
    }

    return WorkoutId.easyRun;
  }

  WorkoutId _pickPrioritySession(String goalRace, TrainingPhase phase) {
    if (goalRace == 'half_marathon' || goalRace == 'marathon') {
      return WorkoutId.longEasy;
    }
    return WorkoutId.tempoRun;
  }

  WorkoutId? _preventBackToBackHardRun({
    required WorkoutId workoutId,
    required Readiness readiness,
    required WorkoutType? lastCompletedType,
    required DateTime? lastRunDate,
    DateTime? now,
  }) {
    if (!_isHardWorkoutId(workoutId)) return null;
    if (lastCompletedType == null || !lastCompletedType.isQuality) return null;
    if (!_wasRunYesterday(lastRunDate, now: now)) return null;
    return readiness == Readiness.green
        ? WorkoutId.easyRun
        : WorkoutId.recoveryRun;
  }

  bool _isHardWorkoutId(WorkoutId workoutId) {
    return workoutId == WorkoutId.tempoRun ||
        workoutId == WorkoutId.intervalWorkout ||
        workoutId == WorkoutId.longEasy;
  }

  bool _wasRunYesterday(DateTime? lastRunDate, {DateTime? now}) {
    if (lastRunDate == null) return false;
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final lastDay = DateTime(
      lastRunDate.year,
      lastRunDate.month,
      lastRunDate.day,
    );
    return today.difference(lastDay).inDays == 1;
  }

  WorkoutId? _postHighRpeOverride(
    List<RpeEntry> rpeEntries, {
    required Readiness readiness,
    int threshold = 8,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final recentHighEntries = List<RpeEntry>.from(rpeEntries)
      ..sort((a, b) => b.date.compareTo(a.date));

    final latestHigh = recentHighEntries.firstWhere(
      (entry) => entry.value >= threshold,
      orElse: () => RpeEntry(value: 0, date: DateTime(1970)),
    );
    if (latestHigh.value < threshold) return null;

    final highRpeDay = DateTime(
      latestHigh.date.year,
      latestHigh.date.month,
      latestHigh.date.day,
    );
    final daysSinceHighRpe = today.difference(highRpeDay).inDays;

    if (daysSinceHighRpe < 0) return null;
    if (daysSinceHighRpe <= 1) return WorkoutId.recoveryRun;
    if (daysSinceHighRpe == 2) {
      return readiness == Readiness.green
          ? WorkoutId.easyRun
          : WorkoutId.recoveryRun;
    }
    return null;
  }

  _FatigueDecision _resolveFatigueDecision(RunAnalysis analysis) {
    if (analysis.lastEasyRunTooHard) {
      return _FatigueDecision.downgrade;
    }

    final rpeRising = analysis.recentRpeTrend == RecentRpeTrend.increasing;
    final elevatedRpe = (analysis.avgRpe ?? 0.0) >= 6.5;

    if (rpeRising && elevatedRpe) {
      return _FatigueDecision.downgrade;
    }

    return _FatigueDecision.none;
  }

  WorkoutId _applyFatigueAdjustment(
    WorkoutId workoutId,
    _FatigueDecision decision,
  ) {
    switch (decision) {
      case _FatigueDecision.recovery:
        return WorkoutId.recoveryRun;
      case _FatigueDecision.downgrade:
        return switch (workoutId) {
          WorkoutId.tempoRun ||
          WorkoutId.intervalWorkout ||
          WorkoutId.longEasy ||
          WorkoutId.easyStrides =>
            WorkoutId.easyRun,
          _ => workoutId,
        };
      case _FatigueDecision.none:
        return workoutId;
    }
  }

  WorkoutId _resolveQualitySlot({
    required TrainingPhase phase,
    required Readiness readiness,
    required int daysSinceLastQuality,
    required WorkoutType? lastNonRecoveryType,
    required String goalRace,
  }) {
    if (!phase.allowsQualitySessions) {
      return readiness == Readiness.yellow
          ? WorkoutId.easyStrides
          : WorkoutId.easyRun;
    }

    if (readiness == Readiness.yellow) return WorkoutId.easyStrides;
    if (daysSinceLastQuality < 2) return WorkoutId.easyRun;

    if (phase == TrainingPhase.peak) {
      if (lastNonRecoveryType == WorkoutType.tempo) {
        return WorkoutId.intervalWorkout;
      }
      return WorkoutId.tempoRun;
    }

    if (lastNonRecoveryType == WorkoutType.tempo) {
      return WorkoutId.intervalWorkout;
    }
    return switch (goalRace) {
      '5k' || '10k' => WorkoutId.intervalWorkout,
      _ => WorkoutId.tempoRun,
    };
  }

  WorkoutId _resolveEasySlot({
    required Readiness readiness,
    required WorkoutType? lastType,
  }) {
    if (readiness == Readiness.green &&
        (lastType == WorkoutType.tempo || lastType == WorkoutType.interval)) {
      return WorkoutId.easyStrides;
    }
    return WorkoutId.easyRun;
  }

  bool _longRunEligible({
    required int daysSinceLastLongRun,
    required RunAnalysis analysis,
    required Readiness readiness,
    required double weeklyVolume,
    required double? lastLongRunDistance,
    required double? proposedLongRunDistance,
    required String goalRace,
  }) {
    final threshold = _longRunThreshold(goalRace);
    if (daysSinceLastLongRun < threshold) return false;
    if (readiness == Readiness.red) return false;
    if (weeklyVolume < 8.0) return false;

    final rpeRising = analysis.recentRpeTrend == RecentRpeTrend.increasing;
    final elevatedRpe = (analysis.avgRpe ?? 0.0) >= 6.5;
    if (rpeRising && elevatedRpe) return false;

    if (proposedLongRunDistance != null) {
      final cap = _longRunVolumeCap(weeklyVolume);
      if (proposedLongRunDistance > cap) return false;
    }

    if (lastLongRunDistance != null && proposedLongRunDistance != null) {
      if (proposedLongRunDistance > lastLongRunDistance * 1.10) return false;
    }

    return true;
  }

  double _longRunVolumeCap(double weeklyVolume) {
    return (weeklyVolume * 0.30) > _minimumLongRunCapKm
        ? weeklyVolume * 0.30
        : _minimumLongRunCapKm;
  }

  int _longRunThreshold(String goalRace) => switch (goalRace) {
        'marathon' => 5,
        'half_marathon' => 6,
        _ => 7,
      };

  WorkoutType? _toWorkoutType(WorkoutId? id) {
    if (id == null) return null;
    return switch (id) {
      WorkoutId.easyRun || WorkoutId.easyStrides => WorkoutType.easy,
      WorkoutId.tempoRun => WorkoutType.tempo,
      WorkoutId.intervalWorkout => WorkoutType.interval,
      WorkoutId.longEasy => WorkoutType.long,
      WorkoutId.recoveryRun => WorkoutType.recovery,
      WorkoutId.restDay => WorkoutType.rest,
    };
  }

  WorkoutId _toWorkoutId(WorkoutType workoutType) {
    return switch (workoutType) {
      WorkoutType.easy || WorkoutType.quality => WorkoutId.easyRun,
      WorkoutType.tempo => WorkoutId.tempoRun,
      WorkoutType.interval => WorkoutId.intervalWorkout,
      WorkoutType.long => WorkoutId.longEasy,
      WorkoutType.recovery => WorkoutId.recoveryRun,
      WorkoutType.rest => WorkoutId.restDay,
    };
  }
}
