/// Phase 7 — PlanMaterializationCoordinator: fingerprint + build/recompute.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;
import 'package:run_app/engines/plan/plan_materialization_coordinator.dart';
import 'package:run_app/engines/plan/plan_store.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fingerprint is stable for equal inputs, differs when inputs change', () {
    final a = PlanMaterializationCoordinator.fingerprint(
      goalRace: '10k',
      raceDate: DateTime(2026, 6, 1),
      trainingDays: const [6, 0, 2, 4],
      longRunDayIndex: 6,
      experienceLevel: 'intermediate',
      goalTimeSeconds: 2700,
    );
    final b = PlanMaterializationCoordinator.fingerprint(
      goalRace: '10k',
      raceDate: DateTime(2026, 6, 1),
      trainingDays: const [0, 2, 4, 6], // same set, different order
      longRunDayIndex: 6,
      experienceLevel: 'intermediate',
      goalTimeSeconds: 2700,
    );
    final c = PlanMaterializationCoordinator.fingerprint(
      goalRace: '10k',
      raceDate: DateTime(2026, 6, 1),
      trainingDays: const [0, 2, 4, 6],
      longRunDayIndex: 5, // changed
      experienceLevel: 'intermediate',
      goalTimeSeconds: 2700,
    );
    expect(a, b);
    expect(a, isNot(c));
  });

  test('string → enum mapping', () {
    expect(
      PlanMaterializationCoordinator.raceDistanceFrom('half_marathon'),
      RaceDistance.halfMarathon,
    );
    expect(
      PlanMaterializationCoordinator.raceDistanceFrom('marathon'),
      RaceDistance.marathon,
    );
    expect(
      PlanMaterializationCoordinator.experienceLevelFrom('advanced'),
      ExperienceLevel.advanced,
    );
    expect(
      PlanMaterializationCoordinator.experienceLevelFrom('unknown'),
      ExperienceLevel.intermediate,
    );
  });

  test('buildAndStore writes a loadable plan carrying the fingerprint', () async {
    final now = DateTime(2026, 3, 2);
    final skeleton = RacePlanBuilder.build(
      currentWeeklyKm: 40,
      goalRace: '10k',
      raceDate: now.add(const Duration(days: 63)),
      experienceLevel: 'intermediate',
      now: now,
    );

    final built = await PlanMaterializationCoordinator.instance.buildAndStore(
      skeleton: skeleton,
      trainingDayIndices: const [0, 2, 4, 6],
      longRunDayIndex: 6,
      goalRace: '10k',
      experienceLevel: 'intermediate',
      vdot: 47,
      goalTimeSeconds: 2700,
      now: now,
    );

    final loaded = await PlanStore.instance.load();
    expect(loaded, isNotNull);
    expect(loaded!.planId, built.planId);
    expect(loaded.inputsFingerprint, built.inputsFingerprint);
    expect(loaded.weeks.length, skeleton.weeks.length);
  });

  test('recompute with no skeleton returns null', () async {
    final r = await PlanMaterializationCoordinator.instance.recompute(
      skeleton: null,
      trainingDayIndices: const [0, 2, 4, 6],
      longRunDayIndex: 6,
      goalRace: '10k',
      experienceLevel: 'intermediate',
      vdot: 45,
    );
    expect(r, isNull);
  });
}
