/// ScheduledWorkoutContext — the slice of a [MaterializedDayContext] that the
/// live run-tracking screen needs to (a) drive the in-run step HUD and (b) link
/// the saved activity back to the exact plan day it fulfilled.
///
/// Immutable and widget-free so it can ride route arguments and be built in a
/// test without a PlanStore.
library;

import '../engines/config/workout_template_library.dart'
    show BlockType, ResolvedBlock, ResolvedWorkout;
import '../engines/plan/materialized_plan.dart';
import '../utils/plan_calendar.dart';

class ScheduledWorkoutContext {
  /// Stable id for this plan slot: `"<planId>::w<week>::d<weekday>"`.
  final String dayId;

  final String planId;

  /// 1-based plan week.
  final int weekNumber;

  /// 0 = Monday … 6 = Sunday.
  final int weekday;

  /// Calendar date the session was scheduled for (date-only).
  final DateTime scheduledDate;

  /// Sum of the work blocks' distance — the main-set target.
  final double targetDistanceKm;

  /// Fastest / slowest work-block pace across the whole session, in
  /// seconds per km. Null when every work block is RPE-only.
  final int? targetPaceMinSecPerKm;
  final int? targetPaceMaxSecPerKm;

  /// Every block of the resolved workout, in order — what the step HUD walks.
  final List<ResolvedBlock> blocks;

  const ScheduledWorkoutContext({
    required this.dayId,
    required this.planId,
    required this.weekNumber,
    required this.weekday,
    required this.scheduledDate,
    required this.targetDistanceKm,
    required this.targetPaceMinSecPerKm,
    required this.targetPaceMaxSecPerKm,
    required this.blocks,
  });

  int get stepCount => blocks.length;

  bool get hasStructuredSteps => blocks.length > 1;

  /// Build from a resolved plan day. Returns null when the day has no workout.
  static ScheduledWorkoutContext? fromDayContext(MaterializedDayContext ctx) {
    final workout = ctx.day.workout;
    if (workout == null) return null;
    return fromParts(
      planId: ctx.plan.planId,
      planBuiltAt: ctx.plan.builtAt,
      weekNumber: ctx.week.weekNumber,
      weekday: ctx.day.weekday,
      workout: workout,
    );
  }

  static ScheduledWorkoutContext fromParts({
    required String planId,
    required DateTime planBuiltAt,
    required int weekNumber,
    required int weekday,
    required ResolvedWorkout workout,
  }) {
    final work = workout.blocks
        .where((b) => !b.isRpeOnly && b.type == BlockType.main)
        .toList();
    final int? min = work.isEmpty
        ? null
        : work
              .map((b) => b.paceMinSecondsPerKm)
              .reduce((a, b) => a < b ? a : b);
    final int? max = work.isEmpty
        ? null
        : work
              .map((b) => b.paceMaxSecondsPerKm)
              .reduce((a, b) => a > b ? a : b);

    // [planBuiltAt] is snapped to its week's Monday, so a legacy plan whose
    // anchor is a raw (non-Monday) timestamp still maps weekday 0 to Monday.
    final date = PlanCalendar.dateFor(planBuiltAt, weekNumber, weekday);

    return ScheduledWorkoutContext(
      dayId: '$planId::w$weekNumber::d$weekday',
      planId: planId,
      weekNumber: weekNumber,
      weekday: weekday,
      scheduledDate: date,
      targetDistanceKm: workout.totalDistanceKm,
      targetPaceMinSecPerKm: min,
      targetPaceMaxSecPerKm: max,
      blocks: List.unmodifiable(workout.blocks),
    );
  }
}
