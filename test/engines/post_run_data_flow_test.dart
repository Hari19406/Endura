/// Post-run data flow: RPE lands on the plan day's DayCompletion, and the
/// actual/expected pace pair reaches EngineRuntime so _calibrateVdot banks a
/// pendingVdotNudge. (The summary screen wires these in
/// RunSummaryScreen._finaliseRun; this exercises the same calls without UI.)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/memory/engine_memory_service.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_store.dart';
import 'package:run_app/engines/runtime/engine_runtime.dart';
import 'package:run_app/models/scheduled_workout_context.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _runDate = DateTime(2026, 9, 20, 7);

MaterializedPlan _plan() => MaterializedPlan(
  planId: 'p1',
  builtAt: DateTime.parse('2026-09-14T00:00:00.000Z'),
  builtFromVdot: 45,
  inputsFingerprint: 'fp',
  weeks: [
    MaterializedWeek(
      weekNumber: 1,
      phase: TrainingPhase.build,
      targetKm: 40,
      isCutback: false,
      isFrozen: false,
      days: [
        for (var i = 0; i < 6; i++)
          MaterializedDay(weekday: i, slot: MaterializedSlot.rest),
        const MaterializedDay(
          weekday: 6,
          slot: MaterializedSlot.quality1,
          intent: WorkoutIntent.threshold,
          templateId: 'cruise_intervals',
        ),
      ],
    ),
  ],
);

ScheduledWorkoutContext _sched({int? min = 290, int? max = 310}) =>
    ScheduledWorkoutContext(
      dayId: 'p1::w1::d6',
      planId: 'p1',
      weekNumber: 1,
      weekday: 6,
      scheduledDate: DateTime(2026, 9, 20),
      targetDistanceKm: 8,
      targetPaceMinSecPerKm: min,
      targetPaceMaxSecPerKm: max,
      blocks: const [],
    );

Future<int> _pendingNudge() async =>
    (await EngineMemoryService().load()).pendingVdotNudge;

Future<void> _process({
  double? actual,
  double? expected,
  int? rpe,
  WorkoutIntent intent = WorkoutIntent.threshold,
}) => EngineRuntime.processRun(
  durationMinutes: 40,
  speed: 3.3,
  runDate: _runDate,
  workoutType: 'tempo',
  distanceKm: 8,
  rpe: rpe,
  completedIntent: intent,
  actualPaceSecondsPerKm: actual,
  expectedPaceSecondsPerKm: expected,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ScheduledWorkoutContext.expectedPaceSecPerKm', () {
    test('is the midpoint of the work-pace range', () {
      expect(_sched().expectedPaceSecPerKm, 300);
    });

    test('is null for an RPE-only session', () {
      expect(_sched(min: null, max: null).expectedPaceSecPerKm, isNull);
    });
  });

  group('PlanStore.recordDayRpe', () {
    test('attaches RPE to the completion and keeps the other fields', () async {
      await PlanStore.instance.save(_plan());
      await PlanStore.instance.markDayCompleted(
        weekNumber: 1,
        weekday: 6,
        actualKm: 8.1,
        actualPaceSecPerKm: 295,
        runId: '42',
        completedAt: _runDate,
      );
      expect(
        (await PlanStore.instance.load())!.weeks.single.days[6].completion!.rpe,
        isNull,
      );

      final ok = await PlanStore.instance.recordDayRpe(
        weekNumber: 1,
        weekday: 6,
        rpe: 6,
      );

      expect(ok, isTrue);
      final c = (await PlanStore.instance.load())!.weeks.single.days[6]
          .completion!;
      expect(c.rpe, 6.0);
      expect(c.actualKm, 8.1);
      expect(c.actualPaceSecPerKm, 295);
      expect(c.runId, '42');
    });

    test('returns false when the day has no completion or slot', () async {
      await PlanStore.instance.save(_plan());
      expect(
        await PlanStore.instance.recordDayRpe(weekNumber: 1, weekday: 6, rpe: 5),
        isFalse,
      );
      expect(
        await PlanStore.instance.recordDayRpe(weekNumber: 9, weekday: 6, rpe: 5),
        isFalse,
      );
    });
  });

  group('EngineRuntime.processRun → _calibrateVdot', () {
    test('faster than expected at low RPE banks +1', () async {
      await _process(actual: 280, expected: 300, rpe: 4);
      expect(await _pendingNudge(), 1);
    });

    test('slower than expected at high RPE banks -1', () async {
      await _process(actual: 320, expected: 300, rpe: 8);
      expect(await _pendingNudge(), -1);
    });

    test('a gap under 10 s/km banks nothing', () async {
      await _process(actual: 295, expected: 300, rpe: 4);
      expect(await _pendingNudge(), 0);
    });

    test('missing paces bank nothing (the pre-fix behaviour)', () async {
      await _process(rpe: 4);
      expect(await _pendingNudge(), 0);
    });

    test('non-easy/threshold intents are not calibrated', () async {
      await _process(
        actual: 280,
        expected: 300,
        rpe: 4,
        intent: WorkoutIntent.vo2max,
      );
      expect(await _pendingNudge(), 0);
    });

    test('signals accumulate across runs', () async {
      await _process(actual: 280, expected: 300, rpe: 4);
      await _process(actual: 280, expected: 300, rpe: 4);
      expect(await _pendingNudge(), 2);
    });
  });

  test('completing a scheduled run records RPE and feeds calibration', () async {
    final sched = _sched();
    await PlanStore.instance.save(_plan());

    // 1. Finish: run saved, plan day linked (RPE unknown yet).
    await PlanStore.instance.markDayCompleted(
      weekNumber: sched.weekNumber,
      weekday: sched.weekday,
      actualKm: 8,
      actualPaceSecPerKm: 285,
      completedAt: _runDate,
    );

    // 2. Done tapped: RPE + paces submitted, as _finaliseRun does.
    await PlanStore.instance.recordDayRpe(
      weekNumber: sched.weekNumber,
      weekday: sched.weekday,
      rpe: 4,
    );
    const durationSeconds = 8 * 285; // 8 km at 285 s/km
    await _process(
      actual: durationSeconds / 8, // duration / distance, as _finaliseRun does
      expected: sched.expectedPaceSecPerKm!.toDouble(),
      rpe: 4,
    );

    final day = (await PlanStore.instance.load())!.weeks.single.days[6];
    expect(day.completion!.rpe, 4.0);
    expect(await _pendingNudge(), 1);
  });
}
