import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/services/plan_adaptation_service.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

final _start = DateTime(2026, 1, 5); // Monday → week-1 start
const _service = PlanAdaptationService();

/// Ascending volume ramp for weeks 1–10, then a two-week taper (weeks 11–12).
double _target(int week) {
  if (week <= 10) return 40.0 + (week - 1) * 4; // 40 … 76
  if (week == 11) return 55.0;
  return 40.0; // week 12
}

TrainingPhase _phase(int week) =>
    week >= 11 ? TrainingPhase.taper : TrainingPhase.build;

ResolvedWorkout _wk(String id, WorkoutIntent intent, double km) => ResolvedWorkout(
      templateId: id,
      name: id,
      intent: intent,
      phase: TrainingPhase.build,
      blocks: [
        ResolvedBlock(
          type: BlockType.main,
          distanceKm: km,
          paceMinSecondsPerKm: 300,
          paceMaxSecondsPerKm: 330,
        ),
      ],
    );

MaterializedDay _day(int wd, MaterializedSlot slot, WorkoutIntent? intent,
    double km) {
  final rest = slot == MaterializedSlot.rest;
  return MaterializedDay(
    weekday: wd,
    slot: slot,
    intent: rest ? null : intent,
    templateId: rest ? null : 'tpl_$wd',
    workout: rest ? null : _wk('tpl_$wd', intent!, km),
  );
}

/// Mon Q1 (threshold), Wed easy, Thu Q2 (vo2max), Sat long, Sun easy.
List<MaterializedDay> _days() => [
      _day(0, MaterializedSlot.quality1, WorkoutIntent.threshold, 8),
      _day(1, MaterializedSlot.rest, null, 0),
      _day(2, MaterializedSlot.easy, WorkoutIntent.aerobicBase, 6),
      _day(3, MaterializedSlot.quality2, WorkoutIntent.vo2max, 7),
      _day(4, MaterializedSlot.rest, null, 0),
      _day(5, MaterializedSlot.longRun, WorkoutIntent.endurance, 16),
      _day(6, MaterializedSlot.easy, WorkoutIntent.aerobicBase, 5),
    ];

MaterializedPlan _plan() => MaterializedPlan(
      planId: 'p1',
      builtAt: _start,
      builtFromVdot: 45,
      inputsFingerprint: 'fp',
      weeks: [
        for (var n = 1; n <= 12; n++)
          MaterializedWeek(
            weekNumber: n,
            phase: _phase(n),
            targetKm: _target(n),
            isCutback: false,
            isFrozen: false,
            days: _days(),
          ),
      ],
    );

DateTime _mondayOfWeek(int week) =>
    _start.add(Duration(days: (week - 1) * 7));

List<DateTime> _consecutive(int fromDayOffset, int count) =>
    [for (var i = 0; i < count; i++) _start.add(Duration(days: fromDayOffset + i))];

int _qualityCount(MaterializedWeek w) =>
    w.days.where((d) => d.slot.isQuality).length;

