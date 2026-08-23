import 'package:flutter/material.dart';

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
