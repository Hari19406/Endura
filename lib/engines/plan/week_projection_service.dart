/// WeekProjectionService — resolves a full week for the plan-visibility UI.
///
/// KEY DESIGN RULE:
///   Today  → full pipeline (selector → pace → volume → scaler)
///   Future → projection only (selector → pace → volume, NO scaler)
///   Past   → actual logged data from run history
///
/// CHANGE FROM v1: No longer duplicates template resolution logic.
/// Delegates to WorkoutResolver.resolveTemplate() for consistency.
/// Uses PaceTable + ResolverContext instead of PaceResolver + AthletePaceProfile.
library;

import 'session_selector.dart';
import 'volume_calculator.dart';
import 'workout_resolver.dart';
import '../config/workout_template_library.dart';
import '../daily/dynamic_scaler.dart';
import '../../models/training_phase.dart';
import '../../utils/stats.dart' show RunHistory;


// ============================================================================
// OUTPUT MODELS
// ============================================================================

enum DayStatus { completed, today, projected, rest, missed }

class ProjectedDay {
  final DateTime date;
  final int weekday;
  final DayStatus status;
  final ResolvedWorkout? workout;
  final WorkoutIntent? intent;
  final String? templateName;
  final String dayLabel;
  final double? completedDistanceKm;
  final String? completedPace;
  final int? completedRpe;

  const ProjectedDay({
    required this.date,
    required this.weekday,
    required this.status,
    this.workout,
    this.intent,
    this.templateName,
    required this.dayLabel,
    this.completedDistanceKm,
    this.completedPace,
    this.completedRpe,
  });

  double get distanceKm {
    if (completedDistanceKm != null) return completedDistanceKm!;
    return workout?.totalDistanceKm ?? 0.0;
  }

  bool get hasWorkout =>
      status == DayStatus.today ||
      status == DayStatus.projected ||
      status == DayStatus.completed;

  bool get isQuality => _isQualityIntent(intent);
}

class WeekProjection {
  final List<ProjectedDay> days;
  final int weekNumber;
  final TrainingPhase phase;
  final double totalVolumeKm;
  final int sessionCount;
  final int qualityCount;
  final DateTime weekStart;

  const WeekProjection({
    required this.days,
    required this.weekNumber,
    required this.phase,
    required this.totalVolumeKm,
    required this.sessionCount,
    required this.qualityCount,
    required this.weekStart,
  });
}

// ============================================================================
// SERVICE
// ============================================================================

class WeekProjectionService {
  final SessionSelector _selector;
  final VolumeCalculator _volumeCalculator;
  final WorkoutResolver _resolver;
  final DynamicScaler _scaler;

