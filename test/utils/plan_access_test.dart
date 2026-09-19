import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/plan_access.dart';

void main() {
  test('weeks 1-2 are free, week 3+ locked for non-subscribers', () {
    expect(isPlanWeekLocked(weekNumber: 1, isPro: false), isFalse);
    expect(isPlanWeekLocked(weekNumber: 2, isPro: false), isFalse);
    expect(isPlanWeekLocked(weekNumber: 3, isPro: false), isTrue);
    expect(isPlanWeekLocked(weekNumber: 12, isPro: false), isTrue);
  });

  test('subscribers are never locked', () {
    for (final w in [1, 2, 3, 20]) {
      expect(isPlanWeekLocked(weekNumber: w, isPro: true), isFalse);
    }
  });
}
