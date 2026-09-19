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
    /// Planned run frequency. When supplied, the peak-volume ceiling scales with
    /// it (a 5K peaks higher on 6 easy-heavy days than on 3). Null ⇒ the legacy
    /// experience-only ceiling.
    int? runsPerWeek,
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

    // A near-zero base can't seed a plan: week 1 would be ~1.5 km and the long
    // run 0.3 × nothing. Start from a meaningful floor instead (6 km, or 8 km
    // on a 4+ day schedule) and step up from there.
    // A half marathon needs a bigger floor (12 km, or 14 km on 4+ days): a
    // 6 km base can't safely reach a viable long run in one block.
    final isHalf = _raceDistanceFrom(goalRace) == RaceDistance.halfMarathon;
    final isMarathon = _raceDistanceFrom(goalRace) == RaceDistance.marathon;
    final manyDays = (runsPerWeek ?? 0) >= 4;
    final floored =
        currentWeeklyKm < (isHalf ? _flooredHalfBaselineKm : _flooredBaselineKm);
    final startKm = floored
        ? (isHalf ? (manyDays ? 14.0 : 12.0) : (manyDays ? 8.0 : 6.0))
        : currentWeeklyKm;

    // Peak volume: physiologically honest — current + safe weekly gain over
    // build weeks, capped by a race/experience ceiling.
    var peakVolume = _peakVolume(
      goalRace: goalRace,
      experienceLevel: experienceLevel,
      currentWeeklyKm: startKm,
      buildWeeks: buildWeeks,
      override: peakWeeklyKmOverride,
      runsPerWeek: runsPerWeek,
    );
    // A 5K built up from (near) zero has no business peaking past ~24 km.
    if (floored && _raceDistanceFrom(goalRace) == RaceDistance.fiveK) {
      peakVolume = min(peakVolume, _flooredFiveKPeakCapKm);
    }

    // Weeks that actually step the volume up (not cutbacks, not taper). A
    // marathon's long build spends a real share of its weeks on 3:1 cutbacks,
    // so spreading the climb over `buildWeeks` leaves the ramp short of peak.
    var progressWeeks = 0;
    for (var w = 1; w <= weeksOut; w++) {
      final ph = _phaseFor(w, weeksOut, taperWeeks);
      final isCut = ph != TrainingPhase.taper && w % 4 == 0;
      if (ph != TrainingPhase.taper && !isCut) progressWeeks++;
    }
    final rampWeeks = isMarathon ? max(1, progressWeeks) : buildWeeks;

    final rawIncrement = (peakVolume - startKm) / rampWeeks;
    final maxIncrement = startKm * 0.10;
    final safeIncrement = rawIncrement.clamp(-5.0, max(1.5, maxIncrement));

    final raceDist = _raceDistanceFrom(goalRace);
    var peakLongRunKm = peakLongRunKmOverride != null
        ? peakLongRunKmOverride.clamp(6.0, 46.0).toDouble()
        : _peakLongRunKm(goalRace, experienceLevel);
    // The 5 km floor is right for a runner with a base; from a floored start it
    // would be most of the week, so use a gentler 2.5 km.
    final longRunFloorKm = floored ? _flooredLongRunKm : 5.0;
    // Never start the long run above 75% of where it is heading — a big base
    // (0.3 × 45 km = 13.5 km) against a 10 km peak used to make it shrink.
    var currentLongRunKm = min(
      peakLongRunKm * 0.75,
      max(longRunFloorKm, startKm * 0.30),
    );
    // 5K / 10K / marathon: clamp the long run to the envelope's absolute ceiling
    // (12 / 16 / 34 km) so a high current base or a tuned override can't push it
    // past what the archetype allows — for the marathon this is the strict
    // soft-tissue / glycogen-depletion ceiling.
    if (raceDist == RaceDistance.fiveK ||
        raceDist == RaceDistance.tenK ||
        raceDist == RaceDistance.marathon) {
      final cap = VolumeModel.envelope(raceDist).longRunMaxKm;
      peakLongRunKm = min(peakLongRunKm, cap);
      currentLongRunKm = min(currentLongRunKm, cap);
    }
    // The cap may have lowered the peak; keep the start at most 75% of it.
    currentLongRunKm = min(currentLongRunKm, peakLongRunKm * 0.75);
    final longRunIncrement = (peakLongRunKm - currentLongRunKm) / rampWeeks;
    // A marathon long run has to climb ~2 km a week to reach 24+ km; the
    // 10%-of-current cap that suits shorter races crawls at 0.75 km.
    final safeLongRunIncrement = longRunIncrement.clamp(
      -2.0,
      isMarathon ? max(2.0, currentLongRunKm * 0.10) : currentLongRunKm * 0.10,
    );

    final weeks = <WeekTarget>[];
    var volume = startKm;
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
      // Taper from what the ramp ACTUALLY reached, not the aspirational peak —
      // otherwise a ramp that stalls short of its ceiling (a floored or
      // slow-growing base) is followed by a taper week bigger than any build
      // week. WeekResolver scales these down by its taper multipliers.
      if (phase == TrainingPhase.taper) {
        weeks.add(
          _buildWeek(
            week: w,
            targetKm: min(volume, peakVolume),
            phase: phase,
            goalRace: goalRace,
            experienceLevel: experienceLevel,
            longRunKm: min(longRunKm, peakLongRunKm),
            isDeload: false,
          ),
        );
        continue;
      }

      // ── Normal progression weeks ──────────────────────────────────────
      if (floored) {
        // Week 1 is the floor itself; afterwards step by max(1.5 km, 10% of the
        // current volume) so the ramp never stalls at a tiny base.
        if (w > 1) {
          final stepCap = max(isHalf ? 2.5 : 1.5, volume * 0.10);
          volume = (volume + rawIncrement.clamp(-5.0, stepCap)).clamp(
            startKm,
            peakVolume,
          );
        }
      } else {
        // Marathon: step by max(2.5 km, 10% of the current volume), like the
        // half-marathon floor rule, so a 16-week build from 25 km can reach
        // the low-to-mid 50s.
        final step = isMarathon
            ? rawIncrement.clamp(-5.0, max(2.5, volume * 0.10))
            : safeIncrement;
        volume = (volume + step).clamp(currentWeeklyKm * 0.5, peakVolume);
      }
      longRunKm = (longRunKm + safeLongRunIncrement).clamp(
        longRunFloorKm,
        max(longRunFloorKm, peakLongRunKm),
      );

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

  /// Below this current weekly volume the plan seeds from a fixed floor.
  static const double _flooredBaselineKm = 6.0;
  static const double _flooredHalfBaselineKm = 12.0;
  static const double _flooredLongRunKm = 2.5;
  static const double _flooredFiveKPeakCapKm = 24.0;

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
    int? runsPerWeek,
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
    final marathonBoost =
        _raceDistanceFrom(goalRace) == RaceDistance.marathon ? 0.5 : 0.0;
    final maxWeeklyGain =
        marathonBoost +
        switch (experienceLevel) {
          'advanced' => 3.0,
          'intermediate' => 2.5,
          _ => 2.0,
        };

    // Physiological ceiling per race × experience — single source of truth.
    // When run frequency is known, let it scale the ceiling (5K only for now).
    final ceiling = runsPerWeek != null
        ? VolumeModel.peakKmForRuns(
            race: _raceDistanceFrom(goalRace),
            experience: _experienceFrom(experienceLevel),
            runsPerWeek: runsPerWeek,
          )
        : VolumeModel.peakKm(
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
    '10k' => 2, // 1 deload week + 1 sharpening race week
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
