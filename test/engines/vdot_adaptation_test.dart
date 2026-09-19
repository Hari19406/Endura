/// Safe adaptive vDOT recalibration:
///   • VdotAdaptationGuard — proportional caps, taper lock, consolidation
///     lockout, downward bypass
///   • EngineRuntime.processRun — the guard applied in the weekly evaluation,
///     and a verified shift re-pricing the stored plan
///   • PlanAdaptation.recalibratePaces — forward-only, pace-only, immutable past
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/core/vdot_calculator.dart' show pacesFor;
import 'package:run_app/engines/memory/engine_memory.dart';
import 'package:run_app/engines/memory/engine_memory_service.dart';
import 'package:run_app/engines/plan/adaptation_coordinator.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_adaptation.dart';
import 'package:run_app/engines/plan/plan_store.dart';
import 'package:run_app/engines/runtime/engine_runtime.dart';
import 'package:run_app/engines/runtime/vdot_adaptation_guard.dart';
import 'package:run_app/models/race_plan.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

final _start = DateTime(2026, 1, 5); // Monday — week 1 begins

RacePlan _racePlan({
  required int weeks,
  String goalRace = 'half_marathon',
  String level = 'intermediate',
  int taperLabelled = 0,
}) => RacePlan(
  goalRace: goalRace,
  raceDate: _start.add(Duration(days: weeks * 7)),
  createdAt: _start,
  startingWeeklyKm: 30,
  experienceLevel: level,
  weeks: [
    for (var w = 1; w <= weeks; w++)
      WeekTarget(
        week: w,
        targetKm: 40,
        phase: w > weeks - taperLabelled
            ? TrainingPhase.taper
            : TrainingPhase.build,
        qualityCount: 1,
        hasLongRun: true,
        longRunKm: 16,
        keySession: 'threshold',
      ),
  ],
);

ResolvedWorkout _wk(String id, WorkoutIntent intent, double km, int pace) =>
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
          reps: 2,
        ),
      ],
    );

MaterializedDay _day(
  int wd,
  MaterializedSlot slot, {
  double km = 6,
  int pace = 300,
  bool completed = false,
}) {
  if (slot == MaterializedSlot.rest) {
    return MaterializedDay(weekday: wd, slot: slot);
  }
  return MaterializedDay(
    weekday: wd,
    slot: slot,
    intent: WorkoutIntent.aerobicBase,
    templateId: 'tpl_$wd',
    workout: _wk('tpl_$wd', WorkoutIntent.aerobicBase, km, pace),
    completion: completed
        ? DayCompletion(
            completedAt: _start.add(Duration(days: wd)),
            actualKm: km,
          )
        : null,
  );
}

MaterializedWeek _week(
  int n, {
  bool firstDone = false,
  bool allDone = false,
}) => MaterializedWeek(
  weekNumber: n,
  phase: TrainingPhase.build,
  targetKm: 40,
  isCutback: false,
  isFrozen: false,
  days: [
    _day(0, MaterializedSlot.quality1, completed: firstDone || allDone),
    _day(1, MaterializedSlot.easy, completed: allDone),
    _day(2, MaterializedSlot.easy, completed: allDone),
    _day(3, MaterializedSlot.rest),
    _day(4, MaterializedSlot.easy, completed: allDone),
    _day(5, MaterializedSlot.longRun, km: 16, completed: allDone),
    _day(6, MaterializedSlot.rest),
  ],
);

MaterializedPlan _plan(int weeks, {int vdot = 45}) => MaterializedPlan(
  planId: 'p1',
  builtAt: _start,
  builtFromVdot: vdot,
  inputsFingerprint: 'fp',
  weeks: [for (var n = 1; n <= weeks; n++) _week(n)],
);

/// Persist an athlete mid-plan whose last weekly evaluation was 8 days before
/// [firstRun], so the next run triggers one.
Future<void> _seed({
  required RacePlan racePlan,
  required DateTime firstRun,
  int vdot = 45,
  DateTime? lastUpwardShift,
}) => EngineMemoryService().save(
  EngineMemory(
    vdotScore: vdot,
    vdotAtPlanStart: 45,
    racePlan: racePlan,
    lastProgressionEvaluationDate: firstRun.subtract(const Duration(days: 8)),
    lastVdotUpwardShiftDate: lastUpwardShift,
  ),
  syncToCloud: false,
);

