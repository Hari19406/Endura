/// PlanAdaptationCoordinator — the detection gate in front of
/// PlanAdaptationService. Verifies it only surfaces a prompt when the athlete
/// has genuinely missed 3+ consecutive scheduled sessions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/services/plan_adaptation_coordinator.dart';
import 'package:run_app/services/plan_adaptation_service.dart';

// Week 1 starts Monday 2026-01-05. Training days: Mon / Wed / Fri.
final _builtAt = DateTime(2026, 1, 5);
const _trainingWeekdays = [0, 2, 4];

ResolvedWorkout _wk(String id, WorkoutIntent intent) => ResolvedWorkout(
  templateId: id,
  name: id,
  intent: intent,
  phase: TrainingPhase.build,
  coachNote: '',
  blocks: const [
    ResolvedBlock(
      type: BlockType.main,
      distanceKm: 8,
      paceMinSecondsPerKm: 330,
      paceMaxSecondsPerKm: 360,
    ),
  ],
);

MaterializedPlan _plan({int weeks = 12}) {
  TrainingPhase phaseFor(int n) {
    if (n >= weeks - 1) return TrainingPhase.taper;
    if (n >= weeks - 3) return TrainingPhase.peak;
    return TrainingPhase.build;
  }

  final weekList = <MaterializedWeek>[];
  for (var n = 1; n <= weeks; n++) {
    final phase = phaseFor(n);
    weekList.add(
      MaterializedWeek(
        weekNumber: n,
        phase: phase,
        targetKm: 40,
        isCutback: false,
        isFrozen: false,
        days: [
          for (var wd = 0; wd < 7; wd++)
            if (_trainingWeekdays.contains(wd))
              MaterializedDay(
                weekday: wd,
                slot: wd == 4
                    ? MaterializedSlot.longRun
                    : (wd == 2
                          ? MaterializedSlot.quality1
                          : MaterializedSlot.easy),
                intent: wd == 4
                    ? WorkoutIntent.endurance
                    : (wd == 2
                          ? WorkoutIntent.threshold
                          : WorkoutIntent.aerobicBase),
                templateId: 'w${n}_$wd',
                workout: _wk('w${n}_$wd', WorkoutIntent.aerobicBase),
              )
            else
              MaterializedDay(weekday: wd, slot: MaterializedSlot.rest),
        ],
      ),
    );
  }
  return MaterializedPlan(
    planId: 'p1',
    builtAt: _builtAt,
    builtFromVdot: 45,
    inputsFingerprint: 'fp',
    weeks: weekList,
  );
}

/// The calendar date of session [weekNumber]/[weekday].
DateTime _sessionDate(int weekNumber, int weekday) =>
    _builtAt.add(Duration(days: (weekNumber - 1) * 7 + weekday));

void main() {
  const coord = PlanAdaptationCoordinator();

  test('no missed sessions → no prompt', () {
    // Every past session (weeks 1–3) has a matching completed run.
    final now = DateTime(2026, 1, 26); // Monday, week 4
    final done = [
      for (var w = 1; w <= 3; w++)
        for (final wd in _trainingWeekdays) _sessionDate(w, wd),
    ];
    final prompt = coord.detect(
      plan: _plan(),
      completedRunDates: done,
      now: now,
      remainingWeeksToRace: 8,
    );
    expect(prompt, isNull);
  });

  test('only 2 consecutive missed sessions → no prompt (brief window)', () {
    final now = DateTime(2026, 1, 26); // week 4
    // Done through Mon week 3; missed only Wed + Fri week 3.
    final done = <DateTime>[
      for (var w = 1; w <= 2; w++)
        for (final wd in _trainingWeekdays) _sessionDate(w, wd),
      _sessionDate(3, 0),
    ];
    final prompt = coord.detect(
      plan: _plan(),
      completedRunDates: done,
      now: now,
      remainingWeeksToRace: 8,
    );
    expect(prompt, isNull);
  });

  test('3 consecutive missed sessions over ~a week → moderate prompt', () {
    final now = DateTime(2026, 1, 13); // Tue, week 2
    // Only the very first session (Mon week 1) was done; Wed+Fri wk1 and Mon
    // wk2 all missed = 3 sessions, a 6-day calendar gap.
    final prompt = coord.detect(
      plan: _plan(),
      completedRunDates: [_sessionDate(1, 0)],
      now: now,
      remainingWeeksToRace: 10,
    );
    expect(prompt, isNotNull);
    expect(prompt!.missedSessions, 3);
    expect(prompt.missedWindow, MissedWindow.moderate);
    expect(prompt.recalibration.changedPlan, isTrue);
    expect(prompt.rangeKey, startsWith('adapt_2026-01-07_'));
  });

  test('a long gap with no runs → extended prompt', () {
    final now = DateTime(2026, 1, 26); // week 4
    final prompt = coord.detect(
      plan: _plan(),
      completedRunDates: [
        for (final wd in _trainingWeekdays) _sessionDate(1, wd),
      ], // only week 1 done → weeks 2–3 (6 sessions / 14 days) missed
      now: now,
      remainingWeeksToRace: 8,
    );
    expect(prompt, isNotNull);
    expect(prompt!.missedWindow, MissedWindow.extended);
    expect(prompt.recalibration.changedPlan, isTrue);
  });

  test('a run on the most recent scheduled day breaks the streak', () {
    final now = DateTime(2026, 1, 26);
    final done = <DateTime>[
      for (final wd in _trainingWeekdays) _sessionDate(1, wd),
      _sessionDate(3, 4), // most recent past session (Fri wk3) was done
    ];
    final prompt = coord.detect(
      plan: _plan(),
      completedRunDates: done,
      now: now,
      remainingWeeksToRace: 8,
    );
    expect(prompt, isNull);
  });

  test('rangeKey is stable for the same gap', () {
    final now = DateTime(2026, 1, 26);
    final done = [for (final wd in _trainingWeekdays) _sessionDate(1, wd)];
    final a = coord.detect(
      plan: _plan(),
      completedRunDates: done,
      now: now,
      remainingWeeksToRace: 8,
    );
    final b = coord.detect(
      plan: _plan(),
      completedRunDates: done,
      now: now,
      remainingWeeksToRace: 8,
    );
    expect(a!.rangeKey, b!.rangeKey);
  });

  test('empty plan → no prompt', () {
    final prompt = coord.detect(
      plan: MaterializedPlan(
        planId: 'p',
        builtAt: _builtAt,
        builtFromVdot: 45,
        inputsFingerprint: 'fp',
        weeks: const [],
      ),
      completedRunDates: const [],
      now: DateTime(2026, 2, 1),
      remainingWeeksToRace: 6,
    );
    expect(prompt, isNull);
  });
}
