/// Phase 2 — HardDayPlanner constraint solver.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/plan/hard_day_planner.dart';
import 'package:run_app/models/training_phase.dart';

void main() {
  const planner = HardDayPlanner();

  HardDayPlacement place(
    List<int> days,
    int lr,
    int q, {
    TrainingPhase phase = TrainingPhase.build,
  }) => planner.placeHardDays(
    trainingDayIndices: days,
    longRunDayIndex: lr,
    qualityCount: q,
    phase: phase,
  );

  bool adjacent(int a, int b) {
    final d = (a - b).abs();
    return d == 1 || d == 6;
  }

  test('no quality day is adjacent to another quality day or the long run', () {
    final combos = [
      ([0, 2, 4, 6], 6),
      ([0, 1, 2, 3, 4], 4),
      ([1, 3, 5, 6], 6),
      ([0, 1, 3, 5, 6], 6),
      ([0, 2, 3, 4, 5, 6], 6),
      ([1, 2, 3, 4, 5], 3),
    ];
    for (final (days, lr) in combos) {
      for (final q in [1, 2]) {
        final p = place(days, lr, q);
        final qs = p.qualityDays;
        for (final qd in qs) {
          expect(adjacent(qd, p.longRunDay), isFalse,
              reason: 'days=$days lr=$lr q=$q → $qs adj LR');
        }
        if (qs.length == 2) {
          expect(adjacent(qs[0], qs[1]), isFalse,
              reason: 'days=$days lr=$lr q=$q → $qs Q-adjacent');
        }
      }
    }
  });

  test('evenly-spaced 5-day week matches the legacy Easy/Q1/Easy/Q2 layout', () {
    // Mon/Tue/Wed/Thu + long run Sun. Legacy _anchoredPattern (non-LR days by
    // cyclic offset from LR, ranks Easy/Q1/Easy/Q2) → Q1=Tue, Q2=Thu.
    final p = place([0, 1, 2, 3, 6], 6, 2);
    expect(p.longRunDay, 6);
    expect(p.roles[1], HardDayRole.quality1);
    expect(p.roles[3], HardDayRole.quality2);
    expect(p.easyDays, [0, 2]);
  });

  test('Q1 is the first quality day after the long run cyclically', () {
    final p = place([1, 2, 3, 4, 5], 3, 2); // LR Thu
    final q1 = p.roles.entries
        .firstWhere((e) => e.value == HardDayRole.quality1)
        .key;
    final q2 = p.roles.entries
        .firstWhere((e) => e.value == HardDayRole.quality2)
        .key;
    int cyc(int d) => (d - 3 + 7) % 7;
    expect(cyc(q1), lessThan(cyc(q2)));
  });

  test('clustered weekdays: cannot separate two hard days → drops Q2', () {
    // Mon/Tue/Wed + long run Sun. Any two of Mon/Tue/Wed are adjacent.
    final p = place([0, 1, 2, 6], 6, 2);
    expect(p.resolvedQualityCount, 1);
    expect(p.droppedQuality, isTrue);
    expect(adjacent(p.qualityDays.single, 6), isFalse);
  });

  test('deterministic — same inputs give the same placement', () {
    final a = place([0, 1, 2, 3, 4, 5], 5, 2);
    final b = place([0, 1, 2, 3, 4, 5], 5, 2);
    expect(a.roles, b.roles);
  });

  test('qualityCount 0 → every non-LR day easy', () {
    final p = place([0, 2, 4, 6], 6, 0);
    expect(p.qualityDays, isEmpty);
    expect(p.easyDays, [0, 2, 4]);
    expect(p.roles[6], HardDayRole.longRun);
  });

  test('long-run day falls back to last training day when not a training day',
      () {
    final p = place([0, 2, 4], 5, 1); // 5 not trained
    expect(p.longRunDay, 4);
  });

  test('every training day gets exactly one role', () {
    final days = [0, 1, 3, 4, 6];
    final p = place(days, 6, 2);
    expect(p.roles.keys.toSet(), days.toSet());
    expect(p.roles.length, days.length);
  });

  group('qualityCountFor', () {
    test('build ≥5 days → 2, else 1', () {
      expect(
        HardDayPlanner.qualityCountFor(
          trainingDays: 5,
          phase: TrainingPhase.build,
        ),
        2,
      );
      expect(
        HardDayPlanner.qualityCountFor(
          trainingDays: 4,
          phase: TrainingPhase.build,
        ),
        1,
      );
    });

    test('taper always 1; cutback caps at 1', () {
      expect(
        HardDayPlanner.qualityCountFor(
          trainingDays: 6,
          phase: TrainingPhase.taper,
        ),
        1,
      );
      expect(
        HardDayPlanner.qualityCountFor(
          trainingDays: 6,
          phase: TrainingPhase.peak,
          isCutback: true,
        ),
        1,
      );
    });

    test('base → 1 for every day count (beginner intent stays threshold)', () {
      for (final d in [3, 4, 5, 6]) {
        expect(
          HardDayPlanner.qualityCountFor(
            trainingDays: d,
            phase: TrainingPhase.base,
          ),
          1,
        );
      }
    });
  });
}
