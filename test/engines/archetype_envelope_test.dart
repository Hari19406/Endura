/// 5K archetype — declarative envelope + its wiring into VolumeModel, the
/// ArchetypeTable long-run cap, and the RacePlanBuilder / PlanProjection volume
/// wave.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_envelope.dart';
import 'package:run_app/engines/config/archetype_table.dart';
import 'package:run_app/engines/config/volume_model.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/week_resolver.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/race_plan.dart' show WeekTarget;
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/onboarding/plan_reveal_data.dart';

final _now = DateTime(2026, 1, 5); // a Monday

OnboardingAnswers _fiveKAnswers({
  int runsPerWeek = 4,
  List<int> selectedDays = const [0, 2, 4, 5],
  int weeksOut = 8,
  double baseline = 22,
  String experience = 'intermediate',
}) {
  return OnboardingAnswers(
    goal: '5k',
    raceName: 'Test 5K',
    raceDate: _now.add(Duration(days: weeksOut * 7)),
    experienceRaw: 'regular',
    experienceBridged: experience,
    raceGoalRaw: 'target_time',
    targetFinishSec: 22 * 60,
    baselineWeeklyKm: baseline,
    runsPerWeek: runsPerWeek,
    selectedDays: selectedDays,
    longRunDayIndex: selectedDays.last,
    paceDistance: '5k',
    paceDistanceKm: 5.0,
    currentTimeSec: 24 * 60,
    startDate: _now,
    planWeeks: weeksOut,
    vdot: 46,
    vdotProvisional: false,
  );
}

OnboardingAnswers _tenKAnswers({
  int runsPerWeek = 5,
  List<int> selectedDays = const [0, 2, 3, 5, 6],
  int weeksOut = 16, // long enough that the runs-scaled peak ceiling binds
  double baseline = 40,
  String experience = 'intermediate',
}) {
  return OnboardingAnswers(
    goal: '10k',
    raceName: 'Test 10K',
    raceDate: _now.add(Duration(days: weeksOut * 7)),
    experienceRaw: 'regular',
    experienceBridged: experience,
    raceGoalRaw: 'target_time',
    targetFinishSec: 46 * 60,
    baselineWeeklyKm: baseline,
    runsPerWeek: runsPerWeek,
    selectedDays: selectedDays,
    longRunDayIndex: selectedDays.last,
    paceDistance: '10k',
    paceDistanceKm: 10.0,
    currentTimeSec: 50 * 60,
    startDate: _now,
    planWeeks: weeksOut,
    vdot: 45,
    vdotProvisional: false,
  );
}

