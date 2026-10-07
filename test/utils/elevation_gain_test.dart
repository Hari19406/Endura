import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/elevation_gain.dart';
import 'package:run_app/utils/gap_calculator.dart';

/// Samples every 50 m (about the 15 s capture cadence) with [alt] per index.
List<Map<String, dynamic>> _samples(
  int n,
  double? Function(int i) alt, {
  double stepM = 50,
}) => [
  for (var i = 0; i < n; i++)
    {'t': i * 15, 'd': i * stepM, 'alt': alt(i), 'pace': 300},
];

/// Deterministic roughly-normal noise with standard deviation [sigma].
double Function(int) _noise(double sigma, {int seed = 7}) {
  final rng = math.Random(seed);
  return (_) {
    var s = 0.0;
    for (var k = 0; k < 12; k++) {
      s += rng.nextDouble();
    }
    return (s - 6) * sigma;
  };
}

void main() {
  group('ElevationGain.fromTrackSamples', () {
    test('flat run with noisy altitude gives near-zero ascent', () {
      for (final sigma in [1.0, 2.0, 3.0]) {
        final noise = _noise(sigma);
        final gain = ElevationGain.fromTrackSamples(
          _samples(100, (i) => 900 + noise(i)),
        )!;
        expect(gain, lessThan(30), reason: 'sigma $sigma');
      }
    });

    test('far below what summing raw positive deltas would report', () {
      final noise = _noise(2);
      final alts = [for (var i = 0; i < 100; i++) 900 + noise(i)];
      var naive = 0.0;
      for (var i = 1; i < alts.length; i++) {
        final d = alts[i] - alts[i - 1];
        if (d > 0.5 && d < 15) naive += d;
      }
      final cleaned = ElevationGain.fromTrackSamples(
        _samples(100, (i) => alts[i]),
      )!;
      expect(naive, greaterThan(100));
      expect(cleaned, lessThan(naive / 4));
    });

    test('a known climb is measured approximately correctly', () {
      // 50 m of steady climb over 2 km.
      final gain = ElevationGain.fromTrackSamples(
        _samples(41, (i) => 900 + i * (50 / 40)),
      )!;
      expect(gain, closeTo(50, 5));
    });

    test('a noisy known climb is still approximately correct', () {
      final noise = _noise(1.5);
      final gain = ElevationGain.fromTrackSamples(
        _samples(81, (i) => 900 + i * (60 / 80) + noise(i)),
      )!;
      expect(gain, closeTo(60, 15));
    });

    test('climb then descent counts only the climb', () {
      // Up 40 m over 2 km, back down 40 m over 2 km.
      final gain = ElevationGain.fromTrackSamples(
        _samples(81, (i) => 900 + (i <= 40 ? i : 80 - i) * 1.0),
      )!;
      expect(gain, closeTo(40, 6));
    });

    test('a pure descent has zero ascent', () {
      final gain = ElevationGain.fromTrackSamples(
        _samples(41, (i) => 950 - i * 1.0),
      )!;
      expect(gain, lessThan(2));
    });

    test('null altitudes are ignored', () {
      final withGaps = ElevationGain.fromTrackSamples(
        _samples(41, (i) => i.isOdd ? null : 900 + i * (50 / 40)),
      )!;
      expect(withGaps, closeTo(50, 6));
      expect(ElevationGain.fromTrackSamples(_samples(40, (_) => null)), isNull);
    });

    test('0.0 altitude means unavailable, not a 900 m cliff', () {
      expect(ElevationGain.fromTrackSamples(_samples(40, (_) => 0.0)), isNull);
      final withZeros = ElevationGain.fromTrackSamples(
        _samples(60, (i) => i % 7 == 3 ? 0.0 : 900.0),
      )!;
      expect(withZeros, lessThan(2));
    });

    test('a single altitude spike is rejected', () {
      final gain = ElevationGain.fromTrackSamples(
        _samples(60, (i) => i == 30 ? 960.0 : 900.0),
      )!;
      expect(gain, lessThan(3));
    });

    test('fewer than two usable altitude points gives null', () {
      expect(ElevationGain.fromTrackSamples(const []), isNull);
      expect(ElevationGain.fromTrackSamples(_samples(1, (_) => 900)), isNull);
      expect(
        ElevationGain.fromTrackSamples(
          _samples(2, (i) => i == 0 ? 900.0 : null),
        ),
        isNull,
      );
    });

    test('samples without a distance are skipped, result rounds to 0.1 m', () {
      final gain = ElevationGain.fromTrackSamples([
        {'alt': 900.0},
        ..._samples(41, (i) => 900 + i * (50 / 40)),
      ])!;
      expect(gain, closeTo(50, 6));
      expect((gain * 10).roundToDouble(), gain * 10);
    });
  });

  group('ElevationProfile.totalAscent', () {
    test('matches the profile the chart and GAP use', () {
      final samples = [
        for (var i = 0; i < 41; i++)
          GapSample(distanceM: i * 50.0, altitudeM: 900 + i * 1.0),
      ];
      final profile = ElevationProfile.build(samples)!;
      expect(ElevationProfile.totalAscent(samples), profile.ascent);
      expect(profile.ascent, closeTo(40, 5));
    });

    test('null when the profile cannot be built', () {
      expect(ElevationProfile.totalAscent(const []), isNull);
    });
  });

  group('save path', () {
    final src = File('lib/screens/run_screen.dart').readAsStringSync();

    test('run_screen saves ascent from the captured track samples', () {
      expect(
        src,
        contains('ElevationGain.fromTrackSamples(capturedTrackSamples)'),
      );
      expect(src, contains("import '../utils/elevation_gain.dart';"));
    });

    test('the raw live accumulator is gone', () {
      expect(src, isNot(contains('_elevationGainM')));
      expect(src, isNot(contains('_lastAltitudeForGain')));
    });

    test('sample capture is unchanged (raw altitude still stored)', () {
      expect(src, contains("'alt': position.altitude"));
    });
  });
}
