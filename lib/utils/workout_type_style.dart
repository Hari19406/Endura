import 'package:flutter/material.dart';
import '../models/workout_type.dart';
import '../engines/config/workout_template_library.dart' show WorkoutIntent;

/// Shared day-circle color mapping — used anywhere a week is shown as a row
/// of colored dots (Home's THIS WEEK card, the full plan overview). Matches
/// [WorkoutTypeStyle] below so a workout type reads the same color whether
/// it's shown as a badge, a history row, or a day dot.
Color dayColorForWorkoutType(WorkoutType type) => switch (type) {
  WorkoutType.easy => const Color(0xFF4CAF50),
  WorkoutType.quality => const Color(0xFFF57C00),
  WorkoutType.tempo => const Color(0xFFF57C00),
  WorkoutType.interval => const Color(0xFFD32F2F),
  WorkoutType.long => const Color(0xFF1976D2),
  WorkoutType.rest => Colors.white,
};

/// Same mapping keyed by [WorkoutIntent] instead, for screens that only
/// have the engine's intent (e.g. a projected future week with no
/// [WorkoutType] assigned yet). `null` means rest.
Color dayColorForIntent(WorkoutIntent? intent) => switch (intent) {
  WorkoutIntent.aerobicBase => const Color(0xFF4CAF50),
  WorkoutIntent.threshold => const Color(0xFFF57C00),
  WorkoutIntent.raceSpecific => const Color(0xFFF57C00),
  WorkoutIntent.vo2max => const Color(0xFFD32F2F),
  WorkoutIntent.speed => const Color(0xFFD32F2F),
  WorkoutIntent.endurance => const Color(0xFF1976D2),
  null => Colors.white,
};

/// Shared label/color mapping for a run's `workoutType` string, used by any
/// screen that shows a run-history entry (history list, run detail, etc).
class WorkoutTypeStyle {
  static String label(String type) {
    switch (type.toLowerCase()) {
      case 'easy':
        return 'Easy Run';
      case 'tempo':
        return 'Tempo';
      case 'interval':
        return 'Interval';
      case 'long':
        return 'Long Run';
      case 'recovery':
        return 'Recovery';
      case 'free':
        return 'Free Run';
      default:
        return type;
    }
  }

  static Color color(String type) {
    switch (type.toLowerCase()) {
      case 'easy':
        return const Color(0xFF4CAF50);
      case 'tempo':
        return const Color(0xFFF57C00);
      case 'interval':
        return const Color(0xFFD32F2F);
      case 'long':
        return const Color(0xFF1976D2);
      case 'recovery':
        return const Color(0xFF7B1FA2);
      case 'free':
        return const Color(0xFF00E5CC);
      default:
        return const Color(0xFF888888);
    }
  }
}
