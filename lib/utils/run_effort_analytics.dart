// lib/utils/run_effort_analytics.dart
//
// Pure, aligned view of one run's pace, heart rate and elevation on a single
// distance/time axis, so the relationship between them can be charted and
// later interpreted. No Flutter, database or BLE imports.
//
// There is deliberately no second pipeline here: telemetry samples are already
// aligned (one sample carries time, distance, pace, HR and altitude), so
// building the series is a per-sample join. Validity and cleaning are the
// established rules, reused rather than re-implemented:
//   • HR   → HrAnalytics.isValidBpm   (30–230 bpm)
//   • pace → PaceAnalytics.isValidPace (120–1800 s/km)
//   • elevation → ElevationProfile    (null / 0.0 dropped, spikes rejected,
//                                      smoothed over distance)
//   • gradient → GapAnalysis segments (or ElevationProfile.gradientAround)
//   • gaps → PaceAnalytics.gapSeconds (60 s)
//
// This layer only describes the data. It draws no conclusions about fatigue,
// drift or fitness — that belongs to a later coaching layer.

import 'gap_calculator.dart';
import 'hr_analytics.dart';
import 'pace_analytics.dart';

enum EffortChannel { pace, hr, elevation }

/// One raw telemetry point as the effort series needs it.
class EffortInput {
  /// Seconds since the start of the recorded phase; null for samples with no
  /// clock (old runs, synthesised Feed series).
  final double? timeSeconds;
  final double distanceKm;

  /// Instantaneous pace, sec/km.
  final double? paceSecPerKm;
  final int? hrBpm;
  final double? elevationM;

  const EffortInput({
    this.timeSeconds,
    required this.distanceKm,
    this.paceSecPerKm,
    this.hrBpm,
    this.elevationM,
  });
}

/// One aligned point. A channel value is null when it was missing or failed
/// validation at this point.
class EffortPoint {
  final double? timeSeconds;
  final double distanceKm;

  /// Valid pace only (120–1800 s/km), else null.
  final double? paceSecPerKm;

  /// Valid HR only (30–230 bpm), else null.
  final int? hrBpm;

  /// Cleaned, smoothed elevation (metres), else null.
  final double? elevationM;

  /// Smoothed gradient as a fraction (+ is uphill), else null.
  final double? gradient;

  /// True when more than [PaceAnalytics.gapSeconds] separates this point from
  /// the previous one: no line should be drawn between them.
  final bool breakBefore;

  const EffortPoint({
    this.timeSeconds,
    required this.distanceKm,
    this.paceSecPerKm,
    this.hrBpm,
    this.elevationM,
    this.gradient,
    this.breakBefore = false,
  });

  double? valueOf(EffortChannel channel) => switch (channel) {
    EffortChannel.pace => paceSecPerKm,
    EffortChannel.hr => hrBpm?.toDouble(),
    EffortChannel.elevation => elevationM,
  };
}

class RunEffortSeries {
  final List<EffortPoint> points;

  /// At least two points carry a timestamp. Without a clock the series can
  /// still be plotted, but gaps can't be detected and the combined chart is
  /// not offered (Feed runs are synthesised from per-km splits).
  final bool hasTimestamps;

  const RunEffortSeries._(this.points, this.hasTimestamps);

  static const RunEffortSeries empty = RunEffortSeries._([], false);

