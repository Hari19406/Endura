/// Phase 1 — ArchetypeTable.allocate (bounded allocation v3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/models/training_phase.dart';

void main() {
  const races = RaceDistance.values;
  const phases = [
    TrainingPhase.base,
    TrainingPhase.build,
    TrainingPhase.peak,
    TrainingPhase.taper,
  ];
  const experiences = ExperienceLevel.values;

  ArchetypeWeek build(
    double wk,
    int days,
    int q,
    TrainingPhase phase,
    RaceDistance race, {
    ExperienceLevel exp = ExperienceLevel.intermediate,
    double? lrTarget,
    bool ml = false,
  }) => ArchetypeTable.allocate(
    effectiveKm: wk,
    days: days,
    qualityCount: q,
    experience: exp,
    phase: phase,
    raceDistance: race,
    longRunKmTarget: lrTarget,
    allowMediumLong: ml,
  );

  test('sum stays within tolerance across the realistic matrix', () {
    for (final race in races) {
      for (final phase in phases) {
        for (final exp in experiences) {
          for (var days = 3; days <= 7; days++) {
            for (final wk in [25.0, 32.0, 45.0, 60.0, 80.0, 110.0, 130.0]) {
              // Realistic quality count for the week size — the engine never
              // asks for 2 quality sessions on a sub-viable week.
              final q = wk >= 40 ? 2 : (wk >= 25 ? 1 : 0);
              final w = build(wk, days, q, phase, race, exp: exp, ml: true);
              final tol = ArchetypeTable.allocationTolerance(wk);
              expect(
                (w.totalKm - wk).abs(),
                lessThanOrEqualTo(tol + 0.001),
                reason:
                    'race=$race phase=$phase exp=$exp days=$days wk=$wk q=$q '
                    '→ total=${w.totalKm}',
              );
            }
          }
        }
      }
    }
  });

  test('below min-viable (floors exceed the week) overshoots only by the '
      'floor deficit, never wildly', () {
    // 20 km / 4 days / 2 quality: floors sum to 4+5+5+8 = 22. Unavoidable +2.
    final w = build(20, 4, 2, TrainingPhase.build, RaceDistance.fiveK);
    final floorSum = w.sessions.fold(0.0, (s, x) => s + x.floorKm);
    expect(w.totalKm, greaterThanOrEqualTo(20));
    expect(w.totalKm, lessThanOrEqualTo(floorSum + 0.5));
  });

  test('long run stays within its phase/race bounds', () {
    for (final race in races) {
      for (final phase in phases) {
        for (var days = 3; days <= 6; days++) {
          for (final wk in [30.0, 50.0, 90.0]) {
            final w = build(wk, days, 1, phase, race);
            final lr = w.sessions.firstWhere((s) => s.type.isLong);
            // Never more than 55% of the week, never below its 8 km floor.
            expect(lr.effectiveKm, greaterThanOrEqualTo(8.0));
            expect(
              lr.effectiveKm / wk,
              lessThanOrEqualTo(0.56),
              reason: 'race=$race phase=$phase days=$days wk=$wk lr=${lr.km}',
            );
          }
        }
      }
    }
  });

  test('honours the skeleton long-run target when it is in-bounds', () {
    final w = build(60, 5, 2, TrainingPhase.build, RaceDistance.marathon,
        lrTarget: 20);
    final lr = w.sessions.firstWhere((s) => s.type.isLong);
    expect(lr.km, closeTo(20, 2.0));
  });

  test('quality km rises base → build → peak', () {
    double qkm(TrainingPhase p) {
      final w = build(60, 5, 1, p, RaceDistance.tenK);
      return w.sessions.firstWhere((s) => s.type.isQuality).effectiveKm;
    }

    expect(qkm(TrainingPhase.base), lessThan(qkm(TrainingPhase.build)));
    expect(qkm(TrainingPhase.build), lessThanOrEqualTo(qkm(TrainingPhase.peak)));
  });

  test('quality count is honoured; taper caps at 1', () {
    expect(
      build(50, 6, 2, TrainingPhase.build, RaceDistance.halfMarathon)
          .qualityCount,
      2,
    );
    expect(
      build(50, 6, 0, TrainingPhase.base, RaceDistance.fiveK).qualityCount,
      0,
    );
    expect(
      build(50, 6, 2, TrainingPhase.taper, RaceDistance.marathon).qualityCount,
      1,
    );
  });

  test('medium-long appears only for HM/FM, 5+ days, non-taper, when allowed',
      () {
    expect(
      build(70, 6, 2, TrainingPhase.build, RaceDistance.marathon, ml: true)
          .hasMediumLong,
      isTrue,
    );
    expect(
      build(70, 6, 2, TrainingPhase.build, RaceDistance.marathon, ml: false)
          .hasMediumLong,
      isFalse,
    );
    expect(
      build(70, 4, 2, TrainingPhase.build, RaceDistance.marathon, ml: true)
          .hasMediumLong,
      isFalse,
    );
    expect(
      build(40, 5, 1, TrainingPhase.build, RaceDistance.fiveK, ml: true)
          .hasMediumLong,
      isFalse,
    );
    expect(
      build(70, 6, 1, TrainingPhase.taper, RaceDistance.marathon, ml: true)
          .hasMediumLong,
      isFalse,
    );
  });

  test('session count == training days', () {
    for (var days = 3; days <= 7; days++) {
      final w = build(55, days, days >= 5 ? 2 : 1, TrainingPhase.build,
          RaceDistance.halfMarathon, ml: true);
      expect(w.sessionCount, days, reason: 'days=$days');
      expect(w.hasLongRun, isTrue);
    }
  });

  test('no session below its floor; floors do not blow the weekly total', () {
    final w = build(24, 5, 2, TrainingPhase.build, RaceDistance.fiveK);
    for (final s in w.sessions) {
      expect(s.km, greaterThanOrEqualTo(s.floorKm - 0.001));
    }
    // 24 km / 5 days with 2 quality is floor-tight but must not overshoot wildly.
    expect(w.totalKm, lessThanOrEqualTo(24 + 3.0));
  });

  test('zero / negative week returns empty', () {
    expect(build(0, 5, 2, TrainingPhase.build, RaceDistance.tenK).sessions,
        isEmpty);
  });
}
