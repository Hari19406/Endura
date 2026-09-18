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

  /// The athlete deliberately skipped this day from the pre-run briefing
  /// screen — distinct from [missed], which is an overdue/never-touched day.
  skipped,

  /// A training day whose scheduled date is in the past and was never done.
  missed,

  /// A scheduled rest day.
  restDay,

  /// A training day that is today or still ahead.
  upcoming,

  /// A week-1 slot that falls before the plan's start date — the plan is
  /// Monday-aligned, so a plan created on a Friday still owns Mon–Thu of week
  /// 1 as slots, but they were never the athlete's to do. Not [missed], and
  /// not tappable.
  prePlan,
}

/// [planStart], when given, is the plan's first day (date-only): any slot
/// dated before it is [CalendarDayStatus.prePlan]. Omit it for a plan with no
/// partial first week.
CalendarDayStatus calendarDayStatus(
  MaterializedDay day, {
  required DateTime scheduledDate,
  required DateTime now,
  DateTime? planStart,
}) {
  if (day.completion != null) return CalendarDayStatus.completed;

  final sched =
      DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day);
  if (planStart != null &&
      sched.isBefore(DateTime(planStart.year, planStart.month, planStart.day))) {
    return CalendarDayStatus.prePlan;
  }

  if (day.isSkipped) return CalendarDayStatus.skipped;
  if (day.isRest) return CalendarDayStatus.restDay;

  final today = DateTime(now.year, now.month, now.day);
  if (sched.isBefore(today)) return CalendarDayStatus.missed;
  return CalendarDayStatus.upcoming;
}