/// One completed threshold run. [fast] → faster than expected at low RPE (an
/// upward signal); otherwise slower at high RPE (a downward one).
Future<EngineMemory> _run(DateTime date, {bool fast = true}) async {
  await EngineRuntime.processRun(
    durationMinutes: 40,
    speed: 3.3,
    runDate: date,
    workoutType: 'tempo',
    distanceKm: 8,
    rpe: fast ? 4 : 8,
    completedIntent: WorkoutIntent.threshold,
    actualPaceSecondsPerKm: fast ? 280 : 320,
    expectedPaceSecondsPerKm: 300,
  );
  return EngineMemoryService().load();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── The guard, in isolation ───────────────────────────────────────────────

  group('VdotAdaptationGuard.limitsFor', () {
    test('≤ 4 weeks allows no upward gain', () {
      expect(
        VdotAdaptationGuard.limitsFor(planWeeks: 4, isBeginner: false)
            .maxUpwardGain,
        0,
      );
    });

    test('≤ 8 weeks: +1, 14-day consolidation', () {
      final l = VdotAdaptationGuard.limitsFor(planWeeks: 8, isBeginner: true);
      expect(l.maxUpwardGain, 1);
      expect(l.consolidationDays, 14);
    });

    test('≥ 9 weeks: +2 (+3 beginner), 28-day consolidation', () {
      final open = VdotAdaptationGuard.limitsFor(
        planWeeks: 9,
        isBeginner: false,
      );
      final beginner = VdotAdaptationGuard.limitsFor(
        planWeeks: 16,
        isBeginner: true,
      );
      expect(open.maxUpwardGain, 2);
      expect(beginner.maxUpwardGain, 3);
      expect(open.consolidationDays, 28);
      expect(beginner.consolidationDays, 28);
    });
  });

  group('VdotAdaptationGuard.resolve', () {
    final plan16 = _racePlan(weeks: 16);
    final midPlan = _start.add(const Duration(days: 21));

    VdotShiftDecision resolve({
      int proposed = 1,
      int current = 45,
      RacePlan? plan,
      DateTime? lastUp,
      DateTime? today,
    }) => VdotAdaptationGuard.resolve(
      proposed: proposed,
      currentVdot: current,
      anchorVdot: 45,
      plan: plan ?? plan16,
      lastUpwardShift: lastUp,
      today: today ?? midPlan,
    );

    test('lets an upward nudge through mid-plan', () {
      expect(resolve().applied, 1);
    });

    test('consolidation blocks until the full interval has elapsed', () {
      final up = midPlan.subtract(const Duration(days: 27));
      expect(resolve(lastUp: up).reason, VdotShiftReason.consolidationLockout);
      final ok = midPlan.subtract(const Duration(days: 28));
      expect(resolve(lastUp: ok, current: 46).applied, 1);
    });

    test('8-week plan consolidates for 14 days', () {
      final plan8 = _racePlan(weeks: 8);
      final up = midPlan.subtract(const Duration(days: 13));
      expect(
        resolve(plan: plan8, lastUp: up).reason,
        VdotShiftReason.consolidationLockout,
      );
      final ok = midPlan.subtract(const Duration(days: 14));
      // Consolidated, but the plan's single +1 is already spent.
      expect(
        resolve(plan: plan8, lastUp: ok, current: 46).reason,
        VdotShiftReason.gainCapReached,
      );
    });

    test('never exceeds the plan gain cap', () {
      expect(resolve(current: 47).reason, VdotShiftReason.gainCapReached);
      final beginner = _racePlan(weeks: 16, level: 'beginner');
      expect(resolve(plan: beginner, current: 47).applied, 1);
      expect(
        resolve(plan: beginner, current: 48).reason,
        VdotShiftReason.gainCapReached,
      );
    });

    test('downward shifts bypass every upward guard', () {
      final taper = _start.add(const Duration(days: 15 * 7 + 2));
      final d = resolve(
        proposed: -1,
        lastUp: taper.subtract(const Duration(days: 1)),
        today: taper,
      );
      expect(d.applied, -1);
      expect(d.reason, VdotShiftReason.downwardBypass);
      expect(
        resolve(proposed: -1, plan: _racePlan(weeks: 4)).applied,
        -1,
      );
    });

    test('taper windows: final week ≤ 8 wks; 2 half / 3 marathon otherwise', () {
      bool taper(RacePlan p, int week) => VdotAdaptationGuard.isInTaper(
        plan: p,
        today: _start.add(Duration(days: (week - 1) * 7 + 2)),
      );
      final eight = _racePlan(weeks: 8);
      expect(taper(eight, 7), isFalse);
      expect(taper(eight, 8), isTrue);

      final half = _racePlan(weeks: 16);
      expect(taper(half, 14), isFalse);
      expect(taper(half, 15), isTrue);

      final marathon = _racePlan(weeks: 16, goalRace: 'marathon');
      expect(taper(marathon, 13), isFalse);
      expect(taper(marathon, 14), isTrue);
    });

    test('a plan-labelled taper week locks even outside the window', () {
      final p = _racePlan(weeks: 12, goalRace: '10k', taperLabelled: 2);
      // Week 11 is labelled taper but is not the final 10K week.
      expect(
        resolve(
          plan: p,
          today: _start.add(const Duration(days: 10 * 7 + 2)),
        ).reason,
        VdotShiftReason.taperLock,
      );
    });
  });

  // ── The weekly evaluation in EngineRuntime ───────────────────────────────

  group('EngineRuntime weekly evaluation', () {
    test('4-week plan: no upward shift despite fast paces at low RPE', () async {
      final day = _start.add(const Duration(days: 9));
      await _seed(racePlan: _racePlan(weeks: 4), firstRun: day);
      await PlanStore.instance.save(_plan(4));

      final m = await _run(day);

      expect(m.vdotScore, 45);
      expect(m.lastVdotUpwardShiftDate, isNull);
      expect(m.vdotIsProvisional, isFalse, reason: 'evaluation still ran');
      expect((await PlanStore.instance.load())!.builtFromVdot, 45);
    });

    test('16-week plan: an upward shift locks out the next for 4 weeks', () async {
      final racePlan = _racePlan(weeks: 16);
      final first = DateTime(2026, 1, 19);
      await _seed(racePlan: racePlan, firstRun: first);
      await PlanStore.instance.save(_plan(16));

      var m = await _run(first);
      expect(m.vdotScore, 46);
      expect(m.lastVdotUpwardShiftDate, first);
      expect((await PlanStore.instance.load())!.builtFromVdot, 46);

      // Weeks 1–3 after the shift: fast runs, but locked out.
      for (final d in [
        DateTime(2026, 1, 26),
        DateTime(2026, 2, 2),
        DateTime(2026, 2, 9),
      ]) {
        m = await _run(d);
        expect(m.vdotScore, 46, reason: 'locked out on $d');
        expect(m.lastVdotUpwardShiftDate, first);
      }

      // Exactly 28 days later the lockout has lapsed.
      m = await _run(DateTime(2026, 2, 16));
      expect(m.vdotScore, 47);
      expect(m.lastVdotUpwardShiftDate, DateTime(2026, 2, 16));
      expect((await PlanStore.instance.load())!.builtFromVdot, 47);

      // Consolidated again — but +2 is an intermediate's plan maximum.
      m = await _run(DateTime(2026, 3, 16));
      expect(m.vdotScore, 47);
    });

    test('taper lock: no upward shift in the final marathon weeks', () async {
      final racePlan = _racePlan(weeks: 16, goalRace: 'marathon');

      // Control — week 9, mid-build: the same evidence does raise vDOT.
      final build = _start.add(const Duration(days: 8 * 7 + 2));
      await _seed(racePlan: racePlan, firstRun: build);
      expect((await _run(build)).vdotScore, 46);

      // Week 14 is the first of the 3 taper weeks.
      SharedPreferences.setMockInitialValues({});
      final taper = _start.add(const Duration(days: 13 * 7 + 2));
      await _seed(racePlan: racePlan, firstRun: taper);
      final m = await _run(taper);
      expect(m.vdotScore, 45);
      expect(m.lastVdotUpwardShiftDate, isNull);
    });

    test('downward shift bypasses the consolidation lockout', () async {
      final racePlan = _racePlan(weeks: 16);
      final up = DateTime(2026, 1, 19);
      await _seed(racePlan: racePlan, firstRun: up);
      await PlanStore.instance.save(_plan(16));
      await _run(up);

      // A week later: fast would be locked out, but a struggling athlete
      // still gets easier paces.
      final m = await _run(DateTime(2026, 1, 26), fast: false);
      expect(m.vdotScore, 45);
      expect(
        m.lastVdotUpwardShiftDate,
        up,
        reason: 'a downward move must not reset the upward clock',
      );
      expect((await PlanStore.instance.load())!.builtFromVdot, 45);
    });
  });

  // ── PlanAdaptation.recalibratePaces ──────────────────────────────────────

  group('PlanAdaptation.recalibratePaces', () {
    // Week 2 is current on Wednesday (index 2): Mon done, Tue missed, Wed today.
    final asOf = _start.add(const Duration(days: 9));

    MaterializedPlan build() => MaterializedPlan(
      planId: 'p1',
      builtAt: _start,
      builtFromVdot: 45,
      inputsFingerprint: 'fp',
      weeks: [
        _week(1, allDone: true),
        _week(2, firstDone: true),
        _week(3),
        _week(4),
      ],
    );

    int paceOf(MaterializedPlan p, int week, int day) => p
        .weekByNumber(week)!
        .days[day]
        .workout!
        .blocks
        .first
        .paceMinSecondsPerKm;

    test('re-prices only future uncompleted days', () {
      final plan = build();
      final res = PlanAdaptation.recalibratePaces(
        plan: plan,
        newVdot: 47,
        asOfDate: asOf,
      );

      double mid(int v) {
        final e = pacesFor(v).ePaceSecPerKm;
        return (e.$1 + e.$2) / 2.0;
      }

      final factor = mid(47) / mid(45);
      expect(factor, lessThan(1));

      // Frozen week — same instance, byte for byte.
      expect(identical(res.plan.weekByNumber(1), plan.weekByNumber(1)), isTrue);
      // Completed Monday, missed Tuesday and today (Wed) keep their paces.
      expect(paceOf(res.plan, 2, 0), 300);
      expect(paceOf(res.plan, 2, 1), 300);
      expect(paceOf(res.plan, 2, 2), 300);
      // Thursday-onward and every later week are re-priced to the new VDOT.
      for (final (w, d) in [(2, 4), (2, 5), (3, 0), (3, 5), (4, 2)]) {
        expect(paceOf(res.plan, w, d), (300 * factor).round(), reason: 'W$w D$d');
        expect(
          res.plan.weekByNumber(w)!.days[d].workout!.blocks.first
              .paceMaxSecondsPerKm,
          (320 * factor).round(),
        );
      }
      expect(res.plan.builtFromVdot, 47);
      expect(res.applied.single.reason, 'pace_recalibrated');
      expect(res.plan.adaptationLog, hasLength(1));
    });

    test('days, volume and workout types are 100% unchanged', () {
      final plan = build();
      final res = PlanAdaptation.recalibratePaces(
        plan: plan,
        newVdot: 49,
        asOfDate: asOf,
      );

      expect(res.plan.weeks, hasLength(plan.weeks.length));
      for (var i = 0; i < plan.weeks.length; i++) {
        final a = plan.weeks[i];
        final b = res.plan.weeks[i];
        expect(b.weekNumber, a.weekNumber);
        expect(b.targetKm, a.targetKm);
        expect(b.phase, a.phase);
        expect(b.isCutback, a.isCutback);
        expect(b.days, hasLength(a.days.length));
        for (var d = 0; d < a.days.length; d++) {
          final x = a.days[d];
          final y = b.days[d];
          expect(y.weekday, x.weekday);
          expect(y.slot, x.slot);
          expect(y.intent, x.intent);
          expect(y.templateId, x.templateId);
          expect(y.completion, same(x.completion));
          expect(y.workout?.totalDistanceKm, x.workout?.totalDistanceKm);
          expect(y.workout?.name, x.workout?.name);
          expect(
            y.workout?.blocks.map((k) => (k.type, k.distanceKm, k.reps)),
            x.workout?.blocks.map((k) => (k.type, k.distanceKm, k.reps)),
          );
        }
      }
    });

    test('a slower VDOT eases the remaining paces', () {
      final res = PlanAdaptation.recalibratePaces(
        plan: build(),
        newVdot: 44,
        asOfDate: asOf,
      );
      expect(paceOf(res.plan, 3, 0), greaterThan(300));
      expect(paceOf(res.plan, 2, 0), 300);
    });

    test('is a no-op when the VDOT has not moved', () {
      final plan = build();
      final res = PlanAdaptation.recalibratePaces(
        plan: plan,
        newVdot: 45,
        asOfDate: asOf,
      );
      expect(res.changed, isFalse);
      expect(identical(res.plan, plan), isTrue);
    });
  });

  group('AdaptationCoordinator.reconcileNow(paceOnly)', () {
    test('re-prices the stored plan from the current memory vDOT', () async {
      await PlanStore.instance.save(_plan(6));
      await EngineMemoryService().save(
        const EngineMemory(vdotScore: 47),
        syncToCloud: false,
      );

      final applied = await AdaptationCoordinator.instance.reconcileNow(
        asOfDate: _start.add(const Duration(days: 1)),
        paceOnly: true,
      );

      expect(applied.single.reason, 'pace_recalibrated');
      final stored = (await PlanStore.instance.load())!;
      expect(stored.builtFromVdot, 47);
      expect(
        stored.weekByNumber(3)!.days[1].workout!.blocks.first.paceMinSecondsPerKm,
        lessThan(300),
      );
    });
  });
}
