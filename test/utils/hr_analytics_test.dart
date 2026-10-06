import 'package:endura/utils/hr_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

HrPoint p(double? t, int? bpm) => HrPoint(timeSeconds: t, bpm: bpm);

HrZoneStat zoneOf(List<HrZoneStat> zones, int z) =>
    zones.firstWhere((s) => s.zone == z);

void main() {
  group('HrAnalytics.summary', () {
    test('averages and peaks valid readings', () {
      final s = HrAnalytics.summary([
        p(0, 140),
        p(15, 150),
        p(30, 160),
      ])!;
      expect(s.avg, 150);
      expect(s.peak, 160);
      expect(s.count, 3);
    });

    test('ignores null and physiologically invalid readings', () {
      final s = HrAnalytics.summary([
        p(0, null),
        p(15, 29), // < 30
        p(30, 231), // > 230
        p(45, 150),
        p(60, 170),
      ])!;
      expect(s.avg, 160);
      expect(s.peak, 170);
      expect(s.count, 2);
    });

    test('boundary values 30 and 230 are valid', () {
      final s = HrAnalytics.summary([p(0, 30), p(1, 230)])!;
      expect(s.peak, 230);
      expect(s.count, 2);
    });

    test('null for empty or all-invalid input', () {
      expect(HrAnalytics.summary(const []), isNull);
      expect(HrAnalytics.summary([p(0, null), p(1, 10)]), isNull);
    });
  });

  group('HrAnalytics.zones — boundaries', () {
    // maxHr 200 → Z1 100–120, Z2 120–140, Z3 140–160, Z4 160–180, Z5 180–200.
    int zoneFor(int bpm) {
      final zones = HrAnalytics.zones([p(0, bpm), p(10, bpm)], 200);
      return zones.firstWhere((z) => z.durationSeconds > 0).zone;
    }

    test('zone edges', () {
      expect(zoneFor(100), 1);
      expect(zoneFor(119), 1);
      expect(zoneFor(120), 2);
      expect(zoneFor(139), 2);
      expect(zoneFor(140), 3);
      expect(zoneFor(159), 3);
      expect(zoneFor(160), 4);
      expect(zoneFor(179), 4);
      expect(zoneFor(180), 5);
      expect(zoneFor(200), 5);
    });

    test('below Z1 counts as Z1 and above max counts as Z5', () {
      expect(zoneFor(60), 1);
      expect(zoneFor(215), 5);
    });

    test('returns five zones with bpm bounds from max HR', () {
      final zones = HrAnalytics.zones([p(0, 150), p(10, 150)], 200);
      expect(zones.map((z) => z.zone), [1, 2, 3, 4, 5]);
      expect(zones.map((z) => z.label), [
        'Recovery',
        'Easy',
        'Aerobic',
        'Threshold',
        'VO₂ Max',
      ]);
      expect([zones.first.bpmLow, zones.first.bpmHigh], [100, 120]);
      expect([zones.last.bpmLow, zones.last.bpmHigh], [180, 200]);
    });
  });

  group('HrAnalytics.zones — time weighting', () {
    test('credits the delta to the next sample, not a sample count', () {
      // Z3 reading for 10 s, then Z4 for 20 s, last reading borrows 20 s.
      final zones = HrAnalytics.zones([p(0, 150), p(10, 170), p(30, 170)], 200);
      expect(zoneOf(zones, 3).durationSeconds, 10);
      expect(zoneOf(zones, 4).durationSeconds, 40);
      expect(zoneOf(zones, 3).percentage, closeTo(0.2, 1e-9));
      expect(zoneOf(zones, 4).percentage, closeTo(0.8, 1e-9));
    });

    test('percentages sum to 1', () {
      final zones = HrAnalytics.zones([
        p(0, 110),
        p(12, 130),
        p(25, 150),
        p(40, 170),
        p(55, 190),
        p(70, 190),
      ], 200);
      final sum = zones.fold<double>(0, (a, z) => a + z.percentage);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('caps a long-but-not-dropout interval at 30 s', () {
      // 45 s gap: capped to 30 s; last reading borrows that 30 s.
      final zones = HrAnalytics.zones([p(0, 150), p(45, 150)], 200);
      expect(zoneOf(zones, 3).durationSeconds, 60);
    });

    test('order of input does not matter when timestamps exist', () {
      final a = HrAnalytics.zones([p(0, 150), p(10, 170), p(30, 170)], 200);
      final b = HrAnalytics.zones([p(30, 170), p(0, 150), p(10, 170)], 200);
      expect(
        b.map((z) => z.durationSeconds).toList(),
        a.map((z) => z.durationSeconds).toList(),
      );
    });

    test('samples without timestamps are credited 15 s each', () {
      final zones = HrAnalytics.zones([p(null, 150), p(null, 150)], 200);
      expect(zoneOf(zones, 3).durationSeconds, 30);
    });

    test('a single reading is credited the fallback interval', () {
      final zones = HrAnalytics.zones([p(0, 150)], 200);
      expect(zoneOf(zones, 3).durationSeconds, 15);
    });
  });

  group('HrAnalytics.zones — gaps, nulls, invalid, empty', () {
    test('a dropout longer than 60 s credits nothing and is not borrowed', () {
      // 150 for 10 s; 190 s dropout; 170 for 10 s (+10 s borrowed).
      final zones = HrAnalytics.zones([
        p(0, 150),
        p(10, 150),
        p(200, 170),
        p(210, 170),
      ], 200);
      expect(zoneOf(zones, 3).durationSeconds, 10);
      expect(zoneOf(zones, 4).durationSeconds, 20);
      final total = zones.fold<int>(0, (a, z) => a + z.durationSeconds);
      expect(total, 30);
    });

    test('null HR readings credit no time but end the previous interval', () {
      final zones = HrAnalytics.zones([p(0, 150), p(10, null), p(20, 150)], 200);
      expect(zoneOf(zones, 3).durationSeconds, 20);
    });

    test('invalid readings are skipped', () {
      final zones = HrAnalytics.zones([
        p(0, 20),
        p(10, 250),
        p(20, 150),
        p(30, 150),
      ], 200);
      final total = zones.fold<int>(0, (a, z) => a + z.durationSeconds);
      expect(zoneOf(zones, 3).durationSeconds, total);
      expect(total, 20);
    });

    test('empty when there is nothing valid to credit', () {
      expect(HrAnalytics.zones(const [], 200), isEmpty);
      expect(HrAnalytics.zones([p(0, null), p(10, null)], 200), isEmpty);
      expect(HrAnalytics.zones([p(0, 20), p(10, 300)], 200), isEmpty);
    });

    test('empty for a non-positive max HR', () {
      expect(HrAnalytics.zones([p(0, 150), p(10, 150)], 0), isEmpty);
    });
  });

  group('HrAnalytics.zones — consistency across runs', () {
    test('same max HR gives identical zone bounds and assignment', () {
      final runA = HrAnalytics.zones([p(0, 150), p(15, 172), p(30, 172)], 190);
      // A harder run with a higher peak must not move the boundaries.
      final runB = HrAnalytics.zones([p(0, 150), p(15, 172), p(30, 188)], 190);

      expect(
        runA.map((z) => [z.bpmLow, z.bpmHigh]).toList(),
        runB.map((z) => [z.bpmLow, z.bpmHigh]).toList(),
      );
      // 150 bpm is Z3 in both runs (140.. at maxHr 190 is 133–152).
      expect(zoneOf(runA, 3).durationSeconds, greaterThan(0));
      expect(zoneOf(runB, 3).durationSeconds, greaterThan(0));
    });

    test('deterministic: same input twice gives the same output', () {
      final input = [p(0, 120), p(14, 148), p(29, 171), p(44, 171)];
      final a = HrAnalytics.zones(input, 190);
      final b = HrAnalytics.zones(input, 190);
      expect(
        a.map((z) => [z.durationSeconds, z.percentage]).toList(),
        b.map((z) => [z.durationSeconds, z.percentage]).toList(),
      );
    });

    test('a different max HR moves the bounds', () {
      final a = HrAnalytics.zones([p(0, 150), p(10, 150)], 180);
      final b = HrAnalytics.zones([p(0, 150), p(10, 150)], 200);
      expect(a.first.bpmLow, 90);
      expect(b.first.bpmLow, 100);
    });
  });
}
