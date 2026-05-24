import '../services/coach_message_builder.dart' as message;
import 'vdot_engine/run_history_service.dart';
import 'pace_trend_calculator.dart';
import 'planner/weekly_generator.dart';
import 'planner/race_plan_builder.dart';
import 'planner/absence_detector.dart';
import 'planner/weekly_budget.dart';
import '../models/weekly_plan.dart';
import '../models/workout_type.dart';
import '../models/training_phase.dart';
import '../models/race_plan.dart';
import 'memory/engine_memory.dart';

import '../services/workout_selector.dart' as selector;
import 'package:flutter/foundation.dart';

import 'core/vdot_calculator.dart';
import 'core/pace_table.dart';
import 'config/workout_template_library.dart';
import 'plan/workout_resolver.dart';
import 'plan/session_selector.dart' as session;
import 'plan/week_resolver.dart';
import 'plan/weekly_volume_resolver.dart';
import 'daily/dynamic_scaler.dart';

typedef CoachMessage = message.CoachMessage;

// ============================================================================
// DATA CLASSES
// ============================================================================

class HistoricalTrainingData {
  final int daysSinceLastQuality;
  final int daysSinceLastLongRun;
  final double weeklyVolume;
  final List<SavedRun> recentRuns;

  const HistoricalTrainingData({
    required this.daysSinceLastQuality,
    required this.daysSinceLastLongRun,
    required this.weeklyVolume,
    this.recentRuns = const [],
  });
}

class UserMetrics {
  final int avgEasyPace;
  final int tempoCapabilityPace;
  final int intervalCapabilityPace;
  final double recentAvgDistance;
  final double recentWeeklyVolumeKm;
  final double longestRecentRun;
  final int runsPerWeek;
  final String goalRace;
  final String experienceLevel;
  final String goalIntent;
  final double? avgRpe;
  final selector.RecentRpeTrend recentRpeTrend;
  final bool lastEasyRunTooHard;
  final int? prTimeSeconds;
  final String? prDistance;
  final bool prIsRecent;
  final double weeklyMileageKm;

  const UserMetrics({
    required this.avgEasyPace,
    required this.tempoCapabilityPace,
    required this.intervalCapabilityPace,
    required this.recentAvgDistance,
    required this.recentWeeklyVolumeKm,
    required this.longestRecentRun,
    this.runsPerWeek = 4,
    required this.goalRace,
    this.experienceLevel = 'beginner',
    this.goalIntent = 'structured',
    this.avgRpe,
    this.recentRpeTrend = selector.RecentRpeTrend.unknown,
    this.lastEasyRunTooHard = false,
    this.prTimeSeconds,
    this.prDistance,
    this.prIsRecent = true,
    this.weeklyMileageKm = 0,
  });
}

enum ProgressionDecision { progress, hold, regress }

class ProgressionProfile {
  final ProgressionDecision decision;
  final double weeklyVolumeMultiplier;
  final double longRunMultiplier;
  final double sessionVolumeMultiplier;
  final double sessionIntensityMultiplier;
  final bool allowProgression;

  const ProgressionProfile({
    required this.decision,
    required this.weeklyVolumeMultiplier,
    required this.longRunMultiplier,
    required this.sessionVolumeMultiplier,
    required this.sessionIntensityMultiplier,
    required this.allowProgression,
  });
}

// ============================================================================
// POST-PLAN STATE
// ============================================================================

/// Result of evaluating whether the plan has ended and what state to apply.
class PostPlanState {
  /// The memory to persist (may be identical to input if nothing changed).
  final EngineMemory memory;

  /// True if the race plan's total weeks have now elapsed.
  final bool justCompleted;

  /// True if maintenance mode was auto-entered this evaluation.
  final bool justEnteredMaintenance;

  const PostPlanState({
    required this.memory,
    this.justCompleted = false,
    this.justEnteredMaintenance = false,
  });
}

// ============================================================================
// ENGINE
// ============================================================================

class CoachEngine {
  static const double _maxSafeProgressionMultiplier = 1.0825;

  final message.CoachMessageBuilder _coachMessageBuilder;
  final WorkoutResolver _workoutResolver;
  final WeekResolver _weekResolver;
  final WeeklyVolumeResolver _volumeResolver;

  CoachEngine({
    message.CoachMessageBuilder? coachMessageBuilder,
    WorkoutResolver? workoutResolver,
    WeekResolver? weekResolver,
    WeeklyVolumeResolver? volumeResolver,
  })  : _coachMessageBuilder =
            coachMessageBuilder ?? message.CoachMessageBuilder(),
        _workoutResolver = workoutResolver ?? const WorkoutResolver(),
        _weekResolver = weekResolver ?? const WeekResolver(),
        _volumeResolver = volumeResolver ?? WeeklyVolumeResolver();

