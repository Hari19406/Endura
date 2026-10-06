import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/athlete_physiology.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 10, 6);
  // Exactly 30 years old on [now] -> 208 - 0.7 * 30 = 187.
  final dob30 = DateTime(1996, 10, 6);

  group('AthletePhysiology.resolve - priority order', () {
    test('user-set wins over everything', () {
      final r = AthletePhysiology.resolve(
        userSet: 195,
        dob: dob30,
        observedPeak: 201,
        now: now,
      );
      expect(r, const MaxHrResolution(195, MaxHrSource.userSet));
      expect(r.caption, 'Max HR: 195 bpm · User set');
    });

    test('age formula is next: 208 - 0.7 x age, not 220 - age', () {
      final r = AthletePhysiology.resolve(
        dob: dob30,
        observedPeak: 201,
        now: now,
      );
      expect(r, const MaxHrResolution(187, MaxHrSource.ageFormula));
      expect(r.bpm, isNot(190)); // 220 - 30
    });

    test('observed peak is used without a DOB', () {
      final r = AthletePhysiology.resolve(observedPeak: 192, now: now);
      expect(r, const MaxHrResolution(192, MaxHrSource.observed));
    });

    test('falls back to 190', () {
      final r = AthletePhysiology.resolve(now: now);
      expect(r, const MaxHrResolution(190, MaxHrSource.fallback));
      expect(r.caption, 'Max HR: 190 bpm · Default');
    });
  });

  group('AthletePhysiology.resolve - validation falls through', () {
    test('implausible user-set value is ignored', () {
      expect(
        AthletePhysiology.resolve(userSet: 90, dob: dob30, now: now).source,
        MaxHrSource.ageFormula,
      );
      expect(
        AthletePhysiology.resolve(userSet: 250, now: now).source,
        MaxHrSource.fallback,
      );
    });

    test('implausible age (future DOB, or over 100) is ignored', () {
      expect(
        AthletePhysiology.resolve(
          dob: DateTime(2030, 1, 1),
          observedPeak: 180,
          now: now,
        ).source,
        MaxHrSource.observed,
      );
      expect(
        AthletePhysiology.resolve(dob: DateTime(1900, 1, 1), now: now).source,
        MaxHrSource.fallback,
      );
    });

    test('a peak below 120 is not treated as a max HR', () {
      expect(AthletePhysiology.resolve(observedPeak: 150, now: now).bpm, 150);
      expect(
        AthletePhysiology.resolve(observedPeak: 110, now: now).source,
        MaxHrSource.fallback,
      );
    });

    test('age is whole years: a later birthday is not yet counted', () {
      // Born 1996-12-01 -> still 29 on 2026-10-06 -> 208 - 20.3 = 188.
      final r = AthletePhysiology.resolve(dob: DateTime(1996, 12, 1), now: now);
      expect(r.bpm, 188);
    });
  });

  group('AthletePhysiology (prefs + observed peak)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('stored user value wins and skips the observed lookup', () async {
      SharedPreferences.setMockInitialValues({
        'max_hr': 196,
        'dob': dob30.toIso8601String(),
      });
      var lookups = 0;
      final p = AthletePhysiology(
        observedPeakLoader: () async {
          lookups++;
          return 200;
        },
      );
      final r = await p.resolveMaxHr(now: now);
      expect(r, const MaxHrResolution(196, MaxHrSource.userSet));
      expect(lookups, 0);
    });

    test('stored DOB is used when no user value is set', () async {
      SharedPreferences.setMockInitialValues({'dob': dob30.toIso8601String()});
      final p = AthletePhysiology(observedPeakLoader: () async => 200);
      final r = await p.resolveMaxHr(now: now);
      expect(r, const MaxHrResolution(187, MaxHrSource.ageFormula));
    });

    test('observed peak is used with no user value and no DOB', () async {
      final p = AthletePhysiology(observedPeakLoader: () async => 193);
      final r = await p.resolveMaxHr(now: now);
      expect(r, const MaxHrResolution(193, MaxHrSource.observed));
    });

    test(
      'default when nothing is known; a failing loader is tolerated',
      () async {
        final p = AthletePhysiology(
          observedPeakLoader: () async => throw StateError('db down'),
        );
        final r = await p.resolveMaxHr(now: now);
        expect(r, MaxHrResolution.fallback);
      },
    );

    test('setUserMaxHr persists, validates, and clears', () async {
      final p = AthletePhysiology(observedPeakLoader: () async => null);

      expect(await p.setUserMaxHr(60), isFalse);
      expect(await p.loadUserMaxHr(), isNull);

      expect(await p.setUserMaxHr(198), isTrue);
      expect(await p.loadUserMaxHr(), 198);
      expect((await p.resolveMaxHr(now: now)).source, MaxHrSource.userSet);

      expect(await p.setUserMaxHr(null), isTrue);
      expect(await p.loadUserMaxHr(), isNull);
      expect((await p.resolveMaxHr(now: now)).source, MaxHrSource.fallback);
    });
  });
}