const _speedIntents = {
  WorkoutIntent.threshold,
  WorkoutIntent.vo2max,
  WorkoutIntent.speed,
  WorkoutIntent.raceSpecific,
};

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  group('classifyWindow', () {
    test('maps consecutive-day spans to the right window', () {
      expect(_service.classifyWindow(const []), MissedWindow.none);
      expect(_service.classifyWindow(_consecutive(2, 1)), MissedWindow.brief);
      expect(_service.classifyWindow(_consecutive(2, 2)), MissedWindow.brief);
      expect(_service.classifyWindow(_consecutive(2, 3)), MissedWindow.moderate);
      expect(_service.classifyWindow(_consecutive(2, 7)), MissedWindow.moderate);
      expect(_service.classifyWindow(_consecutive(2, 8)), MissedWindow.extended);
      expect(_service.classifyWindow(_consecutive(2, 21)), MissedWindow.extended);
    });

    test('uses the longest streak, not the raw count', () {
      // Five missed days, one per week — never two in a row.
      final scattered = [for (var w = 0; w < 5; w++) _start.add(Duration(days: w * 7))];
      expect(_service.classifyWindow(scattered), MissedWindow.brief);
    });

    test('de-duplicates repeated dates within a day', () {
      final d = _start.add(const Duration(days: 3));
      expect(
        _service.classifyWindow([d, d, DateTime(d.year, d.month, d.day, 18)]),
        MissedWindow.brief,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('brief (1–2 days)', () {
    test('leaves every week untouched and never shifts mileage forward', () {
      final plan = _plan();
      final res = _service.evaluateAndRecalibrate(
        activePlan: plan,
        currentDate: _mondayOfWeek(3),
        missedWorkoutDates: _consecutive(12, 2), // Sat + Sun of week 2
        remainingWeeksToRace: 9,
      );

      expect(res.missedWindow, MissedWindow.brief);
      expect(res.changedPlan, isFalse);

      for (var n = 1; n <= 12; n++) {
        final before = plan.weekByNumber(n)!;
        final after = res.updatedPlan.weekByNumber(n)!;
        expect(after.targetKm, before.targetKm, reason: 'week $n volume held');
        expect(after.toJson().toString(), before.toJson().toString(),
            reason: 'week $n structurally identical — no catch-up cram');
      }
      // downstream quality workouts intact
      for (var n = 3; n <= 10; n++) {
        expect(_qualityCount(res.updatedPlan.weekByNumber(n)!), 2);
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('moderate (3–7 days)', () {
    late MaterializedPlan plan;
    late PlanRecalibration res;

    setUp(() {
      plan = _plan();
      res = _service.evaluateAndRecalibrate(
        activePlan: plan,
        currentDate: _mondayOfWeek(3),
        missedWorkoutDates: _consecutive(9, 5), // Wed wk2 → Sun wk2 (5 days)
        remainingWeeksToRace: 9,
      );
    });

    test('detects the moderate window', () {
      expect(res.missedWindow, MissedWindow.moderate);
      expect(res.changedPlan, isTrue);
    });

    test('reduces the return-week volume by 15–20%', () {
      final origin = _target(3);
      final after = res.updatedPlan.weekByNumber(3)!.targetKm;
      expect(after / origin, inInclusiveRange(0.80, 0.85));
      expect(after, closeTo(origin * 0.82, 0.5));
    });

    test('converts the first upcoming quality session into an easy run', () {
      final wk3 = res.updatedPlan.weekByNumber(3)!;
      final mon = wk3.days[0];
      expect(mon.slot, MaterializedSlot.easy);
      expect(mon.intent, WorkoutIntent.aerobicBase);
      expect(mon.workout!.intent, WorkoutIntent.aerobicBase);
      // only the FIRST hard session is downgraded — Thursday's quality survives
      expect(wk3.days[3].slot, MaterializedSlot.quality2);
    });

    test('resumes normal progression from the following week', () {
      for (var n = 4; n <= 10; n++) {
        expect(res.updatedPlan.weekByNumber(n)!.targetKm, _target(n),
            reason: 'week $n untouched');
        expect(_qualityCount(res.updatedPlan.weekByNumber(n)!), 2);
      }
    });

    test('leaves the two-week taper intact', () {
      for (final n in [11, 12]) {
        expect(identical(res.updatedPlan.weekByNumber(n), plan.weekByNumber(n)),
            isTrue);
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('extended (8–21+ days)', () {
    late MaterializedPlan plan;
    late PlanRecalibration res;

    setUp(() {
      plan = _plan();
      res = _service.evaluateAndRecalibrate(
        activePlan: plan,
        currentDate: _mondayOfWeek(3),
        missedWorkoutDates: _consecutive(4, 10), // 10 consecutive days
        remainingWeeksToRace: 9,
      );
    });

    test('detects the extended window', () {
      expect(res.missedWindow, MissedWindow.extended);
      expect(res.changedPlan, isTrue);
    });

    test('cuts the re-anchor week volume by 25–35%', () {
      final origin = _target(3);
      final after = res.updatedPlan.weekByNumber(3)!.targetKm;
      expect(after / origin, inInclusiveRange(0.65, 0.75));
      expect(after, closeTo(origin * 0.70, 0.1));
    });

    test('zeroes out speedwork for 14 days', () {
      final windowEnd = _mondayOfWeek(3).add(const Duration(days: 14));
      for (final w in res.updatedPlan.weeks) {
        for (final d in w.days) {
          final date = _start
              .add(Duration(days: (w.weekNumber - 1) * 7 + d.weekday));
          final inWindow =
              !date.isBefore(_mondayOfWeek(3)) && !date.isAfter(windowEnd);
          if (!inWindow) continue;
          expect(d.slot.isQuality, isFalse,
              reason: '${date.toIso8601String()} still a quality slot');
          expect(_speedIntents.contains(d.intent), isFalse,
              reason: '${date.toIso8601String()} still speed intent ${d.intent}');
        }
      }
      // weeks fully inside the window have no quality at all
      expect(_qualityCount(res.updatedPlan.weekByNumber(3)!), 0);
      expect(_qualityCount(res.updatedPlan.weekByNumber(4)!), 0);
    });

    test('rebuilds to race day without exceeding safe weekly progression', () {
      for (var n = 3; n <= 9; n++) {
        final cur = res.updatedPlan.weekByNumber(n)!.targetKm;
        final next = res.updatedPlan.weekByNumber(n + 1)!.targetKm;
        expect(next, lessThanOrEqualTo(cur * 1.10 + 0.1),
            reason: 'week ${n + 1} jumps more than ~10% over week $n');
        // and never inflates past the athlete's original target
        expect(res.updatedPlan.weekByNumber(n)!.targetKm,
            lessThanOrEqualTo(_target(n) + 0.1));
      }
      // the wave actually ramps back up rather than staying flat
      expect(res.updatedPlan.weekByNumber(4)!.targetKm,
          greaterThan(res.updatedPlan.weekByNumber(3)!.targetKm));
    });

    test('preserves the two-week taper regardless of the layoff', () {
      for (final n in [11, 12]) {
        expect(identical(res.updatedPlan.weekByNumber(n), plan.weekByNumber(n)),
            isTrue);
        expect(res.updatedPlan.weekByNumber(n)!.targetKm, _target(n));
        expect(_qualityCount(res.updatedPlan.weekByNumber(n)!), 2,
            reason: 'taper intensity structure untouched');
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('taper safety', () {
    test('a long layoff inside the taper leaves the whole plan unchanged', () {
      final plan = _plan();
      final res = _service.evaluateAndRecalibrate(
        activePlan: plan,
        currentDate: _mondayOfWeek(11), // already tapering
        missedWorkoutDates: _consecutive(60, 12), // 12 days off
        remainingWeeksToRace: 2,
      );

      expect(res.missedWindow, MissedWindow.extended,
          reason: 'the layoff is still classified honestly');
      for (var n = 1; n <= 12; n++) {
        expect(res.updatedPlan.weekByNumber(n)!.toJson().toString(),
            plan.weekByNumber(n)!.toJson().toString(),
            reason: 'week $n untouched during the taper');
      }
      expect(res.coachExplanation.toLowerCase(), contains('taper'));
    });
  });
}
