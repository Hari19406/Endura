import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/onboarding/plan_reveal_data.dart';

/// Fixed "today" so plan length is deterministic.
final _now = DateTime(2026, 1, 5); // a Monday

OnboardingAnswers _answers({
  String goal = 'half_marathon',
  int weeksOut = 16,
  double baseline = 30,
  int runsPerWeek = 4,
  List<int> selectedDays = const [0, 2, 4, 5],
  int? longRunDayIndex = 5,
  String experience = 'intermediate',
}) {
  final raceDate = _now.add(Duration(days: weeksOut * 7));
  return OnboardingAnswers(
    goal: goal,
    raceName: 'Test Half',
    raceDate: raceDate,
    experienceRaw: 'regular',
    experienceBridged: experience,
    raceGoalRaw: 'finish',
    baselineWeeklyKm: baseline,
    runsPerWeek: runsPerWeek,
    selectedDays: selectedDays,
    longRunDayIndex: longRunDayIndex,
    paceDistance: 'half',
    paceDistanceKm: 21.0975,
    currentTimeSec: 6600,
    startDate: _now,
    planWeeks: weeksOut,
    vdot: 44,
    vdotProvisional: false,
  );
}

void main() {
  group('PlanProjection', () {
    test('covers every week of the race plan', () {
      final a = _answers();
      final projection = PlanProjection.build(a, now: _now);
      final racePlan = RacePlanBuilder.build(
        currentWeeklyKm: a.baselineWeeklyKm,
        goalRace: a.goal,
        raceDate: a.raceDate,
        experienceLevel: a.experienceBridged,
        now: _now,
      );

      expect(projection.weeks.length, racePlan.weeks.length);
      expect(projection.weeks.first.week, 1);
    });

    // The single most important assertion here. WeekTarget.targetKm is the
    // un-reduced build volume; if the reveal renders that instead of
    // WeekResolver's output, cutback weeks show ~43% too much mileage and the
    // curve no longer matches the plan the athlete actually gets.
    test('cutback weeks render the reduced volume, not the raw target', () {
      final a = _answers();
      final projection = PlanProjection.build(a, now: _now);
      final racePlan = RacePlanBuilder.build(
        currentWeeklyKm: a.baselineWeeklyKm,
        goalRace: a.goal,
        raceDate: a.raceDate,
        experienceLevel: a.experienceBridged,
        now: _now,
      );

      final cutbacks = projection.weeks.where(
        (p) => p.isCutback && p.phase != TrainingPhase.taper,
      );
      expect(cutbacks, isNotEmpty, reason: 'expected at least one cutback week');

      for (final point in cutbacks) {
        final raw = racePlan.weeks
            .firstWhere((w) => w.week == point.week)
            .targetKm;
        expect(
          point.effectiveKm,
          closeTo(raw * 0.70, 0.6),
          reason: 'week ${point.week} should be the 0.70 cutback of $raw',
        );
      }
    });

    test('tapers into the race', () {
      final projection = PlanProjection.build(_answers(), now: _now);
      expect(
        projection.weeks.last.effectiveKm,
        lessThan(projection.peakWeeklyKm),
      );
    });

    test('typical week is a build or peak week, never a cutback', () {
      final projection = PlanProjection.build(_answers(), now: _now);
      final point = projection.weeks.firstWhere(
        (p) => p.week == projection.typicalWeekNumber,
      );
      expect(point.isCutback, isFalse);
      expect(
        point.phase,
        anyOf(TrainingPhase.build, TrainingPhase.peak),
      );
    });

    test('typical week honours the chosen days and long run day', () {
      final a = _answers(
        runsPerWeek: 4,
        selectedDays: const [0, 2, 4, 5],
        longRunDayIndex: 5,
      );
      final projection = PlanProjection.build(a, now: _now);

      expect(projection.typicalWeek.length, 7);

      final training = projection.typicalWeek.where((d) => !d.isRest).toList();
      expect(training.length, a.runsPerWeek);
      expect(
        training.map((d) => d.weekday).toList()..sort(),
        a.selectedDays.toList()..sort(),
      );

      final longRun = projection.typicalWeek.firstWhere((d) => d.weekday == 5);
      expect(longRun.intent, WorkoutIntent.endurance);
    });

    test('peak volume is at least the athlete baseline', () {
      final a = _answers(baseline: 30);
      final projection = PlanProjection.build(a, now: _now);
      expect(
        projection.peakWeeklyKm,
        greaterThanOrEqualTo(a.baselineWeeklyKm),
      );
    });

    // Regression guard for the 7-day archetype fix. Before it, every session in
    // a 7-day week came back with a null distance.
    test('7 runs per week produces real distances on every day', () {
      final a = _answers(
        goal: 'marathon',
        runsPerWeek: 7,
        selectedDays: const [0, 1, 2, 3, 4, 5, 6],
        longRunDayIndex: 5,
        baseline: 60,
      );
      final projection = PlanProjection.build(a, now: _now);

      final training = projection.typicalWeek.where((d) => !d.isRest);
      expect(training.length, 7);
      for (final day in training) {
        expect(
          day.distanceKm,
          isNotNull,
          reason: 'weekday ${day.weekday} had no distance',
        );
        expect(day.distanceKm, greaterThan(0));
      }
    });

    test('a race only two weeks out still projects without throwing', () {
      final a = _answers(weeksOut: 2);
      final projection = PlanProjection.build(a, now: _now);
      expect(projection.weeks, isNotEmpty);
      expect(projection.typicalWeek.length, 7);
    });

    test('fingerprint changes when an answer changes', () {
      expect(
        _answers(runsPerWeek: 4).fingerprint,
        _answers(runsPerWeek: 4).fingerprint,
      );
      expect(
        _answers(runsPerWeek: 4).fingerprint,
        isNot(_answers(runsPerWeek: 5).fingerprint),
      );
    });
  });

  group('planEditFollowUp', () {
    PlanEditFollowUp? call({
      required PlanEditTarget edited,
      String? raceGoal = 'finish',
      int? timeToBeatSec,
      int? targetFinishSec,
      bool needsTargetTime = false,
      int? longRunDayIndex = 5,
      bool daysNeedConfirming = false,
    }) => planEditFollowUp(
      edited: edited,
      raceGoal: raceGoal,
      timeToBeatSec: timeToBeatSec,
      targetFinishSec: targetFinishSec,
      needsTargetTime: needsTargetTime,
      longRunDayIndex: longRunDayIndex,
      daysNeedConfirming: daysNeedConfirming,
    );

    test('goal edit that now needs a target time routes there', () {
      expect(
        call(
          edited: PlanEditTarget.goal,
          raceGoal: 'pr',
          needsTargetTime: true,
          timeToBeatSec: null,
        ),
        PlanEditFollowUp.targetTime,
      );
    });

    test('goal edit with the time already supplied returns to the reveal', () {
      expect(
        call(
          edited: PlanEditTarget.goal,
          raceGoal: 'pr',
          needsTargetTime: true,
          timeToBeatSec: 5400,
        ),
        isNull,
      );
    });

    test('goal edit that does not need a time returns to the reveal', () {
      expect(call(edited: PlanEditTarget.goal), isNull);
    });

    test('runs-per-week edit chains through the day picker first', () {
      expect(
        call(edited: PlanEditTarget.runsPerWeek, daysNeedConfirming: true),
        PlanEditFollowUp.trainingDays,
      );
    });

    test('day-picker edit that cleared the long run day chains on', () {
      expect(
        call(edited: PlanEditTarget.trainingDays, longRunDayIndex: null),
        PlanEditFollowUp.longRunDay,
      );
    });

    test('day-picker edit with the long run day intact returns', () {
      expect(call(edited: PlanEditTarget.trainingDays), isNull);
    });

    test('unrelated edits return straight to the reveal', () {
      expect(call(edited: PlanEditTarget.currentTime), isNull);
      expect(call(edited: PlanEditTarget.planStart), isNull);
      expect(call(edited: PlanEditTarget.longRunDay), isNull);
    });
  });
}
