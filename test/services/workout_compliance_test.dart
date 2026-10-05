/// WorkoutComplianceMatcher — links logged runs back to the scheduled days of a
/// MaterializedPlan.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/services/workout_compliance_matcher.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

final _start = DateTime(2026, 1, 5); // Monday = week-1 start

ResolvedWorkout _wk(double km, {int pace = 300}) => ResolvedWorkout(
      templateId: 'tpl',
      name: 'tpl',
      intent: WorkoutIntent.vo2max,
      phase: TrainingPhase.build,
      blocks: [
        ResolvedBlock(
          type: BlockType.main,
          distanceKm: km,
          paceMinSecondsPerKm: pace,
          paceMaxSecondsPerKm: pace,
        ),
      ],
    );

MaterializedDay _day(int wd, MaterializedSlot slot, {double km = 0}) {
  final rest = slot == MaterializedSlot.rest;
  return MaterializedDay(
    weekday: wd,
    slot: slot,
    intent: rest ? null : WorkoutIntent.vo2max,
    templateId: rest ? null : 'tpl_$wd',
    workout: rest ? null : _wk(km),
  );
}

/// Mon quality1 (10 km), Wed easy (6 km), Sat long (16 km); Tue/Thu/Fri/Sun rest.
List<MaterializedDay> _weekDays() => [
      _day(0, MaterializedSlot.quality1, km: 10),
      _day(1, MaterializedSlot.rest),
      _day(2, MaterializedSlot.easy, km: 6),
      _day(3, MaterializedSlot.rest),
      _day(4, MaterializedSlot.rest),
      _day(5, MaterializedSlot.longRun, km: 16),
      _day(6, MaterializedSlot.rest),
    ];

MaterializedWeek _week(int n) => MaterializedWeek(
      weekNumber: n,
      phase: TrainingPhase.build,
      targetKm: 40,
      isCutback: false,
      isFrozen: false,
      days: _weekDays(),
    );

MaterializedPlan _plan() => MaterializedPlan(
      planId: 'p1',
      builtAt: _start,
      builtFromVdot: 45,
      inputsFingerprint: 'fp',
      weeks: [_week(1), _week(2)],
    );

CompletedActivity _act(
  String id,
  DateTime date,
  double km, {
  int? pace,
  int durationSeconds = 0,
}) =>
    CompletedActivity(
      id: id,
      date: date,
      distanceKm: km,
      paceSecPerKm: pace,
      durationSeconds: durationSeconds,
    );

DateTime _d(int dayOffset) => _start.add(Duration(days: dayOffset));

