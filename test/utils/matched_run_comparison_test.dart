import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/matched_run_comparison.dart';

MatchedRunSummary _run({
  int? id,
  DateTime? date,
  double km = 5.0,
  int seconds = 1500,
  int? pace = 300,
  Map<int, int> splits = const {},
  int? hr,
  double? elev,
  int? gap,
}) => MatchedRunSummary(
  id: id,
  date: date ?? DateTime(2026, 10, 1),
  distanceKm: km,
  durationSeconds: seconds,
  paceSecPerKm: pace,
  splitSeconds: splits,
  avgHr: hr,
  elevationGainM: elev,
  gapSecPerKm: gap,
);

void main() {
  group('MatchedRunComparison.between', () {
    test('time and pace deltas are today minus other (negative = faster)', () {
      final c = MatchedRunComparison.between(
        _run(seconds: 1452, pace: 290),
        _run(seconds: 1500, pace: 300),
      );
      expect(c.timeDeltaSeconds, -48);
      expect(c.paceDeltaSecPerKm, -10);
      expect(c.timeIsLikeForLike, isTrue);
    });

    test('distance difference only appears above 2%', () {
      final within = MatchedRunComparison.between(_run(km: 5.05), _run());
      expect(within.distanceDiffKm, isNull);
      final beyond = MatchedRunComparison.between(_run(km: 5.2), _run());
      expect(beyond.distanceDiffKm, closeTo(0.2, 1e-9));
      expect(beyond.timeIsLikeForLike, isFalse);
    });

    test('split deltas cover only kilometres both runs have', () {
      final c = MatchedRunComparison.between(
        _run(splits: {1: 295, 2: 300, 3: 310, 4: 305}),
        _run(splits: {1: 300, 2: 300, 3: 300}),
      );
      expect([for (final s in c.splitDeltas) (s.km, s.deltaSeconds)], [
        (1, -5),
        (2, 0),
        (3, 10),
      ]);
    });

    test('HR delta only when both runs have HR', () {
      expect(
        MatchedRunComparison.between(_run(hr: 150), _run(hr: 156)).hrDelta,
        -6,
      );
      expect(
        MatchedRunComparison.between(_run(hr: 150), _run()).hrDelta,
        isNull,
      );
      expect(
        MatchedRunComparison.between(_run(), _run(hr: 150)).hrDelta,
        isNull,
      );
    });

    test('GAP delta only when both runs have valid GAP', () {
      expect(
        MatchedRunComparison.between(
          _run(gap: 290),
          _run(gap: 300),
        ).gapDeltaSecPerKm,
        -10,
      );
      expect(
        MatchedRunComparison.between(_run(gap: 290), _run()).gapDeltaSecPerKm,
        isNull,
      );
      expect(
        MatchedRunComparison.between(_run(), _run(gap: 300)).gapDeltaSecPerKm,
        isNull,
      );
    });

    test('elevation delta only when both runs have elevation', () {
      expect(
        MatchedRunComparison.between(
          _run(elev: 80),
          _run(elev: 60),
        ).elevationDeltaM,
        20,
      );
      expect(
        MatchedRunComparison.between(_run(elev: 80), _run()).elevationDeltaM,
        isNull,
      );
    });

    test('missing pace yields no pace delta but keeps the time delta', () {
      final c = MatchedRunComparison.between(
        _run(pace: null, seconds: 1400),
        _run(),
      );
      expect(c.paceDeltaSecPerKm, isNull);
      expect(c.timeDeltaSeconds, -100);
    });
  });

  group('MatchedRunsResult.build', () {
    final today = _run(date: DateTime(2026, 10, 7), seconds: 1450, pace: 290);

    test('no matches gives null', () {
      expect(MatchedRunsResult.build(today, const []), isNull);
    });

    test('picks the latest earlier run as previous and the fastest as best', () {
      final result = MatchedRunsResult.build(today, [
        _run(id: 1, date: DateTime(2026, 9, 1), pace: 280, seconds: 1400),
        _run(id: 2, date: DateTime(2026, 9, 20), pace: 310, seconds: 1550),
        _run(id: 3, date: DateTime(2026, 9, 10), pace: 300, seconds: 1500),
      ])!;
      expect(result.matchCount, 3);
      expect(result.previousCount, 3);
      expect(result.previous!.other.id, 2);
      expect(result.best!.other.id, 1);
      expect(result.previousIsBest, isFalse);
    });

    test('runs after today are matches but never "previous"', () {
      final result = MatchedRunsResult.build(today, [
        _run(id: 1, date: DateTime(2026, 11, 1)),
      ])!;
      expect(result.matchCount, 1);
      expect(result.previousCount, 0);
      expect(result.previous, isNull);
      expect(result.best!.other.id, 1);
    });

    test('previous can also be best', () {
      final result = MatchedRunsResult.build(today, [
        _run(id: 1, date: DateTime(2026, 9, 1), pace: 310),
        _run(id: 2, date: DateTime(2026, 9, 20), pace: 285),
      ])!;
      expect(result.previousIsBest, isTrue);
    });
  });

  test('formatMatchedDuration', () {
    expect(formatMatchedDuration(48), '0:48');
    expect(formatMatchedDuration(-125), '2:05');
    expect(formatMatchedDuration(3725), '1:02:05');
  });
}
