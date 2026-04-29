import 'workout_type.dart';

class WorkoutSequence {
  static const _cycle = [
    WorkoutType.easy,
    WorkoutType.quality,
    WorkoutType.easy,
    WorkoutType.long,
  ];

  static WorkoutType next({WorkoutType? last}) {
    if (last == null) return WorkoutType.easy;
    final canonical = _canonicalize(last);
    final idx = _cycle.indexOf(canonical);
    if (idx < 0) return WorkoutType.easy;
    return _cycle[(idx + 1) % _cycle.length];
  }

  static WorkoutType _canonicalize(WorkoutType t) => switch (t) {
        WorkoutType.tempo => WorkoutType.quality,
        WorkoutType.interval => WorkoutType.quality,
        WorkoutType.recovery => WorkoutType.easy,
        _ => t,
      };
}