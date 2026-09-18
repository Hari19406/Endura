/// Monday-aligned plan weeks: a plan created mid-week (a Friday) must still
/// have weeks that run Monday–Sunday, so a day slot's weekday index is its real
/// calendar weekday everywhere it's turned back into a date.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_materializer.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/race_plan.dart';
import 'package:run_app/models/scheduled_workout_context.dart';
import 'package:run_app/screens/calendar_day_status.dart';
import 'package:run_app/services/plan_restart_service.dart';
import 'package:run_app/services/workout_compliance_matcher.dart';
import 'package:run_app/utils/plan_calendar.dart';

void main() {
  // Fri 18 Sep 2026 — the exact scenario from the bug report.
  final friday = DateTime(2026, 9, 18, 14, 30);
  final monday = DateTime(2026, 9, 14);

  RacePlan skeleton(DateTime created) => RacePlanBuilder.build(
    currentWeeklyKm: 40,
    goalRace: '10k',
    raceDate: created.add(const Duration(days: 12 * 7)),
    experienceLevel: 'intermediate',
    now: created,
    durationWeeks: 12,
  );

  MaterializedPlan materialize(RacePlan s) => const PlanMaterializer().materialize(
    skeleton: s,
    trainingDayIndices: const [0, 2, 4, 6], // Mon/Wed/Fri/Sun
    longRunDayIndex: 6,
    raceDistance: RaceDistance.tenK,
    experienceLevel: ExperienceLevel.intermediate,
    vdot: 46,
    inputsFingerprint: 'fp',
  );

  group('PlanCalendar', () {
    test('mondayOf snaps every day of a week to that week\'s Monday', () {
      for (var d = 14; d <= 20; d++) {
        expect(PlanCalendar.mondayOf(DateTime(2026, 9, d, 23, 59)), monday);
      }
      expect(PlanCalendar.mondayOf(DateTime(2026, 9, 21)), DateTime(2026, 9, 21));
    });

    test('dateFor treats the anchor as any date in week 1', () {
      // Anchor is the Friday, but weekday 0 is still Monday Sep 14.
      expect(PlanCalendar.dateFor(friday, 1, 0), monday);
      expect(PlanCalendar.dateFor(friday, 1, 5), DateTime(2026, 9, 19)); // Sat
      expect(PlanCalendar.dateFor(friday, 2, 0), DateTime(2026, 9, 21));
      expect(PlanCalendar.dateFor(friday, 1, 5).weekday, DateTime.saturday);
    });

    test('daysBetween counts calendar days and ignores time of day', () {
      expect(
        PlanCalendar.daysBetween(
          DateTime(2026, 9, 14, 23, 59),
          DateTime(2026, 9, 15, 0, 1),
        ),
        1,
      );
      expect(PlanCalendar.daysBetween(DateTime(2026, 9, 20), monday), -6);
    });
  });

  group('RacePlan week numbering', () {
    final plan = skeleton(friday);

    test('the anchor is the Monday of the creation week; startDate is the real day', () {
      expect(plan.weekAnchor, monday);
      expect(plan.startDate, DateTime(2026, 9, 18));
      // createdAt itself stays the true instant (plan ids / history use it).
      expect(plan.createdAt, friday);
    });

    test('weeks roll over on Monday, not on the creation weekday', () {
      expect(plan.currentWeekNumber(DateTime(2026, 9, 19)), 1); // Sat
      expect(plan.currentWeekNumber(DateTime(2026, 9, 20)), 1); // Sun
      expect(plan.currentWeekNumber(DateTime(2026, 9, 21)), 2); // Mon
      expect(plan.currentWeekNumber(DateTime(2026, 9, 27)), 2); // Sun
      expect(plan.currentWeekNumber(DateTime(2026, 9, 28)), 3); // Mon
    });
  });

  group('PlanMaterializer anchor', () {
    final s = skeleton(friday);
    final plan = materialize(s);

    test('builtAt is the creation week\'s Monday at local midnight (no UTC)', () {
      expect(plan.builtAt, monday);
      expect(plan.builtAt.isUtc, isFalse);
      expect(plan.builtAt.weekday, DateTime.monday);
      expect(plan.startDate, DateTime(2026, 9, 18));
    });

    test('rebuilding never moves the anchor (it comes from the skeleton, not "now")', () {
      final again = materialize(s);
      expect(again.builtAt, plan.builtAt);
      expect(again.startDate, plan.startDate);
      expect(jsonEncode(again.toJson()), jsonEncode(plan.toJson()));
    });

    test('every slot\'s date lands on its own weekday', () {
      for (final w in plan.weeks) {
        for (final d in w.days) {
          expect(
            plan.dateFor(w.weekNumber, d.weekday).weekday,
            d.weekday + 1, // DateTime: Mon = 1
            reason: 'W${w.weekNumber} slot ${d.weekday}',
          );
        }
      }
    });

    test('Saturday is slot 5 and Sep 19 resolves to it in week 1', () {
      expect(plan.dateFor(1, 5), DateTime(2026, 9, 19));
    });

    test('week-1 slots before the start date are pre-plan; nothing else is', () {
      expect(plan.firstActiveWeekday(1), 4); // Friday
      for (var wd = 0; wd <= 3; wd++) {
        expect(plan.isPrePlanDay(1, wd), isTrue, reason: 'slot $wd');
      }
      for (var wd = 4; wd <= 6; wd++) {
        expect(plan.isPrePlanDay(1, wd), isFalse, reason: 'slot $wd');
      }
      expect(plan.isPrePlanDay(2, 0), isFalse);
      expect(plan.firstActiveWeekday(2), 0);
    });

    test('a plan created on a Monday has no pre-plan days', () {
      final mon = materialize(skeleton(DateTime(2026, 9, 14, 8)));
      expect(mon.firstActiveWeekday(1), 0);
      expect(mon.isPrePlanDay(1, 0), isFalse);
    });

    test('startDate survives a JSON round-trip', () {
      final back = MaterializedPlan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>,
      );
      expect(back.builtAt, plan.builtAt);
      expect(back.startDate, plan.startDate);
      expect(back.firstActiveWeekday(1), 4);
    });

    test('a plan stored before Monday-alignment self-heals on read', () {
      // Legacy shape: builtAt is a raw UTC build timestamp (a Friday), and
      // there is no startDate key.
      final json = jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>
        ..['builtAt'] = friday.toUtc().toIso8601String()
        ..remove('startDate');
      final legacy = MaterializedPlan.fromJson(json);

      expect(legacy.week1Monday, monday);
      expect(legacy.planStartDate, DateTime(2026, 9, 18));
      expect(legacy.dateFor(1, 5), DateTime(2026, 9, 19));
      expect(legacy.firstActiveWeekday(1), 4);
    });
  });

  group('calendarDayStatus — pre-plan', () {
    const training = MaterializedDay(weekday: 0, slot: MaterializedSlot.easy);
    const rest = MaterializedDay(weekday: 1, slot: MaterializedSlot.rest);
    final start = DateTime(2026, 9, 18);
    final now = DateTime(2026, 9, 19); // Saturday

    test('days before the start are prePlan — never "missed"', () {
      expect(
        calendarDayStatus(
          training,
          scheduledDate: DateTime(2026, 9, 14),
          now: now,
          planStart: start,
        ),
        CalendarDayStatus.prePlan,
      );
      // A rest slot before the start is pre-plan too, not a real rest day.
      expect(
        calendarDayStatus(
          rest,
          scheduledDate: DateTime(2026, 9, 15),
          now: now,
          planStart: start,
        ),
        CalendarDayStatus.prePlan,
      );
    });

    test('from the start date on, normal statuses apply', () {
      // Fri Sep 18 was scheduled, is past, and was never done → genuinely missed.
      expect(
        calendarDayStatus(
          training,
          scheduledDate: DateTime(2026, 9, 18),
          now: now,
          planStart: start,
        ),
        CalendarDayStatus.missed,
      );
      expect(
        calendarDayStatus(
          training,
          scheduledDate: DateTime(2026, 9, 19),
          now: now,
          planStart: start,
        ),
        CalendarDayStatus.upcoming,
      );
    });

    test('without a planStart nothing is pre-plan', () {
      expect(
        calendarDayStatus(
          training,
          scheduledDate: DateTime(2026, 9, 14),
          now: now,
        ),
        CalendarDayStatus.missed,
      );
    });
  });

  group('consumers agree on the date', () {
    final plan = materialize(skeleton(friday));

    test('ScheduledWorkoutContext puts today\'s Saturday slot on today', () {
      final sat = plan.weekByNumber(1)!.days.firstWhere((d) => d.weekday == 5);
      // The materialised 4-day plan has no Saturday run, so build the context
      // from a real training slot and check the date arithmetic directly.
      final run = plan.weekByNumber(1)!.days.firstWhere((d) => !d.isRest);
      final ctx = ScheduledWorkoutContext.fromParts(
        planId: plan.planId,
        planBuiltAt: plan.builtAt,
        weekNumber: 1,
        weekday: run.weekday,
        workout: run.workout!,
      );
      expect(ctx.scheduledDate, PlanCalendar.dateFor(monday, 1, run.weekday));
      expect(ctx.scheduledDate.weekday, run.weekday + 1);
      expect(sat.weekday, 5);
    });

    test('ScheduledWorkoutContext agrees whether the anchor is a Monday or a raw legacy Friday', () {
      final run = plan.weekByNumber(1)!.days.firstWhere((d) => !d.isRest);
      ScheduledWorkoutContext build(DateTime anchor) =>
          ScheduledWorkoutContext.fromParts(
            planId: 'p',
            planBuiltAt: anchor,
            weekNumber: 2,
            weekday: run.weekday,
            workout: run.workout!,
          );
      expect(build(monday).scheduledDate, build(friday).scheduledDate);
    });

    test('a pre-plan slot cannot claim a run; the first active slot can', () {
      final week1 = plan.weekByNumber(1)!;
      final monSlot = week1.days.firstWhere((d) => d.weekday == 0);
      final friSlot = week1.days.firstWhere((d) => d.weekday == 4);
      expect(monSlot.isRest, isFalse);
      expect(friSlot.isRest, isFalse);

      CompletedActivity act(String id, DateTime date, double km) => CompletedActivity(
        id: id,
        date: date,
        distanceKm: km,
        durationSeconds: 0,
      );

      // A run on pre-plan Monday Sep 14 (plan starts Sep 18) matches nothing.
      final pre = WorkoutComplianceMatcher.match(
        plan: plan,
        recentActivities: [
          act('pre', DateTime(2026, 9, 14, 7), monSlot.workout!.totalDistanceKm),
        ],
      );
      expect(pre.matches, isEmpty);

      // The same effort on the plan's first active day (Fri Sep 18) does.
      final live = WorkoutComplianceMatcher.match(
        plan: plan,
        recentActivities: [
          act('live', DateTime(2026, 9, 18, 7), friSlot.workout!.totalDistanceKm),
        ],
      );
      expect(live.matches, hasLength(1));
      expect(live.matches.single.weekday, 4);
      expect(live.matches.single.scheduledDate, DateTime(2026, 9, 18));
    });
  });

  group('restart shifts in whole weeks', () {
    test('weeksToShift rounds up to the smallest week multiple that clears the gap', () {
      expect(PlanRestartService.weeksToShift(0), 0);
      expect(PlanRestartService.weeksToShift(1), 1);
      expect(PlanRestartService.weeksToShift(3), 1);
      expect(PlanRestartService.weeksToShift(7), 1);
      expect(PlanRestartService.weeksToShift(8), 2);
      // Ahead of schedule by less than a week: leave it alone.
      expect(PlanRestartService.weeksToShift(-3), 0);
      expect(PlanRestartService.weeksToShift(-9), -1);
    });

    test('the next uncompleted workout is never a pre-plan slot', () {
      final plan = materialize(skeleton(friday));
      final next = PlanRestartService.findNextUncompleted(plan)!;
      expect(next.weekNumber, 1);
      expect(next.weekday, 4); // Friday — Mon/Wed are pre-plan
      expect(next.scheduledDate, DateTime(2026, 9, 18));
    });
  });
}
