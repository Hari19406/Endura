/// VolumeCalculator — final km guardrail for individual sessions.
///
/// CHANGE (Archetype v1): Primary sizing path removed.
///   Session km now comes from ArchetypeTable via WeekResolver.
///   This calculator is now a safety clamp layer only — it applies
///   template distance range bounds and floor minimums on top of
///   the archetype-resolved km value.
///
///   The legacy percentage-based path (recommendedPercentage × weeklyTargetKm)
///   is REMOVED. It was the root cause of the absorber distribution problem.
///
/// Remaining responsibilities:
///   1. Clamp session km to template.distanceByRace[race] (min/max guardrail).
///   2. Apply floor minimums by day role (safety net for extreme scaling).
///   3. Round to nearest 0.5 km.
///
/// The safety cap (single-run ceiling = 40% of weekly target) is also removed.
/// The archetype table owns correct per-session proportions — the cap was only
/// needed because percentage distribution could produce runaway values.
library;

import '../config/workout_template_library.dart';
import '../../models/training_phase.dart';

// ============================================================================
// DAY ROLE — what role this workout plays in the weekly structure
// ============================================================================

enum DayRole { longRun, primaryQuality, secondaryQuality, easyRun }

// ============================================================================
// VOLUME CALCULATOR
// ============================================================================

class VolumeCalculator {
  const VolumeCalculator();

  /// Clamp and validate a session distance produced by ArchetypeTable sizing.
  ///
  /// [archetypeKm]       The km value from ArchetypeTable (already scaled).
  /// [template]          The selected workout template.
  /// [raceDistance]      What the athlete is training for.
  /// [dayRole]           What kind of day this is (for floor enforcement).
  /// [applyTemplateMin]  Whether to enforce the template's minimum km.
  ///                     Set false for beginners where archetype floors apply.
  double clampSession({
    required double archetypeKm,
    required WorkoutTemplate template,
    required RaceDistance raceDistance,
    required DayRole dayRole,
    bool applyTemplateMin = true,
  }) {
    var distance = archetypeKm;

    // Step 1: Clamp to template's declared distance range for this race.
    // This is the primary guardrail — the template knows what distances
    // are sensible for each race/experience combination.
    distance = _clampToTemplateRange(
      distance: distance,
      template: template,
      raceDistance: raceDistance,
      applyMin: applyTemplateMin,
    );

    // Step 2: Apply role-based floor minimums.
    // These catch extreme cases where scale factor × archetype produces
    // something too short to be a useful workout.
    distance = _applyMinimums(distance: distance, dayRole: dayRole);

    // Step 3: Round to nearest 0.5 km.
    return _roundHalf(distance);
  }

  /// Legacy path — kept for backward compatibility with WorkoutResolver's
  /// fallback when no archetype km is available (e.g. first-ever session
  /// before EngineMemory has a baseline).
  ///
  /// Uses template.recommendedPercentage if it still exists on the template,
  /// otherwise falls back to the template's midpoint distance range.
  double calculateWorkoutDistance({
    required double weeklyTargetKm,
    required WorkoutTemplate template,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
    required DayRole dayRole,
    PhaseVariant? variant,
    String experienceLevel = 'intermediate',
    double weekPercentageSum = 1.0,
  }) {
    // Use midpoint of template's distance range as a clean fallback.
    final range = template.distanceByRace[raceDistance];
    double distance;

    if (range != null) {
      distance = (range.minKm + range.maxKm) / 2;
    } else {
      // Absolute last resort — shouldn't happen with a well-formed template.
      distance = switch (dayRole) {
        DayRole.longRun => weeklyTargetKm * 0.32,
        DayRole.primaryQuality => weeklyTargetKm * 0.18,
        DayRole.secondaryQuality => weeklyTargetKm * 0.15,
        DayRole.easyRun => weeklyTargetKm * 0.18,
      };
    }

    if (variant != null) distance *= variant.volumeMultiplier;

    distance = _clampToTemplateRange(
      distance: distance,
      template: template,
      raceDistance: raceDistance,
      applyMin: experienceLevel != 'beginner',
    );

    distance = _applyMinimums(distance: distance, dayRole: dayRole);

    return _roundHalf(distance);
  }

  // ==========================================================================
  // PRIVATE HELPERS
  // ==========================================================================

  double _clampToTemplateRange({
    required double distance,
    required WorkoutTemplate template,
    required RaceDistance raceDistance,
    bool applyMin = true,
  }) {
    final range = template.distanceByRace[raceDistance];
    if (range == null) return distance;
    final min = applyMin ? range.minKm : 0.0;
    return distance.clamp(min, range.maxKm);
  }

  double _applyMinimums({required double distance, required DayRole dayRole}) {
    final minimum = switch (dayRole) {
      DayRole.longRun => 5.0,
      DayRole.primaryQuality => 5.0,
      DayRole.secondaryQuality => 4.0,
      DayRole.easyRun => 3.0,
    };
    return distance < minimum ? minimum : distance;
  }

  double _roundHalf(double v) => (v * 2).round() / 2;
}
