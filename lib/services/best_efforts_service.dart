// lib/services/best_efforts_service.dart
//
// Pure rolling-window extractor: given a run's telemetry (cumulative
// distance + elapsed time), finds the fastest continuous segment for every
// tracked benchmark distance the run actually covered. No DB/Flutter deps —
// testable with plain fixtures, same spirit as engines/pr_engine.dart.

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

class BestEffortsService {
  BestEffortsService._();

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
  /// short) are omitted from the result.
  static List<BestEffortResult> extract(List<TelemetryPoint> points) {
    final results = <BestEffortResult>[];
    for (final category in DistanceCategory.values) {
      final seconds = fastestSegmentSeconds(points, category.meters);
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
  static int? fastestSegmentSeconds(
    List<TelemetryPoint> points,
    double targetMeters,
  ) {
    if (points.length < 2 || targetMeters <= 0) return null;
    if (points.last.distanceMeters < targetMeters) return null;

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
      final startTime = d1 == d0
          ? t0
          : t0 + (targetBoundary - d0) / (d1 - d0) * (t1 - t0);

      final segmentSeconds = points[right].elapsedSeconds - startTime;
      if (segmentSeconds > 0 &&
          (bestSeconds == null || segmentSeconds < bestSeconds)) {
        bestSeconds = segmentSeconds;
      }
    }

    return bestSeconds?.round();
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
