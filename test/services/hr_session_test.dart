import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/hr_session.dart';

void main() {
  final t0 = DateTime(2026, 10, 6, 7, 0, 0);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  void ble(HrSession s, int bpm, int sec, {bool counting = true}) =>
      s.onReading(bpm, at(sec), source: HrSourceKind.ble, counting: counting);
  void poll(HrSession s, int bpm, int sec, {bool counting = true}) =>
      s.onReading(
        bpm,
        at(sec),
        source: HrSourceKind.healthPoll,
        counting: counting,
      );

  group('main-set gating', () {
    test('main-set reading is counted', () {
      final s = HrSession();
      ble(s, 150, 0);
      expect(s.avg, 150);
      expect(s.peak, 150);
      expect(s.countedReadings, 1);
    });

    test('warmup reading is not counted and is not the current HR', () {
      final s = HrSession();
      ble(s, 120, 0, counting: false); // warmup
      expect(s.avg, isNull);
      expect(s.peak, isNull);
      expect(s.currentOrNull(at(1)), isNull);
    });

    test('paused reading is not counted', () {
      final s = HrSession();
      ble(s, 150, 0);
      ble(s, 175, 1, counting: false); // paused
      expect(s.peak, 150);
      expect(s.avg, 150);
      expect(s.currentOrNull(at(2)), 150);
    });

    test('cooldown reading is not counted', () {
      final s = HrSession();
      ble(s, 160, 0);
      ble(s, 100, 1, counting: false); // cooldown
      expect(s.avg, 160);
      expect(s.countedReadings, 1);
    });

    test('warmup/cooldown values affect neither average nor peak', () {
      final s = HrSession();
      ble(s, 200, 0, counting: false); // warmup spike-ish value
      ble(s, 140, 1);
      ble(s, 160, 2);
      ble(s, 90, 3, counting: false); // cooldown
      expect(s.avg, 150);
      expect(s.peak, 160);
    });
  });

  group('validity filter (30–230 bpm)', () {
    test('29 rejected, 30 accepted, 230 accepted, 231 rejected', () {
      final low = HrSession()
        ..onReading(29, at(0), source: HrSourceKind.ble, counting: true);
      expect(low.countedReadings, 0);
      expect(low.rejectedCount, 1);

      final lo = HrSession();
      ble(lo, 30, 0);
      expect(lo.peak, 30);

      final hi = HrSession();
      ble(hi, 230, 0);
      expect(hi.peak, 230);

      final over = HrSession();
      ble(over, 231, 0);
      expect(over.countedReadings, 0);
      expect(over.rejectedCount, 1);
    });

    test('an invalid spike does not affect peak, average or current HR', () {
      final s = HrSession();
      ble(s, 150, 0);
      ble(s, 255, 1); // strap glitch
      ble(s, 0, 2);
      ble(s, 170, 3);
      expect(s.peak, 170);
      expect(s.avg, 160);
      expect(s.rejectedCount, 2);
      expect(s.currentOrNull(at(3)), 170);
    });

    test('an invalid reading does not refresh a stale current value', () {
      final s = HrSession();
      ble(s, 150, 0);
      ble(s, 300, 10); // rejected — must not look like a fresh reading
      expect(s.currentOrNull(at(10)), isNull);
    });
  });

  group('freshness', () {
    test('a fresh BLE reading is returned', () {
      final s = HrSession();
      ble(s, 150, 0);
      expect(s.currentOrNull(at(0)), 150);
      expect(s.currentOrNull(at(4)), 150);
      expect(s.currentOrNull(at(5)), 150); // exactly 5 s is still within it
    });

    test('a BLE reading older than ~5 s is null', () {
      final s = HrSession();
      ble(s, 150, 0);
      expect(s.currentOrNull(at(6)), isNull);
      expect(s.currentOrNull(at(60)), isNull);
    });

    test('a Health Connect poll value stays usable for ~45 s', () {
      final s = HrSession();
      poll(s, 148, 0);
      expect(s.currentOrNull(at(30)), 148);
      expect(s.currentOrNull(at(45)), 148);
    });

    test('a stale Health Connect value is null', () {
      final s = HrSession();
      poll(s, 148, 0);
      expect(s.currentOrNull(at(46)), isNull);
    });

    test('maxAge overrides the per-source window', () {
      final s = HrSession();
      ble(s, 150, 0);
      expect(s.currentOrNull(at(8), maxAge: const Duration(seconds: 10)), 150);
      expect(
        s.currentOrNull(at(8), maxAge: const Duration(seconds: 2)),
        isNull,
      );
    });

    test('no reading at all is null', () {
      expect(HrSession().currentOrNull(at(0)), isNull);
    });
  });

  group('disconnect / staleness in track samples', () {
    test('an old BLE value stops appearing once it goes stale', () {
      final s = HrSession();
      ble(s, 155, 0);
      // Samples every 15 s with the strap silent after t=0.
      final sampled = [
        for (final t in [3, 18, 33, 48]) s.currentOrNull(at(t)),
      ];
      expect(sampled, [155, null, null, null]);
    });

    test('a disconnect event invalidates the BLE reading immediately', () {
      final s = HrSession();
      ble(s, 155, 0);
      s.invalidateCurrent(HrSourceKind.ble);
      expect(s.currentOrNull(at(1)), isNull);
      // What was already counted stays in the run's stats.
      expect(s.avg, 155);
    });

    test('a BLE disconnect does not drop a current Health Connect value', () {
      final s = HrSession();
      poll(s, 148, 0);
      s.invalidateCurrent(HrSourceKind.ble);
      expect(s.currentOrNull(at(10)), 148);
    });

    test('the reading recovers when the strap reconnects', () {
      final s = HrSession();
      ble(s, 155, 0);
      s.invalidateCurrent(HrSourceKind.ble);
      ble(s, 158, 20);
      expect(s.currentOrNull(at(21)), 158);
    });
  });

  group('BLE and Health Connect stay separate', () {
    test('BLE stats win when both delivered counted readings', () {
      final s = HrSession();
      poll(s, 120, 0);
      ble(s, 150, 40);
      ble(s, 170, 41);
      expect(s.activeSource, HrSourceKind.ble);
      expect(s.avg, 160);
      expect(s.peak, 170);
    });

    test('Health Connect stats are used when BLE never delivered', () {
      final s = HrSession();
      poll(s, 140, 35);
      poll(s, 150, 65);
      expect(s.activeSource, HrSourceKind.healthPoll);
      expect(s.avg, 145);
      expect(s.peak, 150);
    });

    test('Health Connect readings obey gating and the validity range', () {
      final s = HrSession();
      poll(s, 140, 0, counting: false);
      poll(s, 400, 30);
      expect(s.activeSource, isNull);
      expect(s.avg, isNull);
    });
  });

  test('reset clears everything for a new run', () {
    final s = HrSession();
    ble(s, 150, 0);
    ble(s, 999, 1);
    s.reset();
    expect(s.avg, isNull);
    expect(s.peak, isNull);
    expect(s.currentOrNull(at(1)), isNull);
    expect(s.rejectedCount, 0);
    expect(s.activeSource, isNull);
  });
}
