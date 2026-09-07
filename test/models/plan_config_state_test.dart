import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/volume_model.dart';
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;
import 'package:run_app/models/plan_config_state.dart';

void main() {
  group('PlanGoalType', () {
    test('race goals expose a RaceDistance, non-race goals do not', () {
      expect(PlanGoalType.half.raceDistance, RaceDistance.halfMarathon);
      expect(PlanGoalType.half.isRace, isTrue);
      expect(PlanGoalType.fitness.raceDistance, isNull);
      expect(PlanGoalType.fitness.isRace, isFalse);
      // non-race goals still train on a reference distance
      expect(PlanGoalType.consistency.volumeReferenceDistance, RaceDistance.tenK);
    });

    test('goalRaceKey round-trips through fromGoalRaceKey', () {
      for (final g in PlanGoalType.values) {
        expect(PlanGoalType.fromGoalRaceKey(g.goalRaceKey), g);
      }
    });
  });

  group('PlanConfigState.fromInputs — bounds come from VolumeModel', () {
    test('weekly + long-run ranges match VolumeModel for the goal', () {
      final cfg = PlanConfigState.fromInputs(
        goalType: PlanGoalType.marathon,
        experience: ExperienceLevel.intermediate,
        vDOT: 48,
        runsPerWeek: 5,
        longRunDay: 7,
        availableDays: {1, 3, 5, 6, 7},
        durationWeeks: 16,
      );

      final band = VolumeModel.onboardingRange(
        race: RaceDistance.marathon,
        experience: ExperienceLevel.intermediate,
        days: 5,
      );
      final lr = VolumeModel.longRunRangeKm(
        race: RaceDistance.marathon,
        experience: ExperienceLevel.intermediate,
      );

      expect(cfg.weeklyVolumeRange.start, band.defaultKm);
      expect(cfg.weeklyVolumeRange.end, band.max);
      expect(cfg.longRunRange.start, lr.start);
      expect(cfg.longRunRange.end, lr.peak);
    });

    test('an over-eager peak override is clamped to the safe cap', () {
      final cfg = PlanConfigState.fromInputs(
        goalType: PlanGoalType.fiveK,
        experience: ExperienceLevel.beginner,
        vDOT: 38,
        runsPerWeek: 3,
        longRunDay: 6,
        availableDays: {1, 3, 6},
        durationWeeks: 10,
        peakWeeklyKmOverride: 999,
      );
      expect(
        cfg.weeklyVolumeRange.end,
        lessThanOrEqualTo(VolumeModel.safeCapKm(RaceDistance.fiveK)),
      );
    });

    test('currentWeeklyKm below the viable floor is lifted to it', () {
      final cfg = PlanConfigState.fromInputs(
        goalType: PlanGoalType.half,
        experience: ExperienceLevel.beginner,
        vDOT: 40,
        runsPerWeek: 4,
        longRunDay: 7,
        availableDays: {1, 3, 5, 7},
        durationWeeks: 12,
        currentWeeklyKm: 5,
      );
      expect(
        cfg.weeklyVolumeRange.start,
        VolumeModel.minViableKm(RaceDistance.halfMarathon),
      );
    });
  });

  group('gradual start factor', () {
    final base = PlanConfigState.fromInputs(
      goalType: PlanGoalType.tenK,
      experience: ExperienceLevel.intermediate,
      vDOT: 50,
      runsPerWeek: 4,
      longRunDay: 6,
      availableDays: {1, 3, 5, 6},
      durationWeeks: 12,
      gradualStart: true,
    );

    test('week 1 starts at 75% and ramps to 100% by week 5', () {
      expect(base.gradualStartFactorForWeek(1), closeTo(0.75, 1e-9));
      expect(base.gradualStartFactorForWeek(5), 1.0);
      expect(base.gradualStartFactorForWeek(9), 1.0);
    });

    test('factor is strictly increasing across weeks 1–4', () {
      final f = [1, 2, 3, 4].map(base.gradualStartFactorForWeek).toList();
      for (var i = 1; i < f.length; i++) {
        expect(f[i], greaterThan(f[i - 1]));
      }
    });

    test('disabled ⇒ always 1.0', () {
      final off = base.copyWith(gradualStart: false);
      for (final w in [1, 2, 3, 4, 5]) {
        expect(off.gradualStartFactorForWeek(w), 1.0);
      }
    });
  });

  group('serialization + identity', () {
    final cfg = PlanConfigState.fromInputs(
      goalType: PlanGoalType.marathon,
      experience: ExperienceLevel.advanced,
      vDOT: 55,
      runsPerWeek: 6,
      longRunDay: 7,
      availableDays: {1, 2, 4, 5, 6, 7},
      durationWeeks: 18,
      gradualStart: true,
    );

    test('toJson/fromJson round-trips', () {
      final back = PlanConfigState.fromJson(cfg.toJson());
      expect(back, cfg);
      expect(back.fingerprint, cfg.fingerprint);
    });

    test('fingerprint changes when a plan-defining input changes', () {
      expect(cfg.copyWith(runsPerWeek: 5).fingerprint, isNot(cfg.fingerprint));
      expect(cfg.copyWith(vDOT: 56).fingerprint, isNot(cfg.fingerprint));
      expect(
        cfg.copyWith(gradualStart: false).fingerprint,
        isNot(cfg.fingerprint),
      );
    });

    test('availableDays is stored unmodifiable', () {
      expect(() => cfg.availableDays.add(3), throwsUnsupportedError);
    });
  });

  group('constructor validation', () {
    PlanConfigState make({
      int runsPerWeek = 4,
      int durationWeeks = 12,
      int longRunDay = 6,
      Set<int>? availableDays,
    }) => PlanConfigState(
      goalType: PlanGoalType.tenK,
      experience: ExperienceLevel.intermediate,
      vDOT: 50,
      runsPerWeek: runsPerWeek,
      weeklyVolumeRange: const RangeValues(30, 55),
      longRunRange: const RangeValues(8, 16),
      longRunDay: longRunDay,
      availableDays: availableDays ?? {1, 3, 5, 6},
      durationWeeks: durationWeeks,
    );

    test('rejects out-of-range inputs', () {
      expect(() => make(runsPerWeek: 1), throwsA(isA<AssertionError>()));
      expect(() => make(runsPerWeek: 8), throwsA(isA<AssertionError>()));
      expect(() => make(durationWeeks: 2), throwsA(isA<AssertionError>()));
      expect(() => make(durationWeeks: 21), throwsA(isA<AssertionError>()));
      expect(() => make(longRunDay: 0), throwsA(isA<AssertionError>()));
      expect(() => make(availableDays: {}), throwsA(isA<AssertionError>()));
      expect(() => make(availableDays: {1, 9}), throwsA(isA<AssertionError>()));
    });

    test('accepts the documented boundaries', () {
      expect(() => make(runsPerWeek: 2), returnsNormally);
      expect(() => make(runsPerWeek: 7), returnsNormally);
      expect(() => make(durationWeeks: 3), returnsNormally);
      expect(() => make(durationWeeks: 20), returnsNormally);
    });
  });
}
