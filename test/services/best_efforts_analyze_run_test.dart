/// BestEffortsService.analyzeRun — the canonical, validated Best Efforts
/// calculation shared by the save path and the historical rebuild.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_service.dart';

/// Samples every [stepM] metres / [stepS] seconds from the first step up to
/// [totalM] (5:00/km by default). Clean data: no glitches.
List<Map<String, dynamic>> _clean({
  required double totalM,
  double stepM = 50,
  double stepS = 15,
}) => [
  for (var d = stepM; d <= totalM + 1e-9; d += stepM)
    {'t': d / stepM * stepS, 'd': d},
];

Map<DistanceCategory, int> _byCategory(List<BestEffortResult> r) => {
  for (final e in r) e.category: e.elapsedSeconds,
};

TelemetryPoint _p(double d, double t) =>
    TelemetryPoint(distanceMeters: d, elapsedSeconds: t);

void main() {
  group('analyzeRun — clean runs (existing behaviour preserved)', () {
    test('a steady 5:00/km run gives the steady time for every distance', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(_clean(totalM: 6000)),
      );
      expect(r[DistanceCategory.m400], 120);
      expect(r[DistanceCategory.k1], 300);
      expect(r[DistanceCategory.mi1], 483); // 1609.34 m x 0.3
      expect(r[DistanceCategory.k3], 900);
      expect(r[DistanceCategory.k5], 1500);
      expect(r.containsKey(DistanceCategory.k10), isFalse);
    });

    test('matches the plain unvalidated extraction on clean data', () {
      final samples = _clean(totalM: 6000);
      final validated = _byCategory(BestEffortsService.analyzeRun(samples));
      final plain = _byCategory(
        BestEffortsService.extract(
          BestEffortsService.pointsFromTrackSamples(samples),
        ),
      );
      expect(validated, plain);
    });

    test('still picks the fastest window, not the run average', () {
      // km 1 at 6:00/km (360 s), km 2 at 4:00/km (240 s).
      final samples = [
        for (var i = 1; i <= 20; i++) {'t': i * 18.0, 'd': i * 50.0},
        for (var i = 1; i <= 20; i++)
          {'t': 360 + i * 12.0, 'd': 1000 + i * 50.0},
      ];
      final r = _byCategory(BestEffortsService.analyzeRun(samples));
      expect(r[DistanceCategory.k1], 240);
    });
  });

  group('analyzeRun — closing point', () {
    // Samples stop at 4950 m (t=1485); the run actually finished at 5020 m.
    final samples = _clean(totalM: 4950);

    test('without the run totals the last 50 m is lost and 5K is missed', () {
      final r = _byCategory(BestEffortsService.analyzeRun(samples));
      expect(r.containsKey(DistanceCategory.k5), isFalse);
    });

    test('the stored distance and duration close the run, recovering 5K', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          samples,
          finalDistanceMeters: 5020,
          finalSeconds: 1506,
        ),
      );
      expect(r[DistanceCategory.k5], 1500);
    });

    test('a closing point that is not ahead of the last sample is ignored', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          samples,
          finalDistanceMeters: 4900, // behind the last sample
          finalSeconds: 1470,
        ),
      );
      expect(r.containsKey(DistanceCategory.k5), isFalse);
    });

    test('a closing point earlier in time than the last sample is dropped', () {
      final points = BestEffortsService.pointsFromTrackSamples(
        samples,
        finalDistanceMeters: 5020,
        finalSeconds: 100, // clock behind the last sample
      );
      expect(points.last.distanceMeters, 4950);
    });

    test(
      'a finish landing in the last sample\'s second is kept, not treated as '
      'a stalled clock',
      () {
        // 3 m more distance in the same whole second: inside the quantisation
        // allowance. It legitimately shaves ~1 s off the 5K window.
        final r = _byCategory(
          BestEffortsService.analyzeRun(
            _clean(totalM: 5000),
            finalDistanceMeters: 5003,
            finalSeconds: 1500,
          ),
        );
        expect(r[DistanceCategory.k5], inInclusiveRange(1499, 1500));
      },
    );

    test('but more than the allowance of distance with no time IS a stall', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          _clean(totalM: 5000),
          finalDistanceMeters: 5100, // 100 m in 0 s
          finalSeconds: 1500,
        ),
      );
      // Windows ending at the closing point are rejected; the clean 5K that
      // ends on the last real sample still counts.
      expect(r[DistanceCategory.k5], 1500);
    });
  });

  group('analyzeRun — non-monotonic samples', () {
    test('samples that go backwards in distance or time are dropped', () {
      final samples = _clean(totalM: 3000);
      samples.insert(20, {'t': 5.0, 'd': 100.0}); // jumps back in both
      samples.insert(40, {'t': 700.0, 'd': 200.0}); // distance goes back
      samples.insert(60, {'t': 50.0, 'd': 2000.0}); // time goes back
      final points = BestEffortsService.pointsFromTrackSamples(samples);
      for (var i = 1; i < points.length; i++) {
        expect(
          points[i].distanceMeters,
          greaterThanOrEqualTo(points[i - 1].distanceMeters),
        );
        expect(
          points[i].elapsedSeconds,
          greaterThanOrEqualTo(points[i - 1].elapsedSeconds),
        );
      }
      // 60 clean samples + the (0, 0) start: all three glitches removed.
      expect(points.length, 61);
    });

    test('the Best Efforts are the same as for the clean run', () {
      final clean = _byCategory(
        BestEffortsService.analyzeRun(_clean(totalM: 3000)),
      );
      final noisy = _clean(totalM: 3000);
      noisy.insert(20, {'t': 5.0, 'd': 100.0});
      noisy.insert(40, {'t': 700.0, 'd': 200.0});
      expect(_byCategory(BestEffortsService.analyzeRun(noisy)), clean);
    });

    test('non-finite and malformed samples are skipped', () {
      final samples = _clean(totalM: 1500);
      samples.insert(5, {'t': double.nan, 'd': 100.0});
      samples.insert(6, {'t': 90.0, 'd': double.infinity});
      samples.insert(7, {'d': 100.0}); // no t
      samples.insert(8, {'t': 30.0}); // no d
      final r = _byCategory(BestEffortsService.analyzeRun(samples));
      expect(r[DistanceCategory.k1], 300);
    });
  });

  group('analyzeRun — stalled clock', () {
    // 1 km normally (5:00/km). Then the clock stalls: the phone keeps adding
    // distance (150 m per sample) while `t` does not move. Afterwards the
    // clock catches up in one jump, then the run continues normally.
    List<Map<String, dynamic>> stalled() => [
      for (var d = 50.0; d <= 1000; d += 50) {'t': d / 50 * 15, 'd': d},
      for (var k = 1; k <= 8; k++) {'t': 300.0, 'd': 1000.0 + k * 150}, // stall
      {'t': 800.0, 'd': 2250.0}, // clock jumps forward
      for (var k = 1; k <= 30; k++) {'t': 800 + k * 15.0, 'd': 2250.0 + k * 50},
    ];

    test('the unvalidated scan believes the impossible window', () {
      final plain = BestEffortsService.extract(
        BestEffortsService.pointsFromTrackSamples(stalled()),
      );
      expect(
        _byCategory(plain)[DistanceCategory.k1]!,
        lessThan(DistanceCategory.k1.ceilingSeconds), // impossibly fast
      );
    });

    test('analyzeRun rejects every window that crosses the stall', () {
      final r = _byCategory(BestEffortsService.analyzeRun(stalled()));
      // The only trustworthy 1 km windows are the normal ones: 300 s.
      expect(r[DistanceCategory.k1], 300);
      expect(r[DistanceCategory.m400]!, greaterThanOrEqualTo(120));
      for (final e in r.entries) {
        expect(
          e.value,
          greaterThanOrEqualTo(e.key.ceilingSeconds.floor()),
          reason: '${e.key.label} is faster than humanly possible',
        );
      }
    });

    test('a run that stalls for good has no effort beyond the stall', () {
      // 2 km of "running" with the clock frozen after the first km.
      final samples = [
        for (var d = 50.0; d <= 1000; d += 50) {'t': d / 50 * 15, 'd': d},
        for (var k = 1; k <= 7; k++) {'t': 300.0, 'd': 1000.0 + k * 150},
      ];
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          samples,
          finalDistanceMeters: 2050,
          finalSeconds: 300,
        ),
      );
      expect(r[DistanceCategory.k1], 300); // the genuine first kilometre
      expect(r.containsKey(DistanceCategory.k3), isFalse);
    });
  });

  group('analyzeRun — impossible speed', () {
    // 5:00/km, except one sample is a 150 m teleport in 5 s (30 m/s).
    List<Map<String, dynamic>> withSpike() => [
      for (var i = 1; i <= 29; i++) {'t': i * 15.0, 'd': i * 50.0},
      {'t': 440.0, 'd': 1600.0}, // 150 m in 5 s
      for (var k = 1; k <= 30; k++) {'t': 440 + k * 15.0, 'd': 1600 + k * 50.0},
    ];

    test('the unvalidated scan lets the spike produce a fast 400 m', () {
      final plain = _byCategory(
        BestEffortsService.extract(
          BestEffortsService.pointsFromTrackSamples(withSpike()),
        ),
      );
      expect(plain[DistanceCategory.m400]!, lessThan(120));
    });

    test('analyzeRun ignores windows containing the spike', () {
      final r = _byCategory(BestEffortsService.analyzeRun(withSpike()));
      expect(r[DistanceCategory.m400], 120); // a clean 400 m elsewhere
    });

    test('the limit is configurable and boundary speed 10 m/s is allowed', () {
      // 150 m in exactly 15 s = 10.0 m/s: not "faster than" the limit.
      final samples = [
        for (var i = 1; i <= 20; i++) {'t': i * 15.0, 'd': i * 150.0},
      ];
      final ok = BestEffortsService.analyzeRun(
        samples,
        rules: const BestEffortsRules(applyCeilings: false),
      );
      expect(_byCategory(ok).containsKey(DistanceCategory.k1), isTrue);
      final strict = BestEffortsService.analyzeRun(
        samples,
        rules: const BestEffortsRules(
          maxSegmentSpeedMps: 9.9,
          applyCeilings: false,
        ),
      );
      expect(_byCategory(strict).isEmpty, isTrue);
    });
  });

  group('analyzeRun — world-record ceiling', () {
    // 7 m/s constant (50 m every 7.14 s): every stretch is plausible
    // (< 10 m/s) but a 5K in ~11:54 is beyond any human.
    List<Map<String, dynamic>> tooFast5k() => [
      for (var i = 1; i <= 104; i++) {'t': i * 50 / 7, 'd': i * 50.0},
    ];

    test('an effort faster than the ceiling is rejected', () {
      final plain = _byCategory(
        BestEffortsService.extract(
          BestEffortsService.pointsFromTrackSamples(tooFast5k()),
        ),
      );
      expect(plain[DistanceCategory.k5]!, lessThan(750));

      final r = _byCategory(BestEffortsService.analyzeRun(tooFast5k()));
      expect(r.containsKey(DistanceCategory.k5), isFalse);
      // 1K at 7 m/s = 143 s, slower than the 1K ceiling, so it survives.
      expect(r[DistanceCategory.k1], 143);
    });

    test('an elite-but-legitimate time just inside the ceiling is kept', () {
      // 5K in 12:40 (760 s): 6.58 m/s.
      final samples = [
        for (var i = 1; i <= 100; i++) {'t': i * 7.6, 'd': i * 50.0},
      ];
      final r = _byCategory(BestEffortsService.analyzeRun(samples));
      expect(r[DistanceCategory.k5], 760);
    });

    test('the ceilings can be switched off by rules', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          tooFast5k(),
          rules: const BestEffortsRules(applyCeilings: false),
        ),
      );
      expect(r.containsKey(DistanceCategory.k5), isTrue);
    });

    test('ceilings are positive and grow with distance', () {
      var last = 0.0;
      for (final c in DistanceCategory.values) {
        expect(c.ceilingSeconds, greaterThan(last), reason: c.label);
        last = c.ceilingSeconds;
      }
    });

    test('rejecting too-fast windows does not forfeit the whole category', () {
      // 5.2 km at an impossible 7 m/s, then 1 km at 5:00/km. Pure-fast 5K
      // windows (714 s) are rejected, but windows that include some of the slow
      // kilometre are slower than the ceiling and still compete.
      final samples = [
        for (var i = 1; i <= 104; i++) {'t': i * 50 / 7, 'd': i * 50.0},
        for (var k = 1; k <= 20; k++)
          {'t': 104 * 50 / 7 + k * 15.0, 'd': 5200.0 + k * 50},
      ];
      final r = _byCategory(BestEffortsService.analyzeRun(samples));
      expect(r[DistanceCategory.k5], isNotNull);
      expect(
        r[DistanceCategory.k5]!,
        greaterThanOrEqualTo(DistanceCategory.k5.ceilingSeconds.floor()),
      );
    });
  });

  group('analyzeRun — sparse samples at a window edge', () {
    // A sample every 300 m / 90 s.
    final sparse = [
      for (var i = 1; i <= 12; i++) {'t': i * 90.0, 'd': i * 300.0},
    ];

    test('a window interpolated across a >60 s bracket is rejected', () {
      final r = _byCategory(BestEffortsService.analyzeRun(sparse));
      expect(r.containsKey(DistanceCategory.k1), isFalse);
    });

    test(
      'a window whose edges sit exactly on samples needs no interpolation',
      () {
        // 3000 m = 10 x 300 m, so every 3K window starts exactly on a sample.
        final r = _byCategory(BestEffortsService.analyzeRun(sparse));
        expect(r[DistanceCategory.k3], 900);
      },
    );

    test(
      'exactly 60 s between bracketing samples is accepted, 61 s is not',
      () {
        List<TelemetryPoint> spaced(double stepS) => [
          _p(0, 0),
          _p(300, stepS),
          _p(600, stepS * 2),
          _p(900, stepS * 3),
          _p(1200, stepS * 4),
        ];
        const rules = BestEffortsRules(applyCeilings: false);
        expect(
          BestEffortsService.fastestSegmentSeconds(
            spaced(60),
            400,
            rules: rules,
          ),
          isNotNull,
        );
        expect(
          BestEffortsService.fastestSegmentSeconds(
            spaced(61),
            400,
            rules: rules,
          ),
          isNull,
        );
      },
    );

    test('normal 15 s sampling is never treated as sparse', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(_clean(totalM: 2000)),
      );
      expect(r[DistanceCategory.k1], 300);
    });

    test('a GPS dropout elsewhere does not invalidate clean windows', () {
      // A 3-minute hole after 2 km; the first 2 km are clean.
      final samples = [
        ..._clean(totalM: 2000),
        {'t': 600.0 + 180, 'd': 2050.0},
        for (var k = 1; k <= 20; k++)
          {'t': 780 + k * 15.0, 'd': 2050 + k * 50.0},
      ];
      final r = _byCategory(BestEffortsService.analyzeRun(samples));
      expect(r[DistanceCategory.k1], 300);
    });
  });

  group('analyzeRun — exact distance boundaries', () {
    test('a run of exactly 1000 m gives exactly the 1K time', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          _clean(totalM: 950),
          finalDistanceMeters: 1000,
          finalSeconds: 300,
        ),
      );
      expect(r[DistanceCategory.k1], 300);
    });

    test('999.9 m does not reach 1K', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          _clean(totalM: 950),
          finalDistanceMeters: 999.9,
          finalSeconds: 299.97,
        ),
      );
      expect(r.containsKey(DistanceCategory.k1), isFalse);
      expect(r[DistanceCategory.m400], 120);
    });

    test('exactly 400 m is enough for the 400 m effort', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          _clean(totalM: 350),
          finalDistanceMeters: 400,
          finalSeconds: 120,
        ),
      );
      expect(r[DistanceCategory.m400], 120);
    });

    test('exactly marathon distance reaches the marathon', () {
      // 42195 m at 6:00/km = 15190 s; 50 m / 18 s.
      final samples = [
        for (var d = 50.0; d <= 42150; d += 50) {'t': d / 50 * 18, 'd': d},
      ];
      final r = _byCategory(
        BestEffortsService.analyzeRun(
          samples,
          finalDistanceMeters: 42195,
          finalSeconds: 42195 * 0.36,
        ),
      );
      expect(r[DistanceCategory.marathon], (42195 * 0.36).round());
    });
  });

  group('analyzeRun — runs shorter than the target', () {
    test('a 3 km run has no 5K, 10K, half or marathon', () {
      final r = _byCategory(
        BestEffortsService.analyzeRun(_clean(totalM: 3000)),
      );
      expect(r.keys, containsAll([DistanceCategory.k1, DistanceCategory.k3]));
      expect(r.containsKey(DistanceCategory.k5), isFalse);
      expect(r.containsKey(DistanceCategory.k10), isFalse);
      expect(r.containsKey(DistanceCategory.half), isFalse);
      expect(r.containsKey(DistanceCategory.marathon), isFalse);
    });

    test('a 300 m run, one sample, and no samples produce nothing', () {
      expect(BestEffortsService.analyzeRun(_clean(totalM: 300)), isEmpty);
      expect(
        BestEffortsService.analyzeRun([
          {'t': 15.0, 'd': 50.0},
        ]),
        isEmpty,
      );
      expect(BestEffortsService.analyzeRun(const []), isEmpty);
    });
  });

  group('analyzeRun — window selection', () {
    test('a glitch costs only the windows it touches, not the whole run', () {
      // 2:00-per-400 m first lap, a teleport mid-run, then a faster lap.
      final samples = [
        for (var i = 1; i <= 8; i++)
          {'t': i * 15.0, 'd': i * 50.0}, // 120 s/400 m
        {'t': 130.0, 'd': 700.0}, // 300 m in 10 s: glitch
        for (var k = 1; k <= 10; k++)
          {'t': 130 + k * 12.0, 'd': 700 + k * 50.0}, // 4:00/km after
      ];
      final r = _byCategory(BestEffortsService.analyzeRun(samples));
      // The best clean 400 m is in the 4:00/km stretch: 96 s.
      expect(r[DistanceCategory.m400], 96);
    });

    test('rules are optional: rules null reproduces the plain scan', () {
      final points = BestEffortsService.pointsFromTrackSamples(
        _clean(totalM: 2000),
      );
      expect(
        BestEffortsService.fastestSegmentSeconds(points, 1000),
        BestEffortsService.fastestSegmentSeconds(
          points,
          1000,
          rules: BestEffortsRules.standard,
        ),
      );
    });
  });
}
