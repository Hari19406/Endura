/// Data layer for the onboarding plan reveal.
///
/// Everything here is pure Dart — no widgets — so the projection can be unit
/// tested without pumping a frame.
///
/// KEY RULE (mirrors PlanOverviewScreen._resolveShape):
///   WeekTarget.targetKm is the UN-REDUCED build volume. Cutback and taper
///   multipliers live inside WeekResolver, so the effective km a user actually
///   sees must come from WeekResolver.resolve(...).targetKm — never from
///   WeekTarget.targetKm directly.
library;

import '../engines/config/archetype_table.dart' show ExperienceLevel;
import '../engines/config/workout_template_library.dart' show RaceDistance;
import '../engines/plan/week_resolver.dart';
import '../engines/planner/race_plan_builder.dart';
import '../models/training_phase.dart';

// ============================================================================
// EDIT TARGETS
// ============================================================================

/// A receipt row's owning question. Deliberately decoupled from `OPage` so the
/// reveal widget never imports the onboarding page enum.
enum PlanEditTarget {
  goal,
  runsPerWeek,
  trainingDays,
  longRunDay,
  currentTime,
  planStart,
}

/// A page that must be visited before returning to the reveal, because the
/// edit invalidated a downstream answer.
enum PlanEditFollowUp { targetTime, trainingDays, longRunDay }

// ============================================================================
// ANSWERS
// ============================================================================

/// Immutable snapshot of every onboarding answer the reveal screen needs.
class OnboardingAnswers {
  final String goal; // '5k' | '10k' | 'half_marathon' | 'marathon'
  final String? raceName;
  final String? raceCity;
  final DateTime raceDate;
  final String experienceRaw; // 'regular', 'competitive', …
  final String experienceBridged; // 'beginner' | 'intermediate' | 'advanced'
  final String? raceGoalRaw; // 'pr' | 'target_time' | 'finish' | 'enjoy' | …
  final int? timeToBeatSec;
  final int? targetFinishSec;
  final double baselineWeeklyKm;
  final int runsPerWeek;
  final List<int> selectedDays; // 0 = Mon
  final int? longRunDayIndex;
  final String paceDistance; // '5k' | '10k' | 'half' | 'marathon'
  final double paceDistanceKm;
  final int currentTimeSec;
  final DateTime startDate;
  final int planWeeks;
  final int vdot;
  final bool vdotProvisional;

  const OnboardingAnswers({
    required this.goal,
    this.raceName,
    this.raceCity,
    required this.raceDate,
    required this.experienceRaw,
    required this.experienceBridged,
    this.raceGoalRaw,
    this.timeToBeatSec,
    this.targetFinishSec,
    required this.baselineWeeklyKm,
    required this.runsPerWeek,
    required this.selectedDays,
    this.longRunDayIndex,
    required this.paceDistance,
    required this.paceDistanceKm,
    required this.currentTimeSec,
    required this.startDate,
    required this.planWeeks,
    required this.vdot,
    required this.vdotProvisional,
  });

  RaceDistance get raceDistance => switch (goal) {
    '10k' => RaceDistance.tenK,
    'half_marathon' => RaceDistance.halfMarathon,
    'marathon' => RaceDistance.marathon,
    _ => RaceDistance.fiveK,
  };

  ExperienceLevel get experienceLevel => switch (experienceBridged) {
    'intermediate' => ExperienceLevel.intermediate,
    'advanced' => ExperienceLevel.advanced,
    _ => ExperienceLevel.beginner,
  };

  /// Cheap value fingerprint. Lets the caller skip recomputing the projection
  /// when the user returns from an edit without actually changing anything.
  String get fingerprint => [
    goal,
    raceDate.toIso8601String(),
    experienceBridged,
    raceGoalRaw ?? '',
    baselineWeeklyKm.toStringAsFixed(2),
    runsPerWeek,
    selectedDays.join(','),
    longRunDayIndex ?? -1,
    paceDistance,
    currentTimeSec,
    startDate.toIso8601String(),
    planWeeks,
    vdot,
  ].join('|');
}

// ============================================================================
// PROJECTION
// ============================================================================

class PlanWeekPoint {
  final int week;
  final double effectiveKm;
  final TrainingPhase phase;
  final bool isCutback;
  final double longRunKm;
  final int qualityCount;

  const PlanWeekPoint({
    required this.week,
    required this.effectiveKm,
    required this.phase,
    required this.isCutback,
    required this.longRunKm,
    required this.qualityCount,
  });
}

/// Everything the reveal screen renders, computed once per answer fingerprint.
class PlanProjection {
  final List<PlanWeekPoint> weeks;

