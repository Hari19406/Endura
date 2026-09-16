/// ActivityDetail.splitsForDisplay — re-buckets km splits into miles from the
/// raw telemetry trace (not just a relabelled pace), with a documented
/// pace-only fallback when there's no trace to re-bucket from.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';

ActivityDetail _base({
  required List<KmSplit> splits,
  required List<TelemetrySample> telemetrySeries,
  Duration movingTime = const Duration(minutes: 10),
  String avgPace = '5:00',
}) => ActivityDetail(
  runnerName: 'Runner',
  timestamp: DateTime(2026, 9, 12),
  source: 'Endura Tracker',
  location: '',
  title: 'Run',
  distanceKm: telemetrySeries.isEmpty
      ? splits.length.toDouble()
      : telemetrySeries.last.distanceKm,
  avgPace: avgPace,
  movingTime: movingTime,
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

  group('healing invalid split durations', () {
    test(
      'a single zero-duration split (e.g. a duplicate GPS timestamp at a km '
      'boundary) is healed from the run\'s remaining moving time, never '
      'rendered as an impossible 0:00',
      () {
        // 3 splits, 10-minute (600s) total moving time. Two good splits sum
        // to 500s, leaving 100s for the one bad split to inherit.
        final a = _base(
          splits: const [
            KmSplit(km: 1, paceSeconds: 250),
            KmSplit(km: 2, paceSeconds: 0), // duplicate-timestamp artifact
            KmSplit(km: 3, paceSeconds: 250),
          ],
          telemetrySeries: const [],
          movingTime: const Duration(seconds: 600),
        );

        final healed = a.splitsForDisplay(useMiles: false);

        expect(healed, hasLength(3));
        expect(healed[0].paceSeconds, 250); // untouched
        expect(healed[1].paceSeconds, 100); // 600 - (250+250)
        expect(healed[2].paceSeconds, 250); // untouched
        expect(healed[1].paceLabel, isNot('0:00'));
      },
    );

    test('a negative split duration is healed the same way as a zero one', () {
      final a = _base(
        splits: const [
          KmSplit(km: 1, paceSeconds: 280),
          KmSplit(km: 2, paceSeconds: -15), // out-of-order km crossing
        ],
        telemetrySeries: const [],
        movingTime: const Duration(seconds: 600),
      );

      final healed = a.splitsForDisplay(useMiles: false);

      expect(healed[1].paceSeconds, 320); // 600 - 280
      expect(healed[1].paceSeconds, greaterThan(0));
    });

    test(
      'when every split is invalid, falls back to the run\'s own average '
      'pace rather than rendering all zeroes',
      () {
        final a = _base(
          splits: const [
            KmSplit(km: 1, paceSeconds: 0),
            KmSplit(km: 2, paceSeconds: 0),
          ],
          telemetrySeries: const [],
          movingTime: const Duration(seconds: 600),
          avgPace: '5:00', // 300 s/km
        );

        final healed = a.splitsForDisplay(useMiles: false);

        expect(healed[0].paceSeconds, 300);
        expect(healed[1].paceSeconds, 300);
      },
    );

    test(
      'leaves a 0 in place only when total moving time genuinely was 0',
      () {
        final a = _base(
          splits: const [KmSplit(km: 1, paceSeconds: 0)],
          telemetrySeries: const [],
          movingTime: Duration.zero,
        );

        final healed = a.splitsForDisplay(useMiles: false);

        expect(healed[0].paceSeconds, 0);
      },
    );

    test('healing also applies to the miles-mode fallback conversion path', () {
      final a = _base(
        splits: const [
          KmSplit(km: 1, paceSeconds: 300),
          KmSplit(km: 2, paceSeconds: 0),
        ],
        telemetrySeries: const [], // forces the pace-only fallback path
        movingTime: const Duration(seconds: 600),
      );

      final miles = a.splitsForDisplay(useMiles: true);

      // Healed km duration (300) is then converted to miles, same as any
      // other stored split — never a 0:00 mile split.
      expect(miles[1].paceSeconds, greaterThan(0));
      expect(miles[1].paceLabel, isNot('0:00'));
    });

    test('fastestSplitSeconds/slowestSplitSeconds ignore sub-60s garbage', () {
      final a = _base(
        splits: const [
          KmSplit(km: 1, paceSeconds: 5), // impossible sprint artifact
          KmSplit(km: 2, paceSeconds: 300),
          KmSplit(km: 3, paceSeconds: 320),
        ],
        telemetrySeries: const [],
      );

      expect(a.fastestSplitSeconds, 300);
      expect(a.slowestSplitSeconds, 320);
    });
  });
}