  // ── Post-plan state evaluation ────────────────────────────────────────────

  /// Call this once per home-screen load, before getNextCoachMessage.
  ///
  /// Detects plan completion, sets planCompletedAt, and auto-enters maintenance
  /// after 7 days. Returns the (possibly updated) memory for the caller to
  /// persist if [PostPlanState.justCompleted] or
  /// [PostPlanState.justEnteredMaintenance] is true.
  PostPlanState checkAndApplyPostPlanState(EngineMemory memory) {
    final now = DateTime.now();

    // ── Already in maintenance — nothing to re-detect ────────────────────
    if (memory.isInMaintenance) {
      return PostPlanState(memory: memory);
    }

    // ── Check if plan just completed ──────────────────────────────────────
    if (memory.hasRacePlan && memory.planCompletedAt == null) {
      final planWeek = memory.racePlan!.currentWeekNumber(now);
      final totalWeeks = memory.racePlan!.totalWeeks;

      if (planWeek > totalWeeks) {
        // Plan has ended — stamp completion date, clear race plan.
        final updated = memory.copyWith(
          planCompletedAt: now,
          clearRacePlan: true,
          currentPhase: TrainingPhase.base, // neutral phase until new plan
        );
        debugPrint('[CoachEngine] Plan complete detected — week $planWeek > $totalWeeks');
        return PostPlanState(memory: updated, justCompleted: true);
      }
    }

    // ── Auto-enter maintenance after 7 days of inaction ───────────────────
    if (memory.shouldAutoEnterMaintenance) {
      final maintenanceKm = (memory.previousWeekTargetKm ??
              memory.baselineWeeklyKm ??
              20.0) *
          0.85;

      final updated = memory.copyWith(
        isInMaintenance: true,
        currentPhase: TrainingPhase.maintenance,
        baselineWeeklyKm: maintenanceKm,
        previousWeekTargetKm: maintenanceKm,
      );
      debugPrint('[CoachEngine] Auto-entering maintenance mode');
      return PostPlanState(memory: updated, justEnteredMaintenance: true);
    }

    return PostPlanState(memory: memory);
  }

  // ── vDOT / pace table ─────────────────────────────────────────────────────

  PaceTable _buildPaceTable(UserMetrics userMetrics, EngineMemory memory) {
    int vdot = memory.vdotScore;

    if (memory.vdotIsProvisional &&
        userMetrics.prTimeSeconds != null &&
        userMetrics.prDistance != null) {
      final distKm = _prDistanceToKm(userMetrics.prDistance!);
      final confidence = userMetrics.prIsRecent
          ? PrConfidence.high
          : PrConfidence.low;
      vdot = vdotFromPr(
        prTimeSeconds: userMetrics.prTimeSeconds!,
        prDistanceKm: distKm,
        confidence: confidence,
      );
    } else if (memory.vdotIsProvisional && userMetrics.avgEasyPace > 0) {
      vdot = vdotFromEasyPace(userMetrics.avgEasyPace.toDouble());
    }

    debugPrint('[PaceTable] vdot=$vdot, provisional=${memory.vdotIsProvisional}');
    return PaceTable(vdot.clamp(30, 85));
  }

  ResolverContext _buildResolverContext(
      UserMetrics userMetrics, EngineMemory memory) {
    return ResolverContext(
      paceTable: _buildPaceTable(userMetrics, memory),
      goalRaceDistance: _goalRaceToPRDistance(_mapGoalRace(userMetrics.goalRace)),
      goalRaceTimeSeconds: null,
    );
  }

  // ── Primary entry point ───────────────────────────────────────────────────

