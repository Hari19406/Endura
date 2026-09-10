/// Phase 3 — PlanStore local-cache behaviour (Supabase not initialised in
/// tests, so the remote path is a no-op and load/save fall back to local).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_store.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:shared_preferences/shared_preferences.dart';

MaterializedPlan planWith({String id = 'p1', int vdot = 45}) => MaterializedPlan(
  planId: id,
  builtAt: DateTime.parse('2026-09-02T10:00:00.000Z'),
  builtFromVdot: vdot,
  inputsFingerprint: 'fp',
  ladderState: const {'threshold': 1},
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
          slot: MaterializedSlot.longRun,
          intent: WorkoutIntent.endurance,
          templateId: 'long_steady',
        ),
      ],
    ),
  ],
);

/// A realistic multi-week plan: a build week (2 quality + long run + easy days
/// + rest), a cutback week, and a taper week — enough shape to prove weeks,
/// long runs and rest days all survive the store round-trip.
MaterializedPlan multiWeekPlan({String id = 'race-1'}) {
  MaterializedWeek week(
    int n,
    TrainingPhase phase,
    double km, {
    bool cutback = false,
  }) => MaterializedWeek(
    weekNumber: n,
    phase: phase,
    targetKm: km,
    isCutback: cutback,
    isFrozen: false,
    days: [
      const MaterializedDay(weekday: 0, slot: MaterializedSlot.rest),
      const MaterializedDay(
        weekday: 1,
        slot: MaterializedSlot.quality1,
        intent: WorkoutIntent.threshold,
        templateId: 'cruise_intervals',
      ),
      const MaterializedDay(
        weekday: 2,
        slot: MaterializedSlot.easy,
        intent: WorkoutIntent.aerobicBase,
        templateId: 'easy_run',
      ),
      const MaterializedDay(weekday: 3, slot: MaterializedSlot.rest),
      const MaterializedDay(
        weekday: 4,
        slot: MaterializedSlot.quality2,
        intent: WorkoutIntent.vo2max,
        templateId: 'vo2_400',
      ),
      const MaterializedDay(weekday: 5, slot: MaterializedSlot.rest),
      const MaterializedDay(
        weekday: 6,
        slot: MaterializedSlot.longRun,
        intent: WorkoutIntent.endurance,
        templateId: 'long_steady',
      ),
    ],
  );

  return MaterializedPlan(
    planId: id,
    builtAt: DateTime.parse('2026-09-10T08:00:00.000Z'),
    builtFromVdot: 48,
    inputsFingerprint: 'fp-multi',
    weeks: [
      week(1, TrainingPhase.build, 45),
      week(2, TrainingPhase.build, 32, cutback: true),
      week(3, TrainingPhase.taper, 24),
    ],
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load() returns null when nothing is stored', () async {
    expect(await PlanStore.instance.load(), isNull);
  });

  test('save() then load() round-trips through the local cache', () async {
    await PlanStore.instance.save(planWith(id: 'race-42', vdot: 51));
    final loaded = await PlanStore.instance.load();

    expect(loaded, isNotNull);
    expect(loaded!.planId, 'race-42');
    expect(loaded.builtFromVdot, 51);
    expect(loaded.weeks.single.days[6].templateId, 'long_steady');
    expect(loaded.ladderState, {'threshold': 1});
  });

  test('save() overwrites the previous plan', () async {
    await PlanStore.instance.save(planWith(id: 'old'));
    await PlanStore.instance.save(planWith(id: 'new'));
    expect((await PlanStore.instance.load())!.planId, 'new');
  });

  test('clearLocal() removes the cached plan', () async {
    await PlanStore.instance.save(planWith());
    await PlanStore.instance.clearLocal();
    expect(await PlanStore.instance.load(), isNull);
  });

  test('a stored updated_at timestamp is written alongside the plan', () async {
    await PlanStore.instance.save(planWith());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('materialized_plan_v1_updated_at'), isNotNull);
  });

  test('isRemoteAvailable is false without an initialised Supabase', () {
    expect(PlanStore.instance.isRemoteAvailable, isFalse);
  });

  group('saveAndSync', () {
    test('reports savedNoRemote when there is no signed-in user', () async {
      final outcome = await PlanStore.instance.saveAndSync(planWith(id: 'x'));
      expect(outcome, PlanSyncOutcome.savedNoRemote);
    });

    test('still writes the local cache (and its timestamp)', () async {
      await PlanStore.instance.saveAndSync(planWith(id: 'local-1', vdot: 52));

      final loaded = await PlanStore.instance.load();
      expect(loaded, isNotNull);
      expect(loaded!.planId, 'local-1');
      expect(loaded.builtFromVdot, 52);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('materialized_plan_v1_updated_at'), isNotNull);
    });

    test(
      'serialises every week, long run and rest day through save→load',
      () async {
        await PlanStore.instance.saveAndSync(multiWeekPlan());
        final loaded = await PlanStore.instance.load();

        expect(loaded, isNotNull);
        expect(loaded!.weeks.map((w) => w.weekNumber), [1, 2, 3]);
        expect(loaded.weeks.map((w) => w.phase), [
          TrainingPhase.build,
          TrainingPhase.build,
          TrainingPhase.taper,
        ]);
        expect(loaded.weeks[1].isCutback, isTrue);

        // Every week keeps its single long run and its rest days.
        for (final w in loaded.weeks) {
          expect(w.days, hasLength(7));
          expect(
            w.days.where((d) => d.slot == MaterializedSlot.longRun).length,
            1,
          );
          expect(
            w.days.where((d) => d.slot == MaterializedSlot.rest).length,
            3,
          );
        }
        expect(loaded.weeks.first.qualityCount, 2);
        expect(loaded.weeks.first.days[6].templateId, 'long_steady');
      },
    );
  });
}
