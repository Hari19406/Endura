import 'weekly_plan.dart';

class TrainingState {
  final double acuteLoad;
  final double chronicLoad;
  final DateTime? lastQualityDate;
  final DateTime? lastLongRunDate;
  final WeeklyPlan? activePlan;

  TrainingState({
    this.acuteLoad = 0,
    this.chronicLoad = 0,
    this.lastQualityDate,
    this.lastLongRunDate,
    this.activePlan,
  });
}
