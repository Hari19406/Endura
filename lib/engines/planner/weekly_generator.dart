import '../../models/weekly_plan.dart';
import '../../models/workout_type.dart';
import '../../models/training_phase.dart';
import '../../models/race_plan.dart';
import 'absence_detector.dart';

class WeeklyGenerator {
  /// Legacy hardcoded active days: Mon, Wed, Thu, Sat (used as fallback).
  static const List<int> _fallbackDays = [0, 2, 3, 5];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Generates a weekly plan.
  ///
  /// [trainingDayIndices] overrides the default schedule.
  /// Indices: 0=Monday … 6=Sunday.
  /// When null, falls back to the legacy [0,2,3,5] pattern.
  static WeeklyPlan generate({
    required DateTime startDate,
    WorkoutType lastCompletedType = WorkoutType.easy,
    WorkoutType? lastNonRecoveryType,
    TrainingPhase phase = TrainingPhase.base,
    int totalRunsCompleted = 0,
    List<int>? trainingDayIndices,
  }) {
    final monday = _toMonday(startDate);
    final activeDays = trainingDayIndices != null
        ? (List<int>.from(trainingDayIndices)..sort())
        : _fallbackDays;

    // Build the workout type pattern for the user's chosen days.
    final pattern = _buildPattern(activeDays, phase, lastNonRecoveryType);

    final days = <PlannedDay>[];
    int patternIdx = 0;

    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));

      if (!activeDays.contains(i)) {
        days.add(PlannedDay(
          date: date,
          workoutType: WorkoutType.rest,
          isRestDay: true,
        ));
        continue;
      }

      final workoutType = pattern[patternIdx++];
      days.add(PlannedDay(
        date: date,
        workoutType: workoutType,
        isRestDay: false,
      ));
    }

    return WeeklyPlan(weekStartDate: monday, days: days);
  }

  static double targetFor({
    WeekTarget? raceWeek,
    double? fourWeekAvgKm,
    AbsenceResult? absence,
  }) {
    double base;
    if (raceWeek != null) {
      base = raceWeek.targetKm;
    } else if (fourWeekAvgKm != null && fourWeekAvgKm > 0) {
      base = fourWeekAvgKm;
    } else {
      base = 15.0;
    }

    if (absence != null) {
      base *= absence.volumeFactor;
    }

    return (base * 2).round() / 2;
  }

  // ── Pattern builder ─────────────────────────────────────────────────────────
  //
  // Given the user's sorted training day indices, assigns workout types
  // respecting coaching rules:
  //   • Long run → must have a rest day AFTER it when possible.
  //   • Quality (tempo/interval) → must have a rest day BEFORE it.
  //   • No two hard days (quality/long) on consecutive training days.
  //   • Easy/recovery fills remaining slots.

  static List<WorkoutType> _buildPattern(
    List<int> sortedDays,
    TrainingPhase phase,
    WorkoutType? lastNonRecovery,
  ) {
    final n = sortedDays.length;
    if (n == 0) return [];

    // Start with all easy.
    final result = List<WorkoutType>.filled(n, WorkoutType.easy);

    // ── 1. Place the long run ────────────────────────────────────────────────
    if (n >= 2) {
      // Find the last day that has a rest day after it.
      int longIdx = n - 1; // fallback: last training day
      for (int i = n - 1; i >= 0; i--) {
        if (_hasRestAfter(sortedDays, i)) {
          longIdx = i;
          break;
        }
      }
      result[longIdx] = WorkoutType.long;

      // ── 2. Place quality sessions ──────────────────────────────────────────
      if (phase.allowsQualitySessions) {
        // How many quality sessions this week?
        final targetQ = n <= 4 ? 1 : 2;
        final maxQ = phase.maxQualityPerWeek;
        final qualityCount = targetQ.clamp(0, maxQ);

        var lastNR = lastNonRecovery;
        int placed = 0;

        // First pass: only days with rest before them (ideal).
        for (int i = 0; i < n && placed < qualityCount; i++) {
          if (result[i] != WorkoutType.easy) { continue; }
          if (!_hasRestBefore(sortedDays, i)) { continue; }
          if (_isAdjacentToHard(result, i)) { continue; }

          result[i] = _pickQualityType(lastNR);
          lastNR = result[i];
          placed++;
        }

        // Second pass: relax the "rest before" constraint if still needed.
        for (int i = 0; i < n && placed < qualityCount; i++) {
          if (result[i] != WorkoutType.easy) { continue; }
          if (_isAdjacentToHard(result, i)) { continue; }

          result[i] = _pickQualityType(lastNR);
          lastNR = result[i];
          placed++;
        }
      }
    }

    return result;
  }

  // ── Rule helpers ────────────────────────────────────────────────────────────

  /// True when the day before position [i] in the week is NOT a training day.
  static bool _hasRestBefore(List<int> sortedDays, int i) {
    if (i == 0) return true; // nothing before Monday
    return sortedDays[i] - sortedDays[i - 1] > 1;
  }

  /// True when the day after position [i] in the week is NOT a training day.
  static bool _hasRestAfter(List<int> sortedDays, int i) {
    if (i == sortedDays.length - 1) return true;
    return sortedDays[i + 1] - sortedDays[i] > 1;
  }

  /// True if placing a hard workout at position [i] would sit adjacent
  /// (±1 slot) to another hard workout already in [result].
  static bool _isAdjacentToHard(List<WorkoutType> result, int i) {
    bool isHard(WorkoutType t) =>
        t == WorkoutType.tempo ||
        t == WorkoutType.interval ||
        t == WorkoutType.long;

    if (i > 0 && isHard(result[i - 1])) return true;
    if (i < result.length - 1 && isHard(result[i + 1])) return true;
    return false;
  }

  static WorkoutType _pickQualityType(WorkoutType? lastNonRecovery) {
    // Alternate: if last quality was tempo → give interval, and vice versa.
    if (lastNonRecovery == WorkoutType.tempo) return WorkoutType.interval;
    return WorkoutType.tempo;
  }

  static DateTime _toMonday(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: weekday - 1));
  }
}
