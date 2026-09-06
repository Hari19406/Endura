/// VolumeModel — the ONE authoritative source for weekly-volume numbers.
///
/// Replaces three tables that disagreed:
///   - WeeklyKmRange.forRaceAndDays  (onboarding slider, no 7-day row, not
///     experience-aware)
///   - RacePlanBuilder._peakVolume `ceiling`  (plan peak)
///   - PeakWeeklyKm.lookup  (a *third* peak table used by VolumeGuidance)
///
/// Everything now derives from `peakKm(race, experience)` + `minViableKm(race)`.
library;

import 'archetype_table.dart' show ExperienceLevel, WeeklyKmRange;
import 'workout_template_library.dart' show RaceDistance;

class VolumeModel {
  const VolumeModel._();

  /// Peak weekly km a full plan ramps toward, by race × experience.
  /// Reconciled between the old `_peakVolume` ceiling (too aggressive for
  /// int/adv) and `PeakWeeklyKm.lookup` (a bit low for adv).
  static double peakKm(RaceDistance race, ExperienceLevel exp) =>
      switch ((race, exp)) {
        (RaceDistance.fiveK, ExperienceLevel.beginner) => 35,
        (RaceDistance.fiveK, ExperienceLevel.intermediate) => 48,
        (RaceDistance.fiveK, ExperienceLevel.advanced) => 62,
        (RaceDistance.tenK, ExperienceLevel.beginner) => 42,
        (RaceDistance.tenK, ExperienceLevel.intermediate) => 58,
        (RaceDistance.tenK, ExperienceLevel.advanced) => 78,
        (RaceDistance.halfMarathon, ExperienceLevel.beginner) => 52,
        (RaceDistance.halfMarathon, ExperienceLevel.intermediate) => 70,
        (RaceDistance.halfMarathon, ExperienceLevel.advanced) => 92,
        (RaceDistance.marathon, ExperienceLevel.beginner) => 60,
        (RaceDistance.marathon, ExperienceLevel.intermediate) => 82,
        (RaceDistance.marathon, ExperienceLevel.advanced) => 112,
      };

  /// Below this weekly volume a plan can only sharpen existing fitness, not
  /// build new fitness for the distance. Used as the onboarding slider floor.
  static double minViableKm(RaceDistance race) => switch (race) {
    RaceDistance.fiveK => 15,
    RaceDistance.tenK => 20,
    RaceDistance.halfMarathon => 30,
    RaceDistance.marathon => 40,
  };

  /// Sane band for what the athlete runs *now*, at onboarding.
  ///   min       — plan-viable floor for the distance
  ///   max       — their achievable peak (hard slider ceiling)
  ///   defaultKm — a realistic current volume, scaling with day count
  ///               (min-ish at 3 days → ~62% of peak at 7 days)
  static WeeklyKmRange onboardingRange({
    required RaceDistance race,
    required ExperienceLevel experience,
    required int days,
  }) {
    final peak = peakKm(race, experience);
    final minV = minViableKm(race);
    final d = days.clamp(3, 7);
    final t = (d - 3) / 4.0;
    final defaultKm = _lerp(minV * 1.25, peak * 0.62, t);
    return WeeklyKmRange(
      min: minV.roundToDouble(),
      max: peak.roundToDouble(),
      defaultKm: defaultKm.roundToDouble(),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
