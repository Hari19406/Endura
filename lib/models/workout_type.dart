enum WorkoutType { easy, tempo, interval, long, recovery, quality, rest }

extension WorkoutTypeX on WorkoutType {
  bool get isQuality =>
      this == WorkoutType.tempo || this == WorkoutType.interval;

  bool get isHard => isQuality || this == WorkoutType.long;

  static WorkoutType fromString(String s) => switch (s) {
        'easy' => WorkoutType.easy,
        'tempo' => WorkoutType.tempo,
        'interval' => WorkoutType.interval,
        'long' => WorkoutType.long,
        'recovery' => WorkoutType.recovery,
        'quality' => WorkoutType.quality,
        'rest' => WorkoutType.rest,
        _ => WorkoutType.easy,
      };
}