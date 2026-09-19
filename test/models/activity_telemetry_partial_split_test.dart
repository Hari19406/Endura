import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/utils/database_service.dart';

RunRecord _run({
  required double km,
  required int seconds,
  List<Map<String, dynamic>> splits = const [],
  List<Map<String, dynamic>> samples = const [],
}) => RunRecord(
  date: DateTime(2026, 9, 20, 7),
  distanceKm: km,
  averagePace: '5:00',
  durationSeconds: seconds,
  routePolyline: '',
  workoutType: 'easy',
  splits: splits,
  trackSamples: samples,
);

void main() {
  test('a 0.7 km run gets a single partial split with per-km pace', () {
    final a = ActivityDetail.fromRunRecord(
      _run(km: 0.7, seconds: 210),
      runnerName: 'x',
    );
    expect(a.splits, hasLength(1));
    expect(a.splits.single.isPartial, isTrue);
    expect(a.splits.single.distanceKm, closeTo(0.7, 1e-9));
    expect(a.splits.single.paceSeconds, 300);
  });

  test('a trailing partial km follows the full splits (stored as deltas)', () {
    final a = ActivityDetail.fromRunRecord(
      _run(
        km: 2.4,
        seconds: 720,
        splits: const [
          {'km': 1, 'seconds': 310},
          {'km': 2, 'seconds': 290},
        ],
      ),
      runnerName: 'x',
    );
    expect(a.splits, hasLength(3));
    expect(a.splits[0].paceSeconds, 310);
    expect(a.splits[1].paceSeconds, 290);
    expect(a.splits[2].isPartial, isTrue);
    expect(a.splits[2].km, 3);
    // (720 - 600) s over 0.4 km = 300 s/km
    expect(a.splits[2].paceSeconds, 300);
  });

  test('runs under 0.1 km get no splits', () {
    final a = ActivityDetail.fromRunRecord(
      _run(km: 0.05, seconds: 20),
      runnerName: 'x',
    );
    expect(a.splits, isEmpty);
  });

  test('flat altitude (0 m gain) still shows the elevation chart', () {
    final a = ActivityDetail.fromRunRecord(
      _run(
        km: 0.7,
        seconds: 210,
        samples: const [
          {'d': 0.0, 'alt': 100.0},
          {'d': 300.0, 'alt': 100.0},
          {'d': 700.0, 'alt': 100.0},
        ],
      ),
      runnerName: 'x',
    );
    expect(a.elevationGainM, isNull);
    expect(a.hasElevationData, isTrue);
  });

  test('no altitude samples hides the elevation chart', () {
    final a = ActivityDetail.fromRunRecord(
      _run(km: 0.7, seconds: 210),
      runnerName: 'x',
    );
    expect(a.hasElevationData, isFalse);
  });
}
