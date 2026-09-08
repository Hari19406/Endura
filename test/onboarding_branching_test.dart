import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;
import 'package:run_app/models/plan_config_state.dart';

void main() {
  final start = DateTime(2026, 1, 5);

  group('goal classification', () {
    test('race distances are race goals, fitness/consistency are not', () {
      for (final g in [
        PlanGoalType.fiveK,
        PlanGoalType.tenK,
        PlanGoalType.half,
        PlanGoalType.marathon,
      ]) {
        expect(g.isRaceGoal, isTrue, reason: g.name);
        expect(g.raceDistance, isNotNull);
      }
      expect(PlanGoalType.fitness.isRaceGoal, isFalse);
      expect(PlanGoalType.consistency.isRaceGoal, isFalse);
      // open-ended goals still train on a general-endurance anchor
      expect(PlanGoalType.fitness.volumeReferenceDistance, RaceDistance.tenK);
    });
  });

  group('deriveDurationWeeks — race branch (race date given)', () {
    test('a race 12 weeks out ⇒ durationWeeks 12', () {
      final d = PlanConfigState.deriveDurationWeeks(
        raceDate: start.add(const Duration(days: 12 * 7)),
        startDate: start,
        sliderWeeks: 16, // ignored on the race branch
      );
      expect(d, 12);
    });

    test('clamps a far-out race down to 20', () {
      final d = PlanConfigState.deriveDurationWeeks(
        raceDate: start.add(const Duration(days: 30 * 7)),
        startDate: start,
        sliderWeeks: 8,
      );
      expect(d, 20);
    });

    test('clamps a very-near race up to 3', () {
      final d = PlanConfigState.deriveDurationWeeks(
        raceDate: start.add(const Duration(days: 6)),
        startDate: start,
        sliderWeeks: 16,
      );
      expect(d, 3);
    });

    test('counts whole weeks from the chosen start date, not from now', () {
      // race is 84 days out, but the athlete starts a week late → 11 weeks left
      final d = PlanConfigState.deriveDurationWeeks(
        raceDate: start.add(const Duration(days: 84)),
        startDate: start.add(const Duration(days: 7)),
        sliderWeeks: 16,
      );
      expect(d, 11);
    });
  });

  group('deriveDurationWeeks — fitness branch (no race date)', () {
    test('uses the slider value verbatim', () {
      expect(
        PlanConfigState.deriveDurationWeeks(
          raceDate: null,
          startDate: start,
          sliderWeeks: 14,
        ),
        14,
      );
    });

    test('clamps the slider to the 3–20 window', () {
      expect(
        PlanConfigState.deriveDurationWeeks(
          raceDate: null,
          startDate: start,
          sliderWeeks: 25,
        ),
        20,
      );
      expect(
        PlanConfigState.deriveDurationWeeks(
          raceDate: null,
          startDate: start,
          sliderWeeks: 1,
        ),
        3,
      );
    });
  });

  group('handoff into PlanConfigState.fromInputs', () {
    test('race goal: config.durationWeeks reflects the race-date derivation', () {
      final weeks = PlanConfigState.deriveDurationWeeks(
        raceDate: start.add(const Duration(days: 12 * 7)),
        startDate: start,
        sliderWeeks: 18,
      );
      final cfg = PlanConfigState.fromInputs(
        goalType: PlanGoalType.half,
        experience: ExperienceLevel.intermediate,
        vDOT: 46,
        runsPerWeek: 5,
        longRunDay: 6,
        availableDays: const {1, 3, 5, 6, 7},
        durationWeeks: weeks,
      );
      expect(cfg.durationWeeks, 12);
      expect(cfg.goalType.isRaceGoal, isTrue);
    });

    test('fitness goal: config.durationWeeks is the slider value', () {
      final weeks = PlanConfigState.deriveDurationWeeks(
        raceDate: null,
        startDate: start,
        sliderWeeks: 16,
      );
      final cfg = PlanConfigState.fromInputs(
        goalType: PlanGoalType.fitness,
        experience: ExperienceLevel.beginner,
        vDOT: 40,
        runsPerWeek: 4,
        longRunDay: 6,
        availableDays: const {1, 3, 5, 6},
        durationWeeks: weeks,
      );
      expect(cfg.durationWeeks, 16);
      expect(cfg.goalType.isRaceGoal, isFalse);
    });
  });
}
