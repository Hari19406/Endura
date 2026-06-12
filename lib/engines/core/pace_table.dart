/// PaceTable — translates vDOT score into training paces via Daniels' zones.
///
/// Accepts a vDOT score (int, 30–85) and looks up the corresponding E/M/T/I/R
/// pace ranges from [kVdotTable]. All pace derivation logic lives here.
/// Downstream callers use [resolve(PaceZone)] — API unchanged from Phase 1.
///
/// v3.4 additions:
///   - tenKPace: between I-pace and T-pace. Used by vo2_1200 (10K-pace reps).
///     Formula: midpoint of T and I zones — harder than threshold, easier than
///     full VO2max. Sits at roughly t.$1 - 5 → i.$2 + 5.
///   - hillRepeats: RPE-only zone (like hillSprints). 30–90 sec controlled
///     uphill effort — no pace target because gradient varies too much.
///   - steadyState: between aerobicEasy and tempo. Used by steady_state
///     template. Sits at M-pace (marathon pace zone) — same numbers as
///     marathonPace but kept as a distinct zone so UI can label it correctly
///     ("Steady State" vs "Marathon Pace").
library;

import 'vdot_calculator.dart';
import 'vdot_table.dart';

// ============================================================================
// PACE ZONE — every distinct pace the engine can prescribe
// ============================================================================

enum PaceZone {
  // ── Easy ────────────────────────────────────────────────────────────────
  shakeout,
  easyRecovery,
  aerobicEasy,
  progressiveStart,
  progressiveEnd,

  // ── Aerobic / moderate ───────────────────────────────────────────────────
  steadyState,      // NEW: M-pace held continuously — HM/FM quality session
  marathonPace,

  // ── Threshold / tempo ───────────────────────────────────────────────────
  thresholdProgStart,
  thresholdProgEnd,
  tempo,
  cruiseIntervals,

  // ── VO2max / interval ────────────────────────────────────────────────────
  tenKPace,         // NEW: between T and I — used for 1200m 10K-pace reps
  vo2Intervals,
  shortShort,
  fourHundredRepeats,
  ladderPyramid,

  // ── Speed / neuromuscular ────────────────────────────────────────────────
  strides,
  speedReps,

  // ── RPE-only ─────────────────────────────────────────────────────────────
  hillSprints,      // 8–12 sec max-effort
  hillRepeats,      // NEW: 30–90 sec controlled uphill — RPE-only

  // ── Goal-pace (require resolveGoalPace) ──────────────────────────────────
  goalPace,
  raceSimulation,
  dressRehearsal,
}

// ============================================================================
// RESOLVED PACE — what the table returns
// ============================================================================

class ResolvedPace {
  final int minSecondsPerKm;
  final int maxSecondsPerKm;
  final bool isRpeOnly;

  const ResolvedPace({
    required this.minSecondsPerKm,
    required this.maxSecondsPerKm,
    this.isRpeOnly = false,
  });

  const ResolvedPace.rpeOnly()
      : minSecondsPerKm = 0,
        maxSecondsPerKm = 0,
        isRpeOnly = true;

  int get targetPace => ((minSecondsPerKm + maxSecondsPerKm) / 2).round();

  String get formatted {
    if (isRpeOnly) return 'RPE — no pace target';
    return '${_fmt(minSecondsPerKm)}–${_fmt(maxSecondsPerKm)}/km';
  }

  String get formattedTarget {
    if (isRpeOnly) return 'RPE effort';
    return '${_fmt(targetPace)}/km';
  }

  static String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// PACE TABLE
// ============================================================================

class PaceTable {
  final int vdotScore;

  const PaceTable(this.vdotScore);

  VdotPaces get _paces => pacesFor(vdotScore);

