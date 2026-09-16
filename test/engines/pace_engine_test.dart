/// PaceEngine.addPoint — the rolling-window pace calculator behind the live
/// run HUD. A duplicate or out-of-order GPS timestamp (clock stutter, or a
/// stale fix replayed after a pause/resume) has no valid time delta to
/// measure speed against; accepting it into the ring buffer used to feed a
/// zero/negative segment straight into the rolling window, and that garbage
/// pace is exactly what could later land in a saved split's duration.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/pace_engine.dart';

GpsPoint _point({
  required double lat,
  required double lng,
  required DateTime timestamp,
  double speed = 3.0,
  double accuracy = 5.0,
}) => GpsPoint(
  lat: lat,
  lng: lng,
  accuracy: accuracy,
  speed: speed,
  timestamp: timestamp,
);

void main() {
  test(
    'a duplicate-timestamp point is dropped instead of corrupting the '
    'rolling window with a zero-time segment',
    () {
      final engine = PaceEngine();
      final t0 = DateTime(2026, 9, 16, 6, 0, 0);

      // Feed a steady ~5:00/km pace (≈3.33 m/s) for a few seconds so the
      // rolling window has real data to protect.
      var lat = 12.9716;
      const stepM = 3.33;
      const metersPerDegreeLat = 111320.0;
      for (var i = 1; i <= 10; i++) {
        lat += stepM / metersPerDegreeLat;
        engine.addPoint(
          _point(lat: lat, lng: 77.5946, timestamp: t0.add(Duration(seconds: i))),
          stepM * i,
          i,
        );
      }
      final before = engine.smoothedPace;
      expect(before, greaterThan(0));

      // A duplicate fix arrives at the exact same timestamp as the last
      // accepted point, several metres further along (GPS stutter).
      final duplicateTimestamp = t0.add(const Duration(seconds: 10));
      final snapshot = engine.addPoint(
        _point(lat: lat + 0.001, lng: 77.5946, timestamp: duplicateTimestamp),
        stepM * 10 + 50,
        10,
      );

      // The point was dropped, not accepted — the smoothed pace is exactly
      // what it was before, not corrupted towards zero/garbage.
      expect(engine.smoothedPace, before);
      expect(snapshot.smoothedPaceSecondsPerKm, before);
    },
  );

  test(
    'an out-of-order point (timestamp earlier than the last accepted one) '
    'is also dropped',
    () {
      final engine = PaceEngine();
      final t0 = DateTime(2026, 9, 16, 6, 0, 0);

      engine.addPoint(
        _point(lat: 12.9716, lng: 77.5946, timestamp: t0),
        0,
        0,
      );
      engine.addPoint(
        _point(lat: 12.9720, lng: 77.5946, timestamp: t0.add(const Duration(seconds: 5))),
        44,
        5,
      );
      final before = engine.smoothedPace;

      // A stale/replayed fix with an earlier timestamp than what's already
      // been accepted.
      engine.addPoint(
        _point(lat: 12.9725, lng: 77.5946, timestamp: t0.add(const Duration(seconds: 3))),
        90,
        5,
      );

      expect(engine.smoothedPace, before);
    },
  );

  test('a normal point with a genuine positive time delta is still accepted', () {
    final engine = PaceEngine();
    final t0 = DateTime(2026, 9, 16, 6, 0, 0);

    var lat = 12.9716;
    const stepM = 3.33; // ≈5:00/km
    const metersPerDegreeLat = 111320.0;
    PaceSnapshot? last;
    for (var i = 1; i <= 15; i++) {
      lat += stepM / metersPerDegreeLat;
      last = engine.addPoint(
        _point(lat: lat, lng: 77.5946, timestamp: t0.add(Duration(seconds: i))),
        stepM * i,
        i,
      );
    }

    expect(last!.smoothedPaceSecondsPerKm, greaterThan(0));
    expect(last.smoothedPaceSecondsPerKm, closeTo(300, 30));
  });
}
