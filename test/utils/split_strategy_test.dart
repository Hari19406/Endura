import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/utils/split_strategy.dart';

List<KmSplit> _splits(List<int> secondsPerKm, {double lastKm = 1.0}) => [
  for (var i = 0; i < secondsPerKm.length; i++)
    KmSplit(
      km: i + 1,
      paceSeconds: secondsPerKm[i],
      distanceKm: i == secondsPerKm.length - 1 ? lastKm : 1.0,
    ),
];

void main() {
  test('first/second half pace are means of the first and last half', () {
    final a = SplitStrategies.analyze(_splits([300, 300, 290, 290]))!;
    expect(a.firstHalfPace, 300);
    expect(a.secondHalfPace, 290);
    expect(a.differenceSecPerKm, -10);
    expect(a.fullKm, 4);
  });

  test('negative split', () {
    final a = SplitStrategies.analyze(_splits([300, 298, 292, 290]))!;
    expect(a.strategy, SplitStrategy.negative);
    expect(a.fade, isFalse);
  });

  test('even split inside the 1% / 3 s band', () {
    final a = SplitStrategies.analyze(_splits([300, 301, 300, 302]))!;
    expect(a.strategy, SplitStrategy.even);
    expect(a.fade, isFalse);
  });

  test('positive split without a fade', () {
    // +5 s on 300 s/km: slower than the even band, below the 3% fade line.
    final a = SplitStrategies.analyze(_splits([300, 300, 305, 305]))!;
    expect(a.strategy, SplitStrategy.positive);
    expect(a.fade, isFalse);
  });

  test('fade when the second half is 3% or more slower', () {
    final a = SplitStrategies.analyze(_splits([300, 300, 320, 320]))!;
    expect(a.strategy, SplitStrategy.positive);
    expect(a.fade, isTrue);
  });

  test('a faster second half is never a fade', () {
    final a = SplitStrategies.analyze(_splits([320, 320, 300, 300]))!;
    expect(a.fade, isFalse);
  });

  test('the trailing partial split is excluded', () {
    // Four full km plus a 0.4 km tail that is wildly slow.
    final withTail = _splits([300, 300, 290, 290, 600], lastKm: 0.4);
    final a = SplitStrategies.analyze(withTail)!;
    expect(a.fullKm, 4);
    expect(a.secondHalfPace, 290);
    expect(a.strategy, SplitStrategy.negative);
  });

  test('an odd number of km leaves the middle kilometre out', () {
    final a = SplitStrategies.analyze(_splits([300, 300, 999, 290, 290]))!;
    expect(a.firstHalfPace, 300);
    expect(a.secondHalfPace, 290);
  });

  test('fewer than 4 full km gives no analysis', () {
    expect(SplitStrategies.analyze(_splits([300, 290, 280])), isNull);
    // 3 full km + a partial is still only 3 full.
    expect(
      SplitStrategies.analyze(_splits([300, 290, 280, 290], lastKm: 0.5)),
      isNull,
    );
    expect(SplitStrategies.analyze(const []), isNull);
  });

  test('zero-pace splits are ignored', () {
    expect(SplitStrategies.analyze(_splits([300, 0, 290, 290])), isNull);
  });
}
