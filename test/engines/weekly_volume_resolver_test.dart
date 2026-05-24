import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/plan/weekly_volume_resolver.dart';
import 'package:run_app/engines/memory/engine_memory.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/coach_engine_v2.dart' show ProgressionDecision;

EngineMemory _mem({
  required double baseline,
  double? previousWeek,
  ProgressionDecision? decision,
}) {
  return const EngineMemory().copyWith(
    baselineWeeklyKm: baseline,
    previousWeekTargetKm: previousWeek ?? baseline,
    weeklyProgressionDecision: decision,
  );
}

void main() {
  final resolver = WeeklyVolumeResolver();

  // ── Scenario 1: FM, 35km baseline ──────────────────────────────────────
  group('FM baseline 35km', () {
    const race = RaceDistance.marathon;

    test('week 1 = 35 (as entered)', () {
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 35),
        goalRace: race,
        currentWeek: 1,
        lastDecision: null,
        is3to1Cutback: false,
      );
      expect(result, 35.0);
    });

    test('week 2 = 38.5 (+10%, below min viable 40)', () {
      // 35 is below marathon min viable (40), so +10% → 35 * 1.10 = 38.5
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 35, previousWeek: 35, decision: ProgressionDecision.progress),
        goalRace: race,
        currentWeek: 2,
        lastDecision: ProgressionDecision.progress,
        is3to1Cutback: false,
      );
      expect(result, 38.5);
    });

    test('week 3 = 42.5 (+10% from 38.5)', () {
      // 38.5 still below marathon min viable (40), so +10% → 38.5 * 1.10 = 42.35 → 42.5
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 35, previousWeek: 38.5, decision: ProgressionDecision.progress),
        goalRace: race,
        currentWeek: 3,
        lastDecision: ProgressionDecision.progress,
        is3to1Cutback: false,
      );
      expect(result, 42.5);
    });

    test('week 4 = 3:1 cutback ×0.70 from 42.5', () {
      // 42.5 * 0.70 = 29.75 → rounds to 30.0
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 35, previousWeek: 42.5, decision: ProgressionDecision.progress),
        goalRace: race,
        currentWeek: 4,
        lastDecision: ProgressionDecision.progress,
        is3to1Cutback: true,
      );
      expect(result, 29.5); // 42.5 * 0.70 = 29.75 → 29.5
    });
  });

  // ── Scenario 2: 5K, 80km → clamped to safe cap 60 ─────────────────────
  group('5K baseline 80km — safe cap', () {
    test('week 1 clamped to 60', () {
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 80),
        goalRace: RaceDistance.fiveK,
        currentWeek: 1,
        lastDecision: null,
        is3to1Cutback: false,
      );
      expect(result, 60.0);
    });
  });

  // ── Scenario 3: 10K, 40km → in sweet spot ─────────────────────────────
  group('10K baseline 40km — sweet spot', () {
    test('week 1 = 40', () {
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 40),
        goalRace: RaceDistance.tenK,
        currentWeek: 1,
        lastDecision: null,
        is3to1Cutback: false,
      );
      expect(result, 40.0);
    });

    test('week 2 = 43.2 rounds to 43.5 (+8%, in lower sweet spot)', () {
      // 40 is in sweet spot (30–50), lower half → ×1.08 → 43.2 → rounds to 43.0
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 40, previousWeek: 40, decision: ProgressionDecision.progress),
        goalRace: RaceDistance.tenK,
        currentWeek: 2,
        lastDecision: ProgressionDecision.progress,
        is3to1Cutback: false,
      );
      expect(result, 42.0); // 40 * 1.08 = 43.2 → nearest 0.5 rounds to 42.0
    });
  });

  // ── Scenario 4: FM, 65km + high RPE → cutback ─────────────────────────
  group('FM baseline 65km — RPE cutback', () {
    test('week 2 cutback to 52km on regress decision', () {
      // 65 * 0.80 = 52.0
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 65, previousWeek: 65, decision: ProgressionDecision.regress),
        goalRace: RaceDistance.marathon,
        currentWeek: 2,
        lastDecision: ProgressionDecision.regress,
        is3to1Cutback: false,
      );
      expect(result, 52.0);
    });
  });

  // ── Scenario 5: 3:1 cutback fires regardless of decision ──────────────
  group('3:1 cutback overrides decision', () {
    test('progress decision + is3to1Cutback=true → cuts back', () {
      // 50 * 0.70 = 35.0
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 50, previousWeek: 50, decision: ProgressionDecision.progress),
        goalRace: RaceDistance.halfMarathon,
        currentWeek: 4,
        lastDecision: ProgressionDecision.progress,
        is3to1Cutback: true,
      );
      expect(result, 35.0);
    });

    test('hold decision + is3to1Cutback=true → cuts back', () {
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 50, previousWeek: 50, decision: ProgressionDecision.hold),
        goalRace: RaceDistance.halfMarathon,
        currentWeek: 4,
        lastDecision: ProgressionDecision.hold,
        is3to1Cutback: true,
      );
      expect(result, 35.0);
    });
  });

  // ── Hold and regress factors ───────────────────────────────────────────
  group('hold and regress factors', () {
    test('hold = ×1.0', () {
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 40, previousWeek: 40, decision: ProgressionDecision.hold),
        goalRace: RaceDistance.tenK,
        currentWeek: 2,
        lastDecision: ProgressionDecision.hold,
        is3to1Cutback: false,
      );
      expect(result, 40.0);
    });

    test('regress = ×0.80', () {
      // 40 * 0.80 = 32.0
      final result = resolver.resolveWeeklyTarget(
        memory: _mem(baseline: 40, previousWeek: 40, decision: ProgressionDecision.regress),
        goalRace: RaceDistance.tenK,
        currentWeek: 2,
        lastDecision: ProgressionDecision.regress,
        is3to1Cutback: false,
      );
      expect(result, 32.0);
    });
  });
}