  /// The representative week shown as "a typical week" — the biggest build or
  /// peak week, not week 1.
  final List<DaySlot> typicalWeek;
  final int typicalWeekNumber;

  /// The week shown in the "preview your next week" card — week 2 (the first
  /// full ramp week), or the last week for very short plans.
  final List<DaySlot> previewWeek;
  final int previewWeekNumber;

  final double minWeeklyKm;
  final double peakWeeklyKm;
  final int peakWeekNumber;
  final double minLongRunKm;
  final double maxLongRunKm;
  final int minQuality;
  final int maxQuality;

  const PlanProjection({
    required this.weeks,
    required this.typicalWeek,
    required this.typicalWeekNumber,
    required this.previewWeek,
    required this.previewWeekNumber,
    required this.minWeeklyKm,
    required this.peakWeeklyKm,
    required this.peakWeekNumber,
    required this.minLongRunKm,
    required this.maxLongRunKm,
    required this.minQuality,
    required this.maxQuality,
  });

  static const _resolver = WeekResolver();

  /// Builds the whole-plan projection. Pure — no persistence, no I/O.
  ///
  /// Throws only if the underlying plan builder does; callers should guard and
  /// degrade to a receipt-only reveal rather than crashing onboarding.
  static PlanProjection build(
    OnboardingAnswers a, {
    DateTime? now,
    // ── Live tuning overrides (plan-tuning sliders on the reveal screen) ──
    double? baselineKmOverride,
    double? peakKmOverride,
    double? peakLongRunKmOverride,
    int? runsPerWeekOverride,
    bool gradualStart = false,
  }) {
    final racePlan = RacePlanBuilder.build(
      currentWeeklyKm: baselineKmOverride ?? a.baselineWeeklyKm,
      goalRace: a.goal,
      raceDate: a.raceDate,
      experienceLevel: a.experienceBridged,
      now: now,
      // Same goal-branch length onboarding will save — the reveal curve must
      // match the plan the athlete approves.
      durationWeeks: a.planWeeks.clamp(3, 20),
      peakWeeklyKmOverride: peakKmOverride,
      peakLongRunKmOverride: peakLongRunKmOverride,
      gradualStart: gradualStart,
      // Runs-per-week scales the 5K volume wave's peak ceiling.
      runsPerWeek: runsPerWeekOverride ?? a.runsPerWeek,
    );

    final baseDays = a.selectedDays.isNotEmpty
        ? a.selectedDays
        : const [0, 1, 2, 3];
    final days =
        (runsPerWeekOverride != null &&
            runsPerWeekOverride != baseDays.length)
        ? spreadTrainingDays(runsPerWeekOverride, a.longRunDayIndex)
        : baseDays;

    final points = <PlanWeekPoint>[];
    final resolutions = <int, WeekResolution>{};

    for (final week in racePlan.weeks) {
      final isCutback = week.week % 4 == 0;
      final resolution = _resolver.resolve(
        weekTarget: week,
        trainingDayIndices: days,
        raceDistance: a.raceDistance,
        phase: week.phase,
        experienceLevel: a.experienceLevel,
        // Un-reduced volume in; WeekResolver applies cutback/taper itself.
        currentWeeklyKm: week.targetKm,
        longRunDayIndex: a.longRunDayIndex,
        weekNumber: week.week,
        isCutbackWeek: isCutback,
        taperWeekNumber: 1,
      );
      resolutions[week.week] = resolution;
      points.add(
        PlanWeekPoint(
          week: week.week,
          effectiveKm: resolution.targetKm,
          phase: week.phase,
          isCutback: isCutback,
          longRunKm: week.longRunKm,
          qualityCount: resolution.qualityCount,
        ),
      );
    }

    final typical = _pickTypicalWeek(points);
    final previewNum = points.length >= 2 ? points[1].week : points.last.week;

    return PlanProjection(
      weeks: points,
      typicalWeek: resolutions[typical.week]?.days ?? const [],
      typicalWeekNumber: typical.week,
      previewWeek: resolutions[previewNum]?.days ?? const [],
      previewWeekNumber: previewNum,
      minWeeklyKm: points.map((p) => p.effectiveKm).reduce(_min),
      peakWeeklyKm: points.map((p) => p.effectiveKm).reduce(_max),
      peakWeekNumber: points
          .reduce((a, b) => b.effectiveKm > a.effectiveKm ? b : a)
          .week,
      minLongRunKm: points.map((p) => p.longRunKm).reduce(_min),
      maxLongRunKm: points.map((p) => p.longRunKm).reduce(_max),
      minQuality: points.map((p) => p.qualityCount).reduce(_minI),
      maxQuality: points.map((p) => p.qualityCount).reduce(_maxI),
    );
  }

