/// WorkoutComplianceMatcher — links completed activities back to the scheduled
/// days of a [MaterializedPlan].
///
/// Pure and forward-only: [match] takes the persisted plan plus a list of
/// recent activities and returns a *clone* of the plan whose matched days carry
/// a [DayCompletion] (with `runId` pointing at the activity), together with a
/// receipt of every link made. No I/O — the caller
/// ([WorkoutComplianceCoordinator]) does the loading and saving.
///
/// RULES
///   • Only training days with a resolved workout and no existing completion are
///     candidates — rest days are never marked complete.
///   • An activity matches a scheduled day when its calendar date is within
///     ±[windowDays] of the day's scheduled date (default ±1: a same-day run, or
///     one that slipped a day) *within the same Mon–Sun week*, AND it clears the completion threshold —
///     ≥ [minCompletionRatio] of the target distance, or the same fraction of
///     the workout's estimated duration.
///   • Each activity is claimed by at most one day; the closest date wins, then
///     the closest-to-target distance.
library;

import 'package:flutter/foundation.dart';

import '../engines/plan/materialized_plan.dart';
import '../utils/plan_calendar.dart';
import '../utils/unit_utils.dart';

/// A logged run reduced to what completion-matching needs. The caller builds
/// these from whatever run/activity record it holds.
@immutable
class CompletedActivity {
  /// Stable identifier — stored on the matched day's [DayCompletion.runId].
  final String id;

  /// When the activity happened.
  final DateTime date;

  final double distanceKm;

  /// Moving time in seconds; 0 when unknown.
  final int durationSeconds;

  /// Average pace in seconds per km; null when unknown.
  final int? paceSecPerKm;

  /// Optional self-rated effort (1–10), carried onto the day's completion.
  final double? rpe;

  const CompletedActivity({
    required this.id,
    required this.date,
    required this.distanceKm,
    this.durationSeconds = 0,
    this.paceSecPerKm,
    this.rpe,
  });
}

/// One scheduled day linked to a completed activity.
@immutable
class ComplianceMatch {
  final int weekNumber;

  /// 0 = Monday … 6 = Sunday.
  final int weekday;
  final DateTime scheduledDate;
  final MaterializedSlot slot;

  final String activityId;
  final DateTime activityDate;

  final double targetKm;
  final double actualKm;

  /// `actualKm / targetKm` (≥ 1.0 for a duration-only match / zero-distance
  /// target).
  final double completionRatio;

  /// `activityDate − scheduledDate` in whole days (negative = ran early).
  final int dayOffset;

  const ComplianceMatch({
    required this.weekNumber,
    required this.weekday,
    required this.scheduledDate,
    required this.slot,
    required this.activityId,
    required this.activityDate,
    required this.targetKm,
    required this.actualKm,
    required this.completionRatio,
    required this.dayOffset,
  });
}

@immutable
class WorkoutComplianceResult {
  /// The plan after matching. Identical instance to the input when [matches] is
  /// empty; otherwise a clone whose matched days carry a [DayCompletion].
  final MaterializedPlan plan;
  final List<ComplianceMatch> matches;

  const WorkoutComplianceResult({required this.plan, required this.matches});

  bool get changed => matches.isNotEmpty;
}

class WorkoutComplianceMatcher {
  const WorkoutComplianceMatcher._();

  /// A session counts as done at this fraction of its target distance/duration.
  static const double kMinCompletionRatio = 0.70;

  /// Default ± window (days) around the scheduled date.
  static const int kDefaultWindowDays = 1;

