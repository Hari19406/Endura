import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/race_time_defaults.dart';

void main() {
  group('untouched race-time placeholder', () {
    int secs(String d) {
      final t = defaultRaceTimeFor(d);
      return t.hours * 3600 + t.minutes * 60 + t.seconds;
    }

    test('exact per-distance defaults in seconds', () {
      expect(secs('5k'), 1800); // 00h 30m 00s
      expect(secs('10k'), 3720); // 01h 02m 00s
      expect(secs('half'), 8280); // 02h 18m 00s
      expect(secs('marathon'), 17100); // 04h 45m 00s
      // never the 43-minute value seen on device
      for (final d in const ['5k', '10k', 'half', 'marathon']) {
        expect(secs(d), isNot(2580), reason: d);
        expect(defaultRaceTimeFor(d).minutes, isNot(43), reason: d);
      }
    });

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
