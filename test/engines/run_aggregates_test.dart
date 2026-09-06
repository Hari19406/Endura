/// RunAggregates — denormalized profile stats rolled from local run history.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/run_aggregates.dart';
import 'package:run_app/utils/database_service.dart' show RunRecord;

RunRecord run({
  required double km,
  required int seconds,
  double elevation = 0,
  DateTime? date,
}) => RunRecord(
  distanceKm: km,
  averagePace: '0:00',
  durationSeconds: seconds,
  date: date ?? DateTime(2026, 1, 1),
  routePolyline: '',
  elevationGain: elevation,
);

void main() {
  test('empty history → all zeros, null PRs', () {
    final a = RunAggregates.fromRuns([]);
    expect(a.totalRuns, 0);
    expect(a.totalDistanceMeters, 0);
    expect(a.best5kSeconds, isNull);
  });

  test('totals sum distance, moving time and elevation', () {
    final a = RunAggregates.fromRuns([
      run(km: 5, seconds: 1500, elevation: 30),
      run(km: 10, seconds: 3000, elevation: 70.4),
    ]);
    expect(a.totalRuns, 2);
    expect(a.totalDistanceMeters, 15000);
    expect(a.totalMovingSeconds, 4500);
    expect(a.totalElevationMeters, 100); // 30 + 70.4 → round
  });

  test('5K PR projects the fastest eligible run onto 5.0 km', () {
    // 4.6 km in 1200s → 260.87 s/km → ×5 ≈ 1304s. A slower 5 km run must lose.
    final a = RunAggregates.fromRuns([
      run(km: 4.6, seconds: 1200),
      run(km: 5.0, seconds: 1500),
    ]);
    expect(a.best5kSeconds, closeTo(1304, 1));
  });

  test('distance gates: a 3 km run never sets the 5K PR', () {
    final a = RunAggregates.fromRuns([run(km: 3, seconds: 600)]);
    expect(a.best5kSeconds, isNull);
    expect(a.best10kSeconds, isNull);
  });

  test('toMap uses the profile column names', () {
    final m = RunAggregates.fromRuns([run(km: 21.1, seconds: 6000)]).toMap();
    expect(
      m.keys,
      containsAll(<String>[
        'total_distance_meters',
        'total_runs',
        'total_moving_seconds',
        'total_elevation_meters',
        'best_5k_seconds',
        'best_10k_seconds',
        'best_half_marathon_seconds',
      ]),
    );
    expect(m['best_half_marathon_seconds'], isNotNull);
  });
}
