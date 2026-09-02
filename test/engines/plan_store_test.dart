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
}
