// lib/services/best_efforts_service.dart
//
// Pure rolling-window extractor: given a run's telemetry (cumulative
// distance + elapsed time), finds the fastest continuous segment for every
// tracked benchmark distance the run actually covered. No DB/Flutter deps —
// testable with plain fixtures, same spirit as engines/pr_engine.dart.
//
// CANONICAL ENTRY POINT: [BestEffortsService.analyzeRun]. It is the one place
// that turns a run's samples into Best Efforts — points, closing point, data
// validation and plausibility — and it is what BOTH the save-time path
// (run_screen) and the historical rebuild call. The lower-level
// [fastestSegmentSeconds] / [extract] stay available as the unvalidated
// building blocks; nothing else should reimplement the calculation.

/// Benchmark distances tracked for Best Efforts, in meters. `.name` is the
/// stable key persisted to `best_efforts.distance_category` — never rename
/// an enum value without a DB migration.
enum DistanceCategory {
  m400,
  k1,
  mi1,
  k3,
  k5,
  k10,
  half,
  marathon;

  double get meters => switch (this) {
    DistanceCategory.m400 => 400,
    DistanceCategory.k1 => 1000,
    DistanceCategory.mi1 => 1609.34,
    DistanceCategory.k3 => 3000,
    DistanceCategory.k5 => 5000,
    DistanceCategory.k10 => 10000,
    DistanceCategory.half => 21097.5,
    DistanceCategory.marathon => 42195,
  };

  String get label => switch (this) {
    DistanceCategory.m400 => '400m',
    DistanceCategory.k1 => '1K',
    DistanceCategory.mi1 => '1 mi',
    DistanceCategory.k3 => '3K',
    DistanceCategory.k5 => '5K',
    DistanceCategory.k10 => '10K',
    DistanceCategory.half => 'Half Marathon',
    DistanceCategory.marathon => 'Marathon',
  };

  /// A time no human has beaten, in seconds: set slightly BELOW the current
  /// world record for the distance so a legitimate elite run is never
  /// rejected, while a GPS or clock glitch (a 5K "in 9 minutes") always is.
  /// Not a performance standard — only a plausibility ceiling.
  double get ceilingSeconds => switch (this) {
    DistanceCategory.m400 => 42, // WR ~43.0
    DistanceCategory.k1 => 130, // WR ~2:11
    DistanceCategory.mi1 => 222, // WR ~3:43
    DistanceCategory.k3 => 435, // WR ~7:17
    DistanceCategory.k5 => 750, // WR ~12:35
    DistanceCategory.k10 => 1560, // WR ~26:11
    DistanceCategory.half => 3360, // WR ~56:42
    DistanceCategory.marathon => 7200, // WR ~2:00:35
  };

  static DistanceCategory? fromKey(String key) {
    for (final c in DistanceCategory.values) {
      if (c.name == key) return c;
    }
    return null;
  }
}

/// One telemetry sample: cumulative distance and elapsed time since the
/// start of the run (or main-set phase), both monotonically non-decreasing.
class TelemetryPoint {
  final double distanceMeters;
  final double elapsedSeconds;

  const TelemetryPoint({
    required this.distanceMeters,
    required this.elapsedSeconds,
  });
}

/// The fastest segment found for one [category] within a single run.
class BestEffortResult {
  final DistanceCategory category;
  final int elapsedSeconds;

  const BestEffortResult({
    required this.category,
    required this.elapsedSeconds,
  });
}

/// One effort from a single run, in the context of ALL of the athlete's
/// retained efforts at that distance: where it ranks and what the current
/// all-time best is. Built by the database from the stored `best_efforts`
/// rows (never recalculated), so it always agrees with the leaderboard.
class RunBestEffort {
  final DistanceCategory category;
  final int elapsedSeconds;

  /// 1 = the all-time best. Ties are broken exactly as the leaderboard orders
  /// them: earlier effort first, then id.
  final int rank;

  /// How many efforts exist at this distance (this one included).
  final int totalEfforts;

  /// The current all-time best time at this distance.
  final int bestSeconds;

  const RunBestEffort({
    required this.category,
    required this.elapsedSeconds,
    required this.rank,
    required this.totalEfforts,
    required this.bestSeconds,
  });

  bool get isPr => rank == 1;

  /// How much slower than the all-time best (0 for the PR itself).
  int get secondsOffBest => elapsedSeconds - bestSeconds;

  /// "PR", "2nd", "3rd", "4th" …
  String get rankLabel => BestEffortsService.rankLabel(rank);
}

