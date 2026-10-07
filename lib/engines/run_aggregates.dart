// lib/engines/run_aggregates.dart
//
// Rolls the full local run history into the handful of numbers denormalized
// onto `profiles` (see migration 20260906000003). The 5K / 10K / half PR
// seconds are the athlete's #1 Best Effort at that distance — the same value
// PREngine and the Best Efforts screens show — so the public figure always
// matches what the owner sees. Totals still come from the runs themselves.

import '../services/best_efforts_service.dart';
import '../utils/database_service.dart' show BestEffortRecord, RunRecord;

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

  factory RunAggregates.fromRuns(
    List<RunRecord> runs, {
    Map<DistanceCategory, BestEffortRecord> bestEfforts = const {},
  }) {
    if (runs.isEmpty) return empty;

    double distanceKm = 0, elevationM = 0;
    int movingSeconds = 0;
    for (final r in runs) {
      distanceKm += r.distanceKm;
      movingSeconds += r.durationSeconds;
      elevationM += r.elevationGain;
    }

    return RunAggregates(
      totalDistanceMeters: (distanceKm * 1000).round(),
      totalRuns: runs.length,
      totalMovingSeconds: movingSeconds,
      totalElevationMeters: elevationM.round(),
      best5kSeconds: bestEfforts[DistanceCategory.k5]?.elapsedSeconds,
      best10kSeconds: bestEfforts[DistanceCategory.k10]?.elapsedSeconds,
      bestHalfMarathonSeconds:
          bestEfforts[DistanceCategory.half]?.elapsedSeconds,
    );
  }
}