  /// Builds the series.
  ///
  /// [gap] supplies per-segment gradients when available; otherwise gradient
  /// comes from the elevation profile. [cleanElevation] false uses elevation
  /// exactly as given — for synthesised series (Feed) whose values are
  /// relative and where 0.0 is a legitimate reading.
  factory RunEffortSeries.build(
    List<EffortInput> inputs, {
    GapAnalysis? gap,
    bool cleanElevation = true,
  }) {
    final src = [
      for (final i in inputs)
        if (i.distanceKm.isFinite) i,
    ];
    if (src.isEmpty) return empty;

    // ── Elevation ────────────────────────────────────────────────────────
    ElevationProfile? profile;
    double? profileStartKm;
    double? profileEndKm;
    if (cleanElevation) {
      profile = ElevationProfile.build([
        for (final i in src)
          GapSample(
            distanceM: i.distanceKm * 1000,
            timeSeconds: i.timeSeconds,
            altitudeM: i.elevationM,
          ),
      ]);
      // Only report elevation inside the span where a real reading exists;
      // the profile holds its end values outside it.
      for (final i in src) {
        final e = i.elevationM;
        if (e == null || !e.isFinite || e == 0.0) continue;
        profileStartKm = profileStartKm == null || i.distanceKm < profileStartKm
            ? i.distanceKm
            : profileStartKm;
        profileEndKm = profileEndKm == null || i.distanceKm > profileEndKm
            ? i.distanceKm
            : profileEndKm;
      }
    }

    double? elevationAt(EffortInput i) {
      if (!cleanElevation) {
        final e = i.elevationM;
        return e != null && e.isFinite ? e : null;
      }
      if (profile == null ||
          profileStartKm == null ||
          profileEndKm == null ||
          i.distanceKm < profileStartKm ||
          i.distanceKm > profileEndKm) {
        return null;
      }
      return profile.elevationAt(i.distanceKm * 1000);
    }

    double? gradientAt(EffortInput i, bool hasElevation) {
      if (!cleanElevation || !hasElevation || profile == null) return null;
      final d = i.distanceKm * 1000;
      if (gap != null) {
        for (final s in gap.segments) {
          if (d >= s.startM && d <= s.endM) return s.gradient;
        }
      }
      return profile.gradientAround(d);
    }

    // ── Join ─────────────────────────────────────────────────────────────
    final points = <EffortPoint>[];
    double? prevT;
    var timed = 0;
    for (final i in src) {
      final t = i.timeSeconds;
      if (t != null) timed++;
      final breakBefore =
          t != null && prevT != null && t - prevT > PaceAnalytics.gapSeconds;
      if (t != null) prevT = t;

      final elevation = elevationAt(i);
      points.add(
        EffortPoint(
          timeSeconds: t,
          distanceKm: i.distanceKm,
          paceSecPerKm: PaceAnalytics.isValidPace(i.paceSecPerKm)
              ? i.paceSecPerKm
              : null,
          hrBpm: HrAnalytics.isValidBpm(i.hrBpm) ? i.hrBpm : null,
          elevationM: elevation,
          gradient: gradientAt(i, elevation != null),
          breakBefore: breakBefore,
        ),
      );
    }
    return RunEffortSeries._(List.unmodifiable(points), timed >= 2);
  }

  // ── Channel availability ─────────────────────────────────────────────────

  int validCount(EffortChannel channel) =>
      points.where((p) => p.valueOf(channel) != null).length;

  /// At least two valid points — enough to draw a line.
  bool has(EffortChannel channel) => validCount(channel) >= 2;

  bool get hasPace => has(EffortChannel.pace);
  bool get hasHr => has(EffortChannel.hr);
  bool get hasElevation => has(EffortChannel.elevation);

  List<EffortChannel> get availableChannels => [
    for (final c in EffortChannel.values)
      if (has(c)) c,
  ];

  int get channelCount => availableChannels.length;

  /// The combined pace · HR · elevation chart needs a clock and at least two
  /// channels to compare.
  bool get supportsCombinedChart => hasTimestamps && channelCount >= 2;

  /// Lowest and highest valid value of [channel], or null with none.
  (double min, double max)? rangeOf(EffortChannel channel) {
    double? lo, hi;
    for (final p in points) {
      final v = p.valueOf(channel);
      if (v == null) continue;
      lo = lo == null || v < lo ? v : lo;
      hi = hi == null || v > hi ? v : hi;
    }
    return lo == null ? null : (lo, hi!);
  }

  // ── Plotting helpers ─────────────────────────────────────────────────────

  /// Contiguous runs of valid points for [channel], split wherever the line
  /// must not be drawn across: a GPS/time gap over
  /// [PaceAnalytics.gapSeconds] between consecutive samples, or between this
  /// channel's own consecutive valid points (e.g. HR missing for minutes).
  /// Invalid or missing points inside a short stretch are simply skipped.
  List<List<EffortPoint>> runsFor(EffortChannel channel) {
    final runs = <List<EffortPoint>>[];
    var current = <EffortPoint>[];
    var sawBreak = false;
    EffortPoint? last;
    for (final p in points) {
      if (p.breakBefore) sawBreak = true;
      if (p.valueOf(channel) == null) continue;

      final longChannelGap =
          last != null &&
          last.timeSeconds != null &&
          p.timeSeconds != null &&
          p.timeSeconds! - last.timeSeconds! > PaceAnalytics.gapSeconds;
      if (current.isNotEmpty && (sawBreak || longChannelGap)) {
        runs.add(current);
        current = <EffortPoint>[];
      }
      current.add(p);
      last = p;
      sawBreak = false;
    }
    if (current.isNotEmpty) runs.add(current);
    return runs;
  }

  /// The point closest to [distanceKm], or null for an empty series.
  EffortPoint? nearest(double distanceKm) {
    EffortPoint? best;
    var bestDist = double.infinity;
    for (final p in points) {
      final d = (p.distanceKm - distanceKm).abs();
      if (d < bestDist) {
        best = p;
        bestDist = d;
      }
    }
    return best;
  }
}
