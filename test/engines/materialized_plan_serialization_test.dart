/// Phase 3 — MaterializedPlan JSON round-trip.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/models/training_phase.dart';

void main() {
  ResolvedWorkout sampleWorkout() => const ResolvedWorkout(
    templateId: 'cruise_intervals_800',
    name: 'Cruise Intervals',
    intent: WorkoutIntent.threshold,
    phase: TrainingPhase.build,
    coachNote: 'Controlled, not hard.',
    blocks: [
      ResolvedBlock(
        type: BlockType.warmup,
        distanceKm: 2.0,
        paceMinSecondsPerKm: 330,
        paceMaxSecondsPerKm: 360,
      ),
      ResolvedBlock(
        type: BlockType.main,
        distanceKm: 0.8,
        paceMinSecondsPerKm: 258,
        paceMaxSecondsPerKm: 264,
        reps: 5,
        recoverySeconds: 90,
        label: '800m',
      ),
      ResolvedBlock(
        type: BlockType.cooldown,
        distanceKm: 1.5,
        paceMinSecondsPerKm: 330,
        paceMaxSecondsPerKm: 360,
      ),
    ],
  );

  MaterializedPlan samplePlan() => MaterializedPlan(
    planId: 'plan-abc',
    builtAt: DateTime.parse('2026-09-02T10:00:00.000Z'),
    builtFromVdot: 48,
    inputsFingerprint: 'fp-123',
    ladderState: {'threshold': 2, 'vo2max': 0},
    sessionProgress: {'threshold': 1},
    weeks: [
      MaterializedWeek(
        weekNumber: 1,
        phase: TrainingPhase.build,
        targetKm: 45.0,
        isCutback: false,
        isFrozen: true,
        days: [
          const MaterializedDay(weekday: 0, slot: MaterializedSlot.rest),
          MaterializedDay(
            weekday: 1,
            slot: MaterializedSlot.quality1,
            intent: WorkoutIntent.threshold,
            templateId: 'cruise_intervals_800',
            progressionStep: 1,
            workout: sampleWorkout(),
            completion: DayCompletion(
              completedAt: DateTime.parse('2026-09-03T07:00:00.000Z'),
              actualKm: 9.1,
              actualPaceSecPerKm: 262,
              rpe: 6,
              runId: 'run-7',
            ),
          ),
          const MaterializedDay(weekday: 2, slot: MaterializedSlot.easy),
          const MaterializedDay(weekday: 3, slot: MaterializedSlot.rest),
          const MaterializedDay(
            weekday: 4,
            slot: MaterializedSlot.quality2,
            intent: WorkoutIntent.vo2max,
            templateId: 'vo2_400',
          ),
          const MaterializedDay(weekday: 5, slot: MaterializedSlot.rest),
          MaterializedDay(
            weekday: 6,
            slot: MaterializedSlot.longRun,
            intent: WorkoutIntent.endurance,
            templateId: 'long_steady',
            workout: sampleWorkout(),
          ),
        ],
      ),
    ],
  );

  test('MaterializedPlan survives a JSON string round-trip', () {
    final original = samplePlan();
    final restored = MaterializedPlan.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(restored.planId, original.planId);
    expect(restored.builtAt, original.builtAt);
    expect(restored.builtFromVdot, 48);
    expect(restored.inputsFingerprint, 'fp-123');
    expect(restored.ladderState, {'threshold': 2, 'vo2max': 0});
    expect(restored.sessionProgress, {'threshold': 1});
    expect(restored.weeks.length, 1);

    final w = restored.weeks.single;
    expect(w.weekNumber, 1);
    expect(w.phase, TrainingPhase.build);
    expect(w.targetKm, 45.0);
    expect(w.isFrozen, isTrue);
    expect(w.days.length, 7);
    expect(w.qualityCount, 2);
    expect(w.hasLongRun, isTrue);

    final tue = w.days[1];
    expect(tue.slot, MaterializedSlot.quality1);
    expect(tue.intent, WorkoutIntent.threshold);
    expect(tue.templateId, 'cruise_intervals_800');
    expect(tue.progressionStep, 1);
    expect(tue.workout!.blocks.length, 3);
    expect(tue.workout!.blocks[1].reps, 5);
    expect(tue.workout!.blocks[1].recoverySeconds, 90);
    expect(tue.workout!.blocks[1].label, '800m');
    expect(tue.workout!.coachNote, 'Controlled, not hard.');
    expect(tue.completion!.actualKm, 9.1);
    expect(tue.completion!.rpe, 6);
    expect(tue.completion!.runId, 'run-7');
  });

  test('re-serialising the restored plan yields identical JSON', () {
    final a = jsonEncode(samplePlan().toJson());
    final b = jsonEncode(
      MaterializedPlan.fromJson(
        jsonDecode(a) as Map<String, dynamic>,
      ).toJson(),
    );
    expect(b, a);
  });

  test('rest days and empty maps round-trip cleanly', () {
    final plan = MaterializedPlan(
      planId: 'p',
      builtAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
      builtFromVdot: 40,
      inputsFingerprint: 'x',
      weeks: [
        MaterializedWeek(
          weekNumber: 1,
          phase: TrainingPhase.base,
          targetKm: 20,
          isCutback: false,
          isFrozen: false,
          days: List.generate(
            7,
            (i) => MaterializedDay(weekday: i, slot: MaterializedSlot.rest),
          ),
        ),
      ],
    );
    final restored = MaterializedPlan.fromJson(
      jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>,
    );
    expect(restored.ladderState, isEmpty);
    expect(restored.sessionProgress, isEmpty);
    expect(restored.weeks.single.days.every((d) => d.isRest), isTrue);
    expect(restored.weeks.single.plannedKm, 0);
  });
}
