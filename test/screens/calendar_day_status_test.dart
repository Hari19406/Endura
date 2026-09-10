/// Calendar reads completion straight from MaterializedPlan — no legacy
/// WeeklyPlan, no markMissedDays.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/screens/calendar_day_status.dart';
import 'package:run_app/screens/plan_overview_screen.dart' show MaterializedWeekStrip;
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/services/workout_compliance_matcher.dart';

final _monday = DateTime(2026, 1, 5); // week-1 Monday

ResolvedWorkout _wk(double km) => ResolvedWorkout(
      templateId: 't',
      name: 't',
      intent: WorkoutIntent.vo2max,
      phase: TrainingPhase.build,
      blocks: [
        ResolvedBlock(
          type: BlockType.main,
          distanceKm: km,
          paceMinSecondsPerKm: 300,
          paceMaxSecondsPerKm: 300,
        ),
      ],
    );

MaterializedDay _day(
  int wd,
  MaterializedSlot slot, {
  double km = 8,
  DayCompletion? completion,
}) {
  final rest = slot == MaterializedSlot.rest;
  return MaterializedDay(
    weekday: wd,
    slot: slot,
    intent: rest ? null : WorkoutIntent.vo2max,
    templateId: rest ? null : 't$wd',
    workout: rest ? null : _wk(km),
    completion: completion,
  );
}

DayCompletion _done() =>
    DayCompletion(completedAt: _monday, actualKm: 8.1, actualPaceSecPerKm: 300);

MaterializedWeek _week(List<MaterializedDay> days) => MaterializedWeek(
      weekNumber: 1,
      phase: TrainingPhase.build,
      targetKm: 40,
      isCutback: false,
      isFrozen: false,
      days: days,
    );

void main() {
  group('calendarDayStatus', () {
    final now = DateTime(2026, 1, 8, 10); // Thursday of week 1

    test('a matched completion reads as completed, any date', () {
      final past = _day(0, MaterializedSlot.quality1, completion: _done());
      final future = _day(6, MaterializedSlot.longRun, completion: _done());
      expect(
        calendarDayStatus(past, scheduledDate: _monday, now: now),
        CalendarDayStatus.completed,
      );
      expect(
        calendarDayStatus(future,
            scheduledDate: _monday.add(const Duration(days: 6)), now: now),
        CalendarDayStatus.completed,
      );
    });

    test('a past training day with no completion is missed', () {
      final d = _day(0, MaterializedSlot.quality1); // Monday, before Thursday
      expect(
        calendarDayStatus(d, scheduledDate: _monday, now: now),
        CalendarDayStatus.missed,
      );
    });

    test('a rest day is never missed', () {
      final d = _day(1, MaterializedSlot.rest);
      expect(
        calendarDayStatus(d,
            scheduledDate: _monday.add(const Duration(days: 1)), now: now),
        CalendarDayStatus.restDay,
      );
    });

    test('today and future training days are upcoming', () {
      final today = _day(3, MaterializedSlot.easy); // Thursday == now
      final ahead = _day(5, MaterializedSlot.longRun); // Saturday
      expect(
        calendarDayStatus(today,
            scheduledDate: _monday.add(const Duration(days: 3)), now: now),
        CalendarDayStatus.upcoming,
      );
      expect(
        calendarDayStatus(ahead,
            scheduledDate: _monday.add(const Duration(days: 5)), now: now),
        CalendarDayStatus.upcoming,
      );
    });
  });

  test('a run matched by WorkoutComplianceMatcher immediately reads as '
      'completed on the calendar', () {
    final plan = MaterializedPlan(
      planId: 'p',
      builtAt: _monday,
      builtFromVdot: 45,
      inputsFingerprint: 'fp',
      weeks: [
        _week([
          _day(0, MaterializedSlot.quality1, km: 10),
          _day(1, MaterializedSlot.rest),
          _day(2, MaterializedSlot.easy, km: 6),
          _day(3, MaterializedSlot.rest),
          _day(4, MaterializedSlot.rest),
          _day(5, MaterializedSlot.longRun, km: 16),
          _day(6, MaterializedSlot.rest),
        ]),
      ],
    );

    final res = WorkoutComplianceMatcher.match(
      plan: plan,
      recentActivities: [
        CompletedActivity(
          id: 'run-1',
          date: _monday, // ran the Monday quality
          distanceKm: 8.0,
          paceSecPerKm: 305,
        ),
      ],
    );
    expect(res.changed, isTrue);

    final mondayDay = res.plan.weekByNumber(1)!.days[0];
    // No re-derivation, no lag — the status is a pure read of day.completion.
    expect(
      calendarDayStatus(
        mondayDay,
        scheduledDate: _monday,
        now: _monday.add(const Duration(days: 2)),
      ),
      CalendarDayStatus.completed,
    );
  });

  testWidgets('MaterializedWeekStrip renders completed / missed / upcoming and '
      'is tappable', (tester) async {
    final week = _week([
      _day(0, MaterializedSlot.quality1, completion: _done()), // completed
      _day(1, MaterializedSlot.rest),
      _day(2, MaterializedSlot.easy), // Wed — past, no completion → missed
      _day(3, MaterializedSlot.rest),
      _day(4, MaterializedSlot.rest),
      _day(5, MaterializedSlot.longRun), // Sat — future → upcoming
      _day(6, MaterializedSlot.rest),
    ]);

    MaterializedDay? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(
        body: MaterializedWeekStrip(
          week: week,
          weekMonday: _monday,
          now: DateTime(2026, 1, 8), // Thursday
          onDayTap: (d, _) => tapped = d,
        ),
      ),
    ));

    // The completed day shows a check.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // The missed training day shows the missed dash.
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pump();
    expect(tapped, isNotNull);
    expect(tapped!.weekday, 0);
  });
}
