import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/volume_model.dart';
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/onboarding/plan_reveal_data.dart';

final _now = DateTime(2026, 1, 5);

RaceDistance _md = RaceDistance.marathon;

double _peakTargetKm(List weeks) => weeks
    .where((w) => w.phase != TrainingPhase.taper)
    .map((w) => w.targetKm as double)
    .fold<double>(0, (a, b) => b > a ? b : a);

void main() {
  group('RacePlanBuilder peak overrides', () {
    test('peakWeeklyKmOverride raises the ramp ceiling (still ≤ safe cap)', () {
      final plain = RacePlanBuilder.build(
        currentWeeklyKm: 40,
        goalRace: 'marathon',
        raceDate: _now.add(const Duration(days: 112)),
        experienceLevel: 'intermediate',
        now: _now,
      );
      final tuned = RacePlanBuilder.build(
        currentWeeklyKm: 40,
        goalRace: 'marathon',
        raceDate: _now.add(const Duration(days: 112)),
        experienceLevel: 'intermediate',
        now: _now,
        peakWeeklyKmOverride: 999, // absurd — must clamp to the safe cap
      );

      expect(_peakTargetKm(tuned.weeks), greaterThan(_peakTargetKm(plain.weeks)));
      expect(
        _peakTargetKm(tuned.weeks),
        lessThanOrEqualTo(VolumeModel.safeCapKm(_md)),
      );
    });

    test('a low peakWeeklyKmOverride caps the plan below its natural peak', () {
      final tuned = RacePlanBuilder.build(
        currentWeeklyKm: 45,
        goalRace: 'marathon',
        raceDate: _now.add(const Duration(days: 140)),
        experienceLevel: 'advanced',
        now: _now,
        peakWeeklyKmOverride: 55,
      );
      // ramp is bounded by the override; never floored below current either
      expect(_peakTargetKm(tuned.weeks), lessThanOrEqualTo(55.0 + 0.01));
      expect(_peakTargetKm(tuned.weeks), greaterThanOrEqualTo(45.0));
    });

    test('peakLongRunKmOverride is honoured and clamped to 6–46', () {
      final tuned = RacePlanBuilder.build(
        currentWeeklyKm: 50,
        goalRace: 'marathon',
        raceDate: _now.add(const Duration(days: 140)),
        experienceLevel: 'intermediate',
        now: _now,
        peakLongRunKmOverride: 999,
      );
      final maxLong = tuned.weeks
          .map((w) => w.longRunKm)
          .fold<double>(0, (a, b) => b > a ? b : a);
      expect(maxLong, lessThanOrEqualTo(46.0 + 0.01));
      expect(maxLong, greaterThan(28.0)); // above the default marathon peak
    });
  });

  group('spreadTrainingDays', () {
    test('produces the requested count, sorted, in 0–6', () {
      for (var n = 2; n <= 7; n++) {
        final d = spreadTrainingDays(n, null);
        expect(d.length, n, reason: 'n=$n');
        expect(d, orderedEquals([...d]..sort()));
        expect(d.every((x) => x >= 0 && x <= 6), isTrue);
        expect(d.toSet().length, n, reason: 'no dupes, n=$n');
      }
    });

    test('always includes a valid long-run day', () {
      expect(spreadTrainingDays(3, 6), contains(6));
      expect(spreadTrainingDays(4, 0), contains(0));
      expect(spreadTrainingDays(5, 3), contains(3));
    });

    test('7 days is the whole week', () {
      expect(spreadTrainingDays(7, null), [0, 1, 2, 3, 4, 5, 6]);
    });
  });

  group('PlanProjection tuning overrides', () {
    OnboardingAnswers answers() => OnboardingAnswers(
      goal: 'half_marathon',
      raceDate: _now.add(const Duration(days: 16 * 7)),
      experienceRaw: 'regular',
      experienceBridged: 'intermediate',
      pastMonthKm: 130,
      baselineWeeklyKm: 30,
      runsPerWeek: 4,
      selectedDays: const [0, 2, 4, 5],
      longRunDayIndex: 5,
      paceDistance: 'half',
      paceDistanceKm: 21.0975,
      currentTimeSec: 6600,
      startDate: _now,
      planWeeks: 16,
      vdot: 44,
      vdotProvisional: false,
    );

    test('gradualStart lowers the week-1 effective volume', () {
      final plain = PlanProjection.build(answers(), now: _now);
      final eased = PlanProjection.build(
        answers(),
        now: _now,
        gradualStart: true,
      );
      expect(eased.weeks.first.effectiveKm, lessThan(plain.weeks.first.effectiveKm));
    });

    test('peakKmOverride flows through to the projected peak', () {
      final low = PlanProjection.build(
        answers(),
        now: _now,
        peakKmOverride: 45,
      );
      expect(low.peakWeeklyKm, lessThanOrEqualTo(46.0));
    });

    test('runsPerWeekOverride changes the training-day count of a week', () {
      final three = PlanProjection.build(
        answers(),
        now: _now,
        runsPerWeekOverride: 3,
      );
      final six = PlanProjection.build(
        answers(),
        now: _now,
        runsPerWeekOverride: 6,
      );
      int trainingDays(List slots) =>
          slots.where((s) => !(s.isRest as bool)).length;
      expect(trainingDays(three.previewWeek), lessThan(trainingDays(six.previewWeek)));
    });

    test('exposes a preview (week 2) resolution', () {
      final p = PlanProjection.build(answers(), now: _now);
      expect(p.previewWeekNumber, 2);
      expect(p.previewWeek, isNotEmpty);
    });
  });
}
