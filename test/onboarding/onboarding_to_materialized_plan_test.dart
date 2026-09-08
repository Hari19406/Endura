/// End-to-end: the race-onboarding screens → PlanConfigState → the generator
/// → a MaterializedPlan. Asserts each screen's value lands where it should.
library;

import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/core/vdot_calculator.dart'
    show PrConfidence, vdotFromPr;
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_materializer.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/plan_config_state.dart';
import 'package:run_app/models/training_phase.dart';

void main() {
  final start = DateTime(2026, 1, 5); // Monday

  group('screen-by-screen data flow into the MaterializedPlan', () {
    // ── Simulated onboarding answers ─────────────────────────────────────
    // 1. Race Selection
    final raceDate = start.add(const Duration(days: 84)); // 12 weeks out
    const goal = PlanGoalType.half;
    // 2. Historical Volume  → "Solid training base" tier
    const baselineKm = 40.0;
    // 3. Runs per Week
    const runsPerWeek = 5;
    // 4. Available Days (1 = Mon … 7 = Sun): Mon / Wed / Fri / Sat / Sun
    const availableDays = <int>{1, 3, 5, 6, 7};
    // 5. Long Run Day: Saturday
    const longRunDay = 6;
    // 6. Benchmark Time: half marathon in 1:45:00
    final benchmarkVdot = vdotFromPr(
      prTimeSeconds: 105 * 60,
      prDistanceKm: 21.0975,
      confidence: PrConfidence.high,
    );
    // 7. Start Date
    final durationWeeks = PlanConfigState.deriveDurationWeeks(
      raceDate: raceDate,
      startDate: start,
      sliderWeeks: 16,
    );

    // 8. → synthesized config (what OPagePlanReveal receives)
    final cfg = PlanConfigState.fromInputs(
      goalType: goal,
      experience: ExperienceLevel.intermediate,
      vDOT: benchmarkVdot.toDouble(),
      runsPerWeek: runsPerWeek,
      longRunDay: longRunDay,
      availableDays: availableDays,
      durationWeeks: durationWeeks,
      currentWeeklyKm: baselineKm,
    );

    // Generator handoff — mirrors onboarding `_saveAll` + `_materializePlan…`.
    final skeleton = RacePlanBuilder.build(
      currentWeeklyKm: cfg.weeklyVolumeRange.start,
      goalRace: cfg.goalType.goalRaceKey,
      raceDate: raceDate,
      experienceLevel: 'intermediate',
      now: start,
      durationWeeks: cfg.durationWeeks,
      gradualStart: cfg.gradualStart,
    );
    final plan = const PlanMaterializer().materialize(
      skeleton: skeleton,
      trainingDayIndices: (cfg.availableDays.map((d) => d - 1).toList())..sort(),
      longRunDayIndex: cfg.longRunDay - 1,
      raceDistance: cfg.goalType.raceDistance!,
      experienceLevel: ExperienceLevel.intermediate,
      vdot: cfg.vDOT.round(),
      inputsFingerprint: 'e2e',
      now: start,
    );

    test('the config carries every screen value unchanged', () {
      expect(cfg.goalType, PlanGoalType.half); // screen 1
      expect(cfg.weeklyVolumeRange.start, 40); // screen 2
      expect(cfg.runsPerWeek, 5); // screen 3
      expect(cfg.availableDays, {1, 3, 5, 6, 7}); // screen 4
      expect(cfg.longRunDay, 6); // screen 5
      expect(cfg.vDOT.round(), benchmarkVdot); // screen 6
      expect(cfg.durationWeeks, 12); // screen 7 (84 days / 7)
    });

    test('race date → durationWeeks → plan length', () {
      expect(plan.weeks.length, 12);
    });

    test('benchmark time → VDOT → the plan\'s baked vDOT', () {
      expect(plan.builtFromVdot, benchmarkVdot);
      expect(benchmarkVdot, inInclusiveRange(40, 55)); // sane for a 1:45 half
    });

    test('long-run day → every non-taper long run lands on Saturday', () {
      for (final w in plan.weeks) {
        if (w.phase == TrainingPhase.taper) continue;
        final longDays = w.days
            .where((d) => d.slot == MaterializedSlot.longRun)
            .map((d) => d.weekday)
            .toList();
        expect(longDays, [5], reason: 'week ${w.weekNumber}'); // 5 = Saturday
      }
    });

    test('available days → training only ever falls on checked weekdays', () {
      const checked = {0, 2, 4, 5, 6}; // {1,3,5,6,7} − 1
      for (final w in plan.weeks) {
        for (final d in w.days.where((d) => !d.isRest)) {
          expect(checked, contains(d.weekday), reason: 'week ${w.weekNumber}');
        }
      }
    });

    test('runs per week → ~5 sessions in a build week', () {
      final build = plan.weeks.firstWhere(
        (w) => w.phase == TrainingPhase.build,
      );
      expect(build.days.where((d) => !d.isRest).length, inInclusiveRange(4, 5));
    });

    test('volume tier → week-1 target sits around the 40 km baseline', () {
      final w1 = plan.weekByNumber(1)!;
      expect(w1.targetKm, inInclusiveRange(30.0, 60.0));
      // and it never blows past the safe cap
      expect(
        plan.weeks.map((w) => w.targetKm).reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(100.0),
      );
    });

    test('every materialized training day has a resolved workout with paces', () {
      for (final w in plan.weeks) {
        for (final d in w.days.where((d) => !d.isRest)) {
          expect(d.workout, isNotNull);
          expect(d.workout!.blocks, isNotEmpty);
        }
      }
    });
  });

  group('guardrails (spec §2)', () {
    PlanConfigState make({
      int runsPerWeek = 4,
      int longRunDay = 6,
      Set<int> availableDays = const {1, 3, 5, 6},
    }) => PlanConfigState.fromInputs(
      goalType: PlanGoalType.tenK,
      experience: ExperienceLevel.intermediate,
      vDOT: 48,
      runsPerWeek: runsPerWeek,
      longRunDay: longRunDay,
      availableDays: availableDays,
      durationWeeks: 12,
    );

    test('longRunDay not among available days is snapped onto one', () {
      final cfg = make(longRunDay: 3, availableDays: const {1, 5, 6});
      expect(cfg.availableDays.contains(cfg.longRunDay), isTrue);
      expect(cfg.longRunDay, 6); // latest available
    });

    test('runsPerWeek greater than the checked days is snapped down', () {
      final cfg = make(runsPerWeek: 7, availableDays: const {1, 3, 5});
      expect(cfg.runsPerWeek, 3);
      expect(cfg.availableDays, {1, 3, 5});
    });

    test('a consistent pair is passed straight through', () {
      final cfg = make(
        runsPerWeek: 4,
        longRunDay: 6,
        availableDays: const {1, 3, 5, 6},
      );
      expect(cfg.runsPerWeek, 4);
      expect(cfg.longRunDay, 6);
    });

    test('the constructor rejects a long run outside available days', () {
      expect(
        () => PlanConfigState(
          goalType: PlanGoalType.tenK,
          experience: ExperienceLevel.intermediate,
          vDOT: 48,
          runsPerWeek: 3,
          weeklyVolumeRange: const RangeValues(30, 55),
          longRunRange: const RangeValues(10, 16),
          longRunDay: 2, // not in the set
          availableDays: const {1, 3, 5},
          durationWeeks: 12,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
