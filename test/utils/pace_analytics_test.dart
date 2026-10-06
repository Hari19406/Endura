import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/pace_analytics.dart';

// Readable fixture zones (sec/km, LOWER = FASTER):
//   Z1 Easy        >= 420  (7:00 or slower)
//   Z2 Marathon    360 .. <420
//   Z3 Threshold   330 .. <360
//   Z4 Interval    300 .. <330
//   Z5 Repetition  < 300   (faster than 5:00)
final config = PaceZoneConfig(cutoffsSecPerKm: [420, 360, 330, 300]);

PacePoint p(double? t, double? pace, {double? km}) =>
    PacePoint(timeSeconds: t, paceSecPerKm: pace, distanceKm: km);

PaceZoneStat zoneOf(List<PaceZoneStat> zones, int z) =>
    zones.firstWhere((s) => s.zone == z);

List<int> durations(List<PaceZoneStat> z) =>
    z.map((s) => s.durationSeconds).toList();

void main() {
  group('zone classification (pace, not speed)', () {
    test('a LOWER sec/km is a HARDER zone', () {
      expect(config.zoneFor(500), 1); // slow jog
      expect(config.zoneFor(390), 2);
      expect(config.zoneFor(345), 3);
      expect(config.zoneFor(315), 4);
      expect(config.zoneFor(280), 5); // fast
    });

    test('pace exactly on a cutoff belongs to the easier zone', () {
      expect(config.zoneFor(420), 1);
      expect(config.zoneFor(419.9), 2);
      expect(config.zoneFor(360), 2);
      expect(config.zoneFor(359.9), 3);
      expect(config.zoneFor(330), 3);
      expect(config.zoneFor(329.9), 4);
      expect(config.zoneFor(300), 4);
      expect(config.zoneFor(299.9), 5);
    });

    test(
      'open-ended: slower than zone 1 stays zone 1, faster than zone 5 stays zone 5',
      () {
        expect(config.zoneFor(900), 1);
        expect(config.zoneFor(150), 5);
      },
    );

    test('zone edges are exposed slow/fast with open ends', () {
      expect(config.slowEdge(1), isNull);
      expect(config.fastEdge(1), 420);
      expect(config.slowEdge(3), 360);
      expect(config.fastEdge(3), 330);
      expect(config.slowEdge(5), 300);
      expect(config.fastEdge(5), isNull);
    });

    test('rejects cutoffs that are not strictly descending', () {
      expect(
        () => PaceZoneConfig(cutoffsSecPerKm: [420, 430, 330, 300]),
        throwsArgumentError,
      );
      expect(
        () => PaceZoneConfig(cutoffsSecPerKm: [420, 360, 360, 300]),
        throwsArgumentError,
      );
      expect(
        () => PaceZoneConfig(cutoffsSecPerKm: [420, 360, 330]),
        throwsArgumentError,
      );
    });
  });

  group('PaceZoneConfig.fromVdot (existing Daniels table)', () {
    test('cutoffs are strictly descending for every supported vDOT', () {
      for (var v = 30; v <= 85; v++) {
        final c = PaceZoneConfig.fromVdot(v); // would throw otherwise
        expect(c.vdot, v);
        expect(c.cutoffsSecPerKm.length, 4);
      }
    });

    test('vDOT 30 cutoffs are the midpoints between E/M/T/I/R ranges', () {
      // E 484-534, M 440-450, T 398-408, I 347-357, R 336-342.
      final c = PaceZoneConfig.fromVdot(30);
      expect(c.cutoffsSecPerKm, [467, 424, 377.5, 344.5]);
    });

    test('a fitter athlete has faster zones', () {
      final slow = PaceZoneConfig.fromVdot(35);
      final fast = PaceZoneConfig.fromVdot(55);
      for (var i = 0; i < 4; i++) {
        expect(fast.cutoffsSecPerKm[i], lessThan(slow.cutoffsSecPerKm[i]));
      }
    });

    test('each Daniels E/M/T/I/R range maps to its own zone at vDOT 50', () {
      // vDOT 50: E 347-395, M 323-333, T 273-283, I 241-251, R 229-235.
      final c = PaceZoneConfig.fromVdot(50);
      expect(c.cutoffsSecPerKm, [340, 303, 262, 238]);
      expect(c.zoneFor(360), 1); // easy
      expect(c.zoneFor(328), 2); // marathon
      expect(c.zoneFor(278), 3); // threshold
      expect(c.zoneFor(246), 4); // interval
      expect(c.zoneFor(232), 5); // repetition
    });
  });

  group('time per zone', () {
    test('every zone receives its expected duration', () {
      // 10 s in each zone, last sample borrows its previous 10 s.
      final zones = PaceAnalytics.zones([
        p(0, 450),
        p(10, 390),
        p(20, 345),
        p(30, 315),
        p(40, 280),
        p(50, 280),
      ], config);
      expect(zones.map((z) => z.zone), [1, 2, 3, 4, 5]);
      expect(zones.map((z) => z.label), [
        'Easy',
        'Marathon',
        'Threshold',
        'Interval',
        'Repetition',
      ]);
      expect(durations(zones), [10, 10, 10, 10, 20]);
    });

    test('percentages are correct and sum to ~100%', () {
      final zones = PaceAnalytics.zones([
        p(0, 450),
        p(10, 450),
        p(20, 390),
        p(30, 390),
        p(40, 280),
        p(50, 280),
      ], config);
      // 20 s Z1, 20 s Z2, 20 s Z5 (last borrows 10 s) => thirds.
      expect(zoneOf(zones, 1).percentage, closeTo(1 / 3, 1e-9));
      expect(zoneOf(zones, 2).percentage, closeTo(1 / 3, 1e-9));
      expect(zoneOf(zones, 5).percentage, closeTo(1 / 3, 1e-9));
      final sum = zones.fold<double>(0, (a, z) => a + z.percentage);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('percentages sum to ~100% for an irregular run', () {
      final zones = PaceAnalytics.zones([
        p(0, 455),
        p(13, 410),
        p(29, 372),
        p(41, 350),
        p(58, 322),
        p(70, 305),
        p(84, 290),
        p(97, 288),
      ], config);
      final sum = zones.fold<double>(0, (a, z) => a + z.percentage);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('is time-weighted, not a sample count', () {
      // Two samples in Z1 but only 5 s apart vs one Z5 sample for 25 s.
      final zones = PaceAnalytics.zones([
        p(0, 450),
        p(5, 450),
        p(10, 280),
        p(35, 280),
      ], config);
      expect(zoneOf(zones, 1).durationSeconds, 10);
      expect(zoneOf(zones, 5).durationSeconds, 50); // 25 s + borrowed 25 s
    });

    test('input order does not matter when timestamps exist', () {
      final a = PaceAnalytics.zones([
        p(0, 450),
        p(10, 390),
        p(30, 390),
      ], config);
      final b = PaceAnalytics.zones([
        p(30, 390),
        p(0, 450),
        p(10, 390),
      ], config);
      expect(durations(a), durations(b));
    });
  });

  group('boundaries and out-of-range pace', () {
    int zoneFor(double pace) {
      final zones = PaceAnalytics.zones([p(0, pace), p(10, pace)], config);
      return zones.firstWhere((z) => z.durationSeconds > 0).zone;
    }

    test('paces exactly on cutoffs land in the easier zone', () {
      expect(zoneFor(420), 1);
      expect(zoneFor(360), 2);
      expect(zoneFor(330), 3);
      expect(zoneFor(300), 4);
    });

    test('faster than the fastest zone cutoff is zone 5 (down to 2:00/km)', () {
      expect(zoneFor(250), 5);
      expect(zoneFor(120), 5); // the fastest believable pace
    });

    test('slower than the slowest cutoff is zone 1 (up to 30:00/km)', () {
      expect(zoneFor(600), 1);
      expect(zoneFor(1800), 1);
    });

    test('impossibly fast or walking-slow pace is not classified at all', () {
      expect(PaceAnalytics.isValidPace(119.9), isFalse);
      expect(PaceAnalytics.isValidPace(120), isTrue);
      expect(PaceAnalytics.isValidPace(1800), isTrue);
      expect(PaceAnalytics.isValidPace(1800.1), isFalse);

      final zones = PaceAnalytics.zones([
        p(0, 60), // 1:00/km - GPS glitch
        p(10, 3000), // 50:00/km - standing/walking
        p(20, 390),
        p(30, 390),
      ], config);
      expect(zoneOf(zones, 2).durationSeconds, 20);
      expect(zoneOf(zones, 1).durationSeconds, 0);
      expect(zoneOf(zones, 5).durationSeconds, 0);
      // Ignored time is excluded from the denominator.
      expect(zoneOf(zones, 2).percentage, closeTo(1.0, 1e-9));
    });
  });

  group('invalid, missing and empty pace', () {
    test('zero and negative pace are ignored', () {
      final zones = PaceAnalytics.zones([
        p(0, 0),
        p(10, -5),
        p(20, 390),
        p(30, 390),
      ], config);
      expect(zoneOf(zones, 2).durationSeconds, 20);
      expect(zoneOf(zones, 2).percentage, closeTo(1.0, 1e-9));
    });

    test('NaN and infinite pace are ignored', () {
      final zones = PaceAnalytics.zones([
        p(0, double.nan),
        p(10, double.infinity),
        p(20, 390),
        p(30, 390),
      ], config);
      expect(zoneOf(zones, 2).durationSeconds, 20);
    });

    test('null pace is ignored but ends the previous interval', () {
      final zones = PaceAnalytics.zones([
        p(0, 390),
        p(10, null),
        p(20, 390),
      ], config);
      expect(zoneOf(zones, 2).durationSeconds, 20); // 10 + borrowed 10
    });

    test('no valid pace samples gives an empty list', () {
      expect(PaceAnalytics.zones(const [], config), isEmpty);
      expect(PaceAnalytics.zones([p(0, null), p(10, null)], config), isEmpty);
      expect(PaceAnalytics.zones([p(0, 0), p(10, 5000)], config), isEmpty);
    });
  });

  group('timestamps, gaps and old runs', () {
    test('timestamp-based duration uses the delta to the next sample', () {
      final zones = PaceAnalytics.zones([
        p(0, 450),
        p(7, 390),
        p(19, 390),
      ], config);
      expect(zoneOf(zones, 1).durationSeconds, 7);
      expect(zoneOf(zones, 2).durationSeconds, 24); // 12 + borrowed 12
    });

    test('an interval over 30 s but under 60 s is capped at 30 s', () {
      final zones = PaceAnalytics.zones([p(0, 450), p(45, 450)], config);
      expect(zoneOf(zones, 1).durationSeconds, 60); // 30 + borrowed 30
    });

    test('a gap over 60 s is a dropout and credits nothing', () {
      final zones = PaceAnalytics.zones([
        p(0, 450),
        p(10, 450), // 190 s dropout follows
        p(200, 280),
        p(210, 280),
      ], config);
      expect(zoneOf(zones, 1).durationSeconds, 10);
      expect(zoneOf(zones, 5).durationSeconds, 20);
      final total = zones.fold<int>(0, (a, z) => a + z.durationSeconds);
      expect(total, 30); // not 210
    });

    test('old samples without timestamps use the 15 s capture interval', () {
      final zones = PaceAnalytics.zones([
        p(null, 450),
        p(null, 450),
        p(null, 280),
      ], config);
      expect(zoneOf(zones, 1).durationSeconds, 30);
      expect(zoneOf(zones, 5).durationSeconds, 15);
      expect(zoneOf(zones, 1).percentage, closeTo(2 / 3, 1e-9));
    });

    test('a single sample is credited the fallback interval', () {
      final zones = PaceAnalytics.zones([p(0, 390)], config);
      expect(zoneOf(zones, 2).durationSeconds, 15);
    });
  });

  group('distance per zone', () {
    test('is the covered distance to the next sample', () {
      final zones = PaceAnalytics.zones([
        p(0, 450, km: 0),
        p(10, 390, km: 0.02),
        p(20, 390, km: 0.05),
        p(30, 390, km: 0.08),
      ], config);
      expect(zoneOf(zones, 1).distanceKm, closeTo(0.02, 1e-9));
      expect(zoneOf(zones, 2).distanceKm, closeTo(0.06, 1e-9));
    });

    test('is null when samples carry no distance', () {
      final zones = PaceAnalytics.zones([p(0, 390), p(10, 390)], config);
      expect(zoneOf(zones, 2).distanceKm, isNull);
    });

    test('capped intervals credit only the capped share of the distance', () {
      // 45 s / 0.1 km segment is capped to 30 s -> 2/3 of the distance.
      final zones = PaceAnalytics.zones([
        p(0, 450, km: 0),
        p(45, 450, km: 0.1),
      ], config);
      expect(zoneOf(zones, 1).distanceKm, closeTo(0.1 * 30 / 45, 1e-9));
    });
  });

  test('zone stats carry the display edges as whole sec/km', () {
    final zones = PaceAnalytics.zones([p(0, 390), p(10, 390)], config);
    expect(zoneOf(zones, 1).slowEdgeSecPerKm, isNull);
    expect(zoneOf(zones, 1).fastEdgeSecPerKm, 420);
    expect(zoneOf(zones, 2).slowEdgeSecPerKm, 420);
    expect(zoneOf(zones, 2).fastEdgeSecPerKm, 360);
    expect(zoneOf(zones, 5).slowEdgeSecPerKm, 300);
    expect(zoneOf(zones, 5).fastEdgeSecPerKm, isNull);
  });

  test('deterministic: the same input gives the same output', () {
    final input = [p(0, 450), p(14, 390), p(29, 330), p(44, 290)];
    final a = PaceAnalytics.zones(input, config);
    final b = PaceAnalytics.zones(input, config);
    expect(
      a.map((z) => [z.durationSeconds, z.percentage]).toList(),
      b.map((z) => [z.durationSeconds, z.percentage]).toList(),
    );
  });
}