  /// The biggest non-cutback build/peak week — the week that best represents
  /// what training actually looks like. Week 1 is the least informative week in
  /// the plan, and on a 4-week multiple it can even be a cutback.
  static PlanWeekPoint _pickTypicalWeek(List<PlanWeekPoint> points) {
    final candidates = points
        .where(
          (p) =>
              !p.isCutback &&
              (p.phase == TrainingPhase.build || p.phase == TrainingPhase.peak),
        )
        .toList();
    final pool = candidates.isNotEmpty ? candidates : points;
    return pool.reduce((a, b) => b.effectiveKm > a.effectiveKm ? b : a);
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;
  static int _minI(int a, int b) => a < b ? a : b;
  static int _maxI(int a, int b) => a > b ? a : b;
}

/// An evenly spread set of [count] training weekdays (0 = Mon … 6 = Sun).
/// When [longRunDayIndex] is valid the spread is *anchored* on it (so the long
/// run always lands on the chosen day) and the day immediately before it is
/// nudged off when possible, so a mid-week medium-long / aerobic day never sits
/// back-to-back with the long run.
///
/// Used when the runs-per-week tuning slider moves off the day set the athlete
/// originally picked.
List<int> spreadTrainingDays(int count, int? longRunDayIndex) {
  final n = count.clamp(2, 7);
  if (n >= 7) return const [0, 1, 2, 3, 4, 5, 6];

  final hasLr = longRunDayIndex != null &&
      longRunDayIndex >= 0 &&
      longRunDayIndex < 7;
  final anchor = hasLr ? longRunDayIndex : 6;

  // Phase-shifted even spread that lands ON the anchor.
  final picks = <int>{};
  for (var i = 0; i < n; i++) {
    picks.add((anchor + (i * 7 / n).round()) % 7);
  }
  for (var d = 0; picks.length < n; d = (d + 1) % 7) {
    picks.add(d);
  }
  var out = picks.toList()..sort();

  // Keep a buffer before the long run: if the preceding weekday is also a
  // training day, move it to a free day that is itself the least clustered.
  if (hasLr && out.length == n) {
    final before = (anchor + 6) % 7;
    if (out.contains(before)) {
      final free = [
        for (var d = 0; d < 7; d++)
          if (!out.contains(d) && d != anchor && d != before) d,
      ]..sort(
          (a, b) =>
              _adjacentPickCount(a, out).compareTo(_adjacentPickCount(b, out)),
        );
      if (free.isNotEmpty) {
        out = (out.where((d) => d != before).toList()..add(free.first))..sort();
      }
    }
  }

  return out.take(n).toList();
}

int _adjacentPickCount(int day, List<int> picks) {
  final prev = (day + 6) % 7;
  final next = (day + 1) % 7;
  return (picks.contains(prev) ? 1 : 0) + (picks.contains(next) ? 1 : 0);
}

// ============================================================================
// EDIT CHAINING
// ============================================================================

/// Which page (if any) must be visited before returning to the reveal, because
/// the edit the user just made invalidated a downstream answer.
///
/// Extracted as a pure function so every branch is unit testable — driving it
/// through the real PageView would need Supabase for the race picker.
///
/// Returns null when the user can go straight back to the reveal.
PlanEditFollowUp? planEditFollowUp({
  required PlanEditTarget edited,
  required String? raceGoal,
  required int? timeToBeatSec,
  required int? targetFinishSec,
  required bool needsTargetTime,
  required int? longRunDayIndex,
  required bool daysNeedConfirming,
}) {
  // Changing the goal can flip targetTime from skipped to required. The edit
  // short-circuit bypasses the normal conditional skip, so without this the
  // page would never be shown and the time would stay null.
  if (edited == PlanEditTarget.goal && needsTargetTime) {
    final missing = raceGoal == 'pr'
        ? timeToBeatSec == null
        : targetFinishSec == null;
    if (missing) return PlanEditFollowUp.targetTime;
  }

  // runsPerWeek resets selectedDays AND nulls longRunDayIndex, so both get
  // re-confirmed rather than silently defaulted.
  if (edited == PlanEditTarget.runsPerWeek && daysNeedConfirming) {
    return PlanEditFollowUp.trainingDays;
  }

  // The day picker also nulls the long run day.
  if ((edited == PlanEditTarget.runsPerWeek ||
          edited == PlanEditTarget.trainingDays) &&
      longRunDayIndex == null) {
    return PlanEditFollowUp.longRunDay;
  }

  return null;
}