void main() {
  test('a run on the scheduled day completes that interval session', () {
    final res = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [_act('run-mon', _d(0), 8.0, pace: 312)],
    );

    expect(res.changed, isTrue);
    expect(res.matches, hasLength(1));

    final m = res.matches.single;
    expect(m.weekNumber, 1);
    expect(m.weekday, 0);
    expect(m.slot, MaterializedSlot.quality1);
    expect(m.activityId, 'run-mon');
    expect(m.completionRatio, closeTo(0.8, 1e-9));
    expect(m.dayOffset, 0);

    final day = res.plan.weekByNumber(1)!.days[0];
    expect(day.isCompleted, isTrue);
    expect(day.completion!.runId, 'run-mon');
    expect(day.completion!.actualKm, 8.0);
    expect(day.completion!.actualPaceSecPerKm, 312);
  });

  test('rest days are never marked complete', () {
    final res = WorkoutComplianceMatcher.match(
      plan: _plan(),
      // A 1.2 km jog logged on a rest day — below every threshold, matches
      // nothing.
      recentActivities: [_act('run-tue', _d(1), 1.2)],
    );

    expect(res.changed, isFalse);
    expect(res.matches, isEmpty);
    for (final w in res.plan.weeks) {
      for (final d in w.days) {
        if (d.slot == MaterializedSlot.rest) {
          expect(d.completion, isNull);
        }
      }
    }
  });

  test('a run weeks away from any scheduled day does not match', () {
    final res = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [_act('run-far', _d(40), 15.0)],
    );
    expect(res.changed, isFalse);
    expect(res.matches, isEmpty);
  });

  test('the ±window is honoured on both sides', () {
    // Friday run (offset −1 from Saturday long), 12 km ≥ 70 % of 16 km.
    final slip = _act('run-fri', _d(4), 12.0);

    final inWindow = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [slip],
      windowDays: 1,
    );
    final m = inWindow.matches.single;
    expect(m.weekday, 5);
    expect(m.slot, MaterializedSlot.longRun);
    expect(m.dayOffset, -1);

    // Same run, zero-tolerance window → no match.
    final tight = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [slip],
      windowDays: 0,
    );
    expect(tight.changed, isFalse);
  });

  test('a run never counts toward a day in a different Mon–Sun week', () {
    // Sunday of week 1 (a rest day) — one day before week 2's Monday quality
    // session. Inside ±1 day, but it belongs to last week, so it must not
    // tick off week 2's Monday and show "1 / N" on a fresh week.
    final sunday = _act('run-sun', _d(6), 8.0);
    final res = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [sunday],
    );
    expect(res.changed, isFalse);
    expect(res.plan.weekByNumber(2)!.days[0].completion, isNull);
  });

  test('clearAutoMatchedCompletions drops only synthetic-id completions', () {
    // Auto-match (id has '#') on Mon, real linked run (numeric id) on Wed.
    final auto = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [_act('2026-01-05T08:00:00.000#8.00', _d(0), 8.0)],
    ).plan;
    final withReal = auto.copyWith(weeks: [
      auto.weeks[0].copyWith(days: [
        for (final d in auto.weeks[0].days)
          d.weekday == 2
              ? d.copyWith(
                  completion: DayCompletion(
                    completedAt: _d(2),
                    actualKm: 6,
                    runId: '42',
                  ),
                )
              : d,
      ]),
      auto.weeks[1],
    ]);

    final cleaned =
        WorkoutComplianceMatcher.clearAutoMatchedCompletions(withReal);
    final days = cleaned.weekByNumber(1)!.days;
    expect(days[0].completion, isNull);
    expect(days[2].completion!.runId, '42');

    // Nothing to clear → same instance.
    expect(
      identical(WorkoutComplianceMatcher.clearAutoMatchedCompletions(cleaned),
          cleaned),
      isTrue,
    );
  });

  test('below the completion threshold on distance → no match', () {
    final res = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [_act('run-short', _d(0), 5.0)], // 50 % of 10 km
    );
    expect(res.changed, isFalse);
  });

  test('short on distance but full duration → matches on the duration path', () {
    // 10 km @ 300 s/km ⇒ planned 3000 s. 2200 s ≈ 73 % clears the threshold.
    final res = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [
        _act('run-time', _d(0), 5.0, durationSeconds: 2200),
      ],
    );
    expect(res.matches.single.weekday, 0);
  });

  test('an already-completed day is skipped (idempotent)', () {
    final first = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [_act('run-mon', _d(0), 9.0)],
    );
    expect(first.changed, isTrue);

    final second = WorkoutComplianceMatcher.match(
      plan: first.plan,
      recentActivities: [_act('run-mon', _d(0), 9.0)],
    );
    expect(second.changed, isFalse);
    expect(identical(second.plan, first.plan), isTrue);
  });

  test('each activity is claimed by at most one day', () {
    final res = WorkoutComplianceMatcher.match(
      plan: _plan(),
      recentActivities: [_act('solo', _d(0), 12.0)],
    );
    expect(res.matches, hasLength(1));
  });

  test('empty inputs return the same plan instance', () {
    final p = _plan();
    expect(
      identical(
        WorkoutComplianceMatcher.match(plan: p, recentActivities: const []).plan,
        p,
      ),
      isTrue,
    );
  });

  test('completedStatsLabel renders distance and pace', () {
    final withPace = DayCompletion(
      completedAt: _start,
      actualKm: 8.2,
      actualPaceSecPerKm: 312,
    );
    expect(
      WorkoutComplianceMatcher.completedStatsLabel(withPace),
      'Completed: 8.2 km @ 5:12 /km',
    );

    final noPace = DayCompletion(completedAt: _start, actualKm: 6.0);
    expect(
      WorkoutComplianceMatcher.completedStatsLabel(noPace),
      'Completed: 6.0 km',
    );
  });
}