  CoachMessage? getNextCoachMessage({
    required UserMetrics userMetrics,
    required selector.RunAnalysis runAnalysis,
    required HistoricalTrainingData historicalTrainingData,
    required selector.WorkoutId? lastWorkoutType,
    required EngineMemory memory,
    List<int> trainingDayIndices = const [],
    session.SelectorReadiness? preRunReadiness,
  }) {
    // ── Guard: maintenance mode uses a simplified path ────────────────────
    if (memory.isInMaintenance) {
      return _getMaintenanceCoachMessage(
        userMetrics: userMetrics,
        memory: memory,
        trainingDayIndices: trainingDayIndices,
        preRunReadiness: preRunReadiness,
      );
    }

    final now = DateTime.now();
    final resolvedRunsPerWeek = userMetrics.runsPerWeek > 0
        ? userMetrics.runsPerWeek
        : (trainingDayIndices.isEmpty ? 4 : trainingDayIndices.length);
    final fourWeekAvgKm = userMetrics.recentWeeklyVolumeKm > 0
        ? userMetrics.recentWeeklyVolumeKm
        : userMetrics.recentAvgDistance * resolvedRunsPerWeek;

    final effectiveTrainingDays = trainingDayIndices.isNotEmpty
        ? trainingDayIndices
        : List.generate(resolvedRunsPerWeek, (i) => i);

    // ── Layer 1: Macro plan ───────────────────────────────────────────────
    final absence = AbsenceDetector.assess(lastRunDate: memory.lastRunDate);

    WeekTarget weekTarget;
    TrainingPhase phase;

    if (memory.hasRacePlan) {
      final raceWeek = memory.racePlan!.currentWeek(now);
      weekTarget = raceWeek ??
          RacePlanBuilder.exploreTarget(
            fourWeekAvgKm: fourWeekAvgKm,
            experienceLevel: memory.racePlan!.experienceLevel,
          );
      phase = weekTarget.phase;
    } else {
      weekTarget = RacePlanBuilder.exploreTarget(
        fourWeekAvgKm: fourWeekAvgKm,
        experienceLevel: userMetrics.experienceLevel,
      );
      phase = memory.currentPhase;
    }

    final progression = _resolveProgression(
      runAnalysis: runAnalysis,
      historicalTrainingData: historicalTrainingData,
      memory: memory,
      now: now,
      trainingDayIndices: effectiveTrainingDays,
    );

    final weekNum = memory.hasRacePlan
        ? memory.racePlan!.currentWeekNumber(now)
        : memory.currentWeek;

    final is3to1Cutback = weekNum % 4 == 0;

    // ── Weekly target km: mileage-system path vs legacy path ─────────────
    final double finalWeeklyTargetKm;

    if (memory.baselineWeeklyKm != null) {
      finalWeeklyTargetKm = _volumeResolver.resolveWeeklyTarget(
        memory: memory,
        goalRace: _mapGoalRace(userMetrics.goalRace),
        currentWeek: weekNum,
        lastDecision: progression.decision,
        is3to1Cutback: is3to1Cutback,
      );
    } else {
      final baseWeeklyTargetKm = WeeklyGenerator.targetFor(
        raceWeek: weekTarget,
        fourWeekAvgKm: fourWeekAvgKm,
        absence: absence,
      );
      final adjustedTargetKm = baseWeeklyTargetKm *
          progression.weeklyVolumeMultiplier
              .clamp(0.90, _maxSafeProgressionMultiplier);
      finalWeeklyTargetKm = _capFinalProgressionValue(
        baseValue: fourWeekAvgKm,
        finalValue: _roundHalf(adjustedTargetKm),
      );
    }

    // ── Layer 2: Weekly budget ────────────────────────────────────────────
    final thisWeekRuns = _filterThisWeek(historicalTrainingData.recentRuns, now);
    final adaptedLongRunKm = _capFinalProgressionValue(
      baseValue: weekTarget.longRunKm,
      finalValue: _roundHalf(
        _clampLongRunTarget(
          current: weekTarget.longRunKm,
          adapted: weekTarget.longRunKm *
              progression.longRunMultiplier
                  .clamp(0.90, _maxSafeProgressionMultiplier),
        ),
      ),
    );
    final adaptedWeekTarget = weekTarget.copyWith(
      targetKm: finalWeeklyTargetKm,
      longRunKm: adaptedLongRunKm,
    );
    final budget = WeeklyBudget.compute(
      thisWeekRuns: thisWeekRuns,
      weekTarget: adaptedWeekTarget,
    );

    // ── Layer 3: Week resolution ──────────────────────────────────────────
    final weekResolution = _weekResolver.resolve(
      weekTarget: adaptedWeekTarget,
      trainingDayIndices: effectiveTrainingDays,
      raceDistance: _mapGoalRace(userMetrics.goalRace),
      phase: phase,
      weekNumber: weekNum,
      recentTemplateIds: memory.recentTemplateIds,
      isCutbackWeek: is3to1Cutback,
    );

    final effectivePlannedIntent = weekResolution.intentForToday(now);

    final selectionContext = session.SelectionContext(
      raceDistance: _mapGoalRace(userMetrics.goalRace),
      phase: _mapTrainingPhase(phase),
      readiness: preRunReadiness ?? session.SelectorReadiness.green,
      daysPerWeek: resolvedRunsPerWeek,
      trainingDayIndices: effectiveTrainingDays,
      todayDayIndex: now.weekday - 1,
      daysSinceLastQuality: historicalTrainingData.daysSinceLastQuality,
      daysSinceLastLongRun: historicalTrainingData.daysSinceLastLongRun,
      lastCompletedTemplateId: memory.lastCompletedTemplateId,
      lastCompletedIntent: memory.lastCompletedWorkoutIntent
          ?? _lastWorkoutToIntent(lastWorkoutType),
      plannedIntent: effectivePlannedIntent,
      weekNumber: weekNum,
      avgRpe: runAnalysis.avgRpe ?? userMetrics.avgRpe,
      weeklyVolumeCompletedKm: budget.volumeDoneKm,
      weeklyTargetKm: finalWeeklyTargetKm,
      qualitySessionsDoneThisWeek: budget.qualityDone,
      longRunDoneThisWeek: budget.longRunDone,
      experienceLevel: userMetrics.experienceLevel,
      goalIntent: userMetrics.goalIntent,
      weekPercentageSum: weekResolution.weekPercentageSum,
    );

    final resolverContext = _buildResolverContext(userMetrics, memory);

    final scalingSignals = ScalingSignals(
      avgRpe: runAnalysis.avgRpe ?? userMetrics.avgRpe,
      lastEasyRunTooHard:
          runAnalysis.lastEasyRunTooHard || userMetrics.lastEasyRunTooHard,
    );

    assert(() {
      print('[CoachEngine] week: $weekNum, phase: ${phase.name}');
      print('[CoachEngine] todayIntent: ${effectivePlannedIntent?.name}');
      print('[CoachEngine] vDOT: ${resolverContext.paceTable.vdotScore}');
      print('[CoachEngine] weeklyTargetKm: $finalWeeklyTargetKm'
          ' (mileageSystem: ${memory.baselineWeeklyKm != null})');
      return true;
    }());

    final result = _workoutResolver.resolve(
      selectionContext: selectionContext,
      resolverContext: resolverContext,
      scalingSignals: scalingSignals,
      longestRecentRunKm: userMetrics.longestRecentRun,
    );

    if (result.isRestDay) return null;

    assert(() {
      print('[CoachEngine] intent: ${result.workout?.intent.name}');
      print('[CoachEngine] wasDowngraded: ${result.wasDowngraded}');
      return true;
    }());

    // ── Build coach context from real signals ─────────────────────────────
    final paces = historicalTrainingData.recentRuns
        .map((r) => paceStringToSeconds(r.averagePace))
        .where((p) => p > 0)
        .toList();
    final paceTrendStr = PaceTrendCalculator.calculate(paces);
    final insufficientPaceData = paces.length < 3;

    final coachContext = message.CoachContext(
      totalRunsCompleted: memory.totalRunsCompleted,
      daysSinceLastRun: absence.daysMissed,
      avgRpe: runAnalysis.avgRpe ?? userMetrics.avgRpe,
      highRpeRecently: memory.hasHighRpe(n: 2, threshold: 8, withinDays: 3),
      easyRunFeltTooHard:
          runAnalysis.lastEasyRunTooHard || userMetrics.lastEasyRunTooHard,
      progression: _toMessageProgressionSignal(progression.decision),
      wasDowngraded: result.wasDowngraded,
      scalingAdjustments: result.scalingAdjustments,
      paceTrending: paceTrendStr == 'improving',
      paceInsufficientData: insufficientPaceData,
    );

    // ── Derive next planned session ───────────────────────────────────────
    final nextInfo = _resolveNextPlannedSession(
      weekResolution: weekResolution,
      now: now,
      trainingDayIndices: effectiveTrainingDays,
    );

    return _coachMessageBuilder.buildMessage(
      context: coachContext,
      resolvedWorkout: result.workout!,
      phase: phase,
      weekNumber: weekNum,
      nextPlannedIntent: nextInfo.$1,
      nextPlannedLabel: nextInfo.$2,
    );
  }