  const WeekProjectionService({
    SessionSelector? selector,
    VolumeCalculator? volumeCalculator,
    WorkoutResolver? resolver,
    DynamicScaler? scaler,
  })  : _selector = selector ?? const SessionSelector(),
        _volumeCalculator = volumeCalculator ?? const VolumeCalculator(),
        _resolver = resolver ?? const WorkoutResolver(),
        _scaler = scaler ?? const DynamicScaler();

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  WeekProjection projectWeek({
    required int weekNumber,
    required TrainingPhase phase,
    required List<int> trainingDayIndices,
    required ResolverContext resolverContext,
    required ScalingSignals scalingSignals,
    required RaceDistance raceDistance,
    required double weeklyTargetKm,
    required List<RunHistory> completedRuns,
    WorkoutIntent? lastCompletedIntent,
    String? lastCompletedTemplateId,
    int daysSinceLastQuality = 999,
    int daysSinceLastLongRun = 999,
    double? longestRecentRunKm,
    double? avgRpe,
    double weeklyVolumeCompletedKm = 0.0,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final todayIndex = today.weekday - 1;
    final currentMonday = today.subtract(Duration(days: todayIndex));
    final weekStart = DateTime(
      currentMonday.year,
      currentMonday.month,
      currentMonday.day,
    );

    final projectedDays = <ProjectedDay>[];
    double totalVolume = 0;
    int sessions = 0;
    int quality = 0;

    var runningLastIntent = lastCompletedIntent;
    var runningLastTemplateId = lastCompletedTemplateId;
    var runningDaysSinceQuality = daysSinceLastQuality;
    var runningDaysSinceLong = daysSinceLastLongRun;

    for (int dayIdx = 0; dayIdx < 7; dayIdx++) {
      final dayDate = weekStart.add(Duration(days: dayIdx));
      final isToday = _isSameDay(dayDate, today);
      final isPast = dayDate.isBefore(
        DateTime(today.year, today.month, today.day),
      );
      final isTrainingDay = trainingDayIndices.contains(dayIdx);

      // ── PAST: use actual logged data ─────────────────────────────────
      if (isPast) {
        final run = _findRunOnDate(completedRuns, dayDate);

        if (run != null) {
          final intent = _intentFromWorkoutType(run.workoutType);
          projectedDays.add(ProjectedDay(
            date: dayDate,
            weekday: dayIdx,
            status: DayStatus.completed,
            intent: intent,
            dayLabel: _dayLabels[dayIdx],
            completedDistanceKm: run.distance,
            completedPace: run.averagePace,
            completedRpe: run.rpe,
          ));
          totalVolume += run.distance;
          sessions++;
          if (_isQualityIntent(intent)) quality++;
          if (intent != null) runningLastIntent = intent;
          runningDaysSinceQuality =
              _isQualityIntent(intent) ? 0 : runningDaysSinceQuality + 1;
          runningDaysSinceLong =
              intent == WorkoutIntent.endurance ? 0 : runningDaysSinceLong + 1;
        } else {
          projectedDays.add(ProjectedDay(
            date: dayDate,
            weekday: dayIdx,
            status: isTrainingDay ? DayStatus.missed : DayStatus.rest,
            dayLabel: _dayLabels[dayIdx],
          ));
          runningDaysSinceQuality++;
          runningDaysSinceLong++;
        }
        continue;
      }

      // ── REST DAY ─────────────────────────────────────────────────────
      if (!isTrainingDay) {
        projectedDays.add(ProjectedDay(
          date: dayDate,
          weekday: dayIdx,
          status: DayStatus.rest,
          dayLabel: _dayLabels[dayIdx],
        ));
        runningDaysSinceQuality++;
        runningDaysSinceLong++;
        continue;
      }

      // ── TODAY or FUTURE: resolve via pipeline ────────────────────────
      final selectionContext = SelectionContext(
        raceDistance: raceDistance,
        phase: phase,
        readiness: SelectorReadiness.green,
        daysPerWeek: trainingDayIndices.length,
        trainingDayIndices: trainingDayIndices,
        todayDayIndex: dayIdx,
        daysSinceLastQuality: runningDaysSinceQuality,
        daysSinceLastLongRun: runningDaysSinceLong,
        lastCompletedTemplateId: runningLastTemplateId,
        lastCompletedIntent: runningLastIntent,
        plannedIntent: null,
        weekNumber: weekNumber,
        avgRpe: avgRpe,
        weeklyVolumeCompletedKm: weeklyVolumeCompletedKm,
        weeklyTargetKm: weeklyTargetKm,
      );

      final selection = _selector.select(selectionContext);

      if (selection == null) {
        projectedDays.add(ProjectedDay(
          date: dayDate,
          weekday: dayIdx,
          status: DayStatus.rest,
          dayLabel: _dayLabels[dayIdx],
        ));
        runningDaysSinceQuality++;
        runningDaysSinceLong++;
        continue;
      }

      // Calculate distance
      final workoutDistance = _volumeCalculator.calculateWorkoutDistance(
        weeklyTargetKm: weeklyTargetKm,
        template: selection.template,
        raceDistance: raceDistance,
        phase: phase,
        dayRole: selection.dayRole,
        variant: selection.variant,
        longestRecentRunKm: longestRecentRunKm,
      );

      // Resolve template → ResolvedWorkout via WorkoutResolver
      final resolvedWorkout = _resolver.resolveTemplate(
        template: selection.template,
        variant: selection.variant,
        totalDistanceKm: workoutDistance,
        resolverContext: resolverContext,
        phase: phase,
        intent: selection.intent,
      );

      // Apply scaler ONLY for today
      final finalWorkout = isToday
          ? _scaler.scale(resolvedWorkout, scalingSignals).workout
          : resolvedWorkout;

      projectedDays.add(ProjectedDay(
        date: dayDate,
        weekday: dayIdx,
        status: isToday ? DayStatus.today : DayStatus.projected,
        workout: finalWorkout,
        intent: selection.intent,
        templateName: selection.template.name,
        dayLabel: _dayLabels[dayIdx],
      ));

      totalVolume += finalWorkout.totalDistanceKm;
      sessions++;
      if (_isQualityIntent(selection.intent)) quality++;

      runningLastIntent = selection.intent;
      runningLastTemplateId = selection.template.id;
      runningDaysSinceQuality =
          _isQualityIntent(selection.intent) ? 0 : runningDaysSinceQuality + 1;
      runningDaysSinceLong =
          selection.intent == WorkoutIntent.endurance
              ? 0
              : runningDaysSinceLong + 1;
    }

    return WeekProjection(
      days: projectedDays,
      weekNumber: weekNumber,
      phase: phase,
      totalVolumeKm: totalVolume,
      sessionCount: sessions,
      qualityCount: quality,
      weekStart: weekStart,
    );
  }

  // ========================================================================
  // HELPERS
  // ========================================================================

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  RunHistory? _findRunOnDate(List<RunHistory> runs, DateTime date) {
    for (final run in runs) {
      if (_isSameDay(run.date, date)) return run;
    }
    return null;
  }

  WorkoutIntent? _intentFromWorkoutType(String? type) {
    return switch (type) {
      'easy'      => WorkoutIntent.aerobicBase,
      'tempo'     => WorkoutIntent.threshold,
      'threshold' => WorkoutIntent.threshold,
      'interval'  => WorkoutIntent.vo2max,
      'long'      => WorkoutIntent.endurance,
      'recovery'  => WorkoutIntent.recovery,
      _           => null,
    };
  }
}

bool _isQualityIntent(WorkoutIntent? intent) {
  if (intent == null) return false;
  return intent == WorkoutIntent.threshold ||
      intent == WorkoutIntent.vo2max ||
      intent == WorkoutIntent.speed ||
      intent == WorkoutIntent.raceSpecific;
}