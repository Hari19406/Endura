/// ScheduledWorkoutContext — the slice of a plan day handed to the live run
/// tracker. Verifies the derivation from a ResolvedWorkout.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/models/scheduled_workout_context.dart';
import 'package:run_app/models/training_phase.dart';

ResolvedWorkout _intervals() => const ResolvedWorkout(
  templateId: 'vo2_1km',
  name: '5 × 1 km',
  intent: WorkoutIntent.vo2max,
  phase: TrainingPhase.build,
  coachNote: '',
  blocks: [
    ResolvedBlock(
      type: BlockType.warmup,
      distanceKm: 2,
      paceMinSecondsPerKm: 330,
      paceMaxSecondsPerKm: 360,
    ),
    ResolvedBlock(
      type: BlockType.main,
      distanceKm: 1,
      paceMinSecondsPerKm: 240,
      paceMaxSecondsPerKm: 250,
      reps: 5,
      recoverySeconds: 90,
      label: '1 km rep',
    ),
    ResolvedBlock(
      type: BlockType.cooldown,
      distanceKm: 1.5,
      paceMinSecondsPerKm: 330,
      paceMaxSecondsPerKm: 360,
    ),
  ],
);

void main() {
  test('fromParts derives id, date, target distance and pace window', () {
    final ctx = ScheduledWorkoutContext.fromParts(
      planId: 'plan_9',
      planBuiltAt: DateTime(2026, 1, 5), // Monday, week 1
      weekNumber: 3,
      weekday: 2, // Wednesday
      workout: _intervals(),
    );

    expect(ctx.dayId, 'plan_9::w3::d2');
    expect(ctx.planId, 'plan_9');
    expect(ctx.weekNumber, 3);
    expect(ctx.weekday, 2);
    // week 1 Mon + 14 days + 2 = 2026-01-21
    expect(ctx.scheduledDate, DateTime(2026, 1, 21));

    // total distance = 2 + (1 × 5) + 1.5
    expect(ctx.targetDistanceKm, closeTo(8.5, 1e-9));

    // pace window comes from the work (main, non-RPE) block only
    expect(ctx.targetPaceMinSecPerKm, 240);
    expect(ctx.targetPaceMaxSecPerKm, 250);

    expect(ctx.stepCount, 3);
    expect(ctx.hasStructuredSteps, isTrue);
  });

  test('a single-block steady run has no structured steps', () {
    final ctx = ScheduledWorkoutContext.fromParts(
      planId: 'p',
      planBuiltAt: DateTime(2026, 1, 5),
      weekNumber: 1,
      weekday: 0,
      workout: const ResolvedWorkout(
        templateId: 'easy',
        name: 'Easy run',
        intent: WorkoutIntent.aerobicBase,
        phase: TrainingPhase.base,
        coachNote: '',
        blocks: [
          ResolvedBlock(
            type: BlockType.main,
            distanceKm: 6,
            paceMinSecondsPerKm: 330,
            paceMaxSecondsPerKm: 360,
          ),
        ],
      ),
    );
    expect(ctx.hasStructuredSteps, isFalse);
    expect(ctx.stepCount, 1);
  });
}
