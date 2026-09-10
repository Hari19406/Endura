/// PlanAdaptationCoordinator — the detection layer over [PlanAdaptationService].
///
/// Compares the persisted [MaterializedPlan]'s scheduled workout days against
/// the athlete's completed run dates up to "now", finds the current run of
/// consecutively-missed sessions, and — once it reaches
/// [missedSessionThreshold] — asks the service for a recalibrated plan the
/// athlete can review from the Home screen's inline coach banner.
///
/// Pure: no I/O. The screen supplies the plan + run dates, renders the prompt,
/// and persists [PlanRecalibration.updatedPlan] itself if the athlete accepts.
library;

import '../engines/plan/materialized_plan.dart';
import 'plan_adaptation_service.dart';

/// A recalibration the athlete has not yet acted on, plus a stable key naming
/// the exact missed range so a dismissal / acceptance does not nag again.
class AdaptationPrompt {
  final PlanRecalibration recalibration;

  /// Number of consecutively-missed scheduled sessions that triggered this.
  final int missedSessions;

  /// Calendar date of the first missed session in the current run.
  final DateTime firstMissedDate;

  /// Stable id for this missed range — persisted on dismiss/accept so the same
  /// gap never re-prompts, while a *longer* gap (new key) still can.
  final String rangeKey;

  const AdaptationPrompt({
    required this.recalibration,
    required this.missedSessions,
    required this.firstMissedDate,
    required this.rangeKey,
  });

  String get coachExplanation => recalibration.coachExplanation;
  MissedWindow get missedWindow => recalibration.missedWindow;
}

class PlanAdaptationCoordinator {
  const PlanAdaptationCoordinator({
    this.service = const PlanAdaptationService(),
  });

  final PlanAdaptationService service;

  /// A gap shorter than this many missed sessions is left alone — Daniels'
  /// brief window ("under ~48 h, nothing to make up"). The service applies the
  /// same rule to the calendar span; this is the count-based gate on top.
  static const int missedSessionThreshold = 3;

  /// Returns a recalibration prompt when the athlete has missed
  /// [missedSessionThreshold]+ scheduled sessions in a row and the service
  /// actually changes the plan; otherwise null.
  ///
  /// [plan]                  the persisted materialised plan.
  /// [completedRunDates]     dates the athlete logged a run (any time-of-day).
  /// [now]                   "today".
  /// [remainingWeeksToRace]  weeks from [now] to race day (0 when unknown or
  ///                         already inside the taper) — bounds the rebuild.
  AdaptationPrompt? detect({
    required MaterializedPlan plan,
    required Iterable<DateTime> completedRunDates,
    required DateTime now,
    required int remainingWeeksToRace,
  }) {
    if (plan.weeks.isEmpty) return null;

    final today = _dateOnly(now);
    final done = completedRunDates.map(_dateOnly).toSet();

    // Every scheduled (non-rest, has-workout) session strictly before today.
    final week1Start = _dateOnly(plan.builtAt);
    final scheduled = <DateTime>[];
    for (final w in plan.weeks) {
      for (final day in w.days) {
        if (day.isRest || day.workout == null) continue;
        final date = week1Start.add(
          Duration(days: (w.weekNumber - 1) * 7 + day.weekday),
        );
        if (date.isBefore(today)) scheduled.add(date);
      }
    }
    if (scheduled.isEmpty) return null;
    scheduled.sort();

    // Walk back from the most recent past session, counting the trailing run
    // with no matching logged run.
    var missed = 0;
    for (var i = scheduled.length - 1; i >= 0; i--) {
      if (done.contains(scheduled[i])) break;
      missed++;
    }
    if (missed < missedSessionThreshold) return null;

    final firstMissed = scheduled[scheduled.length - missed];

    // Hand the service the *calendar* gap (first missed session → yesterday) so
    // its Daniels classification sees the true time away, not just the count of
    // training days (which is sparse — Mon/Wed/Fri etc.).
    final missedDates = <DateTime>[];
    for (
      var d = firstMissed;
      d.isBefore(today);
      d = d.add(const Duration(days: 1))
    ) {
      missedDates.add(d);
    }

    final recal = service.evaluateAndRecalibrate(
      activePlan: plan,
      currentDate: now,
      missedWorkoutDates: missedDates,
      remainingWeeksToRace: remainingWeeksToRace,
    );
    if (!recal.changedPlan) return null;

    final iso = firstMissed.toIso8601String().substring(0, 10);
    return AdaptationPrompt(
      recalibration: recal,
      missedSessions: missed,
      firstMissedDate: firstMissed,
      rangeKey: 'adapt_${iso}_$missed',
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
