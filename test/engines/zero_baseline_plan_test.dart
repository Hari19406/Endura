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

  group('half marathon', () {
    RacePlan hm({
      required double base,
      required String level,
      required int runs,
    }) => RacePlanBuilder.build(
      currentWeeklyKm: base,
      goalRace: 'half_marathon',
      raceDate: now.add(const Duration(days: 84)),
      experienceLevel: level,
      durationWeeks: 12,
      runsPerWeek: runs,
      now: now,
    );

    test('0 km baseline floors week 1 at 12–14 km', () {
      expect(hm(base: 0, level: 'beginner', runs: 3).weeks.first.targetKm,
          inInclusiveRange(12.0, 14.0));
      expect(hm(base: 0, level: 'beginner', runs: 4).weeks.first.targetKm,
          inInclusiveRange(12.0, 14.0));
    });

    test('ramps monotonically into peak, then tapers without a spike', () {
      for (final (base, level, runs) in const [
        (0.0, 'beginner', 3),
        (25.0, 'beginner', 4),
        (45.0, 'intermediate', 4),
      ]) {
        final weeks = hm(base: base, level: level, runs: runs).weeks;
        final build =
            weeks.where((w) => w.phase != TrainingPhase.taper).toList();
        final taper =
            weeks.where((w) => w.phase == TrainingPhase.taper).toList();
        final maxBuild =
            build.map((w) => w.targetKm).reduce((a, b) => a > b ? a : b);
        final maxBuildLr =
            build.map((w) => w.longRunKm).reduce((a, b) => a > b ? a : b);
        for (var i = 1; i < build.length; i++) {
          expect(build[i].targetKm, greaterThanOrEqualTo(build[i - 1].targetKm),
              reason: '$level base=$base week ${build[i].week}');
        }
        expect(taper, isNotEmpty);
        for (final t in taper) {
          expect(t.targetKm, lessThanOrEqualTo(maxBuild),
              reason: '$level base=$base taper week ${t.week} spiked');
          expect(t.longRunKm, lessThanOrEqualTo(maxBuildLr),
              reason: '$level base=$base taper long run spiked');
        }
      }
    });

    test('3-day HM long runs never exceed 42% of the week', () {
      for (final phase in const [
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
      ]) {
        for (final wk in const [12.0, 16.0, 20.0, 30.0, 40.0, 50.0]) {
          final w = ArchetypeTable.allocate(
            effectiveKm: wk,
            days: 3,
            qualityCount: 1,
            experience: ExperienceLevel.intermediate,
            phase: phase,
            raceDistance: RaceDistance.halfMarathon,
          );
          final lr = w.sessions.firstWhere((s) => s.type.isLong);
          expect(lr.effectiveKm / wk, lessThanOrEqualTo(0.42 + 0.02),
              reason: 'phase=$phase wk=$wk lr=${lr.km}');
        }
      }
    });
  });
}
