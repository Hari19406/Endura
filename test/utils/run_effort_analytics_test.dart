import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/gap_calculator.dart';
import 'package:run_app/utils/run_effort_analytics.dart';

/// A run sampled every 50 m / 15 s (5:00/km). [alt] maps distance in metres
/// to altitude; [hr] maps the sample index to bpm.
List<EffortInput> run({
  int count = 41,
  double stepM = 50,
  double stepS = 15,
  double? Function(double dM)? alt,
  int? Function(int i)? hr,
  double? Function(int i)? pace,
  bool withTime = true,
}) => [
  for (var i = 0; i < count; i++)
    EffortInput(
      timeSeconds: withTime ? i * stepS : null,
      distanceKm: i * stepM / 1000,
      paceSecPerKm: pace != null ? pace(i) : stepS / stepM * 1000,
      hrBpm: hr?.call(i),
      elevationM: alt?.call(i * stepM),
    ),
];

void main() {
  group('HR validity', () {
    test('30..230 bpm is valid; outside it, null or missing is not', () {
      final s = RunEffortSeries.build(
        run(count: 6, hr: (i) => [29, 30, 150, 230, 231, null][i]),
      );
      expect(s.points.map((p) => p.hrBpm), [null, 30, 150, 230, null, null]);
    });

    test('a spike is dropped from the series, neighbours untouched', () {
      final s = RunEffortSeries.build(
        run(count: 5, hr: (i) => i == 2 ? 255 : 150),
      );
      expect(s.points.map((p) => p.hrBpm), [150, 150, null, 150, 150]);
      expect(s.rangeOf(EffortChannel.hr), (150.0, 150.0));
    });

    test('all-invalid HR means the channel is unavailable', () {
      final s = RunEffortSeries.build(run(hr: (_) => 20));
      expect(s.hasHr, isFalse);
      expect(s.availableChannels.contains(EffortChannel.hr), isFalse);
    });
  });

  group('pace validity', () {
    test('120..1800 s/km is valid; others are nulled', () {
      const paces = [119.9, 120.0, 300.0, 1800.0, 1800.1, 0.0, -5.0];
      final s = RunEffortSeries.build(
        run(count: paces.length, pace: (i) => paces[i]),
      );
      expect(s.points.map((p) => p.paceSecPerKm), [
        null,
        120.0,
        300.0,
        1800.0,
        null,
        null,
        null,
      ]);
    });

    test('NaN, infinity and null pace are nulled', () {
      final s = RunEffortSeries.build(
        run(
          count: 4,
          pace: (i) => [double.nan, double.infinity, null, 300.0][i],
        ),
      );
      expect(s.points.map((p) => p.paceSecPerKm), [null, null, null, 300.0]);
    });

    test('an invalid pace inside a short stretch does not split the line', () {
      final s = RunEffortSeries.build(
        run(count: 7, pace: (i) => i == 3 ? 0.0 : 300.0),
      );
      expect(s.runsFor(EffortChannel.pace), hasLength(1));
      expect(s.runsFor(EffortChannel.pace).single, hasLength(6));
    });
  });

  group('elevation', () {
    test('missing elevation: channel absent, no gradient', () {
      final s = RunEffortSeries.build(run());
      expect(s.hasElevation, isFalse);
      expect(s.points.every((p) => p.elevationM == null), isTrue);
      expect(s.points.every((p) => p.gradient == null), isTrue);
    });

    test('exactly 0.0 elevation is treated as missing', () {
      expect(RunEffortSeries.build(run(alt: (_) => 0.0)).hasElevation, isFalse);
    });

    test('0.0 readings among real ones do not create cliffs', () {
      final s = RunEffortSeries.build(
        run(alt: (d) => (d / 50).round() % 4 == 1 ? 0.0 : 100.0),
      );
      for (final p in s.points) {
        expect(p.elevationM, closeTo(100, 1));
        expect(p.gradient!.abs(), lessThan(0.01));
      }
    });

    test('elevation outside the span of real readings is null', () {
      final s = RunEffortSeries.build(
        run(alt: (d) => d < 500 ? null : 100.0 + (d - 500) * 0.01),
      );
      // First 10 samples (0..450 m) have no altitude at all.
      expect(s.points.take(10).every((p) => p.elevationM == null), isTrue);
      expect(s.points.last.elevationM, isNotNull);
    });

    test('an altitude spike is rejected', () {
      final s = RunEffortSeries.build(run(alt: (d) => d == 1000 ? 180 : 100));
      expect(s.rangeOf(EffortChannel.elevation)!.$2, lessThan(110));
    });

    test('cleanElevation: false keeps values exactly as given (Feed)', () {
      final s = RunEffortSeries.build(
        run(count: 3, alt: (d) => d == 0 ? 0.0 : 5.0),
        cleanElevation: false,
      );
      expect(s.points.map((p) => p.elevationM), [0.0, 5.0, 5.0]);
      expect(s.points.every((p) => p.gradient == null), isTrue);
    });
  });

  group('flat vs hilly runs', () {
    test('a flat run has ~0 gradient everywhere', () {
      final s = RunEffortSeries.build(run(alt: (_) => 100));
      expect(s.hasElevation, isTrue);
      for (final p in s.points) {
        expect(p.gradient, closeTo(0, 1e-9));
      }
      final r = s.rangeOf(EffortChannel.elevation)!;
      expect(r.$2 - r.$1, closeTo(0, 1e-9));
    });

    test(
      'a hilly run: positive gradient on the climb, negative on descent',
      () {
        // 1 km up at 5%, 1 km down at 5%.
        double alt(double d) =>
            d <= 1000 ? 100 + d * 0.05 : 150 - (d - 1000) * 0.05;
        final s = RunEffortSeries.build(run(alt: alt));
        final climb = s.points.where(
          (p) => p.distanceKm > 0.3 && p.distanceKm < 0.7,
        );
        final descent = s.points.where(
          (p) => p.distanceKm > 1.3 && p.distanceKm < 1.7,
        );
        for (final p in climb) {
          expect(p.gradient, closeTo(0.05, 0.01));
        }
        for (final p in descent) {
          expect(p.gradient, closeTo(-0.05, 0.01));
        }
        final r = s.rangeOf(EffortChannel.elevation)!;
        expect(r.$2 - r.$1, greaterThan(35));
      },
    );

    test('gradient comes from the GAP segments when supplied', () {
      final inputs = run(alt: (d) => 100 + d * 0.05);
      final gap = GapCalculator.analyze([
        for (final i in inputs)
          GapSample(
            distanceM: i.distanceKm * 1000,
            timeSeconds: i.timeSeconds,
            altitudeM: i.elevationM,
          ),
      ])!;
      final s = RunEffortSeries.build(inputs, gap: gap);
      final mid = s.points[20];
      final seg = gap.segments.firstWhere(
        (g) =>
            mid.distanceKm * 1000 >= g.startM &&
            mid.distanceKm * 1000 <= g.endM,
      );
      expect(mid.gradient, seg.gradient);
    });

    test('a hilly run charts a sensible elevation range', () {
      final s = RunEffortSeries.build(
        run(alt: (d) => 100 + 20 * math.sin(d / 300)),
      );
      final r = s.rangeOf(EffortChannel.elevation)!;
      expect(r.$1, greaterThan(75));
      expect(r.$2, lessThan(125));
    });
  });

  group('GPS / time gaps', () {
    List<EffortInput> withGap() => [
      ...run(count: 11), // 0..500 m, t 0..150
      // 3 minutes pass; only 50 m covered
      const EffortInput(timeSeconds: 330, distanceKm: 0.55, paceSecPerKm: 300),
      for (var i = 1; i <= 10; i++)
        EffortInput(
          timeSeconds: 330.0 + i * 15,
          distanceKm: 0.55 + i * 0.05,
          paceSecPerKm: 300,
        ),
    ];

    test('a >60 s gap is flagged on the point after it', () {
      final s = RunEffortSeries.build(withGap());
      final flagged = s.points.where((p) => p.breakBefore).toList();
      expect(flagged, hasLength(1));
      expect(flagged.single.timeSeconds, 330);
    });

    test('exactly 60 s is not a gap; just over is', () {
      final ok = RunEffortSeries.build([
        const EffortInput(timeSeconds: 0, distanceKm: 0, paceSecPerKm: 300),
        const EffortInput(timeSeconds: 60, distanceKm: 0.1, paceSecPerKm: 300),
      ]);
      expect(ok.points.last.breakBefore, isFalse);
      final gap = RunEffortSeries.build([
        const EffortInput(timeSeconds: 0, distanceKm: 0, paceSecPerKm: 300),
        const EffortInput(timeSeconds: 61, distanceKm: 0.1, paceSecPerKm: 300),
      ]);
      expect(gap.points.last.breakBefore, isTrue);
    });

    test('lines are split into separate runs at the gap, per channel', () {
      final s = RunEffortSeries.build(withGap());
      final runs = s.runsFor(EffortChannel.pace);
      expect(runs, hasLength(2));
      expect(runs[0].last.timeSeconds, 150);
      expect(runs[1].first.timeSeconds, 330);
    });

    test('a channel missing for minutes splits only that channel', () {
      // HR present for the first 2 min, absent for 4 min, then back.
      final s = RunEffortSeries.build(
        run(count: 41, hr: (i) => (i < 8 || i > 24) ? 150 : null),
      );
      expect(s.runsFor(EffortChannel.hr), hasLength(2));
      expect(s.runsFor(EffortChannel.pace), hasLength(1));
    });

    test('a short HR dropout (<= 60 s) is bridged, not split', () {
      final s = RunEffortSeries.build(
        run(count: 20, hr: (i) => (i == 5 || i == 6) ? null : 150),
      );
      expect(s.runsFor(EffortChannel.hr), hasLength(1));
    });

    test('a gap does not flag a break inside the clean stretches', () {
      final s = RunEffortSeries.build(withGap());
      expect(s.points.where((p) => p.breakBefore), hasLength(1));
    });
  });

  group('missing timestamps (old runs)', () {
    test('no clock: no gaps detected, one run, no combined chart', () {
      final s = RunEffortSeries.build(
        run(withTime: false, hr: (_) => 150, alt: (_) => 100),
      );
      expect(s.hasTimestamps, isFalse);
      expect(s.points.every((p) => !p.breakBefore), isTrue);
      expect(s.runsFor(EffortChannel.pace), hasLength(1));
      expect(s.channelCount, 3);
      expect(s.supportsCombinedChart, isFalse);
    });

    test('a single timestamp is not a clock', () {
      final s = RunEffortSeries.build([
        const EffortInput(timeSeconds: 0, distanceKm: 0, paceSecPerKm: 300),
        const EffortInput(distanceKm: 0.05, paceSecPerKm: 300),
      ]);
      expect(s.hasTimestamps, isFalse);
    });
  });

  group('channel availability', () {
    test('available channels are listed pace, hr, elevation', () {
      final s = RunEffortSeries.build(
        run(hr: (_) => 150, alt: (d) => 100 + d * 0.01),
      );
      expect(s.availableChannels, [
        EffortChannel.pace,
        EffortChannel.hr,
        EffortChannel.elevation,
      ]);
      expect(s.channelCount, 3);
      expect(s.supportsCombinedChart, isTrue);
    });

    test('one valid point is not enough for a channel', () {
      final s = RunEffortSeries.build(run(hr: (i) => i == 3 ? 150 : null));
      expect(s.hasHr, isFalse);
      expect(s.validCount(EffortChannel.hr), 1);
    });

    test('the combined chart needs two channels and a clock', () {
      // pace only
      expect(RunEffortSeries.build(run()).supportsCombinedChart, isFalse);
      // pace + HR
      expect(
        RunEffortSeries.build(run(hr: (_) => 150)).supportsCombinedChart,
        isTrue,
      );
      // HR only (no valid pace)
      expect(
        RunEffortSeries.build(
          run(hr: (_) => 150, pace: (_) => null),
        ).supportsCombinedChart,
        isFalse,
      );
    });

    test('empty and non-finite input is harmless', () {
      expect(RunEffortSeries.build(const []).points, isEmpty);
      expect(RunEffortSeries.build(const []).supportsCombinedChart, isFalse);
      final s = RunEffortSeries.build(const [
        EffortInput(distanceKm: double.nan, paceSecPerKm: 300),
        EffortInput(distanceKm: 0, paceSecPerKm: 300),
      ]);
      expect(s.points, hasLength(1));
    });
  });

  group('helpers', () {
    test('rangeOf and nearest', () {
      final s = RunEffortSeries.build(run(hr: (i) => 140 + i));
      expect(s.rangeOf(EffortChannel.hr), (140.0, 180.0));
      expect(s.rangeOf(EffortChannel.elevation), isNull);
      expect(s.nearest(1.0)!.distanceKm, closeTo(1.0, 1e-9));
      expect(s.nearest(1.02)!.distanceKm, closeTo(1.0, 1e-9));
      expect(s.nearest(1.04)!.distanceKm, closeTo(1.05, 1e-9));
      expect(RunEffortSeries.empty.nearest(1), isNull);
    });
  });
}