/// Data-quality rules for [BestEffortsService.analyzeRun]. Deliberately
/// conservative: the goal is that an obvious GPS or clock glitch can't become
/// a personal best, not to second-guess a fast but legitimate runner.
class BestEffortsRules {
  /// A stretch between two samples faster than this is not running (10 m/s is
  /// 1:40/km, beyond what any recreational runner holds even for 15 s).
  final double maxSegmentSpeedMps;

  /// Distance may advance this far while the clock does not (whole-second
  /// quantisation, a finish line landing in the same second as the last
  /// sample). More than this with Δt ≤ 0 is a stalled clock.
  final double maxStallDistanceM;

  /// A window whose start edge has to be interpolated across samples further
  /// apart than this is too sparse to trust (normal spacing is ~15 s).
  final double maxEdgeGapSeconds;

  /// Reject any effort faster than [DistanceCategory.ceilingSeconds].
  final bool applyCeilings;

  const BestEffortsRules({
    this.maxSegmentSpeedMps = 10.0,
    this.maxStallDistanceM = 5.0,
    this.maxEdgeGapSeconds = 60.0,
    this.applyCeilings = true,
  });

  static const standard = BestEffortsRules();
}

class BestEffortsService {
  BestEffortsService._();

  /// THE canonical Best Efforts calculation for one run: decodes the track
  /// samples, closes the run with its true totals, and returns the validated
  /// fastest window for every [DistanceCategory] the run covers.
  ///
  /// [finalDistanceMeters]/[finalSeconds] are the run's stored totals
  /// (`distanceKm × 1000`, `durationSeconds`): the last sample can sit up to
  /// ~150 m / 15 s short of the finish, so they are appended as a closing
  /// point. Windows that cross a stalled clock, an impossible-speed stretch or
  /// sparse samples — and times beyond the plausibility ceiling — are
  /// discarded, never rounded into a PB.
  static List<BestEffortResult> analyzeRun(
    List<Map<String, dynamic>> trackSamples, {
    double? finalDistanceMeters,
    double? finalSeconds,
    BestEffortsRules rules = BestEffortsRules.standard,
  }) {
    final points = pointsFromTrackSamples(
      trackSamples,
      finalDistanceMeters: finalDistanceMeters,
      finalSeconds: finalSeconds,
    );
    return extract(points, rules: rules);
  }

  /// Converts a run's decoded `track_samples_json` (each `{'t': seconds,
  /// 'd': cumulativeMeters, ...}`) into [TelemetryPoint]s, prepending an
  /// implicit (0, 0) start point since samples begin partway into the
  /// main-set phase.
  ///
  /// Samples are only recorded every ~15s/150m, so the last one can sit up to
  /// 150m short of the finish. Pass [finalDistanceMeters]/[finalSeconds] (the
  /// run's true main-set totals) to append the finish line as a closing point,
  /// otherwise a run that barely clears a benchmark distance loses it or gets
  /// a slower window. Samples that go backwards in distance or time (GPS
  /// glitches) are dropped so the scan's monotonic assumption holds.
  static List<TelemetryPoint> pointsFromTrackSamples(
    List<Map<String, dynamic>> samples, {
    double? finalDistanceMeters,
    double? finalSeconds,
  }) {
    final points = <TelemetryPoint>[
      const TelemetryPoint(distanceMeters: 0, elapsedSeconds: 0),
    ];

    void add(double d, double t) {
      if (!d.isFinite || !t.isFinite) return;
      final last = points.last;
      if (d < last.distanceMeters || t < last.elapsedSeconds) return;
      points.add(TelemetryPoint(distanceMeters: d, elapsedSeconds: t));
    }

    for (final s in samples) {
      final d = (s['d'] as num?)?.toDouble();
      final t = (s['t'] as num?)?.toDouble();
      if (d == null || t == null) continue;
      add(d, t);
    }
    if (finalDistanceMeters != null &&
        finalSeconds != null &&
        finalDistanceMeters > points.last.distanceMeters) {
      add(finalDistanceMeters, finalSeconds);
    }
    return points;
  }

  /// Extracts the fastest continuous segment for every [DistanceCategory]
  /// that [points] actually reaches. Categories never reached (run too
  /// short) are omitted from the result. With [rules] null this is the plain,
  /// unvalidated scan; [analyzeRun] always passes rules.
  static List<BestEffortResult> extract(
    List<TelemetryPoint> points, {
    BestEffortsRules? rules,
  }) {
    final results = <BestEffortResult>[];
    for (final category in DistanceCategory.values) {
      final seconds = fastestSegmentSeconds(
        points,
        category.meters,
        rules: rules,
        ceilingSeconds: (rules?.applyCeilings ?? false)
            ? category.ceilingSeconds
            : null,
      );
      if (seconds != null) {
        results.add(
          BestEffortResult(category: category, elapsedSeconds: seconds),
        );
      }
    }
    return results;
  }

