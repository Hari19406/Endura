/// 5K archetype — declarative envelope + its wiring into VolumeModel, the
/// ArchetypeTable long-run cap, and the RacePlanBuilder / PlanProjection volume
/// wave.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_envelope.dart';
import 'package:run_app/engines/config/archetype_table.dart';
import 'package:run_app/engines/config/volume_model.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
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

    test('non-5K distances ignore run frequency (unchanged ceiling)', () {
      for (final race in [
        RaceDistance.tenK,
        RaceDistance.halfMarathon,
        RaceDistance.marathon,
      ]) {
        for (final l in ExperienceLevel.values) {
          for (var r = 3; r <= 7; r++) {
            expect(
              VolumeModel.peakKmForRuns(
                  race: race, experience: l, runsPerWeek: r),
              VolumeModel.peakKm(race, l),
              reason: '$race $l $r',
            );
          }
        }
      }
    });

    test('baseline / peak band helpers delegate to the envelope; 5K safe cap '
        'aligns with the peak ceiling', () {
      expect(VolumeModel.baselineBandKm(RaceDistance.fiveK),
          RaceArchetypeEnvelope.fiveK.baselineKm);
      expect(VolumeModel.peakBandKm(RaceDistance.fiveK),
          RaceArchetypeEnvelope.fiveK.peakKm);
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
}
