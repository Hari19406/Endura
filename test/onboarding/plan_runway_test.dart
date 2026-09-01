import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/plan_runway.dart';

PlanRunway _r(String goal, int weeks) =>
    PlanRunway.resolve(goal: goal, weeksAvailable: weeks);

void main() {
  group('regimes', () {
    test('too little time is a fast-track build', () {
      final r = _r('marathon', 9);
      expect(r.regime, RunwayRegime.short);
      expect(r.verdict, 'Fast-track training');
      expect(r.foundationWeeks, 0);
    });

    test('the right amount is endorsed', () {
      final r = _r('marathon', 16);
      expect(r.regime, RunwayRegime.matched);
      expect(r.verdict, 'Recommended for optimal performance');
      expect(r.warningFor('marathon'), isNull);
    });

    test('surplus becomes a base phase rather than a wait', () {
      final r = _r('marathon', 20);
      expect(r.regime, RunwayRegime.surplus);
      expect(r.foundationWeeks, 4);
      expect(r.verdict, contains('base phase'));
      expect(r.warningFor('marathon'), isNull);
    });

    test('a couple of spare weeks still counts as matched', () {
      // Not worth inventing a one-week foundation block.
      expect(_r('marathon', 17).regime, RunwayRegime.matched);
      expect(_r('marathon', 18).regime, RunwayRegime.matched);
      expect(_r('marathon', 19).regime, RunwayRegime.surplus);
    });
  });

  group('per-distance thresholds', () {
    test('shorter races need less runway', () {
      expect(
        PlanRunway.recommendedFor('5k'),
        lessThan(PlanRunway.recommendedFor('half_marathon')),
      );
      expect(
        PlanRunway.recommendedFor('half_marathon'),
        lessThan(PlanRunway.recommendedFor('marathon')),
      );
    });

    test('12 weeks is plenty for a 5K but tight for a marathon', () {
      expect(_r('5k', 12).regime, RunwayRegime.surplus);
      expect(_r('marathon', 12).regime, RunwayRegime.short);
    });
  });

  group('short-notice interception', () {
    test('fires only below the minimum viable build', () {
      expect(_r('marathon', 5).isShortNotice, isTrue);
      expect(_r('marathon', 7).isShortNotice, isTrue);
      expect(_r('marathon', 8).isShortNotice, isFalse);
    });

    test('a compressed-but-viable plan is not intercepted', () {
      // 10 weeks for a marathon is short — warned about, but not blocked at
      // the picker. Interception is reserved for genuinely too close.
      final r = _r('marathon', 10);
      expect(r.regime, RunwayRegime.short);
      expect(r.isShortNotice, isFalse);
    });

    test('a 5K three weeks out is intercepted', () {
      expect(_r('5k', 3).isShortNotice, isTrue);
      expect(_r('5k', 4).isShortNotice, isFalse);
    });
  });

  group('warning copy', () {
    test('names the recommended length and the actual one', () {
      final warning = _r('marathon', 9).warningFor('marathon');
      expect(warning, isNotNull);
      expect(warning, contains('16+ weeks'));
      expect(warning, contains('9 weeks'));
      expect(warning, contains('marathon'));
    });

    test('is absent whenever the runway is adequate', () {
      expect(_r('marathon', 16).warningFor('marathon'), isNull);
      expect(_r('marathon', 24).warningFor('marathon'), isNull);
      expect(_r('5k', 8).warningFor('5k'), isNull);
    });
  });
}
