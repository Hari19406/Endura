/// Phase 5 — PlanMaterializer: skeleton → full MaterializedPlan.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_materializer.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/race_plan.dart';
import 'package:run_app/models/training_phase.dart';

void main() {
  final now = DateTime(2026, 3, 2); // a Monday
  RacePlan skeleton({
    String race = 'half_marathon',
    double km = 45,
    String exp = 'intermediate',
    int weeks = 12,
  }) => RacePlanBuilder.build(
    currentWeeklyKm: km,
    goalRace: race,
    raceDate: now.add(Duration(days: weeks * 7)),
    experienceLevel: exp,
    now: now,
  );

  MaterializedPlan materialize(
    RacePlan s, {
    MaterializedPlan? previous,
    int vdot = 46,
  }) => const PlanMaterializer().materialize(
    skeleton: s,
    trainingDayIndices: const [0, 2, 4, 6], // Mon/Wed/Fri/Sun
    longRunDayIndex: 6,
    raceDistance: RaceDistance.halfMarathon,
    experienceLevel: ExperienceLevel.intermediate,
    vdot: vdot,
    inputsFingerprint: 'fp-1',
    previous: previous,
    now: now,
  );

  test('every skeleton week is materialised with resolved workouts', () {
    final s = skeleton();
    final plan = materialize(s);

    expect(plan.weeks.length, s.weeks.length);
    for (final w in plan.weeks) {
      expect(w.days.length, 7);
      for (final d in w.days.where((d) => !d.isRest)) {
        expect(d.templateId, isNotNull, reason: 'W${w.weekNumber} ${d.weekday}');
        expect(d.workout, isNotNull);
        expect(d.workout!.blocks, isNotEmpty);
        // Every non-RPE block carries a real pace band.
        for (final b in d.workout!.blocks) {
          if (!b.isRpeOnly) {
            expect(b.paceMinSecondsPerKm, greaterThan(0));
            expect(b.paceMaxSecondsPerKm, greaterThanOrEqualTo(b.paceMinSecondsPerKm));
          }
        }
      }
    }
  });

  test('plan carries ladder + sessionProgress state', () {
    final plan = materialize(skeleton());
    expect(plan.ladderState, isNotEmpty);
    // threshold / vo2max ladders advance across a 12-week HM plan.
    expect(plan.ladderState.keys, contains('threshold'));
  });

  test('weekly planned volume tracks the resolved target', () {
    final plan = materialize(skeleton());
    for (final w in plan.weeks) {
      final tol = w.targetKm * 0.15 + 3; // resolver tol + block rounding
      expect(
        (w.plannedKm - w.targetKm).abs(),
        lessThanOrEqualTo(tol),
        reason: 'W${w.weekNumber} planned=${w.plannedKm} target=${w.targetKm}',
      );
    }
  });

  test('materialisation is deterministic', () {
    final s = skeleton();
    final a = jsonEncode(materialize(s).toJson());
    final b = jsonEncode(materialize(s).toJson());
    expect(a, b);
  });

  test('frozen weeks from a previous plan are carried over untouched', () {
    final s = skeleton();
    final first = materialize(s);

    // Freeze week 1 with a marker completion.
    final w1 = first.weeks.first;
    final frozenW1 = w1.copyWith(
      isFrozen: true,
      days: [
        w1.days.first.copyWith(
          completion: DayCompletion(
            completedAt: now,
            actualKm: 12.3,
            runId: 'run-frozen',
          ),
        ),
        ...w1.days.skip(1),
      ],
    );
    final withFrozen = first.copyWith(
      weeks: [frozenW1, ...first.weeks.skip(1)],
    );

    final rebuilt = materialize(s, previous: withFrozen);

    // Week 1 identical to the frozen copy; later weeks re-resolved.
    expect(rebuilt.weeks.first.isFrozen, isTrue);
    expect(rebuilt.weeks.first.days.first.completion?.runId, 'run-frozen');
    expect(jsonEncode(rebuilt.weeks.first.toJson()),
        jsonEncode(frozenW1.toJson()));
    expect(rebuilt.planId, first.planId); // stable id
  });

  test('a lower vDOT bakes slower paces', () {
    final s = skeleton();
    int firstEasyPace(MaterializedPlan p) {
      for (final w in p.weeks) {
        for (final d in w.days) {
          if (d.slot == MaterializedSlot.easy && d.workout != null) {
            return d.workout!.blocks.first.paceMinSecondsPerKm;
          }
        }
      }
      return 0;
    }

    final fast = firstEasyPace(materialize(s, vdot: 55));
    final slow = firstEasyPace(materialize(s, vdot: 38));
    expect(slow, greaterThan(fast)); // more sec/km = slower
  });

  test('session progression: reps rise across weeks on the same threshold rung, '
      'then the rung advances', () {
    // 5-day intermediate 10K: threshold Q1 in base, one quality/week.
    final plan = const PlanMaterializer().materialize(
      skeleton: skeleton(race: '10k', km: 45, exp: 'intermediate', weeks: 14),
      trainingDayIndices: const [0, 2, 4, 6],
      longRunDayIndex: 6,
      raceDistance: RaceDistance.tenK,
      experienceLevel: ExperienceLevel.intermediate,
      vdot: 46,
      inputsFingerprint: 'fp',
      now: now,
    );

    // Walk the non-cutback quality days in order; group consecutive runs on the
    // same templateId and check reps are non-decreasing within a group and the
    // template changes between groups.
    final quality = <({int week, String tpl, int reps})>[];
    for (final w in plan.weeks) {
      if (w.isCutback) continue;
      for (final d in w.days) {
        if (d.slot != MaterializedSlot.quality1) continue;
        final main = d.workout!.blocks.firstWhere(
          (b) => b.type == BlockType.main && b.reps != null,
          orElse: () => d.workout!.blocks.first,
        );
        quality.add((week: w.weekNumber, tpl: d.templateId!, reps: main.reps ?? 0));
      }
    }

    expect(quality.length, greaterThan(4));

    // At least one rung shows a rep increase week-to-week.
    var sawRepRise = false;
    var sawTemplateChange = false;
    for (var i = 1; i < quality.length; i++) {
      if (quality[i].tpl == quality[i - 1].tpl) {
        if (quality[i].reps > quality[i - 1].reps) sawRepRise = true;
      } else {
        sawTemplateChange = true;
      }
    }
    expect(sawRepRise, isTrue, reason: 'reps never rose on a held rung: $quality');
    expect(sawTemplateChange, isTrue, reason: 'rung never advanced: $quality');
  });

  test('cutback weeks keep the medium-long run for HM (structural down week)',
      () {
    final plan = const PlanMaterializer().materialize(
      skeleton: skeleton(race: 'half_marathon', km: 55, exp: 'advanced'),
      trainingDayIndices: const [0, 2, 3, 5, 6],
      longRunDayIndex: 6,
      raceDistance: RaceDistance.halfMarathon,
      experienceLevel: ExperienceLevel.advanced,
      vdot: 50,
      inputsFingerprint: 'fp',
      now: now,
    );
    // Non-taper cutbacks only — taper weeks never carry a medium-long.
    final cutbacks = plan.weeks.where(
      (w) => w.isCutback && !w.isFrozen && w.phase != TrainingPhase.taper,
    );
    expect(cutbacks, isNotEmpty);
    for (final w in cutbacks) {
      expect(
        w.days.any((d) => d.slot == MaterializedSlot.mediumLong),
        isTrue,
        reason: 'W${w.weekNumber} cutback lost its medium-long',
      );
    }
  });

  test('taper weeks reduce volume below the preceding peak', () {
    final plan = materialize(skeleton());
    final peak = plan.weeks
        .where((w) => w.phase == TrainingPhase.peak)
        .map((w) => w.targetKm)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final taper = plan.weeks.where((w) => w.phase == TrainingPhase.taper);
    expect(taper, isNotEmpty);
    for (final w in taper) {
      expect(w.targetKm, lessThan(peak));
    }
  });
}
