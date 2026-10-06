// lib/utils/gap_calculator.dart

import 'dart:math' as math;

/// Grade-Adjusted Pace (GAP) — the flat-ground pace that would cost the same
/// effort as the pace actually run on a gradient, using the Minetti et al.
/// (2002) cost-of-running polynomial normalised to flat-ground cost. Pure
/// functions, no I/O — run_screen (save time) and ActivityDetail (display and
/// per-split GAP) both go through here so the maths lives in one place.
///
/// DIRECTION. Uphill costs more energy per metre than flat, so running a
/// given pace uphill is the effort of a FASTER flat pace: GAP < actual.
/// Downhill is cheaper, so GAP > actual. In sec/km terms
/// `gap = pace × flatCost / gradedCost`.
///
/// RELIABILITY. Raw GPS altitude is noisy (several metres, and 0.0 when
/// unavailable), and track samples are tens of metres apart, so gradients are
/// never taken between adjacent samples. [GapCalculator.analyze] cleans the
/// altitude (missing/0.0 removed, spikes rejected, smoothed over distance) and
/// measures the gradient over a ≥100 m baseline, clamped to ±20 %.
class GapCalculator {
  GapCalculator._();

  // ── Tunables ─────────────────────────────────────────────────────────────

  /// Distance over which the gradient is measured (centred on each segment).
  static const double gradientBaselineM = 100;

  /// Below this the gradient window (shrunk near the ends of the elevation
  /// profile) is too short to trust and the segment is treated as flat.
  static const double minGradientBaselineM = 50;

  /// Half-width of the distance-based elevation smoothing window.
  static const double smoothingHalfWindowM = 90;

  /// Spacing of the uniform distance grid altitude is resampled onto before
  /// smoothing, so the window is in metres rather than in sample counts.
  static const double gridStepM = 20;

  /// A reading further than this from the median of its 5-point neighbourhood
  /// is a spike and is dropped.
  static const double spikeThresholdM = 15;

  /// Gradient clamp (fraction). Tighter than the Minetti curve's ±0.45
  /// validity: steeper road-running grades are far more likely noise.
  static const double maxAbsGradient = 0.20;

  /// Valid segment pace, sec/km (same range as pace zones).
  static const double minValidPaceSecPerKm = 120;
  static const double maxValidPaceSecPerKm = 1800;

  /// A gap between samples longer than this is a dropout, not running.
  static const double maxSegmentGapSeconds = 60;

  /// Fewer metres of valid segments than this and no run-level GAP is given.
  static const double minAnalysisDistanceM = 200;

  /// A split needs valid segments over at least this share of its distance.
  static const double minSplitCoverage = 0.7;

  // ── Cost model ───────────────────────────────────────────────────────────

  /// Cost of running (J/kg/m) as a function of gradient (fraction, e.g. 0.05
  /// = 5% uphill). Validated over roughly ±45% grade; clamp outside that.
  static double _costOfRunning(double gradient) {
    final g = gradient.clamp(-0.45, 0.45);
    return 155.4 * math.pow(g, 5) -
        30.4 * math.pow(g, 4) -
        43.3 * math.pow(g, 3) +
        46.3 * math.pow(g, 2) +
        19.5 * g +
        3.6;
  }

  /// Multiplier turning an actual pace/time into its flat-equivalent:
  /// `flatCost / gradedCost` — below 1 uphill, above 1 downhill.
  static double flatEquivalentFactor(double gradient) =>
      _costOfRunning(0.0) / _costOfRunning(gradient);

  /// Grade-adjusted pace in sec/km given an actual pace (sec/km) and
  /// gradient (fraction). Uphill → faster than [paceSecPerKm], downhill →
  /// slower, flat → unchanged.
  static double gradeAdjustedPaceSecPerKm(
    double paceSecPerKm,
    double gradient,
  ) => paceSecPerKm * flatEquivalentFactor(gradient);

  // ── Run analysis ─────────────────────────────────────────────────────────

