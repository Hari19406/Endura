/// RaceArchetypeEnvelope — the declarative physiological "shape" of a plan for
/// one race distance: the volume band it lives in, how big the long run may get,
/// how long the taper runs, and what the weekly session mix looks like.
///
/// This is a *specification*, not an allocator. The engine
/// ([RacePlanBuilder] / [ArchetypeTable] / [WeekResolver]) reads these bounds
/// and builds a concrete plan that respects them; the onboarding reveal reads
/// them to describe the plan to the athlete before it is built.
///
/// The 5K envelope is the reference implementation of the intended contract:
///   • baseline volume  18–25 km/wk
///   • peak volume       45–55 km/wk, scaled by runs/week
///   • long run          ≤ 25% of the week, 10–12 km hard ceiling
///   • taper             7–10 days (one deload / sharpening week)
///   • Q1 VO2 max / short intervals · Q2 (5+ runs) threshold / hill strides ·
///     everything else easy aerobic
library;

import 'dart:math' as math;

import 'workout_template_library.dart' show RaceDistance, WorkoutIntent;

/// A closed `[min, max]` interval of weekly kilometres.
typedef KmBand = ({double min, double max});

/// A closed `[min, max]` interval of days.
typedef DayBand = ({int min, int max});

class RaceArchetypeEnvelope {
  final RaceDistance race;

  /// Where a typical athlete's *current* weekly volume sits when they start a
  /// plan for this distance. Drives the onboarding baseline suggestion.
  final KmBand baselineKm;

  /// The weekly-volume ceiling band a full plan ramps toward. The actual peak
  /// is picked inside this band by runs/week — see [peakForRuns].
  final KmBand peakKm;

  /// The long run may never exceed this fraction of the week's volume …
  final double longRunMaxFractionOfWeek;

  /// … nor this many kilometres, whichever is smaller. See [longRunCapKm].
  final double longRunMaxKm;

  /// Calendar length of the race taper.
  final DayBand taperDays;

  /// Number of distinct taper weeks in the macrocycle.
  final int taperWeeks;

  /// Primary quality session intent (Q1) and a short human label.
  final WorkoutIntent quality1Intent;
  final String quality1Label;

  /// Secondary quality session intent (Q2) — only scheduled at
  /// [quality2MinRunsPerWeek] runs/week or more.
  final WorkoutIntent quality2Intent;
  final String quality2Label;
  final int quality2MinRunsPerWeek;

  /// One-line description of the weekly session mix for the reveal UI.
  final String sessionMixSummary;

  const RaceArchetypeEnvelope({
    required this.race,
    required this.baselineKm,
    required this.peakKm,
    required this.longRunMaxFractionOfWeek,
    required this.longRunMaxKm,
    required this.taperDays,
    required this.taperWeeks,
    required this.quality1Intent,
    required this.quality1Label,
    required this.quality2Intent,
    required this.quality2Label,
    required this.quality2MinRunsPerWeek,
    required this.sessionMixSummary,
  });

  // ── Derived helpers ───────────────────────────────────────────────────────

  /// Peak weekly volume for [runsPerWeek], linearly across [peakKm] from 3
  /// runs (`min`) to 6+ runs (`max`).
  double peakForRuns(int runsPerWeek) {
    final r = runsPerWeek.clamp(3, 6);
    final t = (r - 3) / 3.0;
    return peakKm.min + (peakKm.max - peakKm.min) * t;
  }

  /// Hard cap on a single long run given the week's volume: the smaller of
  /// [longRunMaxFractionOfWeek] of the week and [longRunMaxKm].
  double longRunCapKm(double weeklyKm) =>
      math.min(weeklyKm * longRunMaxFractionOfWeek, longRunMaxKm);

  /// Whether a Q2 session is scheduled at this run frequency.
  bool hasSecondQualityAt(int runsPerWeek) =>
      runsPerWeek >= quality2MinRunsPerWeek;

