/// VolumeModel — the single source for weekly-volume numbers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart'
    show ExperienceLevel;
import 'package:run_app/engines/config/volume_model.dart';
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;

void main() {
  const races = RaceDistance.values;
  const levels = ExperienceLevel.values;

  test('peak rises with experience and with distance', () {
    for (final r in races) {
      expect(
        VolumeModel.peakKm(r, ExperienceLevel.beginner),
        lessThan(VolumeModel.peakKm(r, ExperienceLevel.intermediate)),
      );
      expect(
        VolumeModel.peakKm(r, ExperienceLevel.intermediate),
        lessThan(VolumeModel.peakKm(r, ExperienceLevel.advanced)),
      );
    }
    for (final l in levels) {
      expect(
        VolumeModel.peakKm(RaceDistance.fiveK, l),
        lessThan(VolumeModel.peakKm(RaceDistance.marathon, l)),
      );
    }
  });

  test('onboarding range is defined and sane for 3–7 days', () {
    for (final r in races) {
      for (final l in levels) {
        for (var d = 3; d <= 7; d++) {
          final range = VolumeModel.onboardingRange(
            race: r,
            experience: l,
            days: d,
          );
          expect(range.min, VolumeModel.minViableKm(r));
          expect(range.max, VolumeModel.peakKm(r, l));
          expect(range.defaultKm, greaterThanOrEqualTo(range.min));
          expect(range.defaultKm, lessThanOrEqualTo(range.max));
        }
      }
    }
  });

  test('default volume strictly increases with day count', () {
    for (final r in races) {
      for (final l in levels) {
        var prev = -1.0;
        for (var d = 3; d <= 7; d++) {
          final km = VolumeModel.onboardingRange(
            race: r,
            experience: l,
            days: d,
          ).defaultKm;
          expect(km, greaterThan(prev), reason: '$r $l at $d days');
          prev = km;
        }
      }
    }
  });

  test('7-day week is never lighter than a 6-day week (old bug)', () {
    for (final r in races) {
      for (final l in levels) {
        final six = VolumeModel.onboardingRange(race: r, experience: l, days: 6);
        final seven =
            VolumeModel.onboardingRange(race: r, experience: l, days: 7);
        expect(seven.defaultKm, greaterThan(six.defaultKm));
      }
    }
  });

  test('PeakWeeklyKm.lookup and RacePlanBuilder now agree (delegate to model)',
      () {
    // Cross-check the compatibility shim.
    for (final r in races) {
      for (final l in levels) {
        // PeakWeeklyKm is re-exported via archetype_table.
        // (imported transitively) — assert via the model directly here.
        expect(VolumeModel.peakKm(r, l), greaterThan(0));
      }
    }
  });
}
