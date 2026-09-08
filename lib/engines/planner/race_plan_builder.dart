import 'dart:math';
import '../../models/race_plan.dart';
import '../../models/training_phase.dart';
import '../config/archetype_table.dart' show ExperienceLevel;
import '../config/volume_model.dart';
import '../config/workout_template_library.dart' show RaceDistance;

/// RacePlanBuilder — builds a WeekTarget list for the engine.
///
/// TAPER VOLUME:
///   RacePlanBuilder passes peakVolume as targetKm for taper weeks.
///   WeekResolver._taperMultiplier() owns the actual taper reduction.
///   No double-scaling.
///
/// CUTBACK WEEKS:
///   targetKm stores the UN-reduced build volume (same as a normal week).
///   WeekResolver owns the 0.70 multiplier — same pattern as taper.
///   All sessions kept — structure unchanged.
///
/// PEAK VOLUME:
///   Capped at current + (buildWeeks × maxSafeWeeklyGain) rather than
///   an arbitrary floor × multiplier. Physiologically honest progression.
class RacePlanBuilder {
  static RacePlan build({
    required double currentWeeklyKm,
    required String goalRace,
    required DateTime raceDate,
    required String experienceLevel,
    DateTime? now,
    /// Explicit macrocycle length. When null the length is derived from the
    /// race date (existing behaviour). Clamped to 1–20.
    int? durationWeeks,
    /// Ease weeks 1–4 in from ~75% of the ramped volume, smoothing back to
    /// 100% by week 5. Only touches non-cutback build/base weeks.
    bool gradualStart = false,
    /// User-tuned peak weekly volume (from the plan-tuning sliders). Replaces
    /// the physiological ceiling calc; still floored at [currentWeeklyKm] and
    /// capped at the distance's safe cap.
    double? peakWeeklyKmOverride,
    /// User-tuned peak long-run distance. Clamped to a sane 6–46 km band.
    double? peakLongRunKmOverride,
  }) {
    final today = now ?? DateTime.now();
    final derivedWeeks = max(1, raceDate.difference(today).inDays ~/ 7);
    final weeksOut = (durationWeeks ?? derivedWeeks).clamp(1, 20);

    if (weeksOut < 4) {
      return _buildMinimalPlan(
        currentWeeklyKm: currentWeeklyKm,
        goalRace: goalRace,
        raceDate: raceDate,
        experienceLevel: experienceLevel,
        weeksOut: weeksOut,
        today: today,
      );
    }

    final taperWeeks = _taperWeeksFor(goalRace);
    final buildWeeks = max(1, weeksOut - taperWeeks);

    // Peak volume: physiologically honest — current + safe weekly gain over
    // build weeks, capped by a race/experience ceiling.
    final peakVolume = _peakVolume(
      goalRace: goalRace,
      experienceLevel: experienceLevel,
      currentWeeklyKm: currentWeeklyKm,
      buildWeeks: buildWeeks,
      override: peakWeeklyKmOverride,
    );

    final rawIncrement = (peakVolume - currentWeeklyKm) / buildWeeks;
    final maxIncrement = currentWeeklyKm * 0.10;
    final safeIncrement = rawIncrement.clamp(-5.0, max(1.5, maxIncrement));

    final double peakLongRunKm = peakLongRunKmOverride != null
        ? peakLongRunKmOverride.clamp(6.0, 46.0).toDouble()
        : _peakLongRunKm(goalRace, experienceLevel);
    final currentLongRunKm = max(5.0, currentWeeklyKm * 0.30);
    final longRunIncrement = (peakLongRunKm - currentLongRunKm) / buildWeeks;
    final safeLongRunIncrement = longRunIncrement.clamp(
      -2.0,
      currentLongRunKm * 0.10,
    );

    final weeks = <WeekTarget>[];
    var volume = currentWeeklyKm;
    var longRunKm = currentLongRunKm;

    for (var w = 1; w <= weeksOut; w++) {
      final phase = _phaseFor(w, weeksOut, taperWeeks);

      // ── Cutback weeks (3:1 cycle) ─────────────────────────────────────
      // Keep all sessions including long run. Volume via 0.70 multiplier.
      if ((phase == TrainingPhase.base ||
              phase == TrainingPhase.build ||
              phase == TrainingPhase.peak) &&
          w % 4 == 0) {
        weeks.add(
          _buildWeek(
            week: w,
            targetKm: volume,
            phase: phase,
            goalRace: goalRace,
            experienceLevel: experienceLevel,
            longRunKm: longRunKm,
            isDeload: true,
          ),
        );
        continue;
      }

      // ── Taper weeks ───────────────────────────────────────────────────
      // Pass peakVolume — WeekResolver._taperMultiplier() handles reduction.
      if (phase == TrainingPhase.taper) {
        weeks.add(
          _buildWeek(
            week: w,
            targetKm: peakVolume,
            phase: phase,
            goalRace: goalRace,
            experienceLevel: experienceLevel,
            longRunKm: peakLongRunKm,
            isDeload: false,
          ),
        );
        continue;
      }

      // ── Normal progression weeks ──────────────────────────────────────
      volume = (volume + safeIncrement).clamp(
        currentWeeklyKm * 0.5,
        peakVolume,
      );
      longRunKm = (longRunKm + safeLongRunIncrement).clamp(5.0, peakLongRunKm);

      // Gradual start eases the *prescribed* volume for weeks 1–4 without
      // slowing the underlying ramp — `volume` / `longRunKm` keep compounding
      // at full rate, only the week's target is scaled down.
      final ease = _gradualStartFactor(w, gradualStart);

      weeks.add(
        _buildWeek(
          week: w,
          targetKm: volume * ease,
          phase: phase,
          goalRace: goalRace,
          experienceLevel: experienceLevel,
          longRunKm: longRunKm * ease,
          isDeload: false,
        ),
      );
    }

    return RacePlan(
      goalRace: goalRace,
      raceDate: raceDate,
      createdAt: today,
      startingWeeklyKm: currentWeeklyKm,
      experienceLevel: experienceLevel,
      weeks: weeks,
    );
  }

