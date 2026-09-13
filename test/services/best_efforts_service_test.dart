import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_service.dart';

void main() {
  group('BestEffortsService.fastestSegmentSeconds', () {
    test('constant pace: fastest 1km matches the steady per-km split', () {
      final points = [
        const TelemetryPoint(distanceMeters: 0, elapsedSeconds: 0),
        const TelemetryPoint(distanceMeters: 500, elapsedSeconds: 150),
        const TelemetryPoint(distanceMeters: 1000, elapsedSeconds: 300),
        const TelemetryPoint(distanceMeters: 1500, elapsedSeconds: 450),
        const TelemetryPoint(distanceMeters: 2000, elapsedSeconds: 600),
        const TelemetryPoint(distanceMeters: 2500, elapsedSeconds: 750),
        const TelemetryPoint(distanceMeters: 3000, elapsedSeconds: 900),
        const TelemetryPoint(distanceMeters: 3500, elapsedSeconds: 1050),
        const TelemetryPoint(distanceMeters: 4000, elapsedSeconds: 1200),
        const TelemetryPoint(distanceMeters: 4500, elapsedSeconds: 1350),
        const TelemetryPoint(distanceMeters: 5000, elapsedSeconds: 1500),
      ];

      expect(
        BestEffortsService.fastestSegmentSeconds(points, 1000),
        300,
      );
      expect(
        BestEffortsService.fastestSegmentSeconds(points, 5000),
        1500,
      );
    });

    test('picks the fastest window, not the whole-run average', () {
      // First 2km slow (500s/km), last 2km fast (300s/km).
      final points = [
        const TelemetryPoint(distanceMeters: 0, elapsedSeconds: 0),
        const TelemetryPoint(distanceMeters: 1000, elapsedSeconds: 500),
        const TelemetryPoint(distanceMeters: 2000, elapsedSeconds: 1000),
        const TelemetryPoint(distanceMeters: 3000, elapsedSeconds: 1300),
        const TelemetryPoint(distanceMeters: 4000, elapsedSeconds: 1600),
      ];

      // Whole-run average pace would be 1600/4 = 400s/km, but the fastest
      // continuous 1km segment (km 2-3 or km 3-4) ran at 300s.
      expect(
        BestEffortsService.fastestSegmentSeconds(points, 1000),
        300,
      );
    });

    test('interpolates between samples that straddle the target boundary', () {
      final points = [
        const TelemetryPoint(distanceMeters: 0, elapsedSeconds: 0),
        const TelemetryPoint(distanceMeters: 300, elapsedSeconds: 90),
        const TelemetryPoint(distanceMeters: 700, elapsedSeconds: 180),
        const TelemetryPoint(distanceMeters: 1200, elapsedSeconds: 260),
      ];

      // Fastest 500m: from the interpolated point at 700m (t=180) back to
      // the sample at 1200m (t=260) is NOT it — the fastest window is the
      // one ending at 1200m, starting at the interpolated 700m mark
      // (exactly a sample here), giving 260 - 180 = 80s.
      expect(
        BestEffortsService.fastestSegmentSeconds(points, 500),
        80,
      );
    });

    test('returns null when the run never reaches the target distance', () {
      final points = [
        const TelemetryPoint(distanceMeters: 0, elapsedSeconds: 0),
        const TelemetryPoint(distanceMeters: 800, elapsedSeconds: 240),
      ];

      expect(BestEffortsService.fastestSegmentSeconds(points, 1000), isNull);
    });

    test('returns null for fewer than 2 points', () {
      expect(BestEffortsService.fastestSegmentSeconds(const [], 1000), isNull);
      expect(
        BestEffortsService.fastestSegmentSeconds(
          const [TelemetryPoint(distanceMeters: 0, elapsedSeconds: 0)],
          1000,
        ),
        isNull,
      );
    });
  });

  group('BestEffortsService.extract', () {
    test('only returns categories the run actually reached', () {
      // A 3km run at a constant 300s/km pace.
      final points = [
        const TelemetryPoint(distanceMeters: 0, elapsedSeconds: 0),
        const TelemetryPoint(distanceMeters: 1000, elapsedSeconds: 300),
        const TelemetryPoint(distanceMeters: 2000, elapsedSeconds: 600),
        const TelemetryPoint(distanceMeters: 3000, elapsedSeconds: 900),
      ];

      final results = BestEffortsService.extract(points);
      final categories = results.map((r) => r.category).toSet();

      expect(categories, containsAll([
        DistanceCategory.m400,
        DistanceCategory.k1,
        DistanceCategory.k3,
      ]));
      expect(categories, isNot(contains(DistanceCategory.k5)));
      expect(categories, isNot(contains(DistanceCategory.marathon)));

      final k1 = results.firstWhere((r) => r.category == DistanceCategory.k1);
      expect(k1.elapsedSeconds, 300);
    });
  });

  group('BestEffortsService.pointsFromTrackSamples', () {
    test('prepends an implicit (0, 0) start and decodes t/d fields', () {
      final samples = [
        {'t': 15, 'd': 60.0, 'pace': 250.0},
        {'t': 30, 'd': 130.0},
      ];

      final points = BestEffortsService.pointsFromTrackSamples(samples);

      expect(points.length, 3);
      expect(points[0].distanceMeters, 0);
      expect(points[0].elapsedSeconds, 0);
      expect(points[1].distanceMeters, 60.0);
      expect(points[1].elapsedSeconds, 15);
      expect(points[2].distanceMeters, 130.0);
      expect(points[2].elapsedSeconds, 30);
    });

    test('skips malformed samples missing t or d', () {
      final samples = [
        {'t': 15},
        {'d': 60.0},
        {'t': 30, 'd': 100.0},
      ];

      final points = BestEffortsService.pointsFromTrackSamples(samples);

      expect(points.length, 2); // implicit (0,0) + the one valid sample
      expect(points[1].distanceMeters, 100.0);
      expect(points[1].elapsedSeconds, 30);
    });
  });

  group('BestEffortsService.formatElapsed', () {
    test('formats sub-hour durations as m:ss', () {
      expect(BestEffortsService.formatElapsed(90), '1:30');
      expect(BestEffortsService.formatElapsed(59), '0:59');
    });

    test('formats hour-plus durations as h:mm:ss', () {
      expect(BestEffortsService.formatElapsed(3661), '1:01:01');
    });
  });

  group('DistanceCategory', () {
    test('fromKey round-trips through .name', () {
      for (final category in DistanceCategory.values) {
        expect(DistanceCategory.fromKey(category.name), category);
      }
      expect(DistanceCategory.fromKey('not_a_category'), isNull);
    });
  });
}
