import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/race_time_defaults.dart';

void main() {
  group('untouched race-time placeholder', () {
    test('each distance has its own time, never a 25:00 placeholder', () {
      for (final d in const ['5k', '10k', 'half', 'marathon']) {
        final t = defaultRaceTimeFor(d);
        expect(t.hours * 60 + t.minutes, isNot(25), reason: d);
      }
      expect(defaultRaceTimeFor('5k').minutes, 30);
      expect(defaultRaceTimeFor('10k'), (hours: 1, minutes: 2, seconds: 0));
      expect(defaultRaceTimeFor('half'), (hours: 2, minutes: 18, seconds: 0));
      expect(
        defaultRaceTimeFor('marathon'),
        (hours: 4, minutes: 45, seconds: 0),
      );
    });

    test('fallback VDOT is conservative (~33–35) for every distance', () {
      for (final d in const ['5k', '10k', 'half', 'marathon']) {
        expect(fallbackVdotFor(d), inInclusiveRange(32, 35), reason: d);
        expect(fallbackVdotFor(d), lessThan(85));
      }
    });
  });
}