  static WeekTarget exploreTarget({
    required double fourWeekAvgKm,
    required String experienceLevel,
  }) {
    final target = fourWeekAvgKm <= 0 ? 15.0 : fourWeekAvgKm;
    final longRunKm = max(5.0, target * 0.30);
    return WeekTarget(
      week: 1,
      targetKm: target,
      phase: TrainingPhase.base,
      qualityCount: experienceLevel == 'beginner' ? 0 : 1,
      hasLongRun: fourWeekAvgKm >= 10.0,
      longRunKm: longRunKm,
      keySession: experienceLevel == 'beginner' ? 'easy' : 'tempo',
    );
  }

  // ============================================================================
  // PRIVATE HELPERS
  // ============================================================================

  static WeekTarget _buildWeek({
    required int week,
    required double targetKm,
    required TrainingPhase phase,
    required String goalRace,
    required String experienceLevel,
    required double longRunKm,
    required bool isDeload,
  }) {
    final qualityCount = _qualityCount(phase, experienceLevel, isDeload);
    final hasLongRun = _shouldHaveLongRun(phase, goalRace);
    final keySession = _keySession(phase, goalRace);
    final adjustedLongRun = hasLongRun ? _roundHalf(longRunKm) : 0.0;

    return WeekTarget(
      week: week,
      targetKm: _roundHalf(targetKm),
      phase: phase,
      qualityCount: qualityCount,
      hasLongRun: hasLongRun,
      longRunKm: adjustedLongRun,
      keySession: keySession,
    );
  }

  static int _qualityCount(TrainingPhase phase, String level, bool isDeload) {
    if (isDeload) return 1; // cutback always keeps Q1
    return switch (phase) {
      TrainingPhase.base => 1,
      TrainingPhase.build => level == 'beginner' ? 1 : 2,
      TrainingPhase.peak => 2,
      TrainingPhase.taper => 1,
      TrainingPhase.maintenance => 1,
    };
  }

  /// Long run is always present except 5K taper.
  /// Cutback weeks keep the long run — just shorter via volume multiplier.
  static bool _shouldHaveLongRun(TrainingPhase phase, String goalRace) {
    if (phase == TrainingPhase.taper) {
      return goalRace == 'half_marathon' || goalRace == 'marathon';
    }
    return true;
  }

  static String _keySession(TrainingPhase phase, String goalRace) {
    return switch (phase) {
      TrainingPhase.base => 'easy',
      TrainingPhase.build => switch (goalRace) {
        '5k' || '10k' => 'intervals',
        _ => 'tempo',
      },
      TrainingPhase.peak => switch (goalRace) {
        '5k' => 'intervals',
        '10k' => 'tempo',
        _ => 'race_pace',
      },
      TrainingPhase.taper => 'easy',
      TrainingPhase.maintenance => 'easy',
    };
  }

