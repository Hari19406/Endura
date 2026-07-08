import 'package:flutter/material.dart';
import 'services/coach_message_builder.dart' as message;
import 'engines/config/workout_template_library.dart';
import 'models/training_phase.dart';
import 'screens/pre_run_briefing_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PreviewApp());
}

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: PreRunBriefingScreen(
        coachMessage: _mockThresholdMessage(),
        onGoToRun: () {},
      ),
    );
  }
}

message.CoachMessage _mockThresholdMessage() {
  final workout = ResolvedWorkout(
    templateId: 'threshold_3x1k',
    name: 'Threshold Intervals',
    intent: WorkoutIntent.threshold,
    phase: TrainingPhase.base,
    blocks: const [
      ResolvedBlock(
        type: BlockType.warmup,
        distanceKm: 1.5,
        paceMinSecondsPerKm: 360,
        paceMaxSecondsPerKm: 420,
      ),
      ResolvedBlock(
        type: BlockType.main,
        distanceKm: 1.0,
        paceMinSecondsPerKm: 270,
        paceMaxSecondsPerKm: 285,
        reps: 3,
        recoverySeconds: 90,
        label: 'Threshold',
      ),
      ResolvedBlock(
        type: BlockType.cooldown,
        distanceKm: 1.0,
        paceMinSecondsPerKm: 360,
        paceMaxSecondsPerKm: 420,
      ),
    ],
  );

  return message.CoachMessage(
    workoutTitle: 'Threshold Intervals',
    reflectionText:
        'Last session was solid — you held your pace well through the back half. That tells me your aerobic base is coming together.',
    acknowledgementText: 'Three weeks in and the consistency is showing.',
    goalText: 'Hold threshold pace for all 3 reps without drifting.',
    feelText: 'Comfortably hard — controlled breathing, not gasping.',
    phaseLabel: 'Base Phase',
    weekNumber: 3,
    workoutSteps: [],
    resolvedWorkout: workout,
    workoutIntent: WorkoutIntent.threshold,
  );
}
