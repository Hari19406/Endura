/// EngineMemoryService.resetCurrentPlan — the deterministic teardown used
/// when an athlete switches race distance or resets training after injury or
/// a disrupted block. Verifies it clears every plan-scoped field (and the
/// PlanStore materialised plan alongside it) while leaving lifetime athlete
/// state — vDOT, total runs, first/last run dates — completely untouched.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/memory/engine_memory.dart';
import 'package:run_app/engines/memory/engine_memory_service.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_store.dart';
import 'package:run_app/models/race_plan.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _firstRunDate = DateTime(2026, 1, 5);

RacePlan _racePlan() => RacePlan(
  goalRace: 'half_marathon',
  raceDate: DateTime(2026, 12, 1),
  createdAt: DateTime(2026, 9, 1),
  startingWeeklyKm: 30,
  experienceLevel: 'intermediate',
  weeks: const [],
);

MaterializedPlan _materializedPlan() => MaterializedPlan(
  planId: 'hm-plan-1',
  builtAt: DateTime(2026, 9, 1),
  builtFromVdot: 45,
  inputsFingerprint: 'fp',
  ladderState: const {'threshold': 2},
  weeks: [
    MaterializedWeek(
      weekNumber: 1,
      phase: TrainingPhase.build,
      targetKm: 30,
      isCutback: false,
      isFrozen: false,
      days: [
        for (var i = 0; i < 7; i++)
          MaterializedDay(weekday: i, slot: MaterializedSlot.rest),
      ],
    ),
  ],
);

/// A memory with an active plan fully wired up, plus lifetime athlete state
/// that must survive the reset untouched.
EngineMemory _memoryWithActivePlan() => EngineMemory(
  vdotScore: 47,
  vdotIsProvisional: false,
  vdotAtPlanStart: 44,
  totalRunsCompleted: 58,
  currentPhase: TrainingPhase.build,
  currentWeek: 6,
  racePlan: _racePlan(),
  firstRunDate: _firstRunDate,
  lastRunDate: DateTime(2026, 9, 10),
  longRunDayIndex: 6,
  planCompletedAt: null,
  isInMaintenance: false,
  weeklyCompletedKm: 18.5,
  weeklyPlannedKm: 32.0,
  weeklyDowngradeCount: 1,
  ladderPositions: const {'threshold': 2, 'vo2max': 1},
  sessionProgress: const {'threshold': 3},
  materializedPlanId: 'hm-plan-1',
  recentTemplateIds: const ['cruise_intervals', 'easy_run'],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('resetCurrentPlan', () {
    test('clears every plan-scoped field on EngineMemory', () async {
      final service = EngineMemoryService();
      await service.save(_memoryWithActivePlan(), syncToCloud: false);

      await service.resetCurrentPlan(syncToCloud: false);
      final after = await service.load();

      expect(after.hasRacePlan, isFalse);
      expect(after.racePlan, isNull);
      expect(after.activePlan, isNull);
      expect(after.materializedPlanId, isNull);
      expect(after.vdotAtPlanStart, isNull);
      expect(after.longRunDayIndex, isNull);
      expect(after.planCompletedAt, isNull);
      expect(after.isInMaintenance, isFalse);
      expect(after.weeklyPlannedKm, 0.0);
      expect(after.weeklyCompletedKm, 0.0);
      expect(after.weeklyDowngradeCount, 0);
      expect(after.ladderPositions, isEmpty);
      expect(after.sessionProgress, isEmpty);
    });

    test(
      'leaves lifetime athlete state untouched — vDOT, run count, run '
      'history dates and recent template history',
      () async {
        final service = EngineMemoryService();
        await service.save(_memoryWithActivePlan(), syncToCloud: false);

        await service.resetCurrentPlan(syncToCloud: false);
        final after = await service.load();

        expect(after.vdotScore, 47);
        expect(after.vdotIsProvisional, isFalse);
        expect(after.totalRunsCompleted, 58);
        expect(after.firstRunDate, _firstRunDate);
        expect(after.lastRunDate, DateTime(2026, 9, 10));
        expect(after.currentPhase, TrainingPhase.build);
        // currentWeek is re-derived from firstRunDate on every copyWith (not
        // a value resetCurrentPlan itself touches) — same as any other
        // EngineMemory mutation, so compare against that same derivation
        // rather than a value frozen at fixture-build time.
        expect(
          after.currentWeek,
          PhaseEngine.weekNumberFromDate(_firstRunDate),
        );
        expect(after.recentTemplateIds, ['cruise_intervals', 'easy_run']);
      },
    );

    test(
      'also tears down the PlanStore materialised plan, so Home/PlanOverview '
      "can't read a stale plan back after \"Remove Plan\"",
      () async {
        await PlanStore.instance.save(_materializedPlan());
        expect(await PlanStore.instance.load(), isNotNull);

        final service = EngineMemoryService();
        await service.save(_memoryWithActivePlan(), syncToCloud: false);
        await service.resetCurrentPlan(syncToCloud: false);

        expect(await PlanStore.instance.load(), isNull);
      },
    );

    test('is idempotent — calling it with no active plan is a safe no-op', () async {
      final service = EngineMemoryService();
      await service.resetCurrentPlan(syncToCloud: false); // must not throw
      final after = await service.load();
      expect(after.hasRacePlan, isFalse);
      expect(after.totalRunsCompleted, 0);
    });
  });
}
