// lib/services/skip_service.dart
//
// Applies "skip today's workout" logic to the current weekly plan.
//
// Rules:
//   Easy / Recovery  → drop it, mark as rest.
//   Tempo / Interval → try to move to the next available day this week
//                      that has a rest day before it and no hard workout
//                      already on it. If none found, drop it.
//   Long run         → try to move to the next available day with a rest
//                      day after it. If none found, drop it.
//
// Constraints when moving:
//   • Never create two hard days (quality/long) on consecutive indices.
//   • Never add a training day beyond the user's chosen frequency.
//
// Skip counts are persisted so the engine can observe patterns over time.

import 'package:flutter/foundation.dart';
import '../models/weekly_plan.dart';
import '../models/workout_type.dart';
import '../utils/database_service.dart';

class SkipResult {
  /// Updated plan after skip logic applied.
  final WeeklyPlan plan;

  /// If the workout was moved, this is the new date.
  final DateTime? movedToDate;

  /// If moved, this is the original day name (e.g. "Wednesday").
  final String? movedFromDayName;

  const SkipResult({
    required this.plan,
    this.movedToDate,
    this.movedFromDayName,
  });
}

class SkipService {
  // ── Public API ──────────────────────────────────────────────────────────────

  /// Applies skip logic to [plan] for the day matching [skipDate].
  /// [trainingDayIndices] is the user's weekly schedule (0=Mon..6=Sun).
  static Future<SkipResult> applySkip({
    required DateTime skipDate,
    required WeeklyPlan plan,
    required List<int> trainingDayIndices,
  }) async {
    final dayDate = DateTime(skipDate.year, skipDate.month, skipDate.day);

    // Find the day being skipped in the plan.
    final skipIdx = plan.days.indexWhere(
      (d) =>
          d.date.year == dayDate.year &&
          d.date.month == dayDate.month &&
          d.date.day == dayDate.day,
    );

    if (skipIdx < 0) {
      debugPrint('[SkipService] Skip date not found in plan');
      return SkipResult(plan: plan);
    }

    final skippedDay = plan.days[skipIdx];
    if (skippedDay.isCompleted || skippedDay.isRestDay) {
      return SkipResult(plan: plan);
    }

    // Track the skip.
    await _incrementSkipCount(skippedDay.workoutType);

    final type = skippedDay.workoutType;

    // Easy / Recovery: just drop it.
    if (type == WorkoutType.easy || type == WorkoutType.recovery) {
      final updated = _replaceDay(
        plan,
        skipIdx,
        PlannedDay(
          date: skippedDay.date,
          workoutType: WorkoutType.rest,
          isRestDay: true,
        ),
      );
      return SkipResult(plan: updated);
    }

    // Hard types: try to reschedule.
    final sortedTrainingIndices = [...trainingDayIndices]..sort();
    final skippedWeekdayIdx = _weekdayIndex(skippedDay.date); // 0=Mon

    // Candidate dates: rest days after the skipped date, within this week.
    final candidates = _findRescheduleCandidates(
      plan: plan,
      skippedWeekdayIdx: skippedWeekdayIdx,
      sortedTrainingIndices: sortedTrainingIndices,
      workoutType: type,
    );

    if (candidates.isEmpty) {
      // No valid slot — just drop it.
      final updated = _replaceDay(
        plan,
        skipIdx,
        PlannedDay(
          date: skippedDay.date,
          workoutType: WorkoutType.rest,
          isRestDay: true,
        ),
      );
      return SkipResult(plan: updated);
    }

    // Use the first valid candidate.
    final targetDate = candidates.first;
    final targetIdx = plan.days.indexWhere(
      (d) =>
          d.date.year == targetDate.year &&
          d.date.month == targetDate.month &&
          d.date.day == targetDate.day,
    );

    final originalDayName = TrainingDaysServiceHelper.dayName(skippedWeekdayIdx);

    // Mark skipped day as rest.
    var updated = _replaceDay(
      plan,
      skipIdx,
      PlannedDay(
        date: skippedDay.date,
        workoutType: WorkoutType.rest,
        isRestDay: true,
      ),
    );

    // Place moved workout on target day.
    if (targetIdx >= 0) {
      final targetDay = updated.days[targetIdx];
      updated = _replaceDay(
        updated,
        targetIdx,
        PlannedDay(
          date: targetDay.date,
          workoutType: type,
          isRestDay: false,
          movedFromDay: originalDayName,
        ),
      );
    }

    return SkipResult(
      plan: updated,
      movedToDate: targetDate,
      movedFromDayName: originalDayName,
    );
  }

