/// Safety gate + guidance for the runs-per-week slider.
///
/// This is the screen where Endura is measurably safer than the funnels we
/// tore down: they gate the slider on race distance alone, so a first-time
/// marathoner running 10 km/week can select a 113 km/week peak unchallenged.
/// Here the ceiling also respects what the athlete actually runs today.
///
/// NOTE — this deliberately lives in lib/onboarding/ rather than the engine so
/// step 2 could ship without engine changes. It reads only public engine APIs
/// (PeakWeeklyKm.lookup, WeeklyKmRange.forRaceAndDays, ArchetypeTable.build).
/// See ENGINE-TODO below for what should eventually move inward.
library;

import '../engines/config/archetype_table.dart';
import '../engines/config/workout_template_library.dart' show RaceDistance;
import '../models/training_phase.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENGINE-TODO (deferred — do after onboarding is fully implemented)
//
// 1. WeeklyVolumeResolver._ranges is private, so we cannot read the real
//    per-distance safeCap (5K 50 / 10K 80 / HM 100 / FM 130). We approximate
//    with PeakWeeklyKm.lookup, which is a *different* table keyed by
//    experience. Expose the ranges and use the one source of truth.
// 2. WeeklyKmRange.forRaceAndDays has no entry for 7 days — it silently falls
//    back to the 4-day row, which understates a 7-day week badly. Add day 7.
// 3. The slider floor is 3 because ArchetypeTable.build returns null below 3
//    days. A genuine 2-day beginner week needs a 2-day archetype.
// 4. This whole file is arguably engine policy. Once the above land, move it
//    to lib/engines/plan/ and have both onboarding and re-planning use it.
// ─────────────────────────────────────────────────────────────────────────────

/// Hard floor: ArchetypeTable cannot compose a week below 3 days.
const int kMinRunsPerWeek = 3;

/// Hard ceiling: ArchetypeTable tops out at 7.
const int kMaxRunsPerWeek = 7;

class VolumeGuidance {
  /// Largest runs-per-week this athlete may select.
  final int maxRuns;

  /// Where the RECOMMENDED badge sits.
  final int recommendedRuns;

  /// Weekly distance band for the currently selected runs-per-week.
  final int loKm;
  final int hiKm;

  /// Hard quality sessions in the selected week, straight from the archetype.
  final int qualitySessions;

  /// True when the selection is a big jump on what they run today. Not a
  /// block — a flag, so the copy can say so plainly and still let them pass.
  final bool isStretch;

  const VolumeGuidance({
    required this.maxRuns,
    required this.recommendedRuns,
    required this.loKm,
    required this.hiKm,
    required this.qualitySessions,
    required this.isStretch,
  });

  static RaceDistance _race(String goal) => switch (goal) {
    '10k' => RaceDistance.tenK,
    'half_marathon' => RaceDistance.halfMarathon,
    'marathon' => RaceDistance.marathon,
    _ => RaceDistance.fiveK,
  };

  static ExperienceLevel _level(String experience) => switch (experience) {
    'intermediate' => ExperienceLevel.intermediate,
    'advanced' => ExperienceLevel.advanced,
    _ => ExperienceLevel.beginner,
  };

  /// [baselineWeeklyKm] is what the athlete runs now, not what they want to.
  static VolumeGuidance resolve({
    required String goal,
    required String experienceBridged,
    required double baselineWeeklyKm,
    required int selectedRuns,
  }) {
    final race = _race(goal);
    final level = _level(experienceBridged);

    // Two independent ceilings, whichever binds first:
    //   what the distance and experience justify …
    final byExperience = PeakWeeklyKm.lookup(race: race, experience: level);
    //   … and what this athlete's current base can absorb. Roughly doubling
    //   over a full block is aggressive but survivable; the +25 floor keeps
    //   very low bases from being locked out of a real plan entirely.
    final byBaseline = baselineWeeklyKm <= 0
        ? byExperience
        : _max(baselineWeeklyKm * 2.0, baselineWeeklyKm + 25);

    final ceiling = _min(byExperience, byBaseline);

    final maxRuns = _largestDaysWithin(goal, ceiling);
    final recommended = _recommendedDays(
      goal: goal,
      baselineWeeklyKm: baselineWeeklyKm,
      maxRuns: maxRuns,
    );

    final runs = selectedRuns.clamp(kMinRunsPerWeek, maxRuns);
    final range = rangeFor(goal, runs);

    return VolumeGuidance(
      maxRuns: maxRuns,
      recommendedRuns: recommended,
      loKm: range.min.round(),
      hiKm: range.max.round(),
      qualitySessions: _qualityFor(
        weeklyKm: range.defaultKm,
        days: runs,
        level: level,
      ),
      isStretch:
          baselineWeeklyKm > 0 && range.defaultKm > baselineWeeklyKm * 1.8,
    );
  }

  /// Ask the archetype rather than guessing. The old heuristic was
  /// `runsPerWeek >= 5 ? 2 : 1`, which is wrong for a 5-day beginner.
  static int _qualityFor({
    required double weeklyKm,
    required int days,
    required ExperienceLevel level,
  }) {
    final week = ArchetypeTable.build(
      weeklyKm: weeklyKm,
      days: days,
      experience: level,
      phase: TrainingPhase.build,
    );
    return week?.qualityCount ?? (days >= 5 ? 2 : 1);
  }

  /// Weekly range for a day count, working around ENGINE-TODO #2.
  ///
  /// `WeeklyKmRange.forRaceAndDays` has no row for 7 days and silently returns
  /// the 4-day row, so a 7-day week reports *less* volume than a 6-day one
  /// (marathon: 62 km at 6 days, 42 km at 7). Left alone that inverts the
  /// safety gate — 7 days would look like the cheapest option on the slider.
  /// Extrapolate from the 6-day row until the engine has a real 7-day entry.
  static WeeklyKmRange rangeFor(String goal, int days) {
    if (days <= 6) {
      return WeeklyKmRange.forRaceAndDays(race: goal, days: days);
    }
    final six = WeeklyKmRange.forRaceAndDays(race: goal, days: 6);
    return WeeklyKmRange(
      min: six.min * 1.15,
      max: six.max * 1.12,
      defaultKm: six.defaultKm * 1.15,
    );
  }

  static int _largestDaysWithin(String goal, double ceilingKm) {
    var best = kMinRunsPerWeek;
    for (var d = kMinRunsPerWeek; d <= kMaxRunsPerWeek; d++) {
      if (rangeFor(goal, d).defaultKm <= ceilingKm) best = d;
    }
    return best;
  }

  /// The day count whose typical volume sits closest to a sensible early-plan
  /// target — a modest step up from what they run now, not a leap.
  static int _recommendedDays({
    required String goal,
    required double baselineWeeklyKm,
    required int maxRuns,
  }) {
    if (baselineWeeklyKm <= 0) return maxRuns.clamp(kMinRunsPerWeek, 4);
    final target = baselineWeeklyKm * 1.25;

    var best = kMinRunsPerWeek;
    var bestGap = double.infinity;
    for (var d = kMinRunsPerWeek; d <= maxRuns; d++) {
      final gap = (rangeFor(goal, d).defaultKm - target).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = d;
      }
    }
    return best;
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;
}
