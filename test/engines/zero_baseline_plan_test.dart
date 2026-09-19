import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart';
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/race_plan.dart';
import 'package:run_app/models/training_phase.dart';


void main() {
  final now = DateTime(2026, 1, 5);

  RacePlan build0({int runs = 3, double baseline = 0}) => RacePlanBuilder.build(
    currentWeeklyKm: baseline,
    goalRace: '5k',
    raceDate: now.add(const Duration(days: 84)),
    experienceLevel: 'beginner',
    durationWeeks: 12,
    runsPerWeek: runs,
    now: now,
  );

  group('0 km baseline plan (5K first-timer)', () {
    test('week 1 starts between 6 and 8 km', () {
      final plan = build0();
      expect(plan.weeks.first.targetKm, inInclusiveRange(6.0, 8.0));
      expect(build0(runs: 4).weeks.first.targetKm, inInclusiveRange(6.0, 8.0));
    });

    test('progresses without flatlining, then peaks around 18–24 km', () {
      final plan = build0();
      final weeks = plan.weeks;
      final build = weeks.where((w) => w.phase != TrainingPhase.taper).toList();
      for (var i = 1; i < build.length; i++) {
        expect(build[i].targetKm, greaterThanOrEqualTo(build[i - 1].targetKm),
            reason: 'week ${build[i].week} dropped');
      }
      // no stall: volume grows by at least 1 km every non-cutback step
      final normal = build.where((w) => w.week % 4 != 0).toList();
      for (var i = 1; i < normal.length; i++) {
        expect(normal[i].targetKm - normal[i - 1].targetKm,
            greaterThanOrEqualTo(1.0),
            reason: 'stalled at week ${normal[i].week}');
      }
      final peak = weeks.map((w) => w.targetKm).reduce((a, b) => a > b ? a : b);
      expect(peak, inInclusiveRange(18.0, 24.0));
    });

    test('long run starts at 2.5 km or more and never divides to nothing', () {
      final plan = build0();
      expect(plan.weeks.first.longRunKm, greaterThanOrEqualTo(2.5));
      expect(plan.weeks.every((w) => w.targetKm.isFinite), isTrue);
    });

    test('a 6 km week allocates no run under 1.5 km and keeps the sum', () {
      for (final days in const [3, 4]) {
        final wk = days == 4 ? 8.0 : 6.0;
        final w = ArchetypeTable.allocate(
          effectiveKm: wk,
          days: days,
          qualityCount: 1,
          experience: ExperienceLevel.beginner,
          phase: TrainingPhase.base,
          raceDistance: RaceDistance.fiveK,
        );
        expect(w.sessions.length, days);
        for (final s in w.sessions) {
          expect(s.effectiveKm, greaterThanOrEqualTo(1.5),
              reason: 'days=$days ${s.type} ${s.km}');
        }
        expect(w.totalKm, closeTo(wk, ArchetypeTable.allocationTolerance(wk) + 1.5));
        final lr = w.sessions.firstWhere((s) => s.type.isLong);
        expect(lr.effectiveKm / wk, lessThanOrEqualTo(0.40));
      }
    });
  });

  group('long-run progression', () {
    test('a 10K plan on a 45 km base starts below its peak and only climbs', () {
      final plan = RacePlanBuilder.build(
        currentWeeklyKm: 45,
        goalRace: '10k',
        raceDate: now.add(const Duration(days: 84)),
        experienceLevel: 'beginner',
        durationWeeks: 12,
        runsPerWeek: 4,
        now: now,
      );
      final lr = plan.weeks
          .where((w) => w.phase != TrainingPhase.taper)
          .map((w) => w.longRunKm)
          .toList();
      final peakLr = plan.weeks.map((w) => w.longRunKm).reduce(
        (a, b) => a > b ? a : b,
      );
      expect(lr.first, lessThan(peakLr));
      // week 1 already includes one step up from the 75%-of-peak start
      expect(lr.first, lessThanOrEqualTo(peakLr * 0.85));
      for (var i = 1; i < lr.length; i++) {
        expect(lr[i], greaterThanOrEqualTo(lr[i - 1]),
            reason: 'long run shrank at index $i: $lr');
      }
    });
  });
}
