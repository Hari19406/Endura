/// ArchetypeTable — canonical week composition for Endura's plan engine.
///
/// REPLACES: 576-combination hardcoded lookup table.
///
/// HOW IT WORKS:
///   1. Composition rules define session slots by days + experience.
///   2. Quality slot type resolved by phase (tempo in base, intervals in build/peak).
///   3. km per session = weeklyTargetKm × sessionFraction.
///   4. floorKm prevents any session going dangerously short after scaling.
///
/// COMPOSITION RULES:
///   3d → 1E  + 1Q + 1L
///   4d → 2E  + 1Q + 1L
///   5d → 3E  + 1Q + 1L  (intermediate/beginner)
///        2E  + 2Q + 1L  (advanced)
///   6d → 3E  + 2Q + 1L
///
/// CUTBACK WEEKS:
///   Same session structure as normal weeks — no sessions dropped.
///   WeekResolver caps qualityCount to 1 via _anchoredPattern().
///   Volume reduced by 0.70 multiplier in WeekResolver.
///   The Q2 physical slot becomes an easy slot via the pattern cap.
///
/// QUALITY BY PHASE:
///   base       → tempo only (all experience levels)
///   build/peak → interval as Q1, tempo as Q2 (intermediate/advanced)
///   build/peak → tempo only (beginner — no intervals ever)
///
/// EASY FLAVOURS (prevents identical easy sessions):
///   1 easy slot  → easy
///   2 easy slots → recoveryEasy + easyMedium
///   3 easy slots → recoveryEasy + easy + easyMedium
///
///   All three flavours map to WorkoutIntent.aerobicBase.
///   WorkoutIntent.recovery is reserved for pre-run downgrade substitutions only
///   (recovery_shakeout, recovery_walk_jog, rest_day selected at runtime).
///
/// WEEK 1 (WeekResolver responsibility):
///   Apply 0.60 multiplier on top of km values. Floors still apply.
///
/// TAPER:
///   Same session count as normal weeks — no sessions dropped.
///   Always 1 quality slot (tempo only) regardless of day count.
///   Volume reduced via race-aware progressive multiplier in WeekResolver:
///     5K  → race week: 0.55
///     10K → taper W1: 0.75, race week: 0.55
///     HM  → taper W1: 0.78, taper W2: 0.55
///     FM  → taper W1: 0.85, taper W2: 0.65, taper W3: 0.40
///
/// PEAK WEEKLY KM TABLE:
///   5K:  beginner 35 / intermediate 45 / advanced 55
///   10K: beginner 40 / intermediate 55 / advanced 65
///   HM:  beginner 50 / intermediate 65 / advanced 75
///   FM:  beginner 60 / intermediate 75 / advanced 90
library;

import '../../models/training_phase.dart';
import '../config/workout_template_library.dart';

// ============================================================================
// SESSION TYPE
// ============================================================================

enum ArchetypeSessionType {
  recoveryEasy,
  easy,
  easyMedium,
  tempo,
  interval,
  longRun,
}

extension ArchetypeSessionTypeX on ArchetypeSessionType {
  bool get isQuality =>
      this == ArchetypeSessionType.tempo ||
      this == ArchetypeSessionType.interval;

  bool get isEasy =>
      this == ArchetypeSessionType.recoveryEasy ||
      this == ArchetypeSessionType.easy ||
      this == ArchetypeSessionType.easyMedium;

  bool get isLong => this == ArchetypeSessionType.longRun;

  WorkoutIntent get intent => switch (this) {
        // All three easy flavours are aerobicBase.
        // WorkoutIntent.recovery is reserved for pre-run downgrade substitutions.
        ArchetypeSessionType.recoveryEasy => WorkoutIntent.aerobicBase,
        ArchetypeSessionType.easy        => WorkoutIntent.aerobicBase,
        ArchetypeSessionType.easyMedium  => WorkoutIntent.aerobicBase,
        ArchetypeSessionType.tempo       => WorkoutIntent.threshold,
        ArchetypeSessionType.interval    => WorkoutIntent.vo2max,
        ArchetypeSessionType.longRun     => WorkoutIntent.endurance,
      };
}