  /// Full GAP analysis of a run's samples, or null when there isn't enough
  /// usable data (no altitude, too short, no valid segments).
  ///
  /// [finalDistanceM]/[finalSeconds] (the run's true totals) append the
  /// finish line as a closing point, because the last sample is up to ~150 m
  /// or 15 s short of the end.
  static GapAnalysis? analyze(
    List<GapSample> samples, {
    double? finalDistanceM,
    double? finalSeconds,
  }) {
    final pts = <GapSample>[
      for (final s in samples)
        if (s.distanceM.isFinite) s,
    ];
    if (pts.length < 2) return null;

    final last = pts.last;
    if (finalDistanceM != null &&
        finalSeconds != null &&
        last.timeSeconds != null &&
        finalDistanceM > last.distanceM &&
        finalSeconds > last.timeSeconds!) {
      pts.add(GapSample(distanceM: finalDistanceM, timeSeconds: finalSeconds));
    }

    final elevation = ElevationProfile.build(pts);
    if (elevation == null) return null;

    final segments = <GapSegment>[];
    var distanceM = 0.0;
    var rawSeconds = 0.0;
    var adjustedSeconds = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final dd = b.distanceM - a.distanceM;
      if (!(dd > 0)) continue;

      double seconds;
      if (a.timeSeconds != null && b.timeSeconds != null) {
        seconds = b.timeSeconds! - a.timeSeconds!;
        if (!(seconds > 0) || seconds > maxSegmentGapSeconds) continue;
      } else {
        // Old samples with no clock: fall back to the sample's own pace.
        final pace = b.paceSecPerKm;
        if (!_isValidPace(pace)) continue;
        seconds = pace! * dd / 1000;
      }

      final segPace = seconds / (dd / 1000);
      if (!_isValidPace(segPace)) continue;

      final gradient = elevation.gradientAround(
        (a.distanceM + b.distanceM) / 2,
      );
      final adjusted = seconds * flatEquivalentFactor(gradient);
      segments.add(
        GapSegment(
          startM: a.distanceM,
          endM: b.distanceM,
          seconds: seconds,
          adjustedSeconds: adjusted,
          gradient: gradient,
        ),
      );
      distanceM += dd;
      rawSeconds += seconds;
      adjustedSeconds += adjusted;
    }

    if (segments.isEmpty || distanceM < minAnalysisDistanceM) return null;
    return GapAnalysis._(
      segments: List.unmodifiable(segments),
      coveredDistanceM: distanceM,
      avgRawPaceSecPerKm: rawSeconds / (distanceM / 1000),
      avgGapSecPerKm: adjustedSeconds / (distanceM / 1000),
    );
  }

  static bool _isValidPace(double? pace) =>
      pace != null &&
      pace.isFinite &&
      pace >= minValidPaceSecPerKm &&
      pace <= maxValidPaceSecPerKm;

  // ── Legacy entry point (run_screen at save time) ─────────────────────────

  /// Average GAP in sec/km over raw track-sample maps (`{t, d, alt, pace}`
  /// with `d` in metres), or null if it can't be computed.
  static double? averageGapSecPerKm(List<Map<String, dynamic>> trackSamples) {
    final samples = <GapSample>[];
    for (final m in trackSamples) {
      final d = (m['d'] as num?)?.toDouble();
      if (d == null) continue;
      samples.add(
        GapSample(
          distanceM: d,
          timeSeconds: (m['t'] as num?)?.toDouble(),
          altitudeM: (m['alt'] as num?)?.toDouble(),
          paceSecPerKm: (m['pace'] as num?)?.toDouble(),
        ),
      );
    }
    return analyze(samples)?.avgGapSecPerKm;
  }
}

/// One telemetry point as GAP needs it. [distanceM] is cumulative metres.
class GapSample {
  final double distanceM;

  /// Seconds since the start of the phase, or null for old samples.
  final double? timeSeconds;

  /// Altitude in metres; null or exactly 0.0 means unavailable.
  final double? altitudeM;

  /// Smoothed instantaneous pace — used ONLY as a fallback for samples with
  /// no timestamps; segment pace otherwise comes from Δtime/Δdistance.
  final double? paceSecPerKm;

  const GapSample({
    required this.distanceM,
    this.timeSeconds,
    this.altitudeM,
    this.paceSecPerKm,
  });
}

/// One valid stretch between two samples.
class GapSegment {
  final double startM;
  final double endM;

  /// Actual time over the segment.
  final double seconds;

  /// Flat-equivalent time over the same distance.
  final double adjustedSeconds;

  /// Clamped gradient used (fraction; + is uphill).
  final double gradient;

  const GapSegment({
    required this.startM,
    required this.endM,
    required this.seconds,
    required this.adjustedSeconds,
    required this.gradient,
  });

  double get lengthM => endM - startM;
}

/// Result of [GapCalculator.analyze].
class GapAnalysis {
  final List<GapSegment> segments;

  /// Total metres covered by valid segments.
  final double coveredDistanceM;

  /// Average actual pace over the valid segments, sec/km — the figure GAP
  /// should be compared with (same segments, same clock).
  final double avgRawPaceSecPerKm;

  /// Σ(flat-equivalent time) / Σ(distance), sec/km.
  final double avgGapSecPerKm;

  const GapAnalysis._({
    required this.segments,
    required this.coveredDistanceM,
    required this.avgRawPaceSecPerKm,
    required this.avgGapSecPerKm,
  });

  /// GAP minus actual pace in sec/km. Negative → GAP faster (net uphill).
  double get deltaSecPerKm => avgGapSecPerKm - avgRawPaceSecPerKm;