  ResolvedPace resolve(PaceZone zone) {
    final p = _paces;
    final e = p.ePaceSecPerKm;
    final m = p.mPaceSecPerKm;
    final t = p.tPaceSecPerKm;
    final i = p.iPaceSecPerKm;
    final r = p.rPaceSecPerKm;

    return switch (zone) {
      // ── Easy zones ──────────────────────────────────────────────────────
      PaceZone.shakeout =>
          ResolvedPace(minSecondsPerKm: e.$2, maxSecondsPerKm: e.$2 + 30),
      PaceZone.easyRecovery =>
          ResolvedPace(minSecondsPerKm: e.$2 - 10, maxSecondsPerKm: e.$2 + 10),
      PaceZone.aerobicEasy =>
          ResolvedPace(minSecondsPerKm: e.$1, maxSecondsPerKm: e.$2),
      PaceZone.progressiveStart =>
          ResolvedPace(minSecondsPerKm: e.$1 + 10, maxSecondsPerKm: e.$2 - 10),
      PaceZone.progressiveEnd =>
          ResolvedPace(minSecondsPerKm: m.$1 - 5, maxSecondsPerKm: m.$1 + 5),

      // ── Aerobic / moderate zones ─────────────────────────────────────────
      // steadyState and marathonPace share the M-pace band.
      // They are distinct enum values so the UI can label them differently.
      PaceZone.steadyState =>
          ResolvedPace(minSecondsPerKm: m.$1, maxSecondsPerKm: m.$2),
      PaceZone.marathonPace =>
          ResolvedPace(minSecondsPerKm: m.$1, maxSecondsPerKm: m.$2),

      // ── Threshold / tempo zones ──────────────────────────────────────────
      PaceZone.thresholdProgStart =>
          ResolvedPace(minSecondsPerKm: t.$1 + 10, maxSecondsPerKm: t.$2 + 20),
      PaceZone.tempo =>
          ResolvedPace(minSecondsPerKm: t.$1, maxSecondsPerKm: t.$2),
      PaceZone.cruiseIntervals =>
          ResolvedPace(minSecondsPerKm: t.$1, maxSecondsPerKm: t.$2 + 10),
      PaceZone.thresholdProgEnd =>
          ResolvedPace(minSecondsPerKm: t.$1 - 5, maxSecondsPerKm: t.$1 + 3),

      // ── VO2max / interval zones ──────────────────────────────────────────
      // tenKPace: midpoint between T and I zones.
      // Harder than threshold cruise, easier than full I-pace.
      // Roughly: min = t.$1 - 8, max = i.$2 + 5.
      PaceZone.tenKPace =>
          ResolvedPace(
            minSecondsPerKm: ((t.$1 + i.$1) ~/ 2) - 5,
            maxSecondsPerKm: ((t.$2 + i.$2) ~/ 2) + 5,
          ),
      PaceZone.vo2Intervals =>
          ResolvedPace(minSecondsPerKm: i.$1, maxSecondsPerKm: i.$2),
      PaceZone.ladderPyramid =>
          ResolvedPace(minSecondsPerKm: i.$1, maxSecondsPerKm: i.$2),
      PaceZone.shortShort =>
          ResolvedPace(minSecondsPerKm: r.$1, maxSecondsPerKm: i.$2),
      PaceZone.fourHundredRepeats =>
          ResolvedPace(minSecondsPerKm: r.$1, maxSecondsPerKm: r.$2),

      // ── Speed / rep zones ────────────────────────────────────────────────
      PaceZone.strides =>
          ResolvedPace(minSecondsPerKm: r.$1, maxSecondsPerKm: r.$2),
      PaceZone.speedReps =>
          ResolvedPace(minSecondsPerKm: r.$1 - 5, maxSecondsPerKm: r.$1 + 3),

      // ── RPE-only ─────────────────────────────────────────────────────────
      PaceZone.hillSprints  => const ResolvedPace.rpeOnly(),
      PaceZone.hillRepeats  => const ResolvedPace.rpeOnly(),

      // ── Goal-pace zones — require resolveGoalPace() ───────────────────────
      PaceZone.goalPace => throw StateError(
          'goalPace requires target finish time. Use resolveGoalPace() instead.',
        ),
      PaceZone.raceSimulation => throw StateError(
          'raceSimulation uses goal pace effort. Use resolveGoalPace() instead.',
        ),
      PaceZone.dressRehearsal => throw StateError(
          'dressRehearsal uses exact goal pace. Use resolveGoalPace() instead.',
        ),
    };
  }

  /// Goal pace derived from a target race time, not from vDOT zones.
  ResolvedPace resolveGoalPace({
    required PRDistance raceDistance,
    required int targetTimeSeconds,
  }) {
    final goalPace = (targetTimeSeconds / raceDistance.distanceKm).round();
    return ResolvedPace(
      minSecondsPerKm: goalPace - 5,
      maxSecondsPerKm: goalPace + 5,
    );
  }
}