  // ── Maintenance mode coach message ────────────────────────────────────────

  CoachMessage? _getMaintenanceCoachMessage({
    required UserMetrics userMetrics,
    required EngineMemory memory,
    required List<int> trainingDayIndices,
    session.SelectorReadiness? preRunReadiness,
  }) {
    final now = DateTime.now();
    final resolvedRunsPerWeek = trainingDayIndices.isNotEmpty
        ? trainingDayIndices.length
        : userMetrics.runsPerWeek;
    final effectiveTrainingDays = trainingDayIndices.isNotEmpty
        ? trainingDayIndices
        : List.generate(resolvedRunsPerWeek, (i) => i);
    final maintenanceKm = memory.baselineWeeklyKm ?? 20.0;

    // Build a synthetic WeekTarget for maintenance.
    final weekTarget = WeekTarget(
      week: memory.currentWeek,
      phase: TrainingPhase.maintenance,
      targetKm: maintenanceKm,
      longRunKm: maintenanceKm * 0.30,
      qualityCount: 1,
      hasLongRun: true,
      keySession: 'easy',
    );

    final weekResolution = _weekResolver.resolve(
      weekTarget: weekTarget,
      trainingDayIndices: effectiveTrainingDays,
      raceDistance: _mapGoalRace(userMetrics.goalRace),
      phase: TrainingPhase.maintenance,
      weekNumber: memory.currentWeek,
      recentTemplateIds: memory.recentTemplateIds,
      isCutbackWeek: false,
    );

    final effectivePlannedIntent = weekResolution.intentForToday(now);

    final selectionContext = session.SelectionContext(
      raceDistance: _mapGoalRace(userMetrics.goalRace),
      phase: TrainingPhase.maintenance,
      readiness: preRunReadiness ?? session.SelectorReadiness.green,
      daysPerWeek: resolvedRunsPerWeek,
      trainingDayIndices: effectiveTrainingDays,
      todayDayIndex: now.weekday - 1,
      daysSinceLastQuality: 999,
      daysSinceLastLongRun: 999,
      lastCompletedTemplateId: memory.lastCompletedTemplateId,
      lastCompletedIntent: memory.lastCompletedWorkoutIntent,
      plannedIntent: effectivePlannedIntent,
      weekNumber: memory.currentWeek,
      avgRpe: null,
      weeklyVolumeCompletedKm: 0,
      weeklyTargetKm: maintenanceKm,
      qualitySessionsDoneThisWeek: 0,
      longRunDoneThisWeek: false,
      experienceLevel: userMetrics.experienceLevel,
      goalIntent: 'steady',
      weekPercentageSum: weekResolution.weekPercentageSum,
    );

    final resolverContext = _buildResolverContext(userMetrics, memory);
    final scalingSignals = const ScalingSignals(avgRpe: null, lastEasyRunTooHard: false);

    final result = _workoutResolver.resolve(
      selectionContext: selectionContext,
      resolverContext: resolverContext,
      scalingSignals: scalingSignals,
      longestRecentRunKm: userMetrics.longestRecentRun,
    );

    if (result.isRestDay) return null;

    final coachContext = message.CoachContext(
      totalRunsCompleted: memory.totalRunsCompleted,
      daysSinceLastRun: 0,
      avgRpe: null,
      highRpeRecently: false,
      easyRunFeltTooHard: false,
      progression: message.ProgressionSignal.holding,
      wasDowngraded: false,
      scalingAdjustments: const [],
      paceTrending: false,
      paceInsufficientData: true,
    );

    final nextInfo = _resolveNextPlannedSession(
      weekResolution: weekResolution,
      now: now,
      trainingDayIndices: effectiveTrainingDays,
    );

    return _coachMessageBuilder.buildMessage(
      context: coachContext,
      resolvedWorkout: result.workout!,
      phase: TrainingPhase.maintenance,
      weekNumber: memory.currentWeek,
      nextPlannedIntent: nextInfo.$1,
      nextPlannedLabel: nextInfo.$2,
    );
  }

