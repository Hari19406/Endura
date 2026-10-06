import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/gap_calculator.dart';

/// A run sampled every [stepM] metres / [stepS] seconds (default 50 m per 15 s
/// = 5:00/km). [alt] maps cumulative distance in metres to altitude.
List<GapSample> synth({
  int count = 41, // 2 km
  double stepM = 50,
  double stepS = 15,
  double Function(double d)? alt,
  double? Function(int i)? paceField,
  bool withTime = true,
}) => [
  for (var i = 0; i < count; i++)
    GapSample(
      distanceM: i * stepM,
      timeSeconds: withTime ? i * stepS : null,
      altitudeM: alt?.call(i * stepM),
      paceSecPerKm: paceField != null ? paceField(i) : stepS / stepM * 1000,
    ),
];

double flatAlt(double d) => 100;

void main() {
  group('formula direction', () {
    test('uphill GAP is faster than actual pace', () {
      final gap = GapCalculator.gradeAdjustedPaceSecPerKm(360, 0.05);
      expect(gap, lessThan(360));
      expect(gap, closeTo(276.7, 1.0)); // 360 x flatCost / gradedCost
    });

    test('flat GAP equals actual pace', () {
      expect(
        GapCalculator.gradeAdjustedPaceSecPerKm(360, 0),
        closeTo(360, 1e-9),
      );
      expect(GapCalculator.flatEquivalentFactor(0), closeTo(1, 1e-12));
    });

    test('downhill GAP is slower than actual pace', () {
      final gap = GapCalculator.gradeAdjustedPaceSecPerKm(360, -0.05);
      expect(gap, greaterThan(360));
      expect(gap, closeTo(471.8, 1.0));
    });

    test('steeper uphill is faster still; steeper downhill slower still', () {
      double g(double grade) =>
          GapCalculator.gradeAdjustedPaceSecPerKm(360, grade);
      expect(g(0.10), lessThan(g(0.05)));
      expect(g(-0.10), greaterThan(g(-0.05)));
    });

    test('factor is the flat/graded cost ratio: below 1 up, above 1 down', () {
      expect(GapCalculator.flatEquivalentFactor(0.08), lessThan(1));
      expect(GapCalculator.flatEquivalentFactor(-0.08), greaterThan(1));
    });
  });

  group('run-level GAP', () {
    test('a flat run: GAP equals the true average segment pace', () {
      final a = GapCalculator.analyze(synth(alt: flatAlt))!;
      expect(a.avgRawPaceSecPerKm, closeTo(300, 1e-6));
      expect(a.avgGapSecPerKm, closeTo(300, 1e-6));
      expect(a.deltaSecPerKm, closeTo(0, 1e-6));
    });

    test('a steady 5% climb at constant pace has GAP faster than actual', () {
      final a = GapCalculator.analyze(synth(alt: (d) => 100 + d * 0.05))!;
      expect(a.avgGapSecPerKm, lessThan(a.avgRawPaceSecPerKm - 40));
      // Away from the ends every segment measures ~5%.
      final mid = a.segments.where((s) => s.startM > 300 && s.endM < 1700);
      for (final s in mid) {
        expect(s.gradient, closeTo(0.05, 0.005));
      }
    });

    test('a steady 5% descent at constant pace has GAP slower than actual', () {
      final a = GapCalculator.analyze(synth(alt: (d) => 300 - d * 0.05))!;
      expect(a.avgGapSecPerKm, greaterThan(a.avgRawPaceSecPerKm + 40));
    });

    test(
      'an out-and-back at the SAME pace has GAP slightly slower, not wild',
      () {
        // 1 km up at 5%, 1 km down at 5%, identical 5:00/km both ways.
        double alt(double d) =>
            d <= 1000 ? 100 + d * 0.05 : 150 - (d - 1000) * 0.05;
        final a = GapCalculator.analyze(synth(alt: alt))!;
        // Running the downhill as hard as the uphill is not equal effort, and
        // the cost curve is convex, so GAP lands above (slower than) raw — but
        // only modestly after smoothing at the turnaround.
        expect(a.avgGapSecPerKm, greaterThan(a.avgRawPaceSecPerKm));
        expect(a.avgGapSecPerKm, lessThan(a.avgRawPaceSecPerKm * 1.15));
      },
    );

    test('an out-and-back at EQUAL EFFORT has GAP ~ flat pace', () {
      // Pace scaled by the cost ratio on each leg (slower up, faster down):
      // the flat-equivalent pace is 5:00/km everywhere.
      const up = 0.05;
      final upF = 1 / GapCalculator.flatEquivalentFactor(up);
      final downF = 1 / GapCalculator.flatEquivalentFactor(-up);
      final samples = <GapSample>[];
      var d = 0.0, t = 0.0;
      for (var i = 0; i <= 40; i++) {
        final goingUp = d < 1000;
        samples.add(
          GapSample(
            distanceM: d,
            timeSeconds: t,
            altitudeM: goingUp ? 100 + d * up : 150 - (d - 1000) * up,
          ),
        );
        t += 15 * (goingUp ? upF : downF);
        d += 50;
      }
      final a = GapCalculator.analyze(samples)!;
      expect((a.avgGapSecPerKm - 300).abs(), lessThan(12));
    });

    test(
      'the legacy averageGapSecPerKm entry point uses the same pipeline',
      () {
        final maps = [
          for (var i = 0; i < 41; i++)
            {
              'd': i * 50.0,
              't': i * 15.0,
              'alt': 100.0 + i * 2.5,
              'pace': 300.0,
            },
        ];
        final fromMaps = GapCalculator.averageGapSecPerKm(maps)!;
        final direct = GapCalculator.analyze(
          synth(alt: (d) => 100 + d * 0.05),
        )!.avgGapSecPerKm;
        expect(fromMaps, closeTo(direct, 1e-9));
        expect(fromMaps, lessThan(300)); // uphill => faster than actual
      },
    );
  });

  group('elevation cleaning', () {
    test('small flat-run altitude noise does not change GAP much', () {
      final rng = math.Random(42);
      final noise = [
        for (var i = 0; i < 41; i++) (rng.nextDouble() - 0.5) * 6,
      ]; // +-3 m
      final a = GapCalculator.analyze(
        synth(alt: (d) => 100 + noise[(d / 50).round()]),
      )!;
      expect((a.avgGapSecPerKm - a.avgRawPaceSecPerKm).abs(), lessThan(6));
      for (final s in a.segments) {
        expect(s.gradient.abs(), lessThan(0.06));
      }
    });

    test('a large altitude spike is rejected', () {
      final spiky = GapCalculator.analyze(
        synth(alt: (d) => d == 1000 ? 180 : 100),
      )!;
      expect(spiky.avgGapSecPerKm, closeTo(300, 1.0));
      expect(spiky.segments.every((s) => s.gradient.abs() < 0.01), isTrue);
    });

    test('exactly 0.0 altitude is treated as missing', () {
      // 100 m profile with 0.0 "no altitude" readings mixed in. If 0.0 were
      // real these would be 100 m cliffs.
      final withZeros = GapCalculator.analyze(
        synth(alt: (d) => (d / 50).round() % 4 == 1 ? 0.0 : 100),
      )!;
      expect(withZeros.avgGapSecPerKm, closeTo(300, 1.0));
      expect(withZeros.segments.every((s) => s.gradient.abs() < 0.01), isTrue);
    });

    test('all-0.0 altitude means no GAP at all', () {
      expect(GapCalculator.analyze(synth(alt: (_) => 0.0)), isNull);
    });

    test('null altitude: none -> null, some -> still works', () {
      expect(GapCalculator.analyze(synth()), isNull); // no alt anywhere
      final some = [
        for (final s in synth(alt: flatAlt))
          (s.distanceM / 50).round() % 3 == 0
              ? GapSample(distanceM: s.distanceM, timeSeconds: s.timeSeconds)
              : s,
      ];
      final a = GapCalculator.analyze(some)!;
      expect(a.avgGapSecPerKm, closeTo(300, 1.0));
    });

    test('the gradient is clamped to +-20%', () {
      // A 50% slope sustained over the whole run: not a spike (it is linear),
      // but steeper than road running ever is.
      final a = GapCalculator.analyze(synth(alt: (d) => 100 + d * 0.5))!;
      final maxG = a.segments.map((s) => s.gradient).reduce(math.max);
      expect(maxG, closeTo(GapCalculator.maxAbsGradient, 1e-9));
      expect(
        a.segments.every(
          (s) => s.gradient.abs() <= GapCalculator.maxAbsGradient,
        ),
        isTrue,
      );
      final down = GapCalculator.analyze(synth(alt: (d) => 2000 - d * 0.5))!;
      expect(
        down.segments.map((s) => s.gradient).reduce(math.min),
        closeTo(-GapCalculator.maxAbsGradient, 1e-9),
      );
    });

    test(
      'smoothing is by distance: irregular spacing gives the same profile',
      () {
        // The same 5% climb sampled evenly and unevenly.
        final even = ElevationProfile.build(synth(alt: (d) => 100 + d * 0.05))!;
        final uneven = <GapSample>[];
        var d = 0.0;
        var i = 0;
        while (d <= 2000) {
          uneven.add(
            GapSample(
              distanceM: d,
              timeSeconds: d * 0.3,
              altitudeM: 100 + d * 0.05,
            ),
          );
          d += i.isEven ? 20 : 120;
          i++;
        }
        final u = ElevationProfile.build(uneven)!;
        for (final m in [300.0, 900.0, 1500.0]) {
          expect(u.gradientAround(m), closeTo(even.gradientAround(m), 0.005));
        }
      },
    );
  });

  group('segments', () {
    test('uses delta time / delta distance, not the smoothed pace field', () {
      // True pace 5:00/km (50 m per 15 s) but the telemetry pace field says
      // 3:20/km. GAP must follow the clock.
      final a = GapCalculator.analyze(
        synth(alt: flatAlt, paceField: (_) => 200),
      )!;
      expect(a.avgRawPaceSecPerKm, closeTo(300, 1e-6));
      expect(a.avgGapSecPerKm, closeTo(300, 1e-6));
    });

    test('a long time gap is ignored and does not dominate', () {
      final base = synth(alt: flatAlt, count: 21);
      final withGap = <GapSample>[
        ...base,
        // 10 minutes pass while only 50 m is covered (a dropout).
        GapSample(distanceM: 1050, timeSeconds: 300 + 600, altitudeM: 100),
        for (var i = 1; i <= 20; i++)
          GapSample(
            distanceM: 1050 + i * 50,
            timeSeconds: 900 + i * 15,
            altitudeM: 100,
          ),
      ];
      final a = GapCalculator.analyze(withGap)!;
      expect(a.avgRawPaceSecPerKm, closeTo(300, 1e-6));
      // The 1000->1050 segment (600 s) is not counted.
      expect(a.coveredDistanceM, closeTo(2000, 1e-6));
    });

    test('invalid-pace segments are ignored', () {
      final s = synth(alt: flatAlt, count: 31);
      final broken = [
        ...s.take(10),
        // 100 m in 5 s = 50 s/km: a GPS jump, not running.
        GapSample(
          distanceM: 450 + 100,
          timeSeconds: 10 * 15 + 5,
          altitudeM: 100,
        ),
        ...[
          for (var i = 12; i < 31; i++)
            GapSample(
              distanceM: i * 50.0 + 50,
              timeSeconds: i * 15.0 - 10 + 5 + 5,
              altitudeM: 100,
            ),
        ],
      ];
      final a = GapCalculator.analyze(broken)!;
      expect(
        a.avgRawPaceSecPerKm,
        greaterThan(GapCalculator.minValidPaceSecPerKm),
      );
      for (final seg in a.segments) {
        final pace = seg.seconds / (seg.lengthM / 1000);
        expect(pace, inInclusiveRange(120, 1800));
      }
    });

    test('too-slow (walking) segments are ignored', () {
      final samples = [
        ...synth(alt: flatAlt, count: 11), // 0..500 m at 300 s/km
        // 30 m in 59 s = 1967 s/km: standing/walking, not running.
        const GapSample(distanceM: 530, timeSeconds: 209, altitudeM: 100),
        for (var i = 1; i <= 15; i++)
          GapSample(
            distanceM: 530.0 + i * 50,
            timeSeconds: 209 + i * 15.0,
            altitudeM: 100,
          ),
      ];
      final a = GapCalculator.analyze(samples)!;
      expect(a.avgRawPaceSecPerKm, closeTo(300, 1e-6));
      // The slow segment's 30 m is not in the covered distance.
      expect(a.coveredDistanceM, closeTo(500 + 750, 1e-6));
    });

    test('zero and negative distance steps are skipped without error', () {
      final samples = [
        ...synth(alt: flatAlt, count: 11),
        GapSample(distanceM: 500, timeSeconds: 165, altitudeM: 100), // no move
        GapSample(
          distanceM: 480,
          timeSeconds: 180,
          altitudeM: 100,
        ), // backwards
        for (var i = 1; i <= 20; i++)
          GapSample(
            distanceM: 500.0 + i * 50,
            timeSeconds: 195 + i * 15.0,
            altitudeM: 100,
          ),
      ];
      final a = GapCalculator.analyze(samples)!;
      expect(a.segments.every((s) => s.lengthM > 0), isTrue);
      expect(a.avgRawPaceSecPerKm, closeTo(300, 6));
    });

    test('short or incomplete runs do not crash', () {
      expect(GapCalculator.analyze(const []), isNull);
      expect(
        GapCalculator.analyze([
          const GapSample(distanceM: 0, timeSeconds: 0, altitudeM: 100),
        ]),
        isNull,
      );
      // 100 m: under the minimum analysis distance.
      expect(GapCalculator.analyze(synth(alt: flatAlt, count: 3)), isNull);
      expect(
        GapCalculator.analyze([
          const GapSample(
            distanceM: double.nan,
            timeSeconds: 0,
            altitudeM: 100,
          ),
          const GapSample(distanceM: 100, timeSeconds: 30, altitudeM: 100),
        ]),
        isNull,
      );
    });

    test('the finish line closes the gap after the last sample', () {
      final withEnd = GapCalculator.analyze(
        synth(alt: flatAlt, count: 21),
        finalDistanceM: 1040,
        finalSeconds: 312,
      )!;
      expect(withEnd.coveredDistanceM, closeTo(1040, 1e-6));
      expect(withEnd.segments.last.endM, 1040);
    });
  });

  group('old samples without timestamps', () {
    test('fall back to the sample pace and still produce a sensible GAP', () {
      final a = GapCalculator.analyze(
        synth(alt: flatAlt, withTime: false, paceField: (_) => 330),
      )!;
      expect(a.avgRawPaceSecPerKm, closeTo(330, 1e-6));
      expect(a.avgGapSecPerKm, closeTo(330, 1e-6));
    });

    test('an old uphill run is still faster than actual', () {
      final a = GapCalculator.analyze(
        synth(
          alt: (d) => 100 + d * 0.05,
          withTime: false,
          paceField: (_) => 330,
        ),
      )!;
      expect(a.avgGapSecPerKm, lessThan(330));
    });

    test('no timestamps and no valid pace: nothing to analyse', () {
      expect(
        GapCalculator.analyze(
          synth(alt: flatAlt, withTime: false, paceField: (_) => null),
        ),
        isNull,
      );
    });
  });

  group('ratioBetween (per-split)', () {
    test('a flat range gives exactly 1', () {
      final a = GapCalculator.analyze(synth(alt: flatAlt))!;
      expect(a.ratioBetween(0, 1), closeTo(1, 1e-9));
    });

    test('an uphill range gives a ratio below 1, downhill above 1', () {
      final up = GapCalculator.analyze(synth(alt: (d) => 100 + d * 0.05))!;
      expect(up.ratioBetween(0.5, 1.5)!, lessThan(0.85));
      final down = GapCalculator.analyze(synth(alt: (d) => 300 - d * 0.05))!;
      expect(down.ratioBetween(0.5, 1.5)!, greaterThan(1.15));
    });

    test('a range with too little valid coverage is null, not invented', () {
      // Only the first 400 m are valid; ask about km 1-2.
      final a = GapCalculator.analyze(synth(alt: flatAlt, count: 9))!;
      expect(a.ratioBetween(1, 2), isNull);

      // Samples cover 0..1500 m.
      final half = GapCalculator.analyze(synth(alt: flatAlt, count: 31))!;
      expect(half.ratioBetween(0.5, 1.5), isNotNull); // fully covered
      expect(half.ratioBetween(1.0, 2.0), isNull); // 500 of 1000 = 50% < 70%
      expect(half.ratioBetween(1.0, 3.5), isNull); // 500 of 2500
    });

    test('segments straddling the range edge are clipped proportionally', () {
      final a = GapCalculator.analyze(synth(alt: (d) => 100 + d * 0.05))!;
      final r = a.ratioBetween(0.525, 1.025)!; // edges fall mid-segment
      expect(r, lessThan(1));
    });

    test('an empty or inverted range is null', () {
      final a = GapCalculator.analyze(synth(alt: flatAlt))!;
      expect(a.ratioBetween(1, 1), isNull);
      expect(a.ratioBetween(2, 1), isNull);
    });
  });
}
