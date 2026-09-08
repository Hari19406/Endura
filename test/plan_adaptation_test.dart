import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_adaptation.dart';
import 'package:run_app/models/plan_config_state.dart';
import 'package:run_app/models/training_phase.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

final _start = DateTime(2026, 1, 5); // Monday = week-1 start

ResolvedWorkout _wk(String id, WorkoutIntent intent, double km, {int pace = 300}) =>
    ResolvedWorkout(
      templateId: id,
      name: id,
      intent: intent,
      phase: TrainingPhase.build,
      blocks: [
        ResolvedBlock(
          type: BlockType.main,
          distanceKm: km,
          paceMinSecondsPerKm: pace,
          paceMaxSecondsPerKm: pace + 20,
        ),
      ],
    );

MaterializedDay _day(
  int wd,
  MaterializedSlot slot, {
  WorkoutIntent? intent,
  double km = 6,
  bool completed = false,
}) {
  final rest = slot == MaterializedSlot.rest;
  return MaterializedDay(
    weekday: wd,
    slot: slot,
    intent: rest ? null : (intent ?? WorkoutIntent.aerobicBase),
    templateId: rest ? null : 'tpl_$wd',
    workout: rest ? null : _wk('tpl_$wd', intent ?? WorkoutIntent.aerobicBase, km),
    completion: completed
        ? DayCompletion(completedAt: _start.add(Duration(days: wd)), actualKm: km)
        : null,
  );
}

MaterializedWeek _week(
  int n,
  List<MaterializedDay> days, {
  TrainingPhase phase = TrainingPhase.build,
  double targetKm = 40,
  bool frozen = false,
}) =>
    MaterializedWeek(
      weekNumber: n,
      phase: phase,
      targetKm: targetKm,
      isCutback: false,
      isFrozen: frozen,
      days: days,
    );

MaterializedPlan _plan(List<MaterializedWeek> weeks, {int vdot = 45}) =>
    MaterializedPlan(
      planId: 'p1',
      builtAt: _start,
      builtFromVdot: vdot,
      inputsFingerprint: 'fp',
      weeks: weeks,
    );

PlanConfigState _config({double vDOT = 45}) => PlanConfigState(
      goalType: PlanGoalType.half,
      experience: ExperienceLevel.intermediate,
      vDOT: vDOT,
      runsPerWeek: 5,
      weeklyVolumeRange: const RangeValues(35, 60),
      longRunRange: const RangeValues(12, 22),
      longRunDay: 6,
      availableDays: const {1, 2, 3, 5, 6},
      durationWeeks: 12,
    );

/// A typical 4-run week: Mon Q1, Wed easy, Fri easy, Sat long.
List<MaterializedDay> _fourRunDays({bool q1Done = false, bool longDone = false}) => [
      _day(0, MaterializedSlot.quality1,
          intent: WorkoutIntent.threshold, completed: q1Done),
      _day(1, MaterializedSlot.rest),
      _day(2, MaterializedSlot.easy),
      _day(3, MaterializedSlot.rest),
      _day(4, MaterializedSlot.easy),
      _day(5, MaterializedSlot.longRun,
          intent: WorkoutIntent.endurance, km: 16, completed: longDone),
      _day(6, MaterializedSlot.rest),
    ];