  /// Rolling two-pointer scan: for every sample `right`, finds the earliest
  /// point in time at which the run was exactly [targetMeters] behind
  /// `right`'s cumulative distance (interpolating between the two bracketing
  /// samples), and keeps the minimum elapsed time across all such windows.
  ///
  /// Both the window's trailing edge and its interpolation pointer only ever
  /// move forward, so this is O(n) per target distance.
  ///
  /// With [rules], a window is skipped (not the whole run) when it contains an
  /// invalid stretch (impossible speed, or distance with no time) or when its
  /// interpolated start edge spans sparse samples; with [ceilingSeconds] a
  /// window faster than the plausibility ceiling is skipped. Remaining valid
  /// windows still compete, so one glitch doesn't forfeit a legitimate effort
  /// elsewhere in the run.
  static int? fastestSegmentSeconds(
    List<TelemetryPoint> points,
    double targetMeters, {
    BestEffortsRules? rules,
    double? ceilingSeconds,
  }) {
    if (points.length < 2 || targetMeters <= 0) return null;
    if (points.last.distanceMeters < targetMeters) return null;

    // invalidBefore[i] = number of invalid stretches among segments 0..i-1.
    List<int>? invalidBefore;
    if (rules != null) {
      invalidBefore = List<int>.filled(points.length, 0);
      for (var i = 1; i < points.length; i++) {
        invalidBefore[i] =
            invalidBefore[i - 1] +
            (_segmentInvalid(points[i - 1], points[i], rules) ? 1 : 0);
      }
    }

    int j = 0;
    double? bestSeconds;

    for (int right = 1; right < points.length; right++) {
      final targetBoundary = points[right].distanceMeters - targetMeters;
      if (targetBoundary < 0) continue;

      while (j + 1 < points.length &&
          points[j + 1].distanceMeters <= targetBoundary) {
        j++;
      }
      if (j + 1 >= points.length) break;

      final d0 = points[j].distanceMeters;
      final d1 = points[j + 1].distanceMeters;
      final t0 = points[j].elapsedSeconds;
      final t1 = points[j + 1].elapsedSeconds;

      if (rules != null) {
        // Any invalid stretch the window passes through (segments j..right-1).
        if (invalidBefore![right] - invalidBefore[j] > 0) continue;
        // Start edge interpolated across sparse samples. Skipped when the edge
        // sits exactly on a sample — nothing is interpolated then.
        final startsOnSample = (targetBoundary - d0).abs() < 1e-9;
        if (!startsOnSample && t1 - t0 > rules.maxEdgeGapSeconds) continue;
      }

      final startTime = d1 == d0
          ? t0
          : t0 + (targetBoundary - d0) / (d1 - d0) * (t1 - t0);

      final segmentSeconds = points[right].elapsedSeconds - startTime;
      if (ceilingSeconds != null && segmentSeconds < ceilingSeconds) continue;
      if (segmentSeconds > 0 &&
          (bestSeconds == null || segmentSeconds < bestSeconds)) {
        bestSeconds = segmentSeconds;
      }
    }

    return bestSeconds?.round();
  }

  /// A stretch between consecutive samples that cannot be real running:
  /// distance advancing with no (or negative) time, beyond the quantisation
  /// allowance, or faster than the maximum plausible speed. A stretch with no
  /// forward movement can only make an effort slower, never a false PB, so it
  /// is never invalid.
  static bool _segmentInvalid(
    TelemetryPoint a,
    TelemetryPoint b,
    BestEffortsRules rules,
  ) {
    final dd = b.distanceMeters - a.distanceMeters;
    if (dd <= 0) return false;
    final dt = b.elapsedSeconds - a.elapsedSeconds;
    if (dt <= 0) return dd > rules.maxStallDistanceM;
    return dd / dt > rules.maxSegmentSpeedMps;
  }

  /// "PR" for rank 1, otherwise the ordinal: 2nd, 3rd, 4th … 11th, 12th, 21st.
  static String rankLabel(int rank) {
    if (rank <= 1) return 'PR';
    final mod100 = rank % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${rank}th';
    return switch (rank % 10) {
      1 => '${rank}st',
      2 => '${rank}nd',
      3 => '${rank}rd',
      _ => '${rank}th',
    };
  }

  /// Formats a duration as `m:ss`, or `h:mm:ss` once it reaches an hour —
  /// matches PREngine's time formatting so PRs and Best Efforts read
  /// consistently.
  static String formatElapsed(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}
