import 'package:flutter/material.dart';
import '../models/workout_type.dart';
import '../engines/config/workout_template_library.dart' show WorkoutIntent;
import '../theme/app_colors.dart';

/// Shared day-circle color mapping — used anywhere a week is shown as a row
/// of colored dots (Home's THIS WEEK card, the full plan overview). Matches
/// [WorkoutTypeStyle] below so a workout type reads the same color whether
/// it's shown as a badge, a history row, or a day dot.
///
/// Resolves through [AppColors.workoutEasy] / etc. so day-dot colors follow
/// the active theme instead of a hardcoded palette.
Color dayColorForWorkoutType(BuildContext context, WorkoutType type) {
  final c = context.colors;
  return switch (type) {
    WorkoutType.easy => c.workoutEasy,
    WorkoutType.quality => c.workoutTempo,
    WorkoutType.tempo => c.workoutTempo,
    WorkoutType.interval => c.workoutInterval,
    WorkoutType.long => c.workoutLong,
    WorkoutType.rest => c.workoutRest,
  };
}

/// Same mapping keyed by [WorkoutIntent] instead, for screens that only
/// have the engine's intent (e.g. a projected future week with no
/// [WorkoutType] assigned yet). `null` means rest.
Color dayColorForIntent(BuildContext context, WorkoutIntent? intent) {
  final c = context.colors;
  return switch (intent) {
    WorkoutIntent.aerobicBase => c.workoutEasy,
    WorkoutIntent.threshold => c.workoutTempo,
    WorkoutIntent.raceSpecific => c.workoutTempo,
    WorkoutIntent.vo2max => c.workoutInterval,
    WorkoutIntent.speed => c.workoutInterval,
    WorkoutIntent.endurance => c.workoutLong,
    null => c.workoutRest,
  };
}

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

  /// Resolves through the active theme's [AppColors.workoutEasy]/etc. tokens.
  /// `free` reuses [AppColors.chartAccent] (the brand cyan already used for
  /// Free Run elsewhere); `recovery` and unrecognized legacy types fall back
  /// to [AppColors.textTertiary] since neither is a current day type.
  static Color color(BuildContext context, String type) {
    final c = context.colors;
    switch (type.toLowerCase()) {
      case 'easy':
        return c.workoutEasy;
      case 'tempo':
        return c.workoutTempo;
      case 'interval':
        return c.workoutInterval;
      case 'long':
        return c.workoutLong;
      case 'free':
        return c.chartAccent;
      case 'recovery':
        return c.textTertiary;
      default:
        return c.textTertiary;
    }
  }

  /// Fixed, theme-independent colors for exported share-card images. Share
  /// cards render as static PNGs (see run_share_card.dart) and must look the
  /// same regardless of the viewer's device theme, so this intentionally
  /// does NOT resolve through [AppColors].
  static Color exportColor(String type) {
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