  static WorkoutComplianceResult match({
    required MaterializedPlan plan,
    required List<CompletedActivity> recentActivities,
    int windowDays = kDefaultWindowDays,
    double minCompletionRatio = kMinCompletionRatio,
  }) {
    if (plan.weeks.isEmpty || recentActivities.isEmpty) {
      return WorkoutComplianceResult(plan: plan, matches: const []);
    }

    final win = windowDays.abs();

    // ── Candidate scheduled days ─────────────────────────────────────────────
    // Dates come from the plan's Monday anchor (`plan.dateFor`) — the same
    // source the calendar and Home strips use, so a slot's date can never
    // differ between what's drawn and what's matched. Pre-plan slots (week-1
    // days before the athlete's start date) were never scheduled for them, so
    // they can't claim a run.
    final candidates = <_Candidate>[];
    for (final w in plan.weeks) {
      for (final d in w.days) {
        if (d.isRest || d.workout == null || d.completion != null) continue;
        if (plan.isPrePlanDay(w.weekNumber, d.weekday)) continue;
        candidates.add(
          _Candidate(w.weekNumber, d, plan.dateFor(w.weekNumber, d.weekday)),
        );
      }
    }
    if (candidates.isEmpty) {
      return WorkoutComplianceResult(plan: plan, matches: const []);
    }
    candidates.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

    final acts = [
      for (final a in recentActivities) (_dateOnly(a.date), a),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    // ── Greedy nearest-match, one activity per day ───────────────────────────
    final claimed = <String>{};
    final matches = <ComplianceMatch>[];
    // weekNumber → weekday → completion
    final completions = <int, Map<int, DayCompletion>>{};

    for (final c in candidates) {
      final target = c.day.workout!.totalDistanceKm;
      final plannedSecs = c.day.workout!.estimatedDuration.inSeconds;

      _Scored? best;
      for (final (aDate, a) in acts) {
        if (claimed.contains(a.id)) continue;
        final offset = PlanCalendar.daysBetween(c.scheduledDate, aDate);
        if (offset.abs() > win) continue;
        // A run belongs to the Mon–Sun week it happened in: the ± slip never
        // crosses a week boundary, otherwise a Sunday run would tick off the
        // *next* Monday and a fresh week would open at "1 / N".
        if (PlanCalendar.mondayOf(aDate) !=
            PlanCalendar.mondayOf(c.scheduledDate)) {
          continue;
        }

        final distRatio = target > 0 ? a.distanceKm / target : 1.0;
        final durRatio = (plannedSecs > 0 && a.durationSeconds > 0)
            ? a.durationSeconds / plannedSecs
            : 0.0;
        if (distRatio < minCompletionRatio && durRatio < minCompletionRatio) {
          continue;
        }

        // Lower score wins: date proximity first, then distance closest to plan.
        final score = offset.abs() * 100 + ((distRatio - 1.0).abs() * 10);
        if (best == null || score < best.score) {
          best = _Scored(a, aDate, offset, distRatio, score);
        }
      }
      if (best == null) continue;

      claimed.add(best.act.id);
      (completions[c.weekNumber] ??= {})[c.day.weekday] = DayCompletion(
        completedAt: best.act.date,
        actualKm: best.act.distanceKm,
        actualPaceSecPerKm: best.act.paceSecPerKm,
        rpe: best.act.rpe,
        runId: best.act.id,
      );
      matches.add(ComplianceMatch(
        weekNumber: c.weekNumber,
        weekday: c.day.weekday,
        scheduledDate: c.scheduledDate,
        slot: c.day.slot,
        activityId: best.act.id,
        activityDate: best.act.date,
        targetKm: target,
        actualKm: best.act.distanceKm,
        completionRatio: best.distRatio,
        dayOffset: best.offset,
      ));
    }

    if (matches.isEmpty) {
      return WorkoutComplianceResult(plan: plan, matches: const []);
    }

    // ── Reassemble (untouched weeks by reference) ────────────────────────────
    final weeks = [
      for (final w in plan.weeks)
        if (!completions.containsKey(w.weekNumber))
          w
        else
          w.copyWith(days: [
            for (final d in w.days)
              completions[w.weekNumber]!.containsKey(d.weekday)
                  ? d.copyWith(
                      completion: completions[w.weekNumber]![d.weekday])
                  : d,
          ]),
    ];

    return WorkoutComplianceResult(
      plan: plan.copyWith(weeks: weeks),
      matches: matches,
    );
  }

  /// "Completed: 8.2 km @ 5:12 /km" — the string the WorkoutCard shows in place
  /// of the Start-Run CTA. Pace is omitted when it wasn't captured.
  static String completedStatsLabel(
    DayCompletion completion, {
    bool useMiles = false,
  }) {
    final dist = UnitUtils.displayDistance(completion.actualKm, useMiles);
    final buf = StringBuffer('Completed: ${dist.toStringAsFixed(1)} '
        '${UnitUtils.unitLabel(useMiles)}');
    final pace = completion.actualPaceSecPerKm;
    if (pace != null && pace > 0) {
      final shown =
          UnitUtils.displayPaceSeconds(pace.toDouble(), useMiles).round();
      buf.write(' @ ${UnitUtils.formatSeconds(shown)} '
          '${UnitUtils.perUnitLabel(useMiles)}');
    }
    return buf.toString();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _Candidate {
  final int weekNumber;
  final MaterializedDay day;
  final DateTime scheduledDate;
  const _Candidate(this.weekNumber, this.day, this.scheduledDate);
}

class _Scored {
  final CompletedActivity act;
  final DateTime actDate;
  final int offset;
  final double distRatio;
  final double score;
  const _Scored(
    this.act,
    this.actDate,
    this.offset,
    this.distRatio,
    this.score,
  );
}
