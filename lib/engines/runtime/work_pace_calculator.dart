/// WorkPaceCalculator — the "actual pace" fed to vDOT calibration.
///
/// Whole-run pace (`duration / distance`) is right for a continuous run, but an
/// interval or cruise-interval session blends its recovery jogs and walking
/// rests into the number, so 5 × 1 km @ 4:30 with 2:00 jogs reads as ~5:10. The
/// plan's target is the *work* pace, so comparing the two would look like a
/// slow run and could nudge vDOT down (or block a valid nudge up).
///
/// For a session with work reps separated by recovery this derives the pace of
/// the work alone from the run's track samples: the fastest stretch of the run
/// that adds up to the planned work distance. That needs no step timestamps
/// (the athlete advances steps by hand, and only per block, not per rep) and no
/// guess at the recovery pace. Anything else — a continuous run, an RPE-only
/// session, missing or too-sparse samples — falls back to the whole-run pace.
///
/// Calibration only. The summary screen still shows the whole-run average.
library;

import '../config/workout_template_library.dart'
    show BlockType, ResolvedBlock;

class WorkPaceCalculator {
  const WorkPaceCalculator._();

  /// Segments faster than this (s/km) are GPS glitches, not running.
  static const int _minPlausiblePace = 120;

  /// The usable samples must cover at least this share of the planned work
  /// distance, or the work pace isn't trustworthy.
  static const double _minCoverage = 0.5;

  /// Distance of planned work in km: main, pace-targeted blocks × their reps.
  /// Recovery distance is never counted.
  static double plannedWorkKm(List<ResolvedBlock> blocks) => blocks
      .where((b) => b.type == BlockType.main && !b.isRpeOnly)
      .fold(0.0, (sum, b) => sum + b.totalDistanceKm);

  /// True for a session whose work is interrupted by recovery: a main block
  /// with several reps and a recovery gap, or main work split by an explicit
  /// recovery block. A single continuous block (steady or tempo) is false.
  static bool hasRecoveryStructure(List<ResolvedBlock> blocks) {
    final work = blocks.where((b) => b.type == BlockType.main && !b.isRpeOnly);
    if (work.isEmpty) return false;
    final repsWithGaps = work.any(
      (b) =>
          (b.reps ?? 1) > 1 &&
          (b.recoverySeconds != null || b.recoveryMeters != null),
    );
    if (repsWithGaps) return true;
    return work.length > 1 && blocks.any((b) => b.type == BlockType.recovery);
  }

  /// Pace in s/km to compare against the plan's target.
  ///
  /// [blocks] are the scheduled workout's blocks (null for a free run).
  /// [trackSamples] are the run's `{t, d, ...}` samples (`t` seconds and `d`
  /// metres, both cumulative over the main phase). Null when there is no
  /// distance to divide by.
  static double? actualPaceSecPerKm({
    required List<ResolvedBlock>? blocks,
    required List<Map<String, dynamic>> trackSamples,
    required double distanceKm,
    required int durationSeconds,
  }) {
    final overall = distanceKm > 0 ? durationSeconds / distanceKm : null;
    if (blocks == null || !hasRecoveryStructure(blocks)) return overall;
    final work = fromTrackSamples(
      samples: trackSamples,
      workDistanceKm: plannedWorkKm(blocks),
    );
    return work ?? overall;
  }

  /// The pace of the fastest [workDistanceKm] of the run — the work reps with
  /// the recovery jogs and rests left out. Null when the samples can't support
  /// it (fewer than two, or covering under half the planned work).
  static double? fromTrackSamples({
    required List<Map<String, dynamic>> samples,
    required double workDistanceKm,
  }) {
    if (workDistanceKm <= 0 || samples.length < 2) return null;

    // Per-stretch (metres, seconds) between consecutive samples, starting from
    // the phase origin.
    final stretches = <({double m, double s})>[];
    var prevT = 0.0;
    var prevD = 0.0;
    for (final sample in samples) {
      final t = (sample['t'] as num?)?.toDouble();
      final d = (sample['d'] as num?)?.toDouble();
      if (t == null || d == null) continue;
      final dt = t - prevT;
      final dd = d - prevD;
      prevT = t;
      prevD = d;
      if (dt <= 0 || dd <= 0) continue; // standing still contributes no work
      if (dt / (dd / 1000) < _minPlausiblePace) continue; // GPS glitch
      stretches.add((m: dd, s: dt));
    }

    final needM = workDistanceKm * 1000;
    final totalM = stretches.fold(0.0, (sum, x) => sum + x.m);
    if (totalM < needM * _minCoverage) return null;

    // Fastest first; take whole stretches until the work distance is filled,
    // the last one only in part.
    stretches.sort((a, b) => (a.s / a.m).compareTo(b.s / b.m));
    var metres = 0.0;
    var seconds = 0.0;
    for (final x in stretches) {
      final remaining = needM - metres;
      if (remaining <= 0) break;
      final take = x.m <= remaining ? x.m : remaining;
      metres += take;
      seconds += x.s * (take / x.m);
    }
    return metres > 0 ? seconds / (metres / 1000) : null;
  }
}