  /// Peak volume: current + safe weekly gain over build weeks,
  /// bounded by a physiological ceiling per race × experience.
  static double _peakVolume({
    required String goalRace,
    required String experienceLevel,
    required double currentWeeklyKm,
    required int buildWeeks,
    double? override,
  }) {
    // User-tuned peak wins outright — the tuning slider is already bounded by
    // VolumeModel.onboardingRange().max — but never below current or above the
    // distance's hard safe cap.
    if (override != null) {
      return max(
        currentWeeklyKm,
        min(VolumeModel.safeCapKm(_raceDistanceFrom(goalRace)), override),
      );
    }

    // Max safe weekly gain: ~2km for beginners, ~2.5km intermediate, ~3km advanced.
    final maxWeeklyGain = switch (experienceLevel) {
      'advanced' => 3.0,
      'intermediate' => 2.5,
      _ => 2.0,
    };

    // Physiological ceiling per race × experience — single source of truth.
    final ceiling = VolumeModel.peakKm(
      _raceDistanceFrom(goalRace),
      _experienceFrom(experienceLevel),
    );

    // Reachable peak given build weeks and safe gain. Never below what the
    // athlete already runs (they may start above the model ceiling), never
    // above the model ceiling unless the current base already exceeds it.
    final reachable = currentWeeklyKm + (buildWeeks * maxWeeklyGain);
    return max(currentWeeklyKm, min(ceiling, reachable));
  }

  static double _peakLongRunKm(String race, String level) {
    return switch (race) {
      '5k' => switch (level) {
        'advanced' => 12.0,
        'intermediate' => 10.0,
        _ => 8.0,
      },
      '10k' => switch (level) {
        'advanced' => 16.0,
        'intermediate' => 14.0,
        _ => 10.0,
      },
      'half_marathon' => switch (level) {
        'advanced' => 24.0,
        'intermediate' => 20.0,
        _ => 16.0,
      },
      'marathon' => switch (level) {
        'advanced' => 35.0,
        'intermediate' => 32.0,
        _ => 28.0,
      },
      _ => 12.0,
    };
  }

  static int _taperWeeksFor(String race) => switch (race) {
    '5k' => 1,
    '10k' => 1,
    'half_marathon' => 2,
    'marathon' => 3,
    _ => 1,
  };

  static TrainingPhase _phaseFor(int week, int total, int taperWeeks) {
    if (week > total - taperWeeks) return TrainingPhase.taper;
    final buildStart = ((total - taperWeeks) * 0.4).ceil();
    if (week <= buildStart) return TrainingPhase.base;
    final peakStart = total - taperWeeks - 1;
    if (week >= peakStart) return TrainingPhase.peak;
    return TrainingPhase.build;
  }

  static RacePlan _buildMinimalPlan({
    required double currentWeeklyKm,
    required String goalRace,
    required DateTime raceDate,
    required String experienceLevel,
    required int weeksOut,
    required DateTime today,
  }) {
    final weeks = List.generate(weeksOut, (i) {
      final isTaper = i == weeksOut - 1 && weeksOut > 1;
      return WeekTarget(
        week: i + 1,
        targetKm: isTaper ? currentWeeklyKm * 0.70 : currentWeeklyKm,
        phase: isTaper ? TrainingPhase.taper : TrainingPhase.build,
        qualityCount: isTaper ? 1 : 2,
        hasLongRun: true, // always keep long run
        longRunKm: max(5.0, currentWeeklyKm * 0.30),
        keySession: isTaper ? 'easy' : 'tempo',
      );
    });
    return RacePlan(
      goalRace: goalRace,
      raceDate: raceDate,
      createdAt: today,
      startingWeeklyKm: currentWeeklyKm,
      experienceLevel: experienceLevel,
      weeks: weeks,
    );
  }

  /// Weeks 1–4 ramp 0.75 → ~0.94; week 5+ is 1.0. Off ⇒ always 1.0.
  /// Mirrors `PlanConfigState.gradualStartFactorForWeek`.
  static double _gradualStartFactor(int week, bool gradualStart) {
    if (!gradualStart || week >= 5) return 1.0;
    const base = 0.75;
    return base + (1.0 - base) * ((week - 1) / 4.0);
  }

  static double _roundHalf(double v) => (v * 2).round() / 2;

  static RaceDistance _raceDistanceFrom(String goalRace) => switch (goalRace) {
    '5k' => RaceDistance.fiveK,
    '10k' => RaceDistance.tenK,
    'half_marathon' => RaceDistance.halfMarathon,
    'marathon' => RaceDistance.marathon,
    _ => RaceDistance.tenK,
  };

  static ExperienceLevel _experienceFrom(String level) => switch (level) {
    'beginner' => ExperienceLevel.beginner,
    'advanced' => ExperienceLevel.advanced,
    _ => ExperienceLevel.intermediate,
  };
}
