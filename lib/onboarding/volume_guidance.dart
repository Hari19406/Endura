/// Safety gate + guidance for the runs-per-week slider.
///
/// This is the screen where Endura is measurably safer than the funnels we
/// tore down: they gate the slider on race distance alone, so a first-time
/// marathoner running 10 km/week can select a 113 km/week peak unchallenged.
/// Here the ceiling also respects what the athlete actually runs today.
///
/// Volume numbers now come from the single source [VolumeModel]
/// (experience-aware, defined for 3–7 days). This file is thin policy on top:
/// how many days an athlete may pick, where RECOMMENDED sits, and whether a
/// selection is a stretch on their current base.
library;

import '../engines/config/archetype_table.dart';
import '../engines/config/volume_model.dart';
import '../engines/config/workout_template_library.dart' show RaceDistance;
import '../models/training_phase.dart';

// ENGINE-TODO (remaining): a genuine 2-day beginner week needs a 2-day
// archetype (ArchetypeTable returns null below 3). And this file is arguably
// engine policy — could move to lib/engines/plan/ so re-planning shares it.

/// Hard floor: ArchetypeTable cannot compose a week below 3 days.
const int kMinRunsPerWeek = 3;

/// Hard ceiling: ArchetypeTable tops out at 7.
const int kMaxRunsPerWeek = 7;

class VolumeGuidance {
  /// Largest runs-per-week this athlete may select.
  final int maxRuns;

  /// Where the RECOMMENDED badge sits.
  final int recommendedRuns;

  /// Projected weekly-distance band for the *currently selected* runs-per-week —
  /// recomputed on every slider step (see [_bandForDays]).
  final int loKm;
  final int hiKm;

  /// Quality sessions the archetype composes for a peak build week at this day
  /// count. Week 1 / Base always opens at one quality — the "at a glance" card
  /// shows the base structure (1 quality · 1 long · rest easy).
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
    final byExperience = VolumeModel.peakKm(race, level);
    //   … and what this athlete's current base can absorb. Roughly doubling
    //   over a full block is aggressive but survivable; the +25 floor keeps
    //   very low bases from being locked out of a real plan entirely.
    final byBaseline = baselineWeeklyKm <= 0
        ? byExperience
        : _max(baselineWeeklyKm * 2.0, baselineWeeklyKm + 25);

    final ceiling = _min(byExperience, byBaseline);

    final maxRuns = _largestDaysWithin(goal, level, ceiling);
    final recommended = _recommendedDays(
      goal: goal,
      experience: experienceBridged,
      baselineWeeklyKm: baselineWeeklyKm,
      maxRuns: maxRuns,
    );

    final runs = selectedRuns.clamp(kMinRunsPerWeek, maxRuns);
    final range = rangeFor(goal, experienceBridged, runs);
    final band = _bandForDays(
      goal: goal,
      experience: experienceBridged,
      days: runs,
      baselineWeeklyKm: baselineWeeklyKm,
    );

    return VolumeGuidance(
      maxRuns: maxRuns,
      recommendedRuns: recommended,
      loKm: band.lo,
      hiKm: band.hi,
      qualitySessions: _qualityFor(
        weeklyKm: range.defaultKm,
        days: runs,
        level: level,
        race: race,
      ),
      isStretch:
          baselineWeeklyKm > 0 && range.defaultKm > baselineWeeklyKm * 1.8,
    );
  }

  /// The realistic *projected weekly volume* window for a specific day count —
  /// what the plan actually runs at that frequency, not the whole 3-to-7-day
  /// span. Centres on the day count's typical volume ([VolumeModel]), floors it
  /// by what the athlete already runs and the distance's min-viable, and caps
  /// at the experience peak. Moves with every slider step.
  static ({int lo, int hi}) _bandForDays({
    required String goal,
    required String experience,
    required int days,
    required double baselineWeeklyKm,
  }) {
    final race = _race(goal);
    final level = _level(experience);
    final typical = VolumeModel.onboardingRange(
      race: race,
      experience: level,
      days: days,
    ).defaultKm;
    final minV = VolumeModel.minViableKm(race);
    // The same runs-scaled ceiling RacePlanBuilder ramps toward, so the band
    // shown here matches the plan that gets built.
    final peak = VolumeModel.peakKmForRuns(
      race: race,
      experience: level,
      runsPerWeek: days,
    );

    var lo = _max(minV, typical * 0.82);
    // never project below what the athlete already sustains at this frequency
    if (baselineWeeklyKm > 0) lo = _max(lo, _min(baselineWeeklyKm, typical));
    final hi = _max(lo + 4, _min(peak, typical * 1.28));

    return (lo: lo.round(), hi: hi.round());
  }

  /// Ask the archetype rather than guessing. The old heuristic was
  /// `runsPerWeek >= 5 ? 2 : 1`, which is wrong for a 5-day beginner.
  static int _qualityFor({
    required double weeklyKm,
    required int days,
    required ExperienceLevel level,
    required RaceDistance race,
  }) {
    final week = ArchetypeTable.build(
      race: race,
      weeklyKm: weeklyKm,
      days: days,
      experience: level,
      phase: TrainingPhase.build,
    );
    return week?.qualityCount ?? (days >= 5 ? 2 : 1);
  }

  /// Weekly range for a race + experience + day count — straight from
  /// [VolumeModel] (defined for 3–7 days, experience-aware).
  static WeeklyKmRange rangeFor(String goal, String experience, int days) =>
      VolumeModel.onboardingRange(
        race: _race(goal),
        experience: _level(experience),
        days: days,
      );

  static int _largestDaysWithin(
    String goal,
    ExperienceLevel level,
    double ceilingKm,
  ) {
    var best = kMinRunsPerWeek;
    for (var d = kMinRunsPerWeek; d <= kMaxRunsPerWeek; d++) {
      final r = VolumeModel.onboardingRange(
        race: _race(goal),
        experience: level,
        days: d,
      );
      if (r.defaultKm <= ceilingKm) best = d;
    }
    return best;
  }

  /// The day count whose typical volume sits closest to a sensible early-plan
  /// target — a modest step up from what they run now, not a leap.
  static int _recommendedDays({
    required String goal,
    required String experience,
    required double baselineWeeklyKm,
    required int maxRuns,
  }) {
    final ceiling = _recommendedCeiling(goal, experience, maxRuns);
    if (baselineWeeklyKm <= 0) return ceiling.clamp(kMinRunsPerWeek, 4);
    final target = baselineWeeklyKm * 1.25;

    var best = kMinRunsPerWeek;
    var bestGap = double.infinity;
    for (var d = kMinRunsPerWeek; d <= ceiling; d++) {
      final gap = (rangeFor(goal, experience, d).defaultKm - target).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = d;
      }
    }
    return best;
  }

  /// Hard ceiling on the RECOMMENDED badge. Never 7 (or 6 for anyone), and a
  /// 5K never recommends more than 4 days (5 for advanced) — the slider may
  /// still allow more, the badge just won't point there.
  static int _recommendedCeiling(String goal, String experience, int maxRuns) {
    final distanceCap = goal == '5k' || goal.isEmpty
        ? (experience == 'advanced' ? 5 : 4)
        : 5;
    final capped = distanceCap < maxRuns ? distanceCap : maxRuns;
    final limit = capped < kMaxRunsPerWeek - 1 ? capped : kMaxRunsPerWeek - 1;
    return limit < kMinRunsPerWeek ? kMinRunsPerWeek : limit;
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;
}
