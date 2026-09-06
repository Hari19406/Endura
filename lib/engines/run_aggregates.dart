// lib/engines/run_aggregates.dart
//
// Rolls the full local run history into the handful of numbers denormalized
// onto `profiles` (see migration 20260906000003). PR seconds use the same
// "fastest eligible run projected onto the target distance" rule as PREngine,
// so the public figure matches what the owner sees on their own Stats tab.

import '../utils/database_service.dart' show RunRecord;

class RunAggregates {
  final int totalDistanceMeters;
  final int totalRuns;
  final int totalMovingSeconds;
  final int totalElevationMeters;
  final int? best5kSeconds;
  final int? best10kSeconds;
  final int? bestHalfMarathonSeconds;

  const RunAggregates({
    required this.totalDistanceMeters,
    required this.totalRuns,
    required this.totalMovingSeconds,
    required this.totalElevationMeters,
    this.best5kSeconds,
    this.best10kSeconds,
    this.bestHalfMarathonSeconds,
  });

  static const empty = RunAggregates(
    totalDistanceMeters: 0,
    totalRuns: 0,
    totalMovingSeconds: 0,
    totalElevationMeters: 0,
  );

  Map<String, dynamic> toMap() => {
    'total_distance_meters': totalDistanceMeters,
    'total_runs': totalRuns,
    'total_moving_seconds': totalMovingSeconds,
    'total_elevation_meters': totalElevationMeters,
    'best_5k_seconds': best5kSeconds,
    'best_10k_seconds': best10kSeconds,
    'best_half_marathon_seconds': bestHalfMarathonSeconds,
  };

  factory RunAggregates.fromRuns(List<RunRecord> runs) {
    if (runs.isEmpty) return empty;

    double distanceKm = 0, elevationM = 0;
    int movingSeconds = 0;
    for (final r in runs) {
      distanceKm += r.distanceKm;
      movingSeconds += r.durationSeconds;
      elevationM += r.elevationGain;
    }

    int? projected(double minKm, double targetKm) {
      double? bestPace; // sec per km
      for (final r in runs) {
        if (r.distanceKm < minKm || r.durationSeconds <= 0) continue;
        final pace = r.durationSeconds / r.distanceKm;
        if (bestPace == null || pace < bestPace) bestPace = pace;
      }
      return bestPace == null ? null : (bestPace * targetKm).round();
    }

    return RunAggregates(
      totalDistanceMeters: (distanceKm * 1000).round(),
      totalRuns: runs.length,
      totalMovingSeconds: movingSeconds,
      totalElevationMeters: elevationM.round(),
      best5kSeconds: projected(4.5, 5.0),
      best10kSeconds: projected(9.0, 10.0),
      bestHalfMarathonSeconds: projected(19.0, 21.0975),
    );
  }
}
