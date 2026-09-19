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
///   All three flavours map to WorkoutIntent.aerobicBase — there is no
///   separate "recovery" intent; a lighter day is still a workout.
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

import 'dart:math' as math;

import '../../models/training_phase.dart';
import '../config/workout_template_library.dart';
import 'volume_model.dart';

// ============================================================================
// SESSION TYPE
// ============================================================================

enum ArchetypeSessionType {
  recoveryEasy,
  easy,
  easyMedium,
  mediumLong,
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

  /// True only for the week's single longest endurance run.
  bool get isLong => this == ArchetypeSessionType.longRun;

  /// A mid-week aerobic run longer than an easy day but shorter than the long
  /// run. Same intent as the long run; kept distinct so binding + audits can
  /// tell them apart.
  bool get isMediumLong => this == ArchetypeSessionType.mediumLong;

  WorkoutIntent get intent => switch (this) {
    // All three easy flavours are aerobicBase — this is just a naming
    // variant for session variety, not a distinct intent.
    ArchetypeSessionType.recoveryEasy => WorkoutIntent.aerobicBase,
    ArchetypeSessionType.easy => WorkoutIntent.aerobicBase,
    ArchetypeSessionType.easyMedium => WorkoutIntent.aerobicBase,
    ArchetypeSessionType.mediumLong => WorkoutIntent.endurance,
    ArchetypeSessionType.tempo => WorkoutIntent.threshold,
    ArchetypeSessionType.interval => WorkoutIntent.vo2max,
    ArchetypeSessionType.longRun => WorkoutIntent.endurance,
  };
}

enum ExperienceLevel { beginner, intermediate, advanced }

// ============================================================================
// FLOOR KM
// ============================================================================

/// No scheduled run is ever shorter than this — anything less is a warm-up,
/// not a workout.
const double minSessionKm = 1.5;

class _Floors {
  static double forType(ArchetypeSessionType type) => switch (type) {
    ArchetypeSessionType.recoveryEasy => 3.0,
    ArchetypeSessionType.easy => 4.0,
    ArchetypeSessionType.easyMedium => 5.0,
    ArchetypeSessionType.mediumLong => 8.0,
    ArchetypeSessionType.tempo => 5.0,
    ArchetypeSessionType.interval => 5.0,
    ArchetypeSessionType.longRun => 8.0,
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
  bool get hasLongRun => sessions.any((s) => s.type.isLong);
  bool get hasMediumLong => sessions.any((s) => s.type.isMediumLong);
  double get totalKm => sessions.fold(0.0, (sum, s) => sum + s.effectiveKm);
}

// ============================================================================
// PEAK WEEKLY KM TABLE
// ============================================================================

/// Kept for call-site compatibility — delegates to the single source.
class PeakWeeklyKm {
  static double lookup({
    required RaceDistance race,
    required ExperienceLevel experience,
  }) => VolumeModel.peakKm(race, experience);
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

  /// Onboarding slider band. Now delegates to [VolumeModel] — experience-aware
  /// and defined for 3–7 days (the old table stopped at 6 and wasn't keyed by
  /// experience). [experience] defaults to intermediate for legacy callers.
  static WeeklyKmRange forRaceAndDays({
    required String race,
    required int days,
    ExperienceLevel experience = ExperienceLevel.intermediate,
  }) => VolumeModel.onboardingRange(
    race: switch (race) {
      '5k' => RaceDistance.fiveK,
      '10k' => RaceDistance.tenK,
      'half_marathon' => RaceDistance.halfMarathon,
      'marathon' => RaceDistance.marathon,
      _ => RaceDistance.tenK,
    },
    experience: experience,
    days: days,
  );
}

// ============================================================================
// ARCHETYPE TABLE — main API
// ============================================================================

class ArchetypeTable {
  const ArchetypeTable._();