enum ExperienceLevel { beginner, intermediate, advanced }

// ============================================================================
// FLOOR KM
// ============================================================================

class _Floors {
  static double forType(ArchetypeSessionType type) => switch (type) {
        ArchetypeSessionType.recoveryEasy => 3.0,
        ArchetypeSessionType.easy        => 4.0,
        ArchetypeSessionType.easyMedium  => 5.0,
        ArchetypeSessionType.tempo       => 5.0,
        ArchetypeSessionType.interval    => 5.0,
        ArchetypeSessionType.longRun     => 8.0,
      };
}

// ============================================================================
// COMPOSITION SLOT
// ============================================================================

class _Slot {
  final ArchetypeSessionType type;
  final double fraction;

  const _Slot(this.type, this.fraction);
}

// ============================================================================
// ARCHETYPE SESSION + WEEK
// ============================================================================

class ArchetypeSession {
  final ArchetypeSessionType type;
  final double km;
  final double floorKm;

  const ArchetypeSession({
    required this.type,
    required this.km,
    required this.floorKm,
  });

  double get effectiveKm => km < floorKm ? floorKm : km;
}

class ArchetypeWeek {
  final List<ArchetypeSession> sessions;

  const ArchetypeWeek(this.sessions);

  int get sessionCount => sessions.length;
  int get qualityCount => sessions.where((s) => s.type.isQuality).length;
  bool get hasLongRun  => sessions.any((s) => s.type.isLong);
  double get totalKm   => sessions.fold(0.0, (sum, s) => sum + s.effectiveKm);
}

// ============================================================================
// PEAK WEEKLY KM TABLE
// ============================================================================

class PeakWeeklyKm {
  static double lookup({
    required RaceDistance race,
    required ExperienceLevel experience,
  }) =>
      switch ((race, experience)) {
        (RaceDistance.fiveK,        ExperienceLevel.beginner)     => 35,
        (RaceDistance.fiveK,        ExperienceLevel.intermediate) => 45,
        (RaceDistance.fiveK,        ExperienceLevel.advanced)     => 55,
        (RaceDistance.tenK,         ExperienceLevel.beginner)     => 40,
        (RaceDistance.tenK,         ExperienceLevel.intermediate) => 55,
        (RaceDistance.tenK,         ExperienceLevel.advanced)     => 65,
        (RaceDistance.halfMarathon, ExperienceLevel.beginner)     => 50,
        (RaceDistance.halfMarathon, ExperienceLevel.intermediate) => 65,
        (RaceDistance.halfMarathon, ExperienceLevel.advanced)     => 75,
        (RaceDistance.marathon,     ExperienceLevel.beginner)     => 60,
        (RaceDistance.marathon,     ExperienceLevel.intermediate) => 75,
        (RaceDistance.marathon,     ExperienceLevel.advanced)     => 90,
        _ => 50,
      };
}

// ============================================================================
// ONBOARDING SLIDER RANGE
// ============================================================================

class WeeklyKmRange {
  final double min;
  final double max;
  final double defaultKm;

  const WeeklyKmRange({
    required this.min,
    required this.max,
    required this.defaultKm,
  });

