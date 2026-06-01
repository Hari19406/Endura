/// VolumeCalculator — determines how far each workout should be.
///
/// Takes the athlete's weekly volume target and the selected template,
/// then calculates the session distance.
///
/// Priority chain:
///   1. template.recommendedPercentage × weeklyTargetKm = raw distance
///   2. PhaseVariant.volumeMultiplier scales the raw distance
///   3. Clamp to template.distanceByRace[raceDistance] (ALWAYS wins)
///   4. Safety cap (single-run ceiling = 40% of weekly target; long run exempt)
///   5. Round to nearest 0.5 km
///
/// This is independent of pace — it only answers "how far", not "how fast".
///
/// NOTE: When the mileage system is active, WeekResolver pre-sizes each slot
/// (absorber model) and WorkoutResolver uses that distance directly. This
/// calculator is the fallback path (legacy / no planned distance).
library;

import '../config/workout_template_library.dart';
import '../../models/training_phase.dart';

// ============================================================================
// DAY ROLE — what role this workout plays in the weekly structure
// ============================================================================

enum DayRole {
  longRun,
  primaryQuality,
  secondaryQuality,
  easyRun,
  recovery,
}

// ============================================================================
// VOLUME CALCULATOR
// ============================================================================

class VolumeCalculator {
  const VolumeCalculator();

  /// Calculate the total workout distance in km for a specific session.
  ///
  /// [weeklyTargetKm]      Total km target for this week.
  /// [template]             The selected workout template.
  /// [raceDistance]          What the athlete is training for.
  /// [phase]                Current training phase.
  /// [dayRole]              What kind of day this is (for safety caps only).
  /// [variant]              Phase variant to apply (may be null).
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
    // Step 1: Normalize this session's share of the weekly target.
    // weekPercentageSum = sum of all selected templates' recommendedPercentage
    // this week. Dividing gives the true proportional slice of the pie.
    final normalizedPct = weekPercentageSum > 0
        ? template.recommendedPercentage / weekPercentageSum
        : template.recommendedPercentage;
    var distance = weeklyTargetKm * normalizedPct;

    // Step 2: Apply phase variant volume multiplier.
    if (variant != null) {
      distance *= variant.volumeMultiplier;
    }

    // Step 3: Clamp to template's distance range for this race (ALWAYS wins).
    distance = _clampToTemplateRange(
      distance: distance,
      template: template,
      raceDistance: raceDistance,
      applyMin: experienceLevel != 'beginner',
    );

    // Step 4: Safety caps.
    distance = _applySafetyCaps(
      distance: distance,
      dayRole: dayRole,
      weeklyTargetKm: weeklyTargetKm,
    );

    // Step 5: Apply minimums.
    distance = _applyMinimums(distance: distance, dayRole: dayRole);

    // Step 6: Round to nearest 0.5 km.
    return _roundHalf(distance);
  }

  /// Clamp distance to the template's declared range for this race distance.
  ///
  /// This is the primary guardrail. The template knows what distances
  /// are sensible for each race — we never exceed those bounds.
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

  /// Safety caps to prevent dangerous volume jumps.
  double _applySafetyCaps({
    required double distance,
    required DayRole dayRole,
    required double weeklyTargetKm,
  }) {
    // Single-run ceiling: no individual run should exceed ~40% of the week's
    // total volume. This replaces the old "longest recent run × 1.15" brake —
    // it needs no run history, is correct from week one (no hardcoded 5km
    // fallback), and scales automatically as weekly volume grows.
    //
    // The long run is exempt: it is *meant* to be the week's biggest run, and
    // is bounded instead by its template max and the weekly progression ramp
    // in WeeklyVolumeResolver.
    if (dayRole != DayRole.longRun && weeklyTargetKm > 0) {
      final safeMax = weeklyTargetKm * 0.40;
      if (distance > safeMax) distance = safeMax;
    }

    return distance;
  }

  /// Minimum distances — workouts shouldn't be too short to be useful.
  double _applyMinimums({
    required double distance,
    required DayRole dayRole,
  }) {
    final minimum = switch (dayRole) {
      DayRole.longRun          => 5.0,
      DayRole.primaryQuality   => 5.0,
      DayRole.secondaryQuality => 4.0,
      DayRole.easyRun          => 3.0,
      DayRole.recovery         => 2.0,
    };
    return distance < minimum ? minimum : distance;
  }

  double _roundHalf(double v) => (v * 2).round() / 2;
}