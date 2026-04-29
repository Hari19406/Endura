enum TrainingPhase { base, build, peak, taper }

extension TrainingPhaseX on TrainingPhase {
  bool get allowsQualitySessions =>
      this == TrainingPhase.build || this == TrainingPhase.peak;

  double get intensityMultiplier => switch (this) {
        TrainingPhase.base => 1.05,
        TrainingPhase.build => 1.0,
        TrainingPhase.peak => 0.95,
        TrainingPhase.taper => 1.08,
      };

  int get maxQualityPerWeek => switch (this) {
        TrainingPhase.base => 0,
        TrainingPhase.build => 2,
        TrainingPhase.peak => 2,
        TrainingPhase.taper => 1,
      };

  double get easyToQualityRatio => switch (this) {
        TrainingPhase.base => 1.0,
        TrainingPhase.build => 0.80,
        TrainingPhase.peak => 0.75,
        TrainingPhase.taper => 0.85,
      };

  String get displayName => switch (this) {
        TrainingPhase.base => 'Base',
        TrainingPhase.build => 'Build',
        TrainingPhase.peak => 'Peak',
        TrainingPhase.taper => 'Taper',
      };

  String get description => switch (this) {
        TrainingPhase.base => 'Building aerobic foundation',
        TrainingPhase.build => 'Adding quality and volume',
        TrainingPhase.peak => 'Race-specific sharpening',
        TrainingPhase.taper => 'Reducing load before race',
      };
}

class PhaseEngine {
  /// Calendar-based week number — advances every 7 days regardless of runs completed.
  static int weekNumberFromDate(DateTime firstRunDate) {
    final daysSince = DateTime.now().difference(firstRunDate).inDays;
    return (daysSince / 7).floor() + 1;
  }

  /// Fallback only — used when firstRunDate is not available.
  static int weekNumber(int totalRunsCompleted) {
    if (totalRunsCompleted <= 0) return 1;
    return (totalRunsCompleted / 4).ceil();
  }

  static TrainingPhase fromRunCount(int totalRunsCompleted) {
    if (totalRunsCompleted < 16) return TrainingPhase.base;
    if (totalRunsCompleted < 32) return TrainingPhase.build;
    if (totalRunsCompleted < 40) return TrainingPhase.peak;
    return TrainingPhase.taper;
  }
}