  /// Clamp an arbitrary weekly-volume figure into `[baselineKm.min, peakKm.max]`.
  double clampWeeklyKm(double km) =>
      km.clamp(baselineKm.min, peakKm.max).toDouble();

  // ── Registry ──────────────────────────────────────────────────────────────

  static RaceArchetypeEnvelope of(RaceDistance race) => switch (race) {
        RaceDistance.fiveK => fiveK,
        RaceDistance.tenK => tenK,
        RaceDistance.halfMarathon => halfMarathon,
        RaceDistance.marathon => marathon,
      };

  /// 5K — speed-biased, low volume, tiny long run, one sharpening week.
  static const fiveK = RaceArchetypeEnvelope(
    race: RaceDistance.fiveK,
    baselineKm: (min: 18, max: 25),
    peakKm: (min: 45, max: 55),
    longRunMaxFractionOfWeek: 0.25,
    longRunMaxKm: 12,
    taperDays: (min: 7, max: 10),
    taperWeeks: 1,
    quality1Intent: WorkoutIntent.vo2max,
    quality1Label: 'VO2 max — 400 m–1 km repeats at 5K pace',
    quality2Intent: WorkoutIntent.threshold,
    quality2Label: 'Threshold or hill strides',
    quality2MinRunsPerWeek: 5,
    sessionMixSummary: '1 VO2 max · 1 threshold (5+ runs) · rest easy aerobic',
  );

  /// 10K — VO2/threshold blend, moderate volume.
  static const tenK = RaceArchetypeEnvelope(
    race: RaceDistance.tenK,
    baselineKm: (min: 25, max: 35),
    peakKm: (min: 42, max: 78),
    longRunMaxFractionOfWeek: 0.30,
    longRunMaxKm: 18,
    taperDays: (min: 7, max: 10),
    taperWeeks: 1,
    quality1Intent: WorkoutIntent.vo2max,
    quality1Label: 'VO2 max — 600 m–1.2 km repeats',
    quality2Intent: WorkoutIntent.threshold,
    quality2Label: 'Threshold / cruise intervals',
    quality2MinRunsPerWeek: 5,
    sessionMixSummary: '1 VO2 max · 1 threshold (5+ runs) · rest easy aerobic',
  );

  /// Half marathon — threshold-led, higher volume, two-week taper.
  static const halfMarathon = RaceArchetypeEnvelope(
    race: RaceDistance.halfMarathon,
    baselineKm: (min: 32, max: 45),
    peakKm: (min: 52, max: 92),
    longRunMaxFractionOfWeek: 0.33,
    longRunMaxKm: 26,
    taperDays: (min: 10, max: 14),
    taperWeeks: 2,
    quality1Intent: WorkoutIntent.threshold,
    quality1Label: 'Threshold — sustained tempo / long cruise intervals',
    quality2Intent: WorkoutIntent.vo2max,
    quality2Label: 'VO2 max or race-pace work',
    quality2MinRunsPerWeek: 5,
    sessionMixSummary:
        '1 threshold · 1 VO2 / race-pace (5+ runs) · long run · rest easy',
  );

  /// Marathon — endurance-led, highest volume, three-week taper.
  static const marathon = RaceArchetypeEnvelope(
    race: RaceDistance.marathon,
    baselineKm: (min: 40, max: 55),
    peakKm: (min: 60, max: 112),
    longRunMaxFractionOfWeek: 0.35,
    longRunMaxKm: 38,
    taperDays: (min: 14, max: 21),
    taperWeeks: 3,
    quality1Intent: WorkoutIntent.threshold,
    quality1Label: 'Threshold — marathon-pace & tempo blocks',
    quality2Intent: WorkoutIntent.raceSpecific,
    quality2Label: 'Race-pace long intervals',
    quality2MinRunsPerWeek: 5,
    sessionMixSummary:
        '1 threshold · 1 race-pace (5+ runs) · long run · rest easy aerobic',
  );
}