  static WeeklyKmRange forRaceAndDays({
    required String race,
    required int days,
  }) {
    const table = <String, Map<int, WeeklyKmRange>>{
      '5k': {
        3: WeeklyKmRange(min: 18, max: 35, defaultKm: 24),
        4: WeeklyKmRange(min: 22, max: 45, defaultKm: 30),
        5: WeeklyKmRange(min: 28, max: 55, defaultKm: 38),
        6: WeeklyKmRange(min: 35, max: 65, defaultKm: 46),
      },
      '10k': {
        3: WeeklyKmRange(min: 18, max: 38, defaultKm: 26),
        4: WeeklyKmRange(min: 24, max: 50, defaultKm: 34),
        5: WeeklyKmRange(min: 32, max: 60, defaultKm: 42),
        6: WeeklyKmRange(min: 40, max: 70, defaultKm: 52),
      },
      'half_marathon': {
        3: WeeklyKmRange(min: 20, max: 42, defaultKm: 28),
        4: WeeklyKmRange(min: 28, max: 55, defaultKm: 38),
        5: WeeklyKmRange(min: 38, max: 68, defaultKm: 46),
        6: WeeklyKmRange(min: 48, max: 75, defaultKm: 54),
      },
      'marathon': {
        3: WeeklyKmRange(min: 22, max: 48, defaultKm: 32),
        4: WeeklyKmRange(min: 32, max: 65, defaultKm: 42),
        5: WeeklyKmRange(min: 45, max: 80, defaultKm: 52),
        6: WeeklyKmRange(min: 55, max: 90, defaultKm: 62),
      },
    };

    final raceMap = table[race] ?? table['10k']!;
    return raceMap[days] ?? raceMap[4]!;
  }
}

// ============================================================================
// ARCHETYPE TABLE — main API
// ============================================================================

class ArchetypeTable {
  const ArchetypeTable._();

  /// Build a week's session list.
  ///
  /// [weeklyKm]   Current week's target km (already scaled by WeekResolver).
  /// [days]       Training days selected (3–6).
  /// [experience] Gates composition and quality type.
  /// [phase]      Drives quality slot type resolution.
  static ArchetypeWeek? build({
    required double weeklyKm,
    required int days,
    required ExperienceLevel experience,
    required TrainingPhase phase,
  }) {
    if (days < 3 || days > 6) return null;

    final slots = phase == TrainingPhase.taper
        ? _taperSlots(days: days)
        : _slots(days: days, experience: experience, phase: phase);

    // Size all non-long-run sessions. Easy/recovery round to nearest 1km for
    // natural coach numbers (5km, 6km etc.). Quality sessions are untouched —
    // same 0.5km rounding as always; the template resolver owns their actual
    // distance. Long run absorbs the remainder so the weekly total stays
    // consistent across 3/4/5/6-day plans.
    final sessions  = <ArchetypeSession>[];
    var allocatedKm = 0.0;

    for (final slot in slots) {
      if (slot.type == ArchetypeSessionType.longRun) continue;

      final rawKm = weeklyKm * slot.fraction;
      final floor = _Floors.forType(slot.type);

      // Easy/recovery: round to nearest 1km.
      // Quality (tempo/interval): 0.5km rounding — same as original, no change.
      final km = slot.type.isEasy ? _roundKm(rawKm) : _round(rawKm);

      sessions.add(ArchetypeSession(type: slot.type, km: km, floorKm: floor));
      allocatedKm += km.clamp(floor, double.infinity);
    }

    // Long run absorbs whatever the weekly km minus all other sessions.
    final longKm    = _round((weeklyKm - allocatedKm).clamp(0.0, double.infinity));
    final longFloor = _Floors.forType(ArchetypeSessionType.longRun);
    sessions.add(ArchetypeSession(
      type: ArchetypeSessionType.longRun,
      km: longKm,
      floorKm: longFloor,
    ));

    return ArchetypeWeek(sessions);
  }

  // ── Composition slots ────────────────────────────────────────────────────

