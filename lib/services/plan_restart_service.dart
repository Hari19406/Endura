/// PlanRestartService — "Restart plan from today": shifts the active plan's
/// whole timeline forward so the next uncompleted workout is no longer in the
/// past.
///
/// Every calendar date on the plan is derived from a single Monday anchor
/// (`RacePlan.createdAt` snapped via `weekAnchor` for week/weekday math,
/// `MaterializedPlan.builtAt` for the stored plan's own day strip) plus a
/// day's fixed (weekNumber, weekday). A slot's weekday is its real calendar
/// weekday, so the shift is always a whole number of WEEKS: the plan stays
/// Monday-aligned, weekly cadence and recovery spacing are preserved exactly
/// as designed, and no already-logged completion is touched. The next
/// uncompleted workout therefore lands on the next occurrence of its own
/// weekday on or after today.
library;

import '../engines/memory/engine_memory_service.dart';
import '../engines/plan/materialized_plan.dart';
import '../engines/plan/plan_store.dart';
import '../models/race_plan.dart';
import '../utils/plan_calendar.dart';

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

  /// The first training day (not rest, not already completed, not pre-plan) in
  /// week/weekday order — null when every training day is done.
  static NextWorkoutInfo? findNextUncompleted(MaterializedPlan plan) {
    final weeks = [...plan.weeks]
      ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));
    for (final week in weeks) {
      final days = [...week.days]..sort((a, b) => a.weekday.compareTo(b.weekday));
      for (final day in days) {
        if (day.isRest || day.isCompleted) continue;
        // Pre-plan slots were never the athlete's to do.
        if (plan.isPrePlanDay(week.weekNumber, day.weekday)) continue;
        return NextWorkoutInfo(
          weekNumber: week.weekNumber,
          weekday: day.weekday,
          scheduledDate: plan.dateFor(week.weekNumber, day.weekday),
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

    final next = findNextUncompleted(materialized);
    if (next == null) return null;

    return PlanCalendar.daysBetween(next.scheduledDate, DateTime.now());
  }

  /// Whole weeks to shift so a workout [behindDays] behind schedule lands on or
  /// after today: the smallest multiple of 7 days that clears the gap. 0 when
  /// on schedule or less than a week ahead.
  static int weeksToShift(int behindDays) => (behindDays / 7).ceil();

  /// Shifts the plan forward by whole weeks so the next uncompleted workout
  /// lands on or after today. Returns false when there is no active plan or
  /// every training day is already completed (nothing to restart); true
  /// otherwise (including the no-op case where the plan is already on
  /// schedule).
  static Future<bool> restartFromToday() async {
    final memory = await EngineMemoryService().load();
    final racePlan = memory.racePlan;
    final materialized = await PlanStore.instance.load();
    if (racePlan == null || materialized == null) return false;

    final next = findNextUncompleted(materialized);
    if (next == null) return false;

    final behindDays = PlanCalendar.daysBetween(
      next.scheduledDate,
      DateTime.now(),
    );
    final offsetDays = weeksToShift(behindDays) * 7;
    if (offsetDays == 0) return true;

    final updatedRacePlan = RacePlan(
      goalRace: racePlan.goalRace,
      raceDate: PlanCalendar.shiftDays(racePlan.raceDate, offsetDays),
      createdAt: PlanCalendar.shiftDays(racePlan.createdAt, offsetDays),
      startingWeeklyKm: racePlan.startingWeeklyKm,
      experienceLevel: racePlan.experienceLevel,
      weeks: racePlan.weeks,
    );
    final updatedMaterialized = materialized.copyWith(
      builtAt: PlanCalendar.shiftDays(materialized.builtAt, offsetDays),
      startDate: materialized.startDate == null
          ? null
          : PlanCalendar.shiftDays(materialized.startDate!, offsetDays),
    );

    // archivePrevious: false — this reshapes the same plan's dates, it does
    // not retire it, so it must not be snapshotted into plan_history.
    await EngineMemoryService().saveRacePlan(
      updatedRacePlan,
      archivePrevious: false,
    );
    await PlanStore.instance.saveAndSync(updatedMaterialized);
    return true;
  }
}
