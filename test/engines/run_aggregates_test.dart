/// RunAggregates — denormalized profile stats rolled from local run history.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/run_aggregates.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/utils/database_service.dart'
    show BestEffortRecord, RunRecord;

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

  BestEffortRecord effort(DistanceCategory c, int seconds) => BestEffortRecord(
    id: '1_${c.name}',
    runId: '1',
    category: c,
    elapsedSeconds: seconds,
    recordedAt: DateTime(2026, 9, 1),
  );

  test('the 5K / 10K / half PRs are the athlete\'s #1 Best Efforts', () {
    final a = RunAggregates.fromRuns(
      [run(km: 21.5, seconds: 6200)],
      bestEfforts: {
        DistanceCategory.k5: effort(DistanceCategory.k5, 1304),
        DistanceCategory.k10: effort(DistanceCategory.k10, 2750),
        DistanceCategory.half: effort(DistanceCategory.half, 5900),
      },
    );
    expect(a.best5kSeconds, 1304);
    expect(a.best10kSeconds, 2750);
    expect(a.bestHalfMarathonSeconds, 5900);
  });

  test(
    'no whole-run projection: fast long runs without Best Efforts set no PR',
    () {
      // The old rule projected the fastest eligible run's average pace onto the
      // distance. That is gone: with no Best Effort there is no PR.
      final a = RunAggregates.fromRuns([
        run(km: 4.6, seconds: 1200),
        run(km: 12, seconds: 3000),
        run(km: 21.5, seconds: 6500),
      ]);
      expect(a.best5kSeconds, isNull);
      expect(a.best10kSeconds, isNull);
      expect(a.bestHalfMarathonSeconds, isNull);
    },
  );

  test('a Best Effort for one distance does not create PRs for others', () {
    final a = RunAggregates.fromRuns(
      [run(km: 6, seconds: 1800)],
      bestEfforts: {DistanceCategory.k5: effort(DistanceCategory.k5, 1500)},
    );
    expect(a.best5kSeconds, 1500);
    expect(a.best10kSeconds, isNull);
    expect(a.bestHalfMarathonSeconds, isNull);
  });

  test('totals are unaffected by Best Efforts', () {
    final runs = [
      run(km: 5, seconds: 1500, elevation: 30),
      run(km: 10, seconds: 3000, elevation: 70.4),
    ];
    final without = RunAggregates.fromRuns(runs);
    final withBe = RunAggregates.fromRuns(
      runs,
      bestEfforts: {DistanceCategory.k5: effort(DistanceCategory.k5, 1400)},
    );
    expect(withBe.totalRuns, without.totalRuns);
    expect(withBe.totalDistanceMeters, without.totalDistanceMeters);
    expect(withBe.totalMovingSeconds, without.totalMovingSeconds);
    expect(withBe.totalElevationMeters, without.totalElevationMeters);
  });

  test('toMap uses the profile column names', () {
    final m = RunAggregates.fromRuns(
      [run(km: 21.1, seconds: 6000)],
      bestEfforts: {DistanceCategory.half: effort(DistanceCategory.half, 5900)},
    ).toMap();
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