  /// Flat-equivalent time ÷ actual time over the distance range
  /// [loKm]–[hiKm], clipping segments that straddle an edge. Multiply a
  /// split's own pace by this to get its GAP (a flat split gives exactly 1).
  /// Null when valid segments cover under [GapCalculator.minSplitCoverage] of
  /// the range.
  double? ratioBetween(double loKm, double hiKm) {
    final lo = loKm * 1000;
    final hi = hiKm * 1000;
    final rangeM = hi - lo;
    if (!(rangeM > 0)) return null;

    var coveredM = 0.0;
    var raw = 0.0;
    var adjusted = 0.0;
    for (final s in segments) {
      final from = math.max(s.startM, lo);
      final to = math.min(s.endM, hi);
      if (!(to > from)) continue;
      final share = (to - from) / s.lengthM;
      coveredM += to - from;
      raw += s.seconds * share;
      adjusted += s.adjustedSeconds * share;
    }
    if (coveredM < rangeM * GapCalculator.minSplitCoverage || raw <= 0) {
      return null;
    }
    return adjusted / raw;
  }
}

/// Cleaned, smoothed altitude as a function of distance.
class ElevationProfile {
  final double _startM;
  final double _endM;
  final List<double> _smoothed; // on a uniform grid from _startM

  ElevationProfile._(this._startM, this._endM, this._smoothed);

  /// Builds the profile from [samples], or null when fewer than two usable
  /// altitude readings remain. Pipeline: drop null/0.0/non-finite, reject
  /// spikes, resample onto a uniform distance grid, smooth over ±
  /// [GapCalculator.smoothingHalfWindowM].
  static ElevationProfile? build(List<GapSample> samples) {
    var pts = <(double d, double alt)>[
      for (final s in samples)
        if (s.altitudeM != null && s.altitudeM!.isFinite && s.altitudeM! != 0.0)
          (s.distanceM, s.altitudeM!),
    ];
    pts = _rejectSpikes(pts);
    if (pts.length < 2) return null;
    if (!(pts.last.$1 > pts.first.$1)) return null;

    final start = pts.first.$1;
    final end = pts.last.$1;
    final n = ((end - start) / GapCalculator.gridStepM).ceil() + 1;
    final grid = List<double>.filled(n, 0);
    var j = 0;
    for (var k = 0; k < n; k++) {
      final d = math.min(start + k * GapCalculator.gridStepM, end);
      while (j + 1 < pts.length - 1 && pts[j + 1].$1 <= d) {
        j++;
      }
      final (d0, a0) = pts[j];
      final (d1, a1) = pts[j + 1];
      grid[k] = d1 == d0
          ? a0
          : a0 + (a1 - a0) * ((d - d0) / (d1 - d0)).clamp(0.0, 1.0);
    }

    final halfPts =
        (GapCalculator.smoothingHalfWindowM / GapCalculator.gridStepM).round();
    final smoothed = List<double>.filled(n, 0);
    for (var k = 0; k < n; k++) {
      // Symmetric window, shrunk at the ends so it never leans one way.
      final h = math.min(halfPts, math.min(k, n - 1 - k));
      var sum = 0.0;
      for (var m = k - h; m <= k + h; m++) {
        sum += grid[m];
      }
      smoothed[k] = sum / (2 * h + 1);
    }
    return ElevationProfile._(start, end, smoothed);
  }

  /// Drops a reading that sits further than
  /// [GapCalculator.spikeThresholdM] from the median of itself and up to two
  /// neighbours each side. Fewer than three points: nothing to compare.
  static List<(double, double)> _rejectSpikes(List<(double, double)> pts) {
    if (pts.length < 3) return pts;
    final kept = <(double, double)>[];
    for (var i = 0; i < pts.length; i++) {
      final lo = math.max(0, i - 2);
      final hi = math.min(pts.length - 1, i + 2);
      final window = [for (var k = lo; k <= hi; k++) pts[k].$2]..sort();
      final mid = window.length ~/ 2;
      final median = window.length.isOdd
          ? window[mid]
          : (window[mid - 1] + window[mid]) / 2;
      if ((pts[i].$2 - median).abs() <= GapCalculator.spikeThresholdM) {
        kept.add(pts[i]);
      }
    }
    return kept;
  }

  /// Smoothed altitude at [distanceM] (held at the ends outside the range).
  double elevationAt(double distanceM) {
    final d = distanceM.clamp(_startM, _endM);
    final pos = (d - _startM) / GapCalculator.gridStepM;
    final k = pos.floor().clamp(0, _smoothed.length - 1);
    if (k >= _smoothed.length - 1) return _smoothed.last;
    final f = pos - k;
    return _smoothed[k] + (_smoothed[k + 1] - _smoothed[k]) * f;
  }

  /// Gradient (fraction) centred on [midM] over
  /// [GapCalculator.gradientBaselineM], the window shrunk symmetrically near
  /// the ends of the profile. Under [GapCalculator.minGradientBaselineM] it is
  /// 0 (flat); otherwise it is clamped to ±[GapCalculator.maxAbsGradient].
  double gradientAround(double midM) {
    final half = math.min(
      GapCalculator.gradientBaselineM / 2,
      math.min(midM - _startM, _endM - midM),
    );
    if (half * 2 < GapCalculator.minGradientBaselineM) return 0;
    final g =
        (elevationAt(midM + half) - elevationAt(midM - half)) / (2 * half);
    return g.clamp(-GapCalculator.maxAbsGradient, GapCalculator.maxAbsGradient);
  }
}