  /// Operational upper bound on the long run as a fraction of the week, per
  /// race — a little softer than each envelope's declared target (5K 25%,
  /// 10K 28%, FM 35%) so the reconciler keeps room on a tight week, but well
  /// below the generic ~0.55 ceiling. HM is capped at 42% (loose, so a 3-day week still can't exceed it).
  static double? _raceLongRunMaxFrac(RaceDistance race) => switch (race) {
        RaceDistance.fiveK => 0.33,
        RaceDistance.tenK => 0.33,
        RaceDistance.marathon => 0.38,
        // Half marathon: a long run is most of the point, so the cap is looser
        // than 5K/10K, but a 3-day week can't put half its volume on one day.
        RaceDistance.halfMarathon => 0.42,
        _ => null,
      };

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
    RaceDistance? race,
  }) {
    if (days < 3 || days > 7) return null;

    final slots = phase == TrainingPhase.taper
        ? _taperSlots(days: days)
        : _slots(days: days, experience: experience, phase: phase);

    // Size all non-long-run sessions. Easy/recovery round to nearest 1km for
    // natural coach numbers (5km, 6km etc.). Quality sessions are untouched —
    // same 0.5km rounding as always; the template resolver owns their actual
    // distance. Long run absorbs the remainder so the weekly total stays
    // consistent across 3/4/5/6-day plans.
    final sessions = <ArchetypeSession>[];
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
    var longKm = _round((weeklyKm - allocatedKm).clamp(0.0, double.infinity));
    final longFloor = _Floors.forType(ArchetypeSessionType.longRun);

    // A race-specific long-run cap (5K: 33% of the week) spills the excess into
    // the easy runs instead of stacking it on one day.
    final raceCap = race == null ? null : _raceLongRunMaxFrac(race);
    if (raceCap != null) {
      final cappedKm = _round(raceCap * weeklyKm);
      final excess = longKm - cappedKm;
      final easyIdx = [
        for (var i = 0; i < sessions.length; i++)
          if (sessions[i].type.isEasy) i,
      ];
      if (excess > 0 && easyIdx.isNotEmpty) {
        final share = excess / easyIdx.length;
        for (final i in easyIdx) {
          final s = sessions[i];
          sessions[i] = ArchetypeSession(
            type: s.type,
            km: _round(s.km + share),
            floorKm: s.floorKm,
          );
        }
        longKm = cappedKm;
      }
    }
    sessions.add(
      ArchetypeSession(
        type: ArchetypeSessionType.longRun,
        km: longKm,
        floorKm: longFloor,
      ),
    );

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
        const _Slot(ArchetypeSessionType.easy, 0.22),
        _Slot(q1, 0.28),
        const _Slot(ArchetypeSessionType.longRun, 0.50),
      ],

      4 => [
        const _Slot(ArchetypeSessionType.recoveryEasy, 0.12),
        const _Slot(ArchetypeSessionType.easyMedium, 0.18),
        _Slot(q1, 0.25),
        const _Slot(ArchetypeSessionType.longRun, 0.45),
      ],

      // 5 days advanced: 2E + 2Q + 1L
      5 when experience == ExperienceLevel.advanced => [
        const _Slot(ArchetypeSessionType.recoveryEasy, 0.10),
        const _Slot(ArchetypeSessionType.easyMedium, 0.16),
        _Slot(q1, 0.18),
        _Slot(q2, 0.18),
        const _Slot(ArchetypeSessionType.longRun, 0.38),
      ],

      // 5 days beginner/intermediate: 3E + 1Q + 1L
      5 => [
        const _Slot(ArchetypeSessionType.recoveryEasy, 0.10),
        const _Slot(ArchetypeSessionType.easy, 0.14),
        const _Slot(ArchetypeSessionType.easyMedium, 0.16),
        _Slot(q1, 0.22),
        const _Slot(ArchetypeSessionType.longRun, 0.38),
      ],

      // 6 days: 3E + 2Q + 1L
      6 => [
        const _Slot(ArchetypeSessionType.recoveryEasy, 0.08),
        const _Slot(ArchetypeSessionType.easy, 0.12),
        const _Slot(ArchetypeSessionType.easyMedium, 0.14),
        _Slot(q1, 0.16),
        _Slot(q2, 0.16),
        const _Slot(ArchetypeSessionType.longRun, 0.34),
      ],

      // 7 days: 4E + 2Q + 1L. Quality count stays at 2 — WeekResolver's
      // anchored pattern never assigns more than two, regardless of day count.
      // The extra day is an easy run, and the long run shrinks accordingly.
      _ => [
        const _Slot(ArchetypeSessionType.recoveryEasy, 0.07),
        const _Slot(ArchetypeSessionType.easy, 0.10),
        const _Slot(ArchetypeSessionType.easy, 0.11),
        const _Slot(ArchetypeSessionType.easyMedium, 0.13),
        _Slot(q1, 0.15),
        _Slot(q2, 0.15),
        const _Slot(ArchetypeSessionType.longRun, 0.29),
      ],
    };
  }

  // ── Taper slots ──────────────────────────────────────────────────────────
  // Same session count as normal weeks — no sessions dropped.
  // Always 1 quality slot (tempo). Volume handled by WeekResolver multiplier.

  static List<_Slot> _taperSlots({required int days}) => switch (days) {
    3 => [
      const _Slot(ArchetypeSessionType.easy, 0.25),
      const _Slot(ArchetypeSessionType.tempo, 0.25),
      const _Slot(ArchetypeSessionType.longRun, 0.50),
    ],
    4 => [
      const _Slot(ArchetypeSessionType.recoveryEasy, 0.12),
      const _Slot(ArchetypeSessionType.easy, 0.18),
      const _Slot(ArchetypeSessionType.tempo, 0.22),
      const _Slot(ArchetypeSessionType.longRun, 0.48),
    ],
    5 => [
      const _Slot(ArchetypeSessionType.recoveryEasy, 0.10),
      const _Slot(ArchetypeSessionType.easy, 0.14),
      const _Slot(ArchetypeSessionType.easyMedium, 0.16),
      const _Slot(ArchetypeSessionType.tempo, 0.22),
      const _Slot(ArchetypeSessionType.longRun, 0.38),
    ],
    6 => [
      const _Slot(ArchetypeSessionType.recoveryEasy, 0.08),
      const _Slot(ArchetypeSessionType.easy, 0.12),
      const _Slot(ArchetypeSessionType.easyMedium, 0.14),
      const _Slot(ArchetypeSessionType.easy, 0.12),
      const _Slot(ArchetypeSessionType.tempo, 0.20),
      const _Slot(ArchetypeSessionType.longRun, 0.34),
    ],
    // 7 days: 5E + 1Q + 1L — taper keeps one quality slot at any day count.
    _ => [
      const _Slot(ArchetypeSessionType.recoveryEasy, 0.07),
      const _Slot(ArchetypeSessionType.easy, 0.11),
      const _Slot(ArchetypeSessionType.easyMedium, 0.12),
      const _Slot(ArchetypeSessionType.easy, 0.11),
      const _Slot(ArchetypeSessionType.easy, 0.10),
      const _Slot(ArchetypeSessionType.tempo, 0.19),
      const _Slot(ArchetypeSessionType.longRun, 0.30),
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
    if (experience == ExperienceLevel.beginner) {
      return ArchetypeSessionType.tempo;
    }
    if (phase == TrainingPhase.base) return ArchetypeSessionType.tempo;
    return ArchetypeSessionType.interval;
  }

  static double _round(double v) => (v * 2).round() / 2; // nearest 0.5km
  static double _roundKm(double v) => v.round().toDouble(); // nearest 1km

  // ==========================================================================
  // BOUNDED ALLOCATION (v3)
  //
  // Deterministic per-session km that SUMS to effectiveKm ± allocationTolerance.
  // Differences from build():
  //   - the long run is a BOUNDED absorber in both directions, not "weekly
  //     minus everything";
  //   - floors feed a reconciliation pass instead of silently inflating the
  //     weekly total;
  //   - quality km is phase-aware (rises base → build → peak);
  //   - an optional medium-long aerobic run for HM/FM at 5+ days.
  //
  // allocate() does NOT decide tempo-vs-interval for quality slots — it emits
  // ArchetypeSessionType.tempo as a sizing placeholder; WeekResolver assigns the
  // real intent from the slot pattern.
  // ==========================================================================

  /// Total |Σ effectiveKm − effectiveKm| is guaranteed ≤ this.
  static double allocationTolerance(double effectiveKm) =>
      math.max(1.0, effectiveKm * 0.02);

  static ArchetypeWeek allocate({
    required double effectiveKm,
    required int days,
    required int qualityCount,
    required ExperienceLevel experience,
    required TrainingPhase phase,
    required RaceDistance raceDistance,
    double? longRunKmTarget,
    bool allowMediumLong = false,
  }) {
    final wk = effectiveKm;
    if (wk <= 0) return const ArchetypeWeek([]);

    final n = days.clamp(3, 7);
    final isTaper = phase == TrainingPhase.taper;
    final qCount = isTaper
        ? qualityCount.clamp(0, 1)
        : qualityCount.clamp(0, 2);

    final hasMediumLong =
        allowMediumLong &&
        !isTaper &&
        n >= 5 &&
        (raceDistance == RaceDistance.halfMarathon ||
            raceDistance == RaceDistance.marathon);

    final easyCount = (n - 1 - (hasMediumLong ? 1 : 0) - qCount).clamp(0, n);
    final easyTypes = _easyFlavours(easyCount);

    // ── Bounds ───────────────────────────────────────────────────────────────
    final (lrMinFrac, lrMaxFrac) = _lrBounds(phase, raceDistance, n);
    // The 8 km absolute floor must not push a capped race (5K/10K) past its
    // operational fraction on a small week.
    final raceCap = _raceLongRunMaxFrac(raceDistance);
    final baseLrFloorKm = raceCap == null ? 8.0 : math.min(8.0, raceCap * wk);

    // On a very small week the per-type floors (easy 3–5 km, quality 5 km, long
    // run 8 km) add up to more than the week itself, and the reconciler would
    // stack the surplus on the long run. Scale every floor down together so the
    // week still fits — but never below a meaningful 1.5 km run.
    final floorSum =
        easyTypes.fold(0.0, (s, t) => s + _Floors.forType(t)) +
        _Floors.forType(ArchetypeSessionType.tempo) * qCount +
        (hasMediumLong ? _Floors.forType(ArchetypeSessionType.mediumLong) : 0) +
        baseLrFloorKm;
    // Only a genuinely tiny week (under ~4.5 km a day) is scaled; an ordinary
    // floor-tight week keeps its floors and overshoots slightly, as before.
    final floorScale = floorSum > wk && wk < 4.5 * n ? wk / floorSum : 1.0;
    double scaled(double floor) =>
        floorScale >= 1.0
            ? floor
            : math.max(minSessionKm, (floor * floorScale * 2).floor() / 2);

    final lrFloorKm = scaled(baseLrFloorKm);
    final lrMin = math.max(lrFloorKm, lrMinFrac * wk);
    final lrMax = math.max(lrMin, lrMaxFrac * wk);

    final lrTarget = longRunKmTarget ?? ((lrMinFrac + lrMaxFrac) / 2 * wk);
    final lrKm = lrTarget.clamp(lrMin, lrMax);

    // At very low weekly volume (e.g. 6 days on a short base plan) `0.9 * lrKm`
    // can fall below the 8 km medium-long floor; guard it here so the clamp
    // below (and the session `max` bound) always has lo ≤ hi.
    final double mlMax = math.max(8.0, 0.9 * lrKm);
    final mlKm = hasMediumLong ? (0.60 * lrKm).clamp(8.0, mlMax) : 0.0;

    final qMin = scaled(_Floors.forType(ArchetypeSessionType.tempo));
    final qMax = math.max(qMin, 0.25 * wk);
    final qEach = (_qualityFrac(phase) * wk).clamp(qMin, qMax);

    // ── Easy pool ────────────────────────────────────────────────────────────
    final easyPool = wk - lrKm - mlKm - qEach * qCount;
    final easyWeights = easyTypes
        .map(
          (t) => switch (t) {
            ArchetypeSessionType.recoveryEasy => 0.78,
            ArchetypeSessionType.easyMedium => 1.18,
            _ => 1.0,
          },
        )
        .toList();
    final weightSum = easyWeights.fold(0.0, (s, w) => s + w);
    // A single easy day carries at most ~20% of the week, and never more than
    // 20 km absolute — long enough for a genuine mid-week aerobic run at high
    // mileage, short enough that it never rivals the long run.
    // A 3-day week has only one easy day to soak up the volume the long run
    // can't take, so it may carry more (otherwise the long run balloons past
    // its race cap to make the week add up).
    final easyMax = ((n == 3 ? 0.34 : 0.20) * wk).clamp(8.0, 20.0);

    final mut = <_MutSession>[];
    for (var i = 0; i < easyTypes.length; i++) {
      final floor = scaled(_Floors.forType(easyTypes[i]));
      final raw = weightSum > 0
          ? (easyPool * easyWeights[i] / weightSum)
          : floor;
      mut.add(
        _MutSession(
          type: easyTypes[i],
          km: _roundKm(raw.clamp(floor, easyMax)),
          min: floor,
          max: math.max(floor, easyMax),
          step: 1.0,
        ),
      );
    }
    if (hasMediumLong) {
      mut.add(
        _MutSession(
          type: ArchetypeSessionType.mediumLong,
          km: _round(mlKm),
          min: 8.0,
          max: math.max(8.0, mlMax),
          step: 0.5,
        ),
      );
    }
    for (var i = 0; i < qCount; i++) {
      mut.add(
        _MutSession(
          type: ArchetypeSessionType.tempo,
          km: _round(qEach),
          min: qMin,
          max: math.max(qMin, qMax),
          step: 0.5,
        ),
      );
    }
    mut.add(
      _MutSession(
        type: ArchetypeSessionType.longRun,
        km: _round(lrKm),
        min: lrMin,
        max: lrMax,
        step: 0.5,
      ),
    );

    _reconcile(
      mut,
      wk,
      allocationTolerance(wk),
      floorScale: floorScale,
      longRunFloorKm: lrFloorKm,
    );

    return ArchetypeWeek(
      mut
          .map(
            (m) => ArchetypeSession(
              type: m.type,
              km: m.km,
              floorKm: math.min(_Floors.forType(m.type), m.min),
            ),
          )
          .toList(),
    );
  }

  // ── Reconciliation ─────────────────────────────────────────────────────────
  // Drive Σ km to wk ± tol by trimming/growing sessions within their bounds,
  // in a deliberate priority order so the long run and quality are touched last.
  static void _reconcile(
    List<_MutSession> mut,
    double wk,
    double tol, {
    double floorScale = 1.0,
    double? longRunFloorKm,
  }) {
    double total() => mut.fold(0.0, (s, m) => s + m.km);

    // Trim order: easy (largest first) → mediumLong → longRun → quality.
    // Grow order:  longRun → easy → mediumLong → quality.
    int rank(ArchetypeSessionType t, {required bool trimming}) {
      final easy = t.isEasy ? 0 : 4;
      final ml = t.isMediumLong ? 1 : 4;
      final lr = t.isLong ? (trimming ? 2 : 0) : 4;
      final q = t.isQuality ? 3 : 4;
      final base = math.min(math.min(easy, ml), math.min(lr, q));
      return trimming ? base : (t.isLong ? 0 : base + 1);
    }

    for (var iter = 0; iter < 500; iter++) {
      final diff = total() - wk;
      if (diff.abs() <= tol) break;
      final trimming = diff > 0;

      final ordered = [...mut]..sort((a, b) {
        final r = rank(a.type, trimming: trimming)
            .compareTo(rank(b.type, trimming: trimming));
        if (r != 0) return r;
        return trimming ? b.km.compareTo(a.km) : a.km.compareTo(b.km);
      });

      var moved = false;
      for (final m in ordered) {
        final room = trimming ? (m.km - m.min) : (m.max - m.km);
        if (room < m.step) continue;
        final want = (diff.abs() - tol);
        final delta = math.min(room, math.max(m.step, _snap(want, m.step)));
        m.km = trimming ? m.km - delta : m.km + delta;
        moved = true;
        break;
      }

      if (moved) continue;

      // Every session is at a soft bound but we still miss tolerance. Bounds
      // are preferences; the sum guarantee is the contract. Relax onto the
      // long run first (it is the natural absorber), then the largest easy,
      // capping the long run at 65% of the week and nothing below its floor.
      final absorber = mut.firstWhere(
        (m) => m.type.isLong,
        orElse: () => ordered.first,
      );
      final hardMax = absorber.type.isLong ? 0.65 * wk : (absorber.max + wk);
      final hardMin = absorber.type.isLong && longRunFloorKm != null
          ? longRunFloorKm
          : (floorScale >= 1.0
                ? _Floors.forType(absorber.type)
                : math.max(
                    minSessionKm,
                    _Floors.forType(absorber.type) * floorScale,
                  ));
      final want = _snap(diff.abs(), absorber.step); // close the whole gap
      if (trimming) {
        absorber.km = math.max(hardMin, absorber.km - want);
      } else {
        absorber.km = math.min(hardMax, absorber.km + want);
      }
      break;
    }
  }

  static double _snap(double v, double step) => (v / step).round() * step;

  static List<ArchetypeSessionType> _easyFlavours(int count) => switch (count) {
    <= 0 => const [],
    1 => const [ArchetypeSessionType.easy],
    2 => const [
      ArchetypeSessionType.recoveryEasy,
      ArchetypeSessionType.easyMedium,
    ],
    3 => const [
      ArchetypeSessionType.recoveryEasy,
      ArchetypeSessionType.easy,
      ArchetypeSessionType.easyMedium,
    ],
    4 => const [
      ArchetypeSessionType.recoveryEasy,
      ArchetypeSessionType.easy,
      ArchetypeSessionType.easy,
      ArchetypeSessionType.easyMedium,
    ],
    _ => const [
      ArchetypeSessionType.recoveryEasy,
      ArchetypeSessionType.easy,
      ArchetypeSessionType.easy,
      ArchetypeSessionType.easy,
      ArchetypeSessionType.easyMedium,
    ],
  };

  /// (minFraction, maxFraction) of the weekly km the long run may occupy.
  static (double, double) _lrBounds(
    TrainingPhase phase,
    RaceDistance race,
    int n,
  ) {
    final center = switch (n) {
      3 => 0.45,
      4 => 0.42,
      5 => 0.36,
      6 => 0.32,
      _ => 0.28,
    };
    final raceAdj = switch (race) {
      RaceDistance.fiveK => -0.03,
      RaceDistance.tenK => -0.01,
      RaceDistance.halfMarathon => 0.0,
      RaceDistance.marathon => 0.02,
    };
    final phaseAdj = switch (phase) {
      TrainingPhase.base => -0.02,
      TrainingPhase.build => 0.0,
      TrainingPhase.peak => 0.02,
      TrainingPhase.taper => 0.0,
      TrainingPhase.maintenance => -0.02,
    };
    final c = (center + raceAdj + phaseAdj).clamp(0.22, 0.52);
    var minFrac = (c - 0.08).clamp(0.18, c);
    var maxFrac = (c + 0.08).clamp(c, 0.55);
    // Per-race operational long-run cap (5K/10K supporting run; marathon 35%
    // ceiling). The declared target and the absolute km ceiling are applied to
    // the skeleton long-run target in RacePlanBuilder.
    final raceCap = _raceLongRunMaxFrac(race);
    if (raceCap != null) {
      maxFrac = math.min(maxFrac, raceCap);
      minFrac = math.min(minFrac, maxFrac);
    }
    return (minFrac, maxFrac);
  }

  /// Per-quality-session fraction of the weekly km, before clamping.
  static double _qualityFrac(TrainingPhase phase) => switch (phase) {
    TrainingPhase.base => 0.10,
    TrainingPhase.build => 0.13,
    TrainingPhase.peak => 0.15,
    TrainingPhase.taper => 0.12,
    TrainingPhase.maintenance => 0.10,
  };
}

class _MutSession {
  final ArchetypeSessionType type;
  double km;
  final double min;
  final double max;
  final double step;

  _MutSession({
    required this.type,
    required this.km,
    required this.min,
    required this.max,
    required this.step,
  });
}