  static List<_Slot> _slots({
    required int days,
    required ExperienceLevel experience,
    required TrainingPhase phase,
  }) {
    final q1 = _q1(phase: phase, experience: experience);
    final q2 = ArchetypeSessionType.tempo; // Q2 always tempo

    return switch (days) {
      3 => [
          const _Slot(ArchetypeSessionType.easy,    0.22),
          _Slot(q1,                                 0.28),
          const _Slot(ArchetypeSessionType.longRun, 0.50),
        ],

      4 => [
          const _Slot(ArchetypeSessionType.recoveryEasy, 0.12),
          const _Slot(ArchetypeSessionType.easyMedium,   0.18),
          _Slot(q1,                                      0.25),
          const _Slot(ArchetypeSessionType.longRun,      0.45),
        ],

      // 5 days advanced: 2E + 2Q + 1L
      5 when experience == ExperienceLevel.advanced => [
          const _Slot(ArchetypeSessionType.recoveryEasy, 0.10),
          const _Slot(ArchetypeSessionType.easyMedium,   0.16),
          _Slot(q1,                                      0.18),
          _Slot(q2,                                      0.18),
          const _Slot(ArchetypeSessionType.longRun,      0.38),
        ],

      // 5 days beginner/intermediate: 3E + 1Q + 1L
      5 => [
          const _Slot(ArchetypeSessionType.recoveryEasy, 0.10),
          const _Slot(ArchetypeSessionType.easy,         0.14),
          const _Slot(ArchetypeSessionType.easyMedium,   0.16),
          _Slot(q1,                                      0.22),
          const _Slot(ArchetypeSessionType.longRun,      0.38),
        ],

      // 6 days: 3E + 2Q + 1L
      _ => [
          const _Slot(ArchetypeSessionType.recoveryEasy, 0.08),
          const _Slot(ArchetypeSessionType.easy,         0.12),
          const _Slot(ArchetypeSessionType.easyMedium,   0.14),
          _Slot(q1,                                      0.16),
          _Slot(q2,                                      0.16),
          const _Slot(ArchetypeSessionType.longRun,      0.34),
        ],
    };
  }

  // ── Taper slots ──────────────────────────────────────────────────────────
  // Same session count as normal weeks — no sessions dropped.
  // Always 1 quality slot (tempo). Volume handled by WeekResolver multiplier.

  static List<_Slot> _taperSlots({required int days}) => switch (days) {
        3 => [
            const _Slot(ArchetypeSessionType.easy,    0.25),
            const _Slot(ArchetypeSessionType.tempo,   0.25),
            const _Slot(ArchetypeSessionType.longRun, 0.50),
          ],
        4 => [
            const _Slot(ArchetypeSessionType.recoveryEasy, 0.12),
            const _Slot(ArchetypeSessionType.easy,         0.18),
            const _Slot(ArchetypeSessionType.tempo,        0.22),
            const _Slot(ArchetypeSessionType.longRun,      0.48),
          ],
        5 => [
            const _Slot(ArchetypeSessionType.recoveryEasy, 0.10),
            const _Slot(ArchetypeSessionType.easy,         0.14),
            const _Slot(ArchetypeSessionType.easyMedium,   0.16),
            const _Slot(ArchetypeSessionType.tempo,        0.22),
            const _Slot(ArchetypeSessionType.longRun,      0.38),
          ],
        _ => [
            const _Slot(ArchetypeSessionType.recoveryEasy, 0.08),
            const _Slot(ArchetypeSessionType.easy,         0.12),
            const _Slot(ArchetypeSessionType.easyMedium,   0.14),
            const _Slot(ArchetypeSessionType.easy,         0.12),
            const _Slot(ArchetypeSessionType.tempo,        0.20),
            const _Slot(ArchetypeSessionType.longRun,      0.34),
          ],
      };

  // ── Quality slot resolution ───────────────────────────────────────────────

  /// Q1 — primary quality slot.
  /// Beginner → always tempo.
  /// Base phase → tempo.
  /// Build/peak intermediate/advanced → interval.
  static ArchetypeSessionType _q1({
    required TrainingPhase phase,
    required ExperienceLevel experience,
  }) {
    if (experience == ExperienceLevel.beginner) return ArchetypeSessionType.tempo;
    if (phase == TrainingPhase.base) return ArchetypeSessionType.tempo;
    return ArchetypeSessionType.interval;
  }

  static double _round(double v)   => (v * 2).round() / 2;  // nearest 0.5km
  static double _roundKm(double v) => v.round().toDouble();  // nearest 1km
}