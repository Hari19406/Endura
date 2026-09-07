/// Stage 5 — the Coach tab reads today's session straight from the persisted
/// MaterializedPlan. These lock the read path + the narration composition.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_materializer.dart';
import 'package:run_app/engines/plan/plan_store.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/services/coach_message_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 3, 2); // a Monday

  MaterializedPlan buildPlan() {
    final skeleton = RacePlanBuilder.build(
      currentWeeklyKm: 45,
      goalRace: 'half_marathon',
      raceDate: now.add(const Duration(days: 84)),
      experienceLevel: 'intermediate',
      now: now,
    );
    return const PlanMaterializer().materialize(
      skeleton: skeleton,
      trainingDayIndices: const [0, 2, 4, 6], // Mon/Wed/Fri/Sun
      longRunDayIndex: 6,
      raceDistance: RaceDistance.halfMarathon,
      experienceLevel: ExperienceLevel.intermediate,
      vdot: 46,
      inputsFingerprint: 'fp-read-path',
      now: now,
    );
  }

  group('MaterializedPlan.contextForWeekday (pure, no I/O)', () {
    final plan = buildPlan();

    test('returns the day bundled with its parent week', () {
      final ctx = plan.contextForWeekday(weekNumber: 1, weekdayIndex: 0);
      expect(ctx, isNotNull);
      expect(ctx!.week.weekNumber, 1);
      expect(ctx.day.weekday, 0);
      expect(ctx.weeklyTargetKm, plan.weekByNumber(1)!.targetKm);
    });

    test('a scheduled training day carries a resolved workout', () {
      final wed = plan.contextForWeekday(weekNumber: 2, weekdayIndex: 2)!;
      expect(wed.isRest, isFalse);
      expect(wed.day.workout, isNotNull);
      expect(wed.day.workout!.blocks, isNotEmpty);
    });

    test('an off day resolves to a rest context', () {
      final tue = plan.contextForWeekday(weekNumber: 2, weekdayIndex: 1)!;
      expect(tue.isRest, isTrue);
    });

    test('a week outside the plan ⇒ null', () {
      expect(plan.contextForWeekday(weekNumber: 999, weekdayIndex: 0), isNull);
    });
  });

  group('PlanStore.getTodayDayContext (mocked SharedPreferences)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('null when no plan is persisted — caller shows a placeholder', () async {
      final ctx = await PlanStore.instance.getTodayDayContext(
        weekNumber: 1,
        now: now,
      );
      expect(ctx, isNull);
    });

    test('after save, returns today\'s day for the requested week', () async {
      await PlanStore.instance.save(buildPlan());
      final ctx = await PlanStore.instance.getTodayDayContext(
        weekNumber: 1,
        now: now, // Monday → weekday index 0
      );
      expect(ctx, isNotNull);
      expect(ctx!.day.weekday, 0);
      expect(ctx.week.weekNumber, 1);
    });

    test('weekday index is derived from `now`', () async {
      await PlanStore.instance.save(buildPlan());
      final ctx = await PlanStore.instance.getTodayDayContext(
        weekNumber: 2,
        now: now.add(const Duration(days: 2)), // Wednesday
      );
      expect(ctx!.day.weekday, 2);
    });
  });

  group('narration is built FROM the persisted workout, never recomputed', () {
    test('buildMessage echoes the stored ResolvedWorkout + week context', () async {
      SharedPreferences.setMockInitialValues({});
      final plan = buildPlan();
      await PlanStore.instance.save(plan);

      final reloaded = await PlanStore.instance.getTodayDayContext(
        weekNumber: 3,
        now: now.add(const Duration(days: 14)), // week 3, a Monday
      );
      // fall back to any non-rest day in week 3 if Monday is a rest slot
      MaterializedDayContext ctx = reloaded ??
          [0, 1, 2, 3, 4, 5, 6]
              .map((wd) => plan.contextForWeekday(weekNumber: 3, weekdayIndex: wd))
              .firstWhere((c) => c != null && !c.isRest)!;
      if (ctx.isRest) {
        ctx = [0, 1, 2, 3, 4, 5, 6]
            .map((wd) => plan.contextForWeekday(weekNumber: 3, weekdayIndex: wd))
            .firstWhere((c) => c != null && !c.isRest)!;
      }

      final msg = CoachMessageBuilder().buildMessage(
        context: const CoachContext(
          totalRunsCompleted: 10,
          daysSinceLastRun: 2,
        ),
        resolvedWorkout: ctx.day.workout!,
        phase: ctx.week.phase,
        weekNumber: ctx.week.weekNumber,
      );

      expect(identical(msg.resolvedWorkout, ctx.day.workout), isTrue);
      expect(msg.workoutIntent, ctx.day.workout!.intent);
      expect(msg.weekNumber, 3);
      expect(msg.totalDistanceKm, ctx.day.workout!.totalDistanceKm);
    });
  });
}
