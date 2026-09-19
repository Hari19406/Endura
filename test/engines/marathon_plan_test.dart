import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart'
    show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_materializer.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/training_phase.dart';

void main() {
  final start = DateTime(2026, 1, 5); // Monday

  ({MaterializedPlan plan, List<double> longRuns}) build({
    int runs = 4,
    double base = 25,
    int weeks = 16,
  }) {
    final skeleton = RacePlanBuilder.build(
      currentWeeklyKm: base,
      goalRace: 'marathon',
      raceDate: start.add(Duration(days: weeks * 7)),
      experienceLevel: 'beginner',
      durationWeeks: weeks,
      runsPerWeek: runs,
      now: start,
    );
    final days = switch (runs) {
      3 => [0, 2, 6],
      4 => [0, 2, 4, 6],
      _ => [0, 1, 3, 4, 6],
    };
    final plan = const PlanMaterializer().materialize(
      skeleton: skeleton,
      trainingDayIndices: days,
      longRunDayIndex: 6,
      raceDistance: RaceDistance.marathon,
      experienceLevel: ExperienceLevel.beginner,
      vdot: 35,
      inputsFingerprint: 'fm-test',
    );
    final longRuns = [
      for (final w in plan.weeks)
        w.days
            .where((d) => d.slot == MaterializedSlot.longRun)
            .fold<double>(0, (m, d) => d.plannedKm > m ? d.plannedKm : m),
    ];
    return (plan: plan, longRuns: longRuns);
  }

  group('16-week beginner marathon from a 25 km base (4 days)', () {
    final r = build();
    final weeks = r.plan.weeks;

    test('is 16 weeks with a 3-week taper', () {
      expect(weeks.length, 16);
      expect(
        weeks.where((w) => w.phase == TrainingPhase.taper).length,
        3,
      );
    });

    test('week 1 starts near the base with no build/taper spike', () {
      expect(weeks.first.plannedKm, inInclusiveRange(25.0, 32.0));
      expect(weeks.first.phase, isNot(TrainingPhase.taper));
      expect(weeks[1].plannedKm, lessThanOrEqualTo(weeks.first.plannedKm + 6));
    });

    test('reaches a peak week of at least 50 km', () {
      final peak = weeks
          .where((w) => w.phase != TrainingPhase.taper)
          .map((w) => w.plannedKm)
          .reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThanOrEqualTo(50.0));
    });

    test('delivers a peak long run of at least 24 km', () {
      final peakLr = r.longRuns.reduce((a, b) => a > b ? a : b);
      expect(peakLr, greaterThanOrEqualTo(24.0));
    });

    test('the 3-week taper steps down smoothly and never exceeds the peak', () {
      final build = weeks.where((w) => w.phase != TrainingPhase.taper);
      final peak =
          build.map((w) => w.plannedKm).reduce((a, b) => a > b ? a : b);
      final taper = [
        for (final w in weeks)
          if (w.phase == TrainingPhase.taper) w.plannedKm,
      ];
      expect(taper.first, lessThan(peak));
      for (var i = 1; i < taper.length; i++) {
        expect(taper[i], lessThan(taper[i - 1]),
            reason: 'taper did not step down: $taper');
      }
      expect(taper.last, lessThan(peak * 0.6));
    });
  });
}
