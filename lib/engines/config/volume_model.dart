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

import 'archetype_envelope.dart';
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

  /// The declarative physiological envelope for a distance — volume band, long-
  /// run ceiling, taper length, session mix. The 5K envelope is authoritative;
  /// [peakKmForRuns] and the 5K long-run cap in [ArchetypeTable] read from it.
  static RaceArchetypeEnvelope envelope(RaceDistance race) =>
      RaceArchetypeEnvelope.of(race);

  /// Suggested band for the athlete's *current* weekly volume when starting a
  /// plan for [race] (onboarding baseline).
  static ({double min, double max}) baselineBandKm(RaceDistance race) =>
      RaceArchetypeEnvelope.of(race).baselineKm;

  /// The peak-volume ceiling band for [race].
  static ({double min, double max}) peakBandKm(RaceDistance race) =>
      RaceArchetypeEnvelope.of(race).peakKm;

  /// Peak weekly volume as a function of run frequency.
  ///
  /// For the 5K this is the envelope's `peakKm` band (45–55 km/wk) interpolated
  /// by [runsPerWeek] and nudged by experience — a runner doing 6 easy-heavy
  /// days peaks higher than one squeezing the same load into 3. Other distances
  /// keep their experience-only [peakKm] for now (runs-scaling is 5K-only until
  /// their envelopes are tuned).
  static double peakKmForRuns({
    required RaceDistance race,
    required ExperienceLevel experience,
    required int runsPerWeek,
  }) {
    if (race != RaceDistance.fiveK) return peakKm(race, experience);
    final env = RaceArchetypeEnvelope.fiveK;
    final byRuns = env.peakForRuns(runsPerWeek);
    final expFactor = switch (experience) {
      ExperienceLevel.beginner => 0.85,
      ExperienceLevel.intermediate => 1.0,
      ExperienceLevel.advanced => 1.12,
    };
    return (byRuns * expFactor).clamp(env.peakKm.min, env.peakKm.max);
  }

  /// Below this weekly volume a plan can only sharpen existing fitness, not
  /// build new fitness for the distance. Used as the onboarding slider floor.
  static double minViableKm(RaceDistance race) => switch (race) {
    RaceDistance.fiveK => 15,
    RaceDistance.tenK => 20,
    RaceDistance.halfMarathon => 30,
    RaceDistance.marathon => 40,
  };

  /// Hard upper bound on weekly volume for a distance, regardless of the
  /// athlete's inputs — a safety clamp, not a training target. Absorbed from
  /// the retired `WeeklyVolumeResolver._ranges` so VolumeModel is the single
  /// source of truth for volume bounds.
  static double safeCapKm(RaceDistance race) => switch (race) {
    RaceDistance.fiveK => 55, // aligned with RaceArchetypeEnvelope.fiveK.peakKm.max
    RaceDistance.tenK => 80,
    RaceDistance.halfMarathon => 100,
    RaceDistance.marathon => 130,
  };

  /// The comfortable weekly-volume band for a distance: below `low` a plan is
  /// under-fuelled, above `high` returns diminish and injury risk climbs. Used
  /// to pick a ramp rate (aggressive below the band, conservative inside it).
  /// Absorbed from `WeeklyVolumeResolver._ranges` (sweetLow / sweetHigh).
  static ({double low, double high}) sweetSpotKm(RaceDistance race) =>
      switch (race) {
        RaceDistance.fiveK => (low: 25, high: 40),
        RaceDistance.tenK => (low: 30, high: 50),
        RaceDistance.halfMarathon => (low: 40, high: 70),
        RaceDistance.marathon => (low: 55, high: 90),
      };

  /// Long-run distance band for a plan: `start` is a safe week-1 long run,
  /// `peak` the longest single run the plan should build toward. Centralised
  /// here (was private in RacePlanBuilder) so every consumer agrees.
  static ({double start, double peak}) longRunRangeKm({
    required RaceDistance race,
    required ExperienceLevel experience,
  }) {
    final peak = switch (race) {
      RaceDistance.fiveK => switch (experience) {
        ExperienceLevel.advanced => 12.0,
        ExperienceLevel.intermediate => 10.0,
        ExperienceLevel.beginner => 8.0,
      },
      RaceDistance.tenK => switch (experience) {
        ExperienceLevel.advanced => 16.0,
        ExperienceLevel.intermediate => 14.0,
        ExperienceLevel.beginner => 10.0,
      },
      RaceDistance.halfMarathon => switch (experience) {
        ExperienceLevel.advanced => 24.0,
        ExperienceLevel.intermediate => 20.0,
        ExperienceLevel.beginner => 16.0,
      },
      RaceDistance.marathon => switch (experience) {
        ExperienceLevel.advanced => 35.0,
        ExperienceLevel.intermediate => 32.0,
        ExperienceLevel.beginner => 28.0,
      },
    };
    final start = _max(5.0, minViableKm(race) * 0.30);
    return (start: start, peak: peak);
  }

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
    // Typical current volume climbs with day count, from a floor (~45% of peak,
    // never below min-viable) at 3 days to ~75% of peak at 7. Always strictly
    // increasing in days, always ≥ minV.
    final lo = _max(minV, peak * 0.45);
    final hi = _max(lo + 4, peak * 0.75);
    final defaultKm = _lerp(lo, hi, t);
    return WeeklyKmRange(
      min: minV.roundToDouble(),
      max: peak.roundToDouble(),
      defaultKm: defaultKm.roundToDouble(),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static double _max(double a, double b) => a > b ? a : b;
}
