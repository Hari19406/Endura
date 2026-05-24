import '../memory/engine_memory.dart';
import '../config/workout_template_library.dart';
import '../coach_engine_v2.dart' show ProgressionDecision;

class WeeklyVolumeResolver {
  // ── Volume range table ───────────────────────────────────────────────────
  static const Map<RaceDistance, _VolumeRange> _ranges = {
    RaceDistance.fiveK:        _VolumeRange(min: 15, sweetLow: 25, sweetHigh: 40, safeCap: 60),
    RaceDistance.tenK:         _VolumeRange(min: 20, sweetLow: 30, sweetHigh: 50, safeCap: 80),
    RaceDistance.halfMarathon: _VolumeRange(min: 30, sweetLow: 40, sweetHigh: 70, safeCap: 100),
    RaceDistance.marathon:     _VolumeRange(min: 40, sweetLow: 55, sweetHigh: 90, safeCap: 130),
  };

  /// Main entry point. Returns weekly target km rounded to nearest 0.5.
  double resolveWeeklyTarget({
    required EngineMemory memory,
    required RaceDistance goalRace,
    required int currentWeek,
    required ProgressionDecision? lastDecision,
    required bool is3to1Cutback,
  }) {
    final range = _ranges[goalRace]!;
    final baseline = memory.baselineWeeklyKm;

    // ── Week 1: seed from baseline, clamped to safe cap only ─────────────
    if (currentWeek == 1 || baseline == null) {
      final week1 = baseline ?? range.sweetLow.toDouble();
      return _round(week1.clamp(0, range.safeCap.toDouble()));
    }

    // ── Subsequent weeks: compound from previousWeekTargetKm ─────────────
    final prev = memory.previousWeekTargetKm ?? baseline;
    final factor = _resolveFactor(prev, range, lastDecision, is3to1Cutback);
    final next = prev * factor;

    // Only clamp to safeCap on the upper end.
    // Don't enforce min viable as a floor — athlete may be below it and
    // building up gradually. Min is only used to determine ramp rate.
    return _round(next.clamp(0.0, range.safeCap.toDouble()));
  }

  double _resolveFactor(
    double prev,
    _VolumeRange range,
    ProgressionDecision? decision,
    bool is3to1Cutback,
  ) {
    // 3:1 hard cutback always wins
    if (is3to1Cutback) return 0.70;

    // RPE-driven cutback
    if (decision == ProgressionDecision.regress) return 0.80;

    // Hold
    if (decision == ProgressionDecision.hold) return 1.0;

    // Progress — ramp rate by position vs sweet spot
    if (prev < range.min)      return 1.10;
    if (prev < range.sweetLow) return 1.10;
    if (prev <= range.sweetHigh) {
      return prev < (range.sweetLow + range.sweetHigh) / 2 ? 1.08 : 1.05;
    }
    return 1.03; // above sweet spot — hold-leaning
  }

  double _round(double km) => (km * 2).round() / 2;
}

class _VolumeRange {
  final int min;
  final int sweetLow;
  final int sweetHigh;
  final int safeCap;

  const _VolumeRange({
    required this.min,
    required this.sweetLow,
    required this.sweetHigh,
    required this.safeCap,
  });
}