  // ── Skip count persistence ─────────────────────────────────────────────────

  static Future<Map<String, int>> loadSkipCounts() async {
    return DatabaseService.instance.getSkipCounts();
  }

  static Future<void> _incrementSkipCount(WorkoutType type) async {
    await DatabaseService.instance.incrementSkipCount(type.name);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// 0 = Monday ... 6 = Sunday
  static int _weekdayIndex(DateTime d) => d.weekday - 1;

  static WeeklyPlan _replaceDay(WeeklyPlan plan, int idx, PlannedDay day) {
    final days = List<PlannedDay>.from(plan.days);
    days[idx] = day;
    return WeeklyPlan(weekStartDate: plan.weekStartDate, days: days);
  }

  /// Returns dates (within the week) that are valid rescheduling targets
  /// for a hard workout.
  ///
  /// For quality (tempo/interval): candidate must have a rest day before it.
  /// For long run: candidate must have a rest day after it.
  /// Neither: creates two consecutive hard days.
  static List<DateTime> _findRescheduleCandidates({
    required WeeklyPlan plan,
    required int skippedWeekdayIdx,
    required List<int> sortedTrainingIndices,
    required WorkoutType workoutType,
  }) {
    final results = <DateTime>[];
    final trainingSet = sortedTrainingIndices.toSet();

    for (final day in plan.days) {
      if (day.isCompleted) continue;
      final dIdx = _weekdayIndex(day.date);

      // Only consider days AFTER the skipped day within this week.
      if (dIdx <= skippedWeekdayIdx) continue;

      // The target slot must currently be a rest day (no workout already there).
      if (!day.isRestDay && day.workoutType != WorkoutType.rest) continue;

      // The target must NOT be a user training day already — we don't
      // want to add extra training days; we're using a natural rest slot.
      // Exception: if it IS a training day but has a rest workout currently.
      if (trainingSet.contains(dIdx)) continue;

      final prevIsRest = !trainingSet.contains(dIdx - 1);
      final nextIsRest = !trainingSet.contains(dIdx + 1);

      // For quality: need rest before to allow recovery.
      if ((workoutType == WorkoutType.tempo ||
              workoutType == WorkoutType.interval) &&
          !prevIsRest) continue;

      // For long: prefer rest day after.
      if (workoutType == WorkoutType.long && !nextIsRest) continue;

      // Check: would this create consecutive hard days?
      final adjacentHard = _hasAdjacentHard(plan, dIdx);
      if (adjacentHard) { continue; }

      results.add(day.date);
    }

    return results;
  }

  static bool _hasAdjacentHard(WeeklyPlan plan, int targetDayIdx) {
    for (final day in plan.days) {
      final dIdx = _weekdayIndex(day.date);
      if ((dIdx - targetDayIdx).abs() == 1) {
        if (day.workoutType == WorkoutType.tempo ||
            day.workoutType == WorkoutType.interval ||
            day.workoutType == WorkoutType.long) {
          return true;
        }
      }
    }
    return false;
  }
}

/// Tiny helper so SkipService doesn't depend on TrainingDaysService directly.
class TrainingDaysServiceHelper {
  static const _names = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  static String dayName(int idx) => _names[idx.clamp(0, 6)];
}
