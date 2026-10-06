/// GAP wiring in ActivityDetail.fromRunRecord: always recomputed from the
/// telemetry (never from the stored, historically inverted gap_average_pace),
/// with per-km and per-mile split GAP.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/utils/database_service.dart';

/// 2 km of samples every 50 m. First km 5:00/km; second km [secondKmPace]
/// s/km. [alt] maps distance (m) to altitude; null drops the altitude key.
List<Map<String, dynamic>> _samples({
  double Function(double d)? alt,
  double secondKmPace = 300,
  bool withTime = true,
  int upToM = 2000,
}) {
  final out = <Map<String, dynamic>>[];
  var t = 0.0;
  for (var d = 0.0; d <= upToM; d += 50) {
    final pace = d < 1000 ? 300.0 : secondKmPace;
    out.add({
      if (withTime) 't': t,
      'd': d,
      if (alt != null) 'alt': alt(d),
      'pace': pace,
    });
    t += pace * 50 / 1000;
  }
  return out;
}

RunRecord _run(
  List<Map<String, dynamic>> samples, {
  double distanceKm = 2.0,
  int? durationSeconds,
  String? storedGap,
  double secondKmPace = 300,
}) {
  final duration = durationSeconds ?? (300 + secondKmPace).round();
  return RunRecord(
    date: DateTime(2026, 9, 20, 7),
    distanceKm: distanceKm,
    averagePace: '5:00',
    durationSeconds: duration,
    routePolyline: '',
    workoutType: 'easy',
    splits: [
      {'km': 1, 'seconds': 300},
      {'km': 2, 'seconds': secondKmPace.round()},
    ],
    gapAveragePace: storedGap,
    trackSamples: samples,
  );
}

double _flat(double d) => 100;
double _climbSecondKm(double d) => d <= 1000 ? 100 : 100 + (d - 1000) * 0.05;
double _climbAll(double d) => 100 + d * 0.05;