  // ── Next planned session derivation ──────────────────────────────────────

  (WorkoutIntent?, String?) _resolveNextPlannedSession({
    required WeekResolution weekResolution,
    required DateTime now,
    required List<int> trainingDayIndices,
  }) {
    final todayIndex = now.weekday - 1;

    for (int dayIdx = todayIndex + 1; dayIdx <= 6; dayIdx++) {
      if (!trainingDayIndices.contains(dayIdx)) continue;

      final slot = weekResolution.slotFor(dayIdx);
      if (slot == null || slot.isRest || slot.intent == null) continue;

      final intent = slot.intent!;
      final daysAhead = dayIdx - todayIndex;
      final dayLabel = daysAhead == 1 ? 'Tomorrow' : _weekdayName(dayIdx);
      return (intent, '$dayLabel · ${_intentDisplayName(intent)}');
    }

    return (null, null);
  }

  String _weekdayName(int dayIndex) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[dayIndex.clamp(0, 6)];
  }

  String _intentDisplayName(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.aerobicBase  => 'Easy Run',
      WorkoutIntent.endurance    => 'Long Run',
      WorkoutIntent.threshold    => 'Threshold Run',
      WorkoutIntent.vo2max       => 'Interval Session',
      WorkoutIntent.speed        => 'Speed Session',
      WorkoutIntent.raceSpecific => 'Race Pace Run',
      WorkoutIntent.recovery     => 'Recovery Run',
    };
  }

  // ── Week resolution for home screen ──────────────────────────────────────

  WeekResolution resolveCurrentWeek({
    required UserMetrics userMetrics,
    required EngineMemory memory,
    required List<int> trainingDayIndices,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final resolvedRunsPerWeek = userMetrics.runsPerWeek > 0
        ? userMetrics.runsPerWeek
        : (trainingDayIndices.isEmpty ? 4 : trainingDayIndices.length);
    final fourWeekAvgKm = userMetrics.recentWeeklyVolumeKm > 0
        ? userMetrics.recentWeeklyVolumeKm
        : userMetrics.recentAvgDistance * resolvedRunsPerWeek;

    WeekTarget weekTarget;
    TrainingPhase phase;

    // Maintenance: synthetic target
    if (memory.isInMaintenance) {
      final maintenanceKm = memory.baselineWeeklyKm ?? 20.0;
      weekTarget = WeekTarget(
        week: memory.currentWeek,
        phase: TrainingPhase.maintenance,
        targetKm: maintenanceKm,
        longRunKm: maintenanceKm * 0.30,
        qualityCount: 1,
        hasLongRun: true,
        keySession: 'easy',
      );
      phase = TrainingPhase.maintenance;
    } else if (memory.hasRacePlan) {
      final raceWeek = memory.racePlan!.currentWeek(today);
      weekTarget = raceWeek ??
          RacePlanBuilder.exploreTarget(
            fourWeekAvgKm: fourWeekAvgKm,
            experienceLevel: memory.racePlan!.experienceLevel,
          );
      phase = weekTarget.phase;
    } else {
      weekTarget = RacePlanBuilder.exploreTarget(
        fourWeekAvgKm: fourWeekAvgKm,
        experienceLevel: userMetrics.experienceLevel,
      );
      phase = memory.currentPhase;
    }

    final weekNum = memory.hasRacePlan
        ? memory.racePlan!.currentWeekNumber(today)
        : memory.currentWeek;

    final effectiveTrainingDays = trainingDayIndices.isNotEmpty
        ? trainingDayIndices
        : List.generate(resolvedRunsPerWeek, (i) => i);

    return _weekResolver.resolve(
      weekTarget: weekTarget,
      trainingDayIndices: effectiveTrainingDays,
      raceDistance: _mapGoalRace(userMetrics.goalRace),
      phase: phase,
      weekNumber: weekNum,
      recentTemplateIds: memory.recentTemplateIds,
    );
  }

  // ── User metrics factory ──────────────────────────────────────────────────

  UserMetrics createUserMetrics({
    required List<SavedRun> runHistory,
    String experienceLevel = 'beginner',
    required String goalRace,
    int runsPerWeek = 4,
    int? prTimeSeconds,
    String? prDistance,
  }) {
    final recentRuns = runHistory.take(5).toList();
    final avgDistance = recentRuns.isEmpty
        ? 5.0
        : recentRuns.fold(0.0, (sum, r) => sum + r.distance) / recentRuns.length;
    final longestRun = runHistory.isEmpty
        ? 5.0
        : runHistory.map((r) => r.distance).reduce((a, b) => a > b ? a : b);

    int avgEasyPace = experienceLevel == 'advanced'
        ? 300
        : experienceLevel == 'intermediate'
            ? 330
            : 360;

    if (recentRuns.isNotEmpty) {
      final paces = recentRuns
          .map((r) => paceStringToSeconds(r.averagePace))
          .where((p) => p > 0)
          .toList();
      if (paces.isNotEmpty) {
        avgEasyPace =
            (paces.reduce((a, b) => a + b) / paces.length).round();
      }
    }

    final weeklyVolumeKm = avgDistance * runsPerWeek;

    return UserMetrics(
      avgEasyPace: avgEasyPace,
      tempoCapabilityPace: (avgEasyPace * 0.85).round(),
      intervalCapabilityPace: (avgEasyPace * 0.75).round(),
      recentAvgDistance: avgDistance,
      recentWeeklyVolumeKm: weeklyVolumeKm,
      longestRecentRun: longestRun,
      runsPerWeek: runsPerWeek,
      goalRace: goalRace,
      avgRpe: null,
      recentRpeTrend: selector.RecentRpeTrend.unknown,
      lastEasyRunTooHard: false,
      prTimeSeconds: prTimeSeconds,
      prDistance: prDistance,
      weeklyMileageKm: weeklyVolumeKm,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<RunSummary> _filterThisWeek(List<SavedRun> runs, DateTime now) {
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final mondayStart = DateTime(monday.year, monday.month, monday.day);
    return runs
        .where((r) => r.date.isAfter(mondayStart))
        .map((r) => RunSummary(
              date: r.date,
              distanceKm: r.distance,
              type: _inferWorkoutType(r),
              rpe: r.rpe,
            ))
        .toList();
  }

  WorkoutType _inferWorkoutType(SavedRun run) {
    if (run.workoutType != null && run.workoutType != 'unknown') {
      return WorkoutTypeX.fromString(run.workoutType!);
    }
    return WorkoutType.easy;
  }

  ProgressionProfile _progressionProfile({
    required selector.RunAnalysis runAnalysis,
    required HistoricalTrainingData historicalTrainingData,
    required EngineMemory memory,
    required int splitSize,
  }) {
    final avgRpe = runAnalysis.avgRpe ?? memory.averageRecentRpe(3) ?? 5.5;
    final hasSufficientRpeTrendData =
        runAnalysis.recentRpeTrend != selector.RecentRpeTrend.unknown;
    final rpeStableOrLower =
        runAnalysis.recentRpeTrend == selector.RecentRpeTrend.stable ||
            runAnalysis.recentRpeTrend == selector.RecentRpeTrend.decreasing;
    final risingRpe =
        runAnalysis.recentRpeTrend == selector.RecentRpeTrend.increasing;
    final completedSuccessfully = _completedSuccessfully(
      historicalTrainingData,
      memory.activePlan,
      splitSize,
    );
    final afterRecoveryDay = memory.lastCompletedType == WorkoutType.recovery;
    final repeatedDowngrades = _repeatedDowngradePressure(
      historicalTrainingData.recentRuns,
    );
    final consistentlyHighRpe =
        avgRpe >= 7.0 || memory.hasHighRpe(n: 3, threshold: 7);

    if (consistentlyHighRpe || repeatedDowngrades) {
      return const ProgressionProfile(
        decision: ProgressionDecision.regress,
        weeklyVolumeMultiplier: 0.92,
        longRunMultiplier: 0.90,
        sessionVolumeMultiplier: 0.94,
        sessionIntensityMultiplier: 1.02,
        allowProgression: false,
      );
    }

    if (afterRecoveryDay) {
      return const ProgressionProfile(
        decision: ProgressionDecision.hold,
        weeklyVolumeMultiplier: 1.0,
        longRunMultiplier: 1.0,
        sessionVolumeMultiplier: 0.98,
        sessionIntensityMultiplier: 1.0,
        allowProgression: false,
      );
    }

    if (risingRpe || !completedSuccessfully) {
      return const ProgressionProfile(
        decision: ProgressionDecision.hold,
        weeklyVolumeMultiplier: 1.0,
        longRunMultiplier: 1.0,
        sessionVolumeMultiplier: 0.98,
        sessionIntensityMultiplier: 1.0,
        allowProgression: false,
      );
    }

    if (hasSufficientRpeTrendData &&
        rpeStableOrLower &&
        avgRpe <= 5.5 &&
        completedSuccessfully) {
      return const ProgressionProfile(
        decision: ProgressionDecision.progress,
        weeklyVolumeMultiplier: 1.07,
        longRunMultiplier: 1.06,
        sessionVolumeMultiplier: 1.04,
        sessionIntensityMultiplier: 0.99,
        allowProgression: true,
      );
    }

    return const ProgressionProfile(
      decision: ProgressionDecision.hold,
      weeklyVolumeMultiplier: 1.0,
      longRunMultiplier: 1.0,
      sessionVolumeMultiplier: 1.0,
      sessionIntensityMultiplier: 1.0,
      allowProgression: false,
    );
  }

  bool _completedSuccessfully(
    HistoricalTrainingData historicalTrainingData,
    WeeklyPlan? activePlan,
    int splitSize,
  ) {
    final recentRuns = historicalTrainingData.recentRuns.take(3).toList();
    if (recentRuns.isEmpty) return true;

    final rpeSum = recentRuns
        .where((r) => r.rpe != null)
        .fold<double>(0.0, (sum, r) => sum + r.rpe!);
    final rpeCount = recentRuns.where((r) => r.rpe != null).length;
    final rpeOk = rpeCount == 0 || (rpeSum / rpeCount) <= 6.5;

    if (activePlan == null) return rpeOk;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final plannedDaysSoFar = activePlan.days.where((d) {
      if (d.isRestDay) return false;
      final plannedDate = DateTime(d.date.year, d.date.month, d.date.day);
      return !plannedDate.isAfter(todayDate);
    }).toList();

    final completed = plannedDaysSoFar.where((d) => d.isCompleted).length;
    final planned = plannedDaysSoFar.length;
    final completionRate = planned == 0 ? 1.0 : completed / planned;

    final progressThreshold = _progressThreshold(splitSize);
    final holdThreshold = _holdThreshold(splitSize);

    if (completionRate >= progressThreshold) return true;
    if (completionRate >= holdThreshold) return rpeOk;
    return false;
  }

  double _progressThreshold(int splitSize) => switch (splitSize) {
        3 => 1.0,
        4 => 0.75,
        5 => 0.80,
        6 => 0.83,
        _ => 0.80,
      };

  double _holdThreshold(int splitSize) => switch (splitSize) {
        3 => 0.67,
        4 => 0.50,
        5 => 0.60,
        6 => 0.50,
        _ => 0.60,
      };

  bool _repeatedDowngradePressure(List<SavedRun> recentRuns) {
    final recent = recentRuns.take(3).toList();
    if (recent.length < 2) return false;
    final pressured = recent.where((r) {
      final isEasyLike =
          r.workoutType == 'easy' || r.workoutType == 'recovery';
      return isEasyLike && (r.rpe ?? 0) >= 7;
    }).length;
    return pressured >= 2;
  }

  double _clampLongRunTarget(
      {required double current, required double adapted}) {
    if (current <= 0) return adapted;
    return adapted.clamp(current * 0.90, current * 1.10);
  }

  double _capFinalProgressionValue({
    required double baseValue,
    required double finalValue,
  }) {
    if (baseValue <= 0) return finalValue;
    return finalValue > baseValue * _maxSafeProgressionMultiplier
        ? baseValue * _maxSafeProgressionMultiplier
        : finalValue;
  }

  double _roundHalf(double value) => (value * 2).round() / 2;

  ProgressionProfile _resolveProgression({
    required selector.RunAnalysis runAnalysis,
    required HistoricalTrainingData historicalTrainingData,
    required EngineMemory memory,
    required DateTime now,
    required List<int> trainingDayIndices,
  }) {
    final lastEval = memory.lastProgressionEvaluationDate;
    final hasEnoughData = memory.totalRunsCompleted >= 3;
    final daysSinceLast =
        lastEval != null ? now.difference(lastEval).inDays : 999;
    final alreadyEvaluated = lastEval != null && daysSinceLast < 7;

    if (!hasEnoughData) {
      return _decisionToProfile(ProgressionDecision.hold);
    }

    if (alreadyEvaluated && memory.weeklyProgressionDecision != null) {
      return _decisionToProfile(memory.weeklyProgressionDecision!);
    }

    return _progressionProfile(
      runAnalysis: runAnalysis,
      historicalTrainingData: historicalTrainingData,
      memory: memory,
      splitSize: trainingDayIndices.length,
    );
  }

  ProgressionProfile _decisionToProfile(ProgressionDecision decision) {
    return switch (decision) {
      ProgressionDecision.progress => const ProgressionProfile(
          decision: ProgressionDecision.progress,
          weeklyVolumeMultiplier: 1.07,
          longRunMultiplier: 1.06,
          sessionVolumeMultiplier: 1.04,
          sessionIntensityMultiplier: 0.99,
          allowProgression: true,
        ),
      ProgressionDecision.hold => const ProgressionProfile(
          decision: ProgressionDecision.hold,
          weeklyVolumeMultiplier: 1.0,
          longRunMultiplier: 1.0,
          sessionVolumeMultiplier: 1.0,
          sessionIntensityMultiplier: 1.0,
          allowProgression: false,
        ),
      ProgressionDecision.regress => const ProgressionProfile(
          decision: ProgressionDecision.regress,
          weeklyVolumeMultiplier: 0.92,
          longRunMultiplier: 0.90,
          sessionVolumeMultiplier: 0.94,
          sessionIntensityMultiplier: 1.02,
          allowProgression: false,
        ),
    };
  }

  // ── Type mappers ──────────────────────────────────────────────────────────

  RaceDistance _mapGoalRace(String goalRace) => switch (goalRace) {
        '5k'            => RaceDistance.fiveK,
        '10k'           => RaceDistance.tenK,
        'half_marathon' => RaceDistance.halfMarathon,
        'marathon'      => RaceDistance.marathon,
        _               => RaceDistance.fiveK,
      };

  TrainingPhase _mapTrainingPhase(TrainingPhase phase) => phase;

  double _prDistanceToKm(String distance) => switch (distance) {
        '5k'            => 5.0,
        '10k'           => 10.0,
        'half'          => 21.0975,
        'half_marathon' => 21.0975,
        'marathon'      => 42.195,
        _               => 5.0,
      };

  PRDistance? _goalRaceToPRDistance(RaceDistance race) => switch (race) {
        RaceDistance.fiveK        => PRDistance.fiveK,
        RaceDistance.tenK         => PRDistance.tenK,
        RaceDistance.halfMarathon => PRDistance.halfMarathon,
        RaceDistance.marathon     => PRDistance.marathon,
      };

  WorkoutIntent? _lastWorkoutToIntent(selector.WorkoutId? id) {
    if (id == null) return null;
    return switch (id) {
      selector.WorkoutId.easyRun         => WorkoutIntent.aerobicBase,
      selector.WorkoutId.easyStrides     => WorkoutIntent.aerobicBase,
      selector.WorkoutId.tempoRun        => WorkoutIntent.threshold,
      selector.WorkoutId.intervalWorkout => WorkoutIntent.vo2max,
      selector.WorkoutId.longEasy        => WorkoutIntent.endurance,
      selector.WorkoutId.recoveryRun     => WorkoutIntent.recovery,
      selector.WorkoutId.restDay         => null,
    };
  }

  message.ProgressionSignal _toMessageProgressionSignal(
          ProgressionDecision decision) =>
      switch (decision) {
        ProgressionDecision.progress => message.ProgressionSignal.progressing,
        ProgressionDecision.hold     => message.ProgressionSignal.holding,
        ProgressionDecision.regress  => message.ProgressionSignal.steppingBack,
      };
}