void main() {
  group('missed key session', () {
    test('shifts a missed quality to the next non-adjacent open day', () {
      final plan = _plan([_week(1, _fourRunDays())]);
      // Tuesday of week 1 — Monday's quality was not done.
      final res = PlanAdaptation.reconcile(
        plan: plan,
        history: const [],
        config: _config(),
        asOfDate: _start.add(const Duration(days: 1)),
      );

      expect(res.changed, isTrue);
      expect(res.applied.single.reason, 'missed_key_shifted');

      final w = res.plan.weekByNumber(1)!;
      expect(w.days[0].slot, MaterializedSlot.easy, reason: 'Mon demoted');
      final qDays = w.days.where((d) => d.slot.isQuality).map((d) => d.weekday);
      expect(qDays, [2], reason: 'quality moved to Wed');
      // hard/easy separation preserved (Wed quality, Sat long — 3 apart)
      bool hard(MaterializedSlot s) => s.isQuality || s.isLongRun;
      for (var i = 0; i + 1 < 7; i++) {
        expect(hard(w.days[i].slot) && hard(w.days[i + 1].slot), isFalse);
      }
    });

    test('drops a missed long run when the previous week is taper', () {
      final taperWeek = _week(
        1,
        [
          _day(0, MaterializedSlot.easy, completed: true),
          _day(1, MaterializedSlot.rest),
          _day(2, MaterializedSlot.quality1,
              intent: WorkoutIntent.threshold, completed: true),
          _day(3, MaterializedSlot.rest),
          _day(4, MaterializedSlot.easy, completed: true),
          _day(5, MaterializedSlot.longRun, intent: WorkoutIntent.endurance),
          _day(6, MaterializedSlot.rest),
        ],
        phase: TrainingPhase.taper,
      );
      final raceWeek = _week(2, _fourRunDays(), phase: TrainingPhase.taper);
      final plan = _plan([taperWeek, raceWeek]);

      final res = PlanAdaptation.reconcile(
        plan: plan,
        history: const [],
        config: _config(),
        asOfDate: _start.add(const Duration(days: 7)), // Monday, week 2
      );

      expect(res.applied.single.reason, 'missed_long_dropped_taper');
      final w2 = res.plan.weekByNumber(2)!;
      expect(w2.days.where((d) => d.slot.isLongRun).length, 1,
          reason: 'no extra long run carried into race week');
    });
  });

  group('volume drift', () {
    test('scales upcoming volume after two shortfall weeks', () {
      final w1 = _week(1, _fourRunDays(q1Done: true, longDone: true), targetKm: 50);
      final w2 = _week(2, _fourRunDays(q1Done: true, longDone: true), targetKm: 50);
      final w3 = _week(3, _fourRunDays(), targetKm: 50);
      final w4 = _week(4, _fourRunDays(), targetKm: 50);
      final plan = _plan([w1, w2, w3, w4]);

      final res = PlanAdaptation.reconcile(
        plan: plan,
        history: [
          RunSession(date: _start.add(const Duration(days: 2)), distanceKm: 15),
          RunSession(date: _start.add(const Duration(days: 9)), distanceKm: 15),
        ], // ~30% of the 50 km planned each week
        config: _config(),
        asOfDate: _start.add(const Duration(days: 14)), // Monday, week 3
      );

      expect(res.applied.map((e) => e.reason), contains('volume_shortfall_scaled'));
      expect(res.plan.weekByNumber(3)!.targetKm, closeTo(50 * 0.88, 0.5));
      expect(res.plan.weekByNumber(4)!.targetKm, closeTo(50 * 0.88, 0.5));
    });
  });

  group('pace recalibration', () {
    test('rescales forward paces and bumps builtFromVdot on a ≥1 VDOT move', () {
      final plan = _plan([
        _week(1, _fourRunDays(q1Done: true, longDone: true)),
        _week(2, _fourRunDays()),
      ], vdot: 45);
      final before = plan.weekByNumber(2)!.days[2].workout!.blocks.first
          .paceMinSecondsPerKm;

      final res = PlanAdaptation.reconcile(
        plan: plan,
        history: const [],
        config: _config(vDOT: 48),
        asOfDate: _start.add(const Duration(days: 7)),
      );

      expect(res.applied.map((e) => e.reason), contains('pace_recalibrated'));
      expect(res.plan.builtFromVdot, 48);
      final after = res.plan.weekByNumber(2)!.days[2].workout!.blocks.first
          .paceMinSecondsPerKm;
      expect(after, lessThan(before), reason: 'faster VDOT → quicker paces');
    });
  });

  group('invariants', () {
    test('completed / past weeks are returned byte-for-byte unchanged', () {
      final w1 = _week(1, _fourRunDays(q1Done: true, longDone: true), targetKm: 50);
      final w2 = _week(2, _fourRunDays(q1Done: true, longDone: true), targetKm: 50);
      final w3 = _week(3, _fourRunDays(), targetKm: 50);
      final w4 = _week(4, _fourRunDays(), targetKm: 50);
      final plan = _plan([w1, w2, w3, w4]);
      final w1Json = w1.toJson().toString();
      final w2Json = w2.toJson().toString();

      final res = PlanAdaptation.reconcile(
        plan: plan,
        history: [
          RunSession(date: _start.add(const Duration(days: 2)), distanceKm: 10),
          RunSession(date: _start.add(const Duration(days: 9)), distanceKm: 10),
        ],
        config: _config(vDOT: 49), // also triggers a pace recal
        asOfDate: _start.add(const Duration(days: 14)),
      );

      expect(res.changed, isTrue);
      expect(identical(res.plan.weekByNumber(1), w1), isTrue);
      expect(identical(res.plan.weekByNumber(2), w2), isTrue);
      expect(res.plan.weekByNumber(1)!.toJson().toString(), w1Json);
      expect(res.plan.weekByNumber(2)!.toJson().toString(), w2Json);
    });

    test('no signals ⇒ the exact same plan instance back', () {
      final plan = _plan([
        _week(1, _fourRunDays(q1Done: true, longDone: true)),
        _week(2, _fourRunDays()),
      ]);
      final res = PlanAdaptation.reconcile(
        plan: plan,
        history: const [],
        config: _config(),
        asOfDate: _start.add(const Duration(days: 7)),
      );
      expect(res.changed, isFalse);
      expect(identical(res.plan, plan), isTrue);
    });

    test('adaptationLog is append-only', () {
      final plan = _plan([_week(1, _fourRunDays())]).copyWith(
        adaptationLog: [
          AdaptationLogEntry(at: _start, reason: 'seed', summary: 'seed'),
        ],
      );
      final res = PlanAdaptation.reconcile(
        plan: plan,
        history: const [],
        config: _config(),
        asOfDate: _start.add(const Duration(days: 1)),
      );
      expect(res.plan.adaptationLog.first.reason, 'seed');
      expect(res.plan.adaptationLog.length, greaterThan(1));
    });
  });
}