void main() {
  group('overall GAP', () {
    test('a flat run: GAP equals the average pace and the delta is zero', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: _flat)),
        runnerName: 'x',
      );
      expect(a.avgGapPace, '5:00');
      expect(a.gapDeltaSeconds, 0);
      expect(a.gap, isNotNull);
    });

    test('an uphill run has GAP faster than its raw pace', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: _climbAll)),
        runnerName: 'x',
      );
      expect(a.avgGapSeconds!, lessThan(300 - 30));
      expect(a.gapDeltaSeconds!, lessThan(-30));
    });

    test('a downhill run has GAP slower than its raw pace', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: (d) => 400 - d * 0.05)),
        runnerName: 'x',
      );
      expect(a.avgGapSeconds!, greaterThan(300 + 30));
      expect(a.gapDeltaSeconds!, greaterThan(30));
    });
  });

  group('historical runs', () {
    test('a deliberately wrong stored gap_average_pace is ignored', () {
      // Flat telemetry, but the stored value (as written by the old inverted
      // formula, or just corrupt) says 9:00.
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: _flat), storedGap: '9:00'),
        runnerName: 'x',
      );
      expect(a.avgGapPace, '5:00');
      expect(a.avgGapPace, isNot('9:00'));
    });

    test('a stored value alone never produces GAP without telemetry', () {
      final a = ActivityDetail.fromRunRecord(
        _run(const [], storedGap: '4:40'),
        runnerName: 'x',
      );
      expect(a.avgGapPace, isNull);
      expect(a.gap, isNull);
    });

    test('an old flat run with no timestamps still gives a sensible GAP', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: _flat, withTime: false)),
        runnerName: 'x',
      );
      expect(a.avgGapPace, '5:00');
      expect(a.gapDeltaSeconds, 0);
    });

    test('an old uphill run with no timestamps is still faster than raw', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: _climbAll, withTime: false)),
        runnerName: 'x',
      );
      expect(a.avgGapSeconds!, lessThan(300));
    });

    test('a run with no altitude has no GAP anywhere', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(), storedGap: '4:40'),
        runnerName: 'x',
      );
      expect(a.avgGapPace, isNull);
      expect(a.gap, isNull);
      expect(a.splits.every((s) => s.gapPaceSeconds == null), isTrue);
    });

    test('all-zero altitude (unavailable) has no GAP', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: (_) => 0.0)),
        runnerName: 'x',
      );
      expect(a.avgGapPace, isNull);
    });
  });

  group('per-km GAP', () {
    test(
      'a flat km matches its pace; a climbing km is faster than its pace',
      () {
        final a = ActivityDetail.fromRunRecord(
          _run(
            _samples(alt: _climbSecondKm, secondKmPace: 400),
            secondKmPace: 400,
          ),
          runnerName: 'x',
        );
        final km1 = a.splits[0];
        final km2 = a.splits[1];
        expect(km1.paceSeconds, 300);
        expect(
          (km1.gapPaceSeconds! - 300).abs(),
          lessThan(15),
        ); // hill starts at km 2
        expect(km2.paceSeconds, 400);
        expect(km2.gapPaceSeconds!, lessThan(400 - 40));
      },
    );

    test('flat splits get GAP exactly equal to their pace', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: _flat)),
        runnerName: 'x',
      );
      expect(a.splits.map((s) => s.gapPaceSeconds), [300, 300]);
      expect(a.splits.first.gapPaceLabel, '5:00');
    });

    test('a split without enough valid coverage gets null, not a guess', () {
      // Samples stop at 1000 m; the finish closes a 1000 m / 300 s stretch,
      // which is a >60 s gap and is skipped, so km 2 has no coverage.
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: _flat, upToM: 1000)),
        runnerName: 'x',
      );
      expect(a.splits[0].gapPaceSeconds, 300);
      expect(a.splits[1].gapPaceSeconds, isNull);
    });

    test('the trailing partial km gets GAP when covered', () {
      // 1.5 km run: one full split plus a 0.5 km partial.
      final samples = _samples(alt: _flat, upToM: 1500);
      final a = ActivityDetail.fromRunRecord(
        RunRecord(
          date: DateTime(2026, 9, 20, 7),
          distanceKm: 1.5,
          averagePace: '5:00',
          durationSeconds: 450,
          routePolyline: '',
          splits: const [
            {'km': 1, 'seconds': 300},
          ],
          trackSamples: samples,
        ),
        runnerName: 'x',
      );
      expect(a.splits, hasLength(2));
      expect(a.splits[1].isPartial, isTrue);
      expect(a.splits[1].gapPaceSeconds, 300);
    });

    test('mile mode carries GAP in per-mile units', () {
      final a = ActivityDetail.fromRunRecord(
        _run(_samples(alt: _climbAll)),
        runnerName: 'x',
      );
      final miles = a.splitsForDisplay(useMiles: true);
      expect(miles, isNotEmpty);
      final first = miles.first;
      expect(first.gapPaceSeconds, isNotNull);
      // Uphill: faster than the same mile's pace, in sec/mile.
      expect(first.gapPaceSeconds!, lessThan(first.paceSeconds));
      expect(first.paceSeconds, closeTo(300 * 1.609344, 2));
    });

    test('mile mode without GAP data leaves GAP null', () {
      final a = ActivityDetail.fromRunRecord(_run(_samples()), runnerName: 'x');
      final miles = a.splitsForDisplay(useMiles: true);
      expect(miles.every((s) => s.gapPaceSeconds == null), isTrue);
    });

    test('km fallback conversion scales GAP to per-mile too', () {
      // Without a fine-grained trace, splitsForDisplay converts the km
      // buckets in place; GAP must be converted with them.
      final km = KmSplit(km: 1, paceSeconds: 300, gapPaceSeconds: 280);
      final detail = ActivityDetail(
        runnerName: 'x',
        timestamp: DateTime(2026, 9, 20),
        source: 'Endura Tracker',
        location: '',
        title: 't',
        distanceKm: 1,
        avgPace: '5:00',
        movingTime: const Duration(minutes: 5),
        splits: [km],
        telemetrySeries: const [],
        hrZones: const [],
      );
      final miles = detail.splitsForDisplay(useMiles: true);
      expect(miles.single.gapPaceSeconds, (280 * 1.609344).round());
    });
  });

  group('KmSplit', () {
    test('copyWith keeps the GAP and label formats m:ss', () {
      const s = KmSplit(km: 1, paceSeconds: 300, gapPaceSeconds: 275);
      final c = s.copyWith(paceSeconds: 310);
      expect(c.gapPaceSeconds, 275);
      expect(c.gapPaceLabel, '4:35');
      expect(const KmSplit(km: 1, paceSeconds: 300).gapPaceLabel, isNull);
    });
  });
}
