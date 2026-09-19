import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/volume_guidance.dart';

VolumeGuidance _g({
  String goal = 'marathon',
  String experience = 'beginner',
  double baseline = 30,
  int selected = 4,
}) => VolumeGuidance.resolve(
  goal: goal,
  experienceBridged: experience,
  baselineWeeklyKm: baseline,
  selectedRuns: selected,
);

void main() {
  group('the safety gate', () {
    // The headline case. The funnel we studied offers this athlete 7 runs and a
    // 113 km/week peak with nothing in the way.
    test('a first marathon on a 10 km base is capped hard', () {
      final g = _g(goal: 'marathon', experience: 'beginner', baseline: 10);
      expect(g.maxRuns, kMinRunsPerWeek);
      expect(g.maxRuns, lessThan(kMaxRunsPerWeek));
    });

    test('an experienced marathoner on a real base is not capped', () {
      final g = _g(goal: 'marathon', experience: 'advanced', baseline: 65);
      expect(g.maxRuns, kMaxRunsPerWeek);
    });

    test('the ceiling rises with the athlete base', () {
      int maxFor(double baseline) => _g(
        goal: 'half_marathon',
        experience: 'intermediate',
        baseline: baseline,
      ).maxRuns;

      final low = maxFor(15);
      final mid = maxFor(35);
      final high = maxFor(60);

      expect(low, lessThanOrEqualTo(mid));
      expect(mid, lessThanOrEqualTo(high));
      expect(low, lessThan(high));
    });

    test('experience alone cannot unlock volume the base cannot support', () {
      // Same tiny base, opposite ends of the experience scale.
      final beginner = _g(
        goal: 'marathon',
        experience: 'beginner',
        baseline: 12,
      ).maxRuns;
      final advanced = _g(
        goal: 'marathon',
        experience: 'advanced',
        baseline: 12,
      ).maxRuns;
      expect(advanced, beginner);
    });

    test('never drops below the archetype floor', () {
      for (final goal in const ['5k', '10k', 'half_marathon', 'marathon']) {
        final g = _g(goal: goal, baseline: 1);
        expect(g.maxRuns, greaterThanOrEqualTo(kMinRunsPerWeek));
      }
    });

    test('an unknown base falls back to the experience ceiling', () {
      final g = _g(goal: '5k', experience: 'intermediate', baseline: 0);
      expect(g.maxRuns, greaterThanOrEqualTo(kMinRunsPerWeek));
      expect(g.recommendedRuns, greaterThanOrEqualTo(kMinRunsPerWeek));
    });
  });

  group('recommendation', () {
    test('always sits inside the selectable range', () {
      for (final goal in const ['5k', '10k', 'half_marathon', 'marathon']) {
        for (final base in const [0.0, 8.0, 25.0, 50.0, 90.0]) {
          final g = _g(goal: goal, baseline: base);
          expect(g.recommendedRuns, greaterThanOrEqualTo(kMinRunsPerWeek));
          expect(g.recommendedRuns, lessThanOrEqualTo(g.maxRuns));
        }
      }
    });
  });

  group('week composition', () {
    test('quality count comes from the archetype, not a heuristic', () {
      // The old rule was `runsPerWeek >= 5 ? 2 : 1`, which over-counts a
      // 5-day beginner — the archetype gives them one quality session.
      final beginner = _g(
        goal: 'half_marathon',
        experience: 'beginner',
        baseline: 45,
        selected: 5,
      );
      final advanced = _g(
        goal: 'half_marathon',
        experience: 'advanced',
        baseline: 45,
        selected: 5,
      );
      expect(beginner.qualitySessions, 1);
      expect(advanced.qualitySessions, 2);
    });

    test('range is a real band, low below high', () {
      final g = _g(goal: 'marathon', experience: 'advanced', baseline: 60);
      expect(g.loKm, lessThan(g.hiKm));
      expect(g.loKm, greaterThan(0));
    });
  });

  group('projected distance band tracks runs-per-week', () {
    VolumeGuidance at(int days) => _g(
      goal: 'half_marathon',
      experience: 'intermediate',
      baseline: 25,
      selected: days,
    );

    test('the band never inverts and both ends move up as days are added', () {
      var prevLo = 0;
      var prevHi = 0;
      for (var d = kMinRunsPerWeek; d <= kMaxRunsPerWeek; d++) {
        final g = at(d);
        expect(g.loKm, lessThan(g.hiKm), reason: '$d days');
        expect(g.loKm, greaterThanOrEqualTo(prevLo), reason: 'lo at $d days');
        expect(g.hiKm, greaterThanOrEqualTo(prevHi), reason: 'hi at $d days');
        prevLo = g.loKm;
        prevHi = g.hiKm;
      }
    });

    test('3 vs 5 vs 7 runs project meaningfully different volume', () {
      expect(at(5).loKm, greaterThan(at(3).loKm));
      expect(at(5).hiKm, greaterThan(at(3).hiKm));
      expect(at(7).hiKm, greaterThan(at(5).hiKm));
    });

    test('a higher current base lifts the floor for the same day count', () {
      int loFor(double base) => _g(
        goal: 'half_marathon',
        experience: 'intermediate',
        baseline: base,
        selected: 4,
      ).loKm;
      expect(loFor(45), greaterThan(loFor(15)));
    });
  });

  group('seven-day weeks', () {
    // Guards the workaround for the missing 7-day row: the raw engine table
    // returns the 4-day values for 7 days, which would make a 7-day week look
    // lighter than a 6-day one and invert the whole gate.
    test('carry more volume than six-day weeks', () {
      for (final goal in const ['5k', '10k', 'half_marathon', 'marathon']) {
        final six = VolumeGuidance.rangeFor(goal, 'intermediate', 6);
        final seven = VolumeGuidance.rangeFor(goal, 'intermediate', 7);
        expect(
          seven.defaultKm,
          greaterThan(six.defaultKm),
          reason: '$goal: 7-day week should exceed the 6-day week',
        );
      }
    });

    test('volume rises monotonically across the whole slider', () {
      for (final goal in const ['5k', '10k', 'half_marathon', 'marathon']) {
        var previous = 0.0;
        for (var d = kMinRunsPerWeek; d <= kMaxRunsPerWeek; d++) {
          final km = VolumeGuidance.rangeFor(goal, 'intermediate', d).defaultKm;
          expect(km, greaterThan(previous), reason: '$goal at $d days');
          previous = km;
        }
      }
    });
  });

  group('stretch warning', () {
    test('fires on a big jump and stays quiet on a sensible one', () {
      // 6 days of marathon training against a 20 km base is a leap.
      final leap = _g(
        goal: 'marathon',
        experience: 'advanced',
        baseline: 20,
        selected: 6,
      );
      final steady = _g(
        goal: 'marathon',
        experience: 'advanced',
        baseline: 60,
        selected: 5,
      );
      expect(leap.isStretch, isTrue);
      expect(steady.isStretch, isFalse);
    });

    test('stays quiet when the base is unknown', () {
      expect(_g(baseline: 0).isStretch, isFalse);
    });
  });

  group('RECOMMENDED badge ceiling', () {
    test('is never 7 days, whatever the base', () {
      for (final goal in const ['5k', '10k', 'half_marathon', 'marathon']) {
        for (final exp in const ['beginner', 'intermediate', 'advanced']) {
          for (final base in const [0.0, 15.0, 25.0, 40.0, 60.0, 75.0]) {
            final g = _g(goal: goal, experience: exp, baseline: base);
            expect(
              g.recommendedRuns,
              lessThan(kMaxRunsPerWeek),
              reason: '$goal/$exp/base=$base -> ${g.recommendedRuns}',
            );
          }
        }
      }
    });

    test('a 5K never recommends more than 4 days (5 for advanced)', () {
      for (final base in const [0.0, 15.0, 25.0, 40.0, 60.0, 75.0]) {
        expect(
          _g(goal: '5k', experience: 'beginner', baseline: base)
              .recommendedRuns,
          lessThanOrEqualTo(4),
        );
        expect(
          _g(goal: '5k', experience: 'intermediate', baseline: base)
              .recommendedRuns,
          lessThanOrEqualTo(4),
        );
        expect(
          _g(goal: '5k', experience: 'advanced', baseline: base)
              .recommendedRuns,
          lessThanOrEqualTo(5),
        );
      }
    });
  });
}
