import '../engines/plan/materialized_plan.dart';

/// How a single day reads on the plan calendar.
///
/// Derived purely from the stored [MaterializedDay] plus the day's real
/// calendar date — no legacy `WeeklyPlan`, no `markMissedDays`. Completion is
/// whatever [MaterializedDay.completion] holds (set by
/// `WorkoutComplianceMatcher`), so the calendar and the Coach card can never
/// disagree.
enum CalendarDayStatus {
  /// A logged run has been matched to this day.
  completed,

  /// A training day whose scheduled date is in the past and was never done.
  missed,

  /// A scheduled rest day.
  restDay,

  /// A training day that is today or still ahead.
  upcoming,
}

CalendarDayStatus calendarDayStatus(
  MaterializedDay day, {
  required DateTime scheduledDate,
  required DateTime now,
}) {
  if (day.completion != null) return CalendarDayStatus.completed;
  if (day.isRest) return CalendarDayStatus.restDay;

  final sched =
      DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day);
  final today = DateTime(now.year, now.month, now.day);
  if (sched.isBefore(today)) return CalendarDayStatus.missed;
  return CalendarDayStatus.upcoming;
}