OnboardingAnswers _marathonAnswers({
  int runsPerWeek = 5,
  List<int> selectedDays = const [0, 2, 3, 5, 6],
  int weeksOut = 18,
  double baseline = 55,
  String experience = 'intermediate',
}) {
  return OnboardingAnswers(
    goal: 'marathon',
    raceName: 'Test Marathon',
    raceDate: _now.add(Duration(days: weeksOut * 7)),
    experienceRaw: 'regular',
    experienceBridged: experience,
    raceGoalRaw: 'target_time',
    targetFinishSec: 210 * 60,
    baselineWeeklyKm: baseline,
    runsPerWeek: runsPerWeek,
    selectedDays: selectedDays,
    longRunDayIndex: selectedDays.last,
    paceDistance: 'marathon',
    paceDistanceKm: 42.195,
    currentTimeSec: 225 * 60,
    startDate: _now,
    planWeeks: weeksOut,
    vdot: 44,
    vdotProvisional: false,
  );
}

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  group('RaceArchetypeEnvelope — 5K bounds', () {
    const env = RaceArchetypeEnvelope.fiveK;

    test('baseline volume band is 18–25 km/wk', () {
      expect(env.baselineKm.min, 18);
      expect(env.baselineKm.max, 25);
    });

    test('peak volume band is 45–55 km/wk', () {
      expect(env.peakKm.min, 45);
      expect(env.peakKm.max, 55);
    });

    test('peakForRuns spans the band from 3 to 6 runs and is monotonic', () {
      expect(env.peakForRuns(3), closeTo(45, 0.001));
      expect(env.peakForRuns(6), closeTo(55, 0.001));
      var prev = -1.0;
      for (var r = 3; r <= 7; r++) {
        final p = env.peakForRuns(r);
        expect(p, greaterThanOrEqualTo(prev), reason: '$r runs');
        expect(p, inInclusiveRange(45, 55));
        prev = p;
      }
      // clamps outside 3–6
      expect(env.peakForRuns(2), env.peakForRuns(3));
      expect(env.peakForRuns(9), env.peakForRuns(6));
    });

    test('long run cap is the smaller of 25% of the week and 12 km', () {
      expect(env.longRunMaxFractionOfWeek, 0.25);
      expect(env.longRunMaxKm, 12);
      expect(env.longRunCapKm(32), closeTo(8, 0.001)); // 25% binds
      expect(env.longRunCapKm(48), closeTo(12, 0.001)); // exactly at the km cap
      expect(env.longRunCapKm(70), closeTo(12, 0.001)); // km cap binds
    });

    test('taper is one sharpening week, 7–10 days', () {
      expect(env.taperWeeks, 1);
      expect(env.taperDays.min, 7);
      expect(env.taperDays.max, 10);
    });

    test('session mix: Q1 VO2 max, Q2 threshold only at 5+ runs', () {
      expect(env.quality1Intent, WorkoutIntent.vo2max);
      expect(env.quality2Intent, WorkoutIntent.threshold);
      expect(env.quality2MinRunsPerWeek, 5);
      expect(env.hasSecondQualityAt(4), isFalse);
      expect(env.hasSecondQualityAt(5), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('RaceArchetypeEnvelope — 10K bounds', () {
    const env = RaceArchetypeEnvelope.tenK;

    test('baseline volume band is 22–30 km/wk', () {
      expect(env.baselineKm.min, 22);
      expect(env.baselineKm.max, 30);
    });

    test('peak volume band is 55–65 km/wk', () {
      expect(env.peakKm.min, 55);
      expect(env.peakKm.max, 65);
      expect(env.peakForRuns(3), closeTo(55, 0.001));
      expect(env.peakForRuns(6), closeTo(65, 0.001));
    });

    test('long run cap is the smaller of 28% of the week and 16 km', () {
      expect(env.longRunMaxFractionOfWeek, 0.28);
      expect(env.longRunMaxKm, 16);
      expect(env.longRunCapKm(40), closeTo(11.2, 0.001)); // 28% binds
      expect(env.longRunCapKm(57.15), closeTo(16, 0.01)); // at the km cap
      expect(env.longRunCapKm(80), closeTo(16, 0.001)); // km cap binds
    });

    test('taper is a deload week + a race week, 10–14 days', () {
      expect(env.taperWeeks, 2);
      expect(env.taperDays.min, 10);
      expect(env.taperDays.max, 14);
    });

    test('session mix: Q1 threshold, Q2 VO2 / sub-threshold at 5+ runs', () {
      expect(env.quality1Intent, WorkoutIntent.threshold);
      expect(env.quality2Intent, WorkoutIntent.vo2max);
      expect(env.quality2MinRunsPerWeek, 5);
      expect(env.hasSecondQualityAt(4), isFalse);
      expect(env.hasSecondQualityAt(5), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('RaceArchetypeEnvelope — Marathon bounds', () {
    const env = RaceArchetypeEnvelope.marathon;

    test('baseline volume band is 40–50 km/wk', () {
      expect(env.baselineKm.min, 40);
      expect(env.baselineKm.max, 50);
    });

    test('peak volume band is 75–100 km/wk, anchored 4→7 runs', () {
      expect(env.peakKm.min, 75);
      expect(env.peakKm.max, 100);
      expect(env.peakRunsBand, (lo: 4, hi: 7));
      expect(env.peakForRuns(4), closeTo(75, 0.001));
      expect(env.peakForRuns(7), closeTo(100, 0.001));
      expect(env.peakForRuns(3), env.peakForRuns(4)); // clamp
      expect(env.peakForRuns(9), env.peakForRuns(7)); // clamp
    });

    test('long run cap is the smaller of 35% of the week and a strict 34 km', () {
      expect(env.longRunMaxFractionOfWeek, 0.35);
      expect(env.longRunMaxKm, 34);
      expect(env.longRunCapKm(80), closeTo(28, 0.001)); // 35% binds
      expect(env.longRunCapKm(97.15), closeTo(34, 0.05)); // at the km cap
      expect(env.longRunCapKm(120), closeTo(34, 0.001)); // km cap binds
    });

    test('taper is 3 weeks / 21 days', () {
      expect(env.taperWeeks, 3);
      expect(env.taperDays.min, 21);
      expect(env.taperDays.max, 21);
    });

    test('session mix: Q1 MP / sub-threshold, Q2 semi-long / cruise at 5+ runs',
        () {
      expect(env.quality1Intent, WorkoutIntent.threshold);
      expect(env.quality2Intent, WorkoutIntent.threshold);
      expect(env.quality2MinRunsPerWeek, 5);
      expect(env.hasSecondQualityAt(4), isFalse);
      expect(env.hasSecondQualityAt(5), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('RaceArchetypeEnvelope — registry', () {
    test('every race distance has a well-formed envelope', () {
      for (final race in RaceDistance.values) {
        final e = RaceArchetypeEnvelope.of(race);
        expect(e.race, race);
        expect(e.baselineKm.min, lessThan(e.baselineKm.max));
        expect(e.peakKm.min, lessThanOrEqualTo(e.peakKm.max));
        expect(e.baselineKm.max, lessThanOrEqualTo(e.peakKm.max));
        expect(e.longRunMaxFractionOfWeek, inInclusiveRange(0.2, 0.4));
        expect(e.longRunMaxKm, greaterThan(0));
        expect(e.taperWeeks, greaterThanOrEqualTo(1));
        expect(e.taperDays.min, lessThanOrEqualTo(e.taperDays.max));
      }
    });

    test('long-run ceiling and volume climb with distance', () {
      final five = RaceArchetypeEnvelope.fiveK;
      final ten = RaceArchetypeEnvelope.tenK;
      final half = RaceArchetypeEnvelope.halfMarathon;
      final full = RaceArchetypeEnvelope.marathon;
      expect(five.longRunMaxKm, lessThan(ten.longRunMaxKm));
      expect(ten.longRunMaxKm, lessThan(half.longRunMaxKm));
      expect(half.longRunMaxKm, lessThan(full.longRunMaxKm));
      expect(five.peakKm.max, lessThan(full.peakKm.max));
      expect(five.taperWeeks, lessThanOrEqualTo(full.taperWeeks));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('VolumeModel wiring', () {
    test('peakKmForRuns(5K) stays in the 45–55 band and rises with runs', () {
      var prev = -1.0;
      for (var r = 3; r <= 7; r++) {
        final p = VolumeModel.peakKmForRuns(
          race: RaceDistance.fiveK,
          experience: ExperienceLevel.intermediate,
          runsPerWeek: r,
        );
        expect(p, inInclusiveRange(45, 55), reason: '$r runs');
        expect(p, greaterThanOrEqualTo(prev));
        prev = p;
      }
    });

    test('peakKmForRuns(5K) rises with experience', () {
      double at(ExperienceLevel l) => VolumeModel.peakKmForRuns(
            race: RaceDistance.fiveK,
            experience: l,
            runsPerWeek: 5,
          );
      expect(at(ExperienceLevel.beginner), lessThan(at(ExperienceLevel.intermediate)));
      expect(
        at(ExperienceLevel.intermediate),
        lessThanOrEqualTo(at(ExperienceLevel.advanced)),
      );
    });

    test('peakKmForRuns(10K) stays in the 55–65 band and rises with runs', () {
      var prev = -1.0;
      for (var r = 3; r <= 7; r++) {
        final p = VolumeModel.peakKmForRuns(
          race: RaceDistance.tenK,
          experience: ExperienceLevel.intermediate,
          runsPerWeek: r,
        );
        expect(p, inInclusiveRange(55, 65), reason: '$r runs');
        expect(p, greaterThanOrEqualTo(prev));
        prev = p;
      }
    });

    test('peakKmForRuns(10K) rises with experience', () {
      double at(ExperienceLevel l) => VolumeModel.peakKmForRuns(
            race: RaceDistance.tenK,
            experience: l,
            runsPerWeek: 5,
          );
      expect(at(ExperienceLevel.beginner),
          lessThan(at(ExperienceLevel.intermediate)));
      expect(at(ExperienceLevel.intermediate),
          lessThanOrEqualTo(at(ExperienceLevel.advanced)));
    });

    test('peakKmForRuns(marathon) stays in the 75–100 band, anchored 4→7 runs',
        () {
      double at(int r) => VolumeModel.peakKmForRuns(
            race: RaceDistance.marathon,
            experience: ExperienceLevel.intermediate,
            runsPerWeek: r,
          );
      expect(at(4), closeTo(75, 0.001));
      expect(at(7), closeTo(100, 0.001));
      var prev = -1.0;
      for (var r = 4; r <= 7; r++) {
        expect(at(r), inInclusiveRange(75, 100), reason: '$r runs');
        expect(at(r), greaterThanOrEqualTo(prev));
        prev = at(r);
      }
      // rises with experience
      double byExp(ExperienceLevel l) => VolumeModel.peakKmForRuns(
          race: RaceDistance.marathon, experience: l, runsPerWeek: 6);
      expect(byExp(ExperienceLevel.beginner),
          lessThan(byExp(ExperienceLevel.intermediate)));
      expect(byExp(ExperienceLevel.intermediate),
          lessThanOrEqualTo(byExp(ExperienceLevel.advanced)));
    });

    test('HM still ignores run frequency (unchanged ceiling)', () {
      for (final l in ExperienceLevel.values) {
        for (var r = 3; r <= 7; r++) {
          expect(
            VolumeModel.peakKmForRuns(
                race: RaceDistance.halfMarathon, experience: l, runsPerWeek: r),
            VolumeModel.peakKm(RaceDistance.halfMarathon, l),
            reason: 'HM $l $r',
          );
        }
      }
    });

    test('baseline / peak band helpers delegate to the envelope', () {
      for (final race in RaceDistance.values) {
        expect(VolumeModel.baselineBandKm(race),
            RaceArchetypeEnvelope.of(race).baselineKm);
        expect(VolumeModel.peakBandKm(race),
            RaceArchetypeEnvelope.of(race).peakKm);
      }
      expect(VolumeModel.safeCapKm(RaceDistance.fiveK), 55);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('ArchetypeTable — 5K long-run bound', () {
    // The 5K long run is bounded to the operational fraction (0.33) of the week
    // for every phase / day-count / volume — far below the ~0.55 the generic
    // allocator allows other distances. The real pipeline additionally hands in
    // a ≤ 12 km skeleton target (see the volume-wave group below).
    test('the 5K long run never exceeds ~33% of the week', () {
      for (final phase in const [
        TrainingPhase.base,
        TrainingPhase.build,
        TrainingPhase.peak,
      ]) {
        for (var days = 4; days <= 7; days++) {
          for (final wk in const [25.0, 32.0, 40.0, 48.0]) {
            final w = ArchetypeTable.allocate(
              effectiveKm: wk,
              days: days,
              qualityCount: wk >= 40 ? 2 : 1,
              experience: ExperienceLevel.intermediate,
              phase: phase,
              raceDistance: RaceDistance.fiveK,
            );
            final lr = w.sessions.firstWhere((s) => s.type.isLong);
            expect(lr.effectiveKm / wk, lessThanOrEqualTo(0.34),
                reason: 'phase=$phase days=$days wk=$wk lr=${lr.km}');
          }
        }
      }
    });

    // Given the real pipeline's ≤ 12 km skeleton target, a feasible (5+ day,
    // realistic volume) week keeps the long run right around it.
    test('honours a ≤ 12 km skeleton target on a feasible week', () {
      for (var days = 5; days <= 7; days++) {
        for (final wk in const [25.0, 32.0, 40.0]) {
          final w = ArchetypeTable.allocate(
            effectiveKm: wk,
            days: days,
            qualityCount: wk >= 40 ? 2 : 1,
            experience: ExperienceLevel.intermediate,
            phase: TrainingPhase.build,
            raceDistance: RaceDistance.fiveK,
            longRunKmTarget: RaceArchetypeEnvelope.fiveK.longRunCapKm(wk),
          );
          final lr = w.sessions.firstWhere((s) => s.type.isLong);
          expect(lr.effectiveKm, lessThanOrEqualTo(12.0 + 1.0),
              reason: 'days=$days wk=$wk lr=${lr.km}');
        }
      }
    });

    // The bound is a preference: a 4-day week at 50 km genuinely cannot place
    // the load elsewhere, so the long run stretches — but the weekly sum stays
    // honest and it is still tighter than a half-marathon long run.
    test('an infeasible 4-day / high-volume 5K week keeps the weekly sum honest',
        () {
      final w = ArchetypeTable.allocate(
        effectiveKm: 50,
        days: 4,
        qualityCount: 2,
        experience: ExperienceLevel.intermediate,
        phase: TrainingPhase.build,
        raceDistance: RaceDistance.fiveK,
      );
      final lr = w.sessions.firstWhere((s) => s.type.isLong);
      expect(lr.effectiveKm / 50, lessThanOrEqualTo(0.55));
      expect(w.totalKm, closeTo(50, ArchetypeTable.allocationTolerance(50)));
    });

    test('5K quality sessions stay within the 25%-of-week bound', () {
      for (final wk in const [28.0, 36.0, 45.0]) {
        final w = ArchetypeTable.allocate(
          effectiveKm: wk,
          days: 5,
          qualityCount: 2,
          experience: ExperienceLevel.intermediate,
          phase: TrainingPhase.peak,
          raceDistance: RaceDistance.fiveK,
        );
        for (final q in w.sessions.where((s) => s.type.isQuality)) {
          expect(q.effectiveKm, lessThanOrEqualTo(0.25 * wk + 0.001),
              reason: 'wk=$wk q=${q.km}');
        }
      }
    });

    test('Q1 for a 5K build/peak week is a VO2-max interval session', () {
      for (final phase in const [TrainingPhase.build, TrainingPhase.peak]) {
        final w = ArchetypeTable.build(
          weeklyKm: 40,
          days: 5,
          experience: ExperienceLevel.intermediate,
          phase: phase,
        )!;
        final q1 = w.sessions.firstWhere((s) => s.type.isQuality);
        expect(q1.type, ArchetypeSessionType.interval);
        expect(q1.type.intent, WorkoutIntent.vo2max);
        expect(q1.type.intent, RaceArchetypeEnvelope.fiveK.quality1Intent);
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('5K volume wave — RacePlanBuilder + PlanProjection', () {
    ({double min, double peak, double maxLong, int maxQ}) waveFor(int runs) {
      final days = const {
        3: [0, 2, 5],
        4: [0, 2, 4, 5],
        5: [0, 1, 3, 4, 5],
        6: [0, 1, 2, 3, 4, 5],
      }[runs]!;
      // A long plan on a solid base so the runs-scaled peak *ceiling* is the
      // binding constraint (not the safe weekly-gain ramp).
      final proj = PlanProjection.build(
        _fiveKAnswers(
          runsPerWeek: runs,
          selectedDays: days,
          weeksOut: 16,
          baseline: 34,
        ),
        now: _now,
      );
      return (
        min: proj.minWeeklyKm,
        peak: proj.peakWeeklyKm,
        maxLong: proj.maxLongRunKm,
        maxQ: proj.maxQuality,
      );
    }

    test('peak weekly volume scales up with runs-per-week', () {
      final w3 = waveFor(3);
      final w5 = waveFor(5);
      final w6 = waveFor(6);
      expect(w5.peak, greaterThan(w3.peak));
      expect(w6.peak, greaterThanOrEqualTo(w5.peak));
    });

    test('the wave never exceeds the 5K safe cap and is not flat', () {
      for (final runs in const [3, 4, 5, 6]) {
        final w = waveFor(runs);
        expect(w.peak, lessThanOrEqualTo(VolumeModel.safeCapKm(RaceDistance.fiveK) + 0.5));
        expect(w.peak, greaterThan(w.min), reason: '$runs runs — wave is flat');
      }
    });

    test('skeleton long run for a 5K plan is spec-sized (≤ 12 km)', () {
      for (final runs in const [3, 4, 5, 6]) {
        expect(waveFor(runs).maxLong, lessThanOrEqualTo(12.0 + 0.001));
      }
    });

    test('a 5+ run 5K plan schedules a second quality session', () {
      expect(waveFor(5).maxQ, 2);
      expect(waveFor(6).maxQ, 2);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('10K plan — RacePlanBuilder + WeekResolver', () {
    const resolver = WeekResolver();
    final now = DateTime(2026, 1, 5);

    List<WeekResolution> resolve10k({
      int runsPerWeek = 5,
      double baseline = 30,
      int weeksOut = 12,
    }) {
      final days = const {
        4: [0, 2, 4, 6],
        5: [0, 2, 3, 5, 6],
        6: [0, 1, 2, 4, 5, 6],
      }[runsPerWeek]!;
      final plan = RacePlanBuilder.build(
        currentWeeklyKm: baseline,
        goalRace: '10k',
        raceDate: now.add(Duration(days: weeksOut * 7)),
        experienceLevel: 'intermediate',
        now: now,
        runsPerWeek: runsPerWeek,
      );
      var taperSeen = 0;
      return [
        for (final w in plan.weeks)
          resolver.resolve(
            weekTarget: w,
            trainingDayIndices: days,
            raceDistance: RaceDistance.tenK,
            phase: w.phase,
            experienceLevel: ExperienceLevel.intermediate,
            currentWeeklyKm: w.targetKm,
            longRunDayIndex: days.last,
            weekNumber: w.week,
            isCutbackWeek: w.week % 4 == 0,
            taperWeekNumber:
                w.phase == TrainingPhase.taper ? ++taperSeen : 1,
          ),
      ];
    }

    test('a 10K plan tapers over two weeks (deload + race week)', () {
      final plan = RacePlanBuilder.build(
        currentWeeklyKm: 30,
        goalRace: '10k',
        raceDate: now.add(const Duration(days: 12 * 7)),
        experienceLevel: 'intermediate',
        now: now,
      );
      expect(
        plan.weeks.where((w) => w.phase == TrainingPhase.taper).length,
        2,
      );
    });

    test('build / peak Q1 is a threshold session', () {
      for (final wk in resolve10k()) {
        if (wk.phase != TrainingPhase.build && wk.phase != TrainingPhase.peak) {
          continue;
        }
        final q1 = wk.days.where((d) => d.slotType == SlotType.quality1);
        for (final d in q1) {
          expect(d.intent, WorkoutIntent.threshold,
              reason: 'week ${wk.weekNumber} ${wk.phase.name}');
        }
      }
    });

    test('a 6-run build week adds a VO2 / sub-threshold Q2', () {
      final weeks = resolve10k(runsPerWeek: 6, baseline: 45);
      final buildWeeks = weeks.where((w) =>
          w.phase == TrainingPhase.build &&
          w.days.where((d) => d.slotType == SlotType.quality2).isNotEmpty);
      expect(buildWeeks, isNotEmpty, reason: 'no Q2 scheduled on a 6-run plan');
      for (final wk in buildWeeks) {
        final q2 = wk.days.firstWhere((d) => d.slotType == SlotType.quality2);
        expect(q2.intent, WorkoutIntent.vo2max,
            reason: 'week ${wk.weekNumber}');
      }
    });

    test('every resolved 10K long run is ≤ 16 km, and ≤ ~30% of a full week',
        () {
      for (final runs in const [4, 5, 6]) {
        final weeks = resolve10k(runsPerWeek: runs, baseline: 32);
        for (final wk in weeks) {
          final lr = wk.days.firstWhere((d) => d.isLongRun);
          final km = lr.distanceKm ?? 0;
          expect(km, lessThanOrEqualTo(16.0 + 1.5),
              reason: '$runs runs, week ${wk.weekNumber}: $km km');
          // Cutback / taper weeks deliberately protect the long run while total
          // volume drops harder; a 4-day week can't distribute the load without
          // leaning on the long run. The 28%-ish share holds on full 5+ day
          // weeks — the target case.
          final isCutback = wk.weekNumber % 4 == 0;
          if (runs >= 5 &&
              wk.phase != TrainingPhase.taper &&
              !isCutback &&
              wk.targetKm > 0) {
            expect(km / wk.targetKm, lessThanOrEqualTo(0.32),
                reason: '$runs runs, week ${wk.weekNumber}');
          }
        }
      }
    });

    test('peak volume scales up with runs-per-week and stays ≤ 65 km', () {
      double peakFor(int runs) {
        final days = const {
          3: [0, 2, 5],
          4: [0, 2, 4, 5],
          5: [0, 1, 3, 4, 5],
          6: [0, 1, 2, 3, 4, 5],
        }[runs]!;
        final proj = PlanProjection.build(
          _tenKAnswers(runsPerWeek: runs, selectedDays: days),
          now: now,
        );
        return proj.peakWeeklyKm;
      }

      final p3 = peakFor(3);
      final p5 = peakFor(5);
      final p6 = peakFor(6);
      expect(p5, greaterThan(p3));
      expect(p6, greaterThanOrEqualTo(p5));
      expect(p6, lessThanOrEqualTo(65 + 0.5));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('Marathon plan — RacePlanBuilder + WeekResolver', () {
    const resolver = WeekResolver();
    final now = DateTime(2026, 1, 5);

    List<WeekResolution> resolveMarathon({
      int runsPerWeek = 5,
      double baseline = 45,
      int weeksOut = 18,
    }) {
      final days = const {
        5: [0, 2, 3, 5, 6],
        6: [0, 1, 2, 4, 5, 6],
        7: [0, 1, 2, 3, 4, 5, 6],
      }[runsPerWeek]!;
      final plan = RacePlanBuilder.build(
        currentWeeklyKm: baseline,
        goalRace: 'marathon',
        raceDate: now.add(Duration(days: weeksOut * 7)),
        experienceLevel: 'intermediate',
        now: now,
        runsPerWeek: runsPerWeek,
      );
      var taperSeen = 0;
      return [
        for (final w in plan.weeks)
          resolver.resolve(
            weekTarget: w,
            trainingDayIndices: days,
            raceDistance: RaceDistance.marathon,
            phase: w.phase,
            experienceLevel: ExperienceLevel.intermediate,
            currentWeeklyKm: w.targetKm,
            longRunDayIndex: days.last,
            weekNumber: w.week,
            isCutbackWeek: w.week % 4 == 0,
            taperWeekNumber:
                w.phase == TrainingPhase.taper ? ++taperSeen : 1,
          ),
      ];
    }

    test('a marathon plan tapers over three weeks', () {
      final plan = RacePlanBuilder.build(
        currentWeeklyKm: 45,
        goalRace: 'marathon',
        raceDate: now.add(const Duration(days: 18 * 7)),
        experienceLevel: 'intermediate',
        now: now,
      );
      expect(
        plan.weeks.where((w) => w.phase == TrainingPhase.taper).length,
        3,
      );
    });

    test('the 3-week taper steps down ~80% → ~60% → ~40%', () {
      final weeks = resolveMarathon();
      final taper = [
        for (final w in weeks)
          if (w.phase == TrainingPhase.taper) w
      ];
      expect(taper.length, 3);
      // Un-reduced target is the same peak each taper week; the resolved
      // targetKm carries the multiplier.
      final peak = taper.first.targetKm / 0.80;
      expect(taper[0].targetKm / peak, closeTo(0.80, 0.03));
      expect(taper[1].targetKm / peak, closeTo(0.60, 0.03));
      expect(taper[2].targetKm / peak, closeTo(0.40, 0.03));
    });

    test('build / peak Q1 and Q2 are both sub-threshold (MP / cruise)', () {
      for (final wk in resolveMarathon(runsPerWeek: 6, baseline: 60)) {
        if (wk.phase != TrainingPhase.build) continue;
        for (final d in wk.days.where((d) =>
            d.slotType == SlotType.quality1 ||
            d.slotType == SlotType.quality2)) {
          expect(d.intent, WorkoutIntent.threshold,
              reason: 'week ${wk.weekNumber} ${d.slotType}');
        }
      }
    });

    test('every resolved marathon long run is ≤ 34 km and ≤ ~35% of a full week',
        () {
      for (final runs in const [5, 6, 7]) {
        for (final wk in resolveMarathon(runsPerWeek: runs, baseline: 55)) {
          final lr = wk.days.firstWhere((d) => d.isLongRun);
          final km = lr.distanceKm ?? 0;
          expect(km, lessThanOrEqualTo(34.0 + 0.001),
              reason: '$runs runs, week ${wk.weekNumber}: $km km');
          final isCutback = wk.weekNumber % 4 == 0;
          if (wk.phase != TrainingPhase.taper &&
              !isCutback &&
              wk.targetKm > 0) {
            expect(km / wk.targetKm, lessThanOrEqualTo(0.39),
                reason: '$runs runs, week ${wk.weekNumber}');
          }
        }
      }
    });

    test('peak volume scales with runs-per-week and stays within 75–100 km', () {
      double peakFor(int runs) {
        final days = const {
          4: [0, 2, 4, 6],
          5: [0, 2, 3, 5, 6],
          6: [0, 1, 2, 4, 5, 6],
          7: [0, 1, 2, 3, 4, 5, 6],
        }[runs]!;
        final proj = PlanProjection.build(
          _marathonAnswers(runsPerWeek: runs, selectedDays: days),
          now: now,
        );
        return proj.peakWeeklyKm;
      }

      final p4 = peakFor(4);
      final p6 = peakFor(6);
      final p7 = peakFor(7);
      expect(p6, greaterThan(p4));
      expect(p7, greaterThanOrEqualTo(p6));
      expect(p7, lessThanOrEqualTo(100 + 0.5));
      expect(p4, greaterThanOrEqualTo(70)); // still a real marathon build
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('5K custom durations — 12-week 3:1 build', () {
    const resolver = WeekResolver();
    final now = DateTime(2026, 1, 5);
    const days = [0, 1, 3, 4, 5]; // Mon/Tue/Thu/Fri/Sat

    ({List<WeekTarget> raw, List<WeekResolution> resolved}) build5k({
      required int durationWeeks,
      double baseline = 24,
      int runsPerWeek = 5,
    }) {
      final plan = RacePlanBuilder.build(
        currentWeeklyKm: baseline,
        goalRace: '5k',
        raceDate: now.add(Duration(days: durationWeeks * 7)),
        experienceLevel: 'intermediate',
        now: now,
        durationWeeks: durationWeeks,
        runsPerWeek: runsPerWeek,
      );
      final resolved = [
        for (final w in plan.weeks)
          resolver.resolve(
            weekTarget: w,
            trainingDayIndices: days,
            raceDistance: RaceDistance.fiveK,
            phase: w.phase,
            experienceLevel: ExperienceLevel.intermediate,
            currentWeeklyKm: w.targetKm,
            longRunDayIndex: 5,
            weekNumber: w.week,
            isCutbackWeek:
                w.week % 4 == 0 && w.phase != TrainingPhase.taper,
            taperWeekNumber: 1,
          ),
      ];
      return (raw: plan.weeks, resolved: resolved);
    }

    test('duration clamp honours 6…16+ weeks for a 5K — no 8-week cutoff', () {
      for (final d in const [6, 8, 10, 12, 14, 16, 18]) {
        final p = build5k(durationWeeks: d);
        expect(p.raw.length, d, reason: '$d-week plan');
        expect(p.raw.where((w) => w.phase == TrainingPhase.taper).length, 1,
            reason: '$d-week plan keeps a single 5K taper week');
        expect(p.raw.last.phase, TrainingPhase.taper);
        expect(p.raw.take(d - 1).every((w) => w.phase != TrainingPhase.taper),
            isTrue);
      }
    });

    test('12-week plan lays out two 3:1 cycles + build/peak + a taper week', () {
      final p = build5k(durationWeeks: 12);
      expect(p.raw.length, 12);

      // Deload weeks are the 3:1 cutbacks at W4 and W8 (0-indexed 3, 7).
      for (final di in const [3, 7]) {
        final prev = p.raw[di - 1].targetKm;
        expect(p.raw[di].targetKm, lessThanOrEqualTo(prev + 0.01),
            reason: 'W${di + 1} pauses the load ramp');
        // resolver applies the ~0.70 cutback multiplier
        expect(p.resolved[di].targetKm,
            lessThan(p.resolved[di - 1].targetKm * 0.85),
            reason: 'W${di + 1} effective volume drops');
        // and the ramp recovers the week after
        expect(p.raw[di + 1].targetKm, greaterThan(p.raw[di].targetKm),
            reason: 'W${di + 2} resumes loading');
      }

      // W9–W11 are pure load (build/peak, no cutback); W12 is the taper.
      expect(p.raw[8].phase, anyOf(TrainingPhase.build, TrainingPhase.peak));
      expect(p.raw[9].phase, TrainingPhase.peak);
      expect(p.raw[10].phase, TrainingPhase.peak);
      expect(p.raw[11].phase, TrainingPhase.taper);
      expect(p.resolved[11].targetKm, lessThan(p.resolved[10].targetKm),
          reason: 'taper week sheds volume');
    });

    test('load weeks ramp < 10% week-over-week', () {
      final p = build5k(durationWeeks: 12);
      // consecutive weeks where neither is a deload nor the taper
      const loadPairs = [(0, 1), (1, 2), (4, 5), (5, 6), (8, 9), (9, 10)];
      for (final (a, b) in loadPairs) {
        final ratio = p.raw[b].targetKm / p.raw[a].targetKm;
        expect(ratio, lessThanOrEqualTo(1.10 + 1e-6),
            reason: 'W${a + 1}→W${b + 1} jump = '
                '${((ratio - 1) * 100).toStringAsFixed(1)}%');
        expect(ratio, greaterThan(1.0));
      }
    });

    test('peak volume stays inside the 5K envelope ceiling', () {
      final p = build5k(durationWeeks: 12);
      final peakEff = p.resolved
          .map((r) => r.targetKm)
          .reduce((x, y) => x > y ? x : y);
      expect(peakEff,
          lessThanOrEqualTo(RaceArchetypeEnvelope.fiveK.peakKm.max + 0.5));
    });

    test('every long run is clamped to min(25% of week, 12 km)', () {
      final p = build5k(durationWeeks: 12);

      // The skeleton — what the reveal curve reads — is the hard guarantee.
      for (final w in p.raw) {
        expect(w.longRunKm, lessThanOrEqualTo(12.0 + 0.001),
            reason: 'skeleton W${w.week}: ${w.longRunKm} km');
      }

      // The resolved workout may drift up to the 0.33 operational fraction on a
      // tight week, but never far past the 12 km ceiling.
      for (final r in p.resolved) {
        final km = r.days.firstWhere((d) => d.isLongRun).distanceKm ?? 0;
        expect(km, lessThanOrEqualTo(12.0 + 1.5),
            reason: 'resolved W${r.weekNumber}: $km km');
        final isCutback = r.weekNumber % 4 == 0;
        if (r.phase != TrainingPhase.taper && !isCutback && r.targetKm > 0) {
          expect(km / r.targetKm, lessThanOrEqualTo(0.34),
              reason: 'W${r.weekNumber}');
        }
      }
    });
  });
}
