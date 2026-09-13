/// PlanRestartService — "Restart plan from today": shifts the active plan's
/// whole timeline so the next uncompleted workout lands on today.
///
/// Every calendar date on the plan is derived from a single anchor
/// (`RacePlan.createdAt` for week/weekday math, `MaterializedPlan.builtAt`
/// for the stored plan's own day strip) plus a day's fixed (weekNumber,
/// weekday). Shifting both anchors by the same day offset therefore moves
/// every day uniformly — preserving weekly cadence and recovery spacing
/// exactly as designed — without touching any already-logged completion.
library;

import '../engines/memory/engine_memory_service.dart';
import '../engines/plan/materialized_plan.dart';
import '../engines/plan/plan_store.dart';
import '../models/race_plan.dart';

class NextWorkoutInfo {
  final int weekNumber;
  final int weekday; // 0 = Monday … 6 = Sunday
  final DateTime scheduledDate;

  const NextWorkoutInfo({
    required this.weekNumber,
    required this.weekday,
    required this.scheduledDate,
  });
}

class PlanRestartService {
  const PlanRestartService._();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The first training day (not rest, not already completed) in week/weekday
  /// order, anchored on [anchor] — null when every training day is done.
  static NextWorkoutInfo? findNextUncompleted(
    MaterializedPlan plan,
    DateTime anchor,
  ) {
    final weeks = [...plan.weeks]
      ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));
    for (final week in weeks) {
      final days = [...week.days]..sort((a, b) => a.weekday.compareTo(b.weekday));
      for (final day in days) {
        if (day.isRest || day.isCompleted) continue;
        final date = anchor.add(
          Duration(days: (week.weekNumber - 1) * 7 + day.weekday),
        );
        return NextWorkoutInfo(
          weekNumber: week.weekNumber,
          weekday: day.weekday,
          scheduledDate: date,
        );
      }
    }
    return null;
  }

  /// Whole-day gap between the next uncompleted workout's originally
  /// scheduled date and today. Positive ⇒ behind schedule. Null when there is
  /// no active plan or nothing left to restart.
  static Future<int?> daysBehindSchedule() async {
    final memory = await EngineMemoryService().load();
    final racePlan = memory.racePlan;
    final materialized = await PlanStore.instance.load();
    if (racePlan == null || materialized == null) return null;

    final anchor = _dateOnly(materialized.builtAt);
    final next = findNextUncompleted(materialized, anchor);
    if (next == null) return null;

    return _dateOnly(DateTime.now()).difference(next.scheduledDate).inDays;
  }

  /// Shifts the plan so the next uncompleted workout lands on today. Returns
  /// false when there is no active plan or every training day is already
  /// completed (nothing to restart); true otherwise (including the no-op case
  /// where the plan is already on schedule).
  static Future<bool> restartFromToday() async {
    final memory = await EngineMemoryService().load();
    final racePlan = memory.racePlan;
    final materialized = await PlanStore.instance.load();
    if (racePlan == null || materialized == null) return false;

    final anchor = _dateOnly(materialized.builtAt);
    final next = findNextUncompleted(materialized, anchor);
    if (next == null) return false;

    final offsetDays =
        _dateOnly(DateTime.now()).difference(next.scheduledDate).inDays;
    if (offsetDays == 0) return true;

    final updatedRacePlan = RacePlan(
      goalRace: racePlan.goalRace,
      raceDate: racePlan.raceDate.add(Duration(days: offsetDays)),
      createdAt: racePlan.createdAt.add(Duration(days: offsetDays)),
      startingWeeklyKm: racePlan.startingWeeklyKm,
      experienceLevel: racePlan.experienceLevel,
      weeks: racePlan.weeks,
    );
    final updatedMaterialized = materialized.copyWith(
      builtAt: materialized.builtAt.add(Duration(days: offsetDays)),
    );

    await EngineMemoryService().saveRacePlan(updatedRacePlan);
    await PlanStore.instance.saveAndSync(updatedMaterialized);
    return true;
  }
}
