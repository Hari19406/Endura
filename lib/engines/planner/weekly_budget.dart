import '../../models/workout_type.dart';
import '../../models/race_plan.dart';

class WeeklyBudget {
  final double volumeDoneKm;
  final double volumeTargetKm;
  final int qualityDone;
  final int qualityBudget;
  final bool longRunDone;
  final bool longRunPlanned;
  final double longRunTargetKm;
  final int runsCompleted;
  final int daysRemaining;

  const WeeklyBudget({
    required this.volumeDoneKm,
    required this.volumeTargetKm,
    required this.qualityDone,
    required this.qualityBudget,
    required this.longRunDone,
    required this.longRunPlanned,
    required this.longRunTargetKm,
    required this.runsCompleted,
    required this.daysRemaining,
  });

  double get volumePercent =>
      volumeTargetKm > 0 ? volumeDoneKm / volumeTargetKm : 0;

  bool get volumeGateFired => volumePercent >= 0.85;

  bool get qualityExhausted => qualityDone >= qualityBudget;

  bool get canDoQuality =>
      !volumeGateFired && !qualityExhausted && daysRemaining >= 1;

  bool get canDoLongRun =>
      !volumeGateFired && longRunPlanned && !longRunDone && daysRemaining >= 1;

  static WeeklyBudget compute({
    required List<RunSummary> thisWeekRuns,
    required WeekTarget weekTarget,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final daysElapsed = today.weekday;
    final daysRemaining = 7 - daysElapsed;

    var volumeDone = 0.0;
    var qualityDone = 0;
    var longRunDone = false;

    for (final run in thisWeekRuns) {
      volumeDone += run.distanceKm;
      if (run.type.isQuality) qualityDone++;
      if (run.type == WorkoutType.long) longRunDone = true;
    }

    return WeeklyBudget(
      volumeDoneKm: volumeDone,
      volumeTargetKm: weekTarget.targetKm,
      qualityDone: qualityDone,
      qualityBudget: weekTarget.qualityCount,
      longRunDone: longRunDone,
      longRunPlanned: weekTarget.hasLongRun,
      longRunTargetKm: weekTarget.longRunKm,
      runsCompleted: thisWeekRuns.length,
      daysRemaining: daysRemaining,
    );
  }

  static WeeklyBudget empty() => const WeeklyBudget(
        volumeDoneKm: 0,
        volumeTargetKm: 30,
        qualityDone: 0,
        qualityBudget: 1,
        longRunDone: false,
        longRunPlanned: true,
        longRunTargetKm: 8,
        runsCompleted: 0,
        daysRemaining: 7,
      );
}

class RunSummary {
  final DateTime date;
  final double distanceKm;
  final WorkoutType type;
  final int? rpe;

  const RunSummary({
    required this.date,
    required this.distanceKm,
    required this.type,
    this.rpe,
  });
}