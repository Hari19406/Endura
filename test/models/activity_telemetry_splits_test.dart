/// ActivityDetail.splitsForDisplay — re-buckets km splits into miles from the
/// raw telemetry trace (not just a relabelled pace), with a documented
/// pace-only fallback when there's no trace to re-bucket from.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';

ActivityDetail _base({
  required List<KmSplit> splits,
  required List<TelemetrySample> telemetrySeries,
}) => ActivityDetail(
  runnerName: 'Runner',
  timestamp: DateTime(2026, 9, 12),
  source: 'Endura Tracker',
  location: '',
  title: 'Run',
  distanceKm: telemetrySeries.isEmpty
      ? splits.length.toDouble()
      : telemetrySeries.last.distanceKm,
  avgPace: '5:00',
  movingTime: const Duration(minutes: 10),
  splits: splits,
  telemetrySeries: telemetrySeries,
  hrZones: const [],
);

void main() {
  test('km mode returns the stored splits unchanged', () {
    final a = _base(
      splits: const [KmSplit(km: 1, paceSeconds: 300)],
      telemetrySeries: const [],
    );
    final result = a.splitsForDisplay(useMiles: false);
    expect(identical(result, a.splits), isTrue);
  });

  test('re-buckets a steady-pace run into 1-mile segments from the trace', () {
    // 3.2 km at a steady 300 s/km — long enough for 2 full miles + a remainder.
    final samples = [
      for (var i = 0; i <= 32; i++)
        TelemetrySample(distanceKm: i * 0.1, paceSeconds: 300),
    ];
    final a = _base(
      splits: const [
        KmSplit(km: 1, paceSeconds: 300),
        KmSplit(km: 2, paceSeconds: 300),
        KmSplit(km: 3, paceSeconds: 300),
      ],
      telemetrySeries: samples,
    );

    final miles = a.splitsForDisplay(useMiles: true);

    // ceil(3.2 / 1.609344) = 2 buckets.
    expect(miles, hasLength(2));
    expect(miles[0].km, 1);
    // A full mile at a steady 300 s/km ≈ 483 s/mi (8:03).
    expect(miles[0].paceSeconds, closeTo(483, 1));
    expect(miles[0].paceLabel, '8:03');
    // The trailing partial bucket is shorter, so its "time" is
    // proportionally smaller — same convention the km bucketer uses for a
    // partial final km.
    expect(miles[1].paceSeconds, lessThan(miles[0].paceSeconds));
  });

  test(
    'falls back to the stored km splits (pace converted in place) when '
    'there is no telemetry trace to re-bucket from',
    () {
      final a = _base(
        splits: const [
          KmSplit(km: 1, paceSeconds: 300, avgHr: 150),
          KmSplit(km: 2, paceSeconds: 310),
        ],
        telemetrySeries: const [],
      );

      final miles = a.splitsForDisplay(useMiles: true);

      expect(miles, hasLength(2));
      // The km index is preserved (still km-shaped boundaries) …
      expect(miles.map((s) => s.km), [1, 2]);
      // … but every pace value is already expressed "as if per mile", so the
      // "always in the requested unit" contract holds even in the fallback.
      expect(miles[0].paceSeconds, (300 * 1.609344).round());
      expect(miles[1].paceSeconds, (310 * 1.609344).round());
      // Non-pace fields pass through untouched.
      expect(miles[0].avgHr, 150);
    },
  );

  test('an empty telemetry series with no total distance falls back safely', () {
    final a = _base(
      splits: const [KmSplit(km: 1, paceSeconds: 300)],
      telemetrySeries: const [TelemetrySample(distanceKm: 0, paceSeconds: 300)],
    );
    final miles = a.splitsForDisplay(useMiles: true);
    // totalKm == 0 → nothing to re-bucket → falls back to converted km splits.
    expect(miles, hasLength(1));
    expect(miles.first.paceSeconds, (300 * 1.609344).round());
  });
}
