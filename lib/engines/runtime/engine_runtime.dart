import 'package:flutter/foundation.dart';
import '../memory/engine_memory_service.dart';
import '../memory/engine_memory.dart';
import '../config/workout_template_library.dart';
import '../../models/workout_type.dart';
import '../../utils/database_service.dart';
import '../progression_decision.dart';
import '../../services/profile_service.dart';

/// Called once after every completed run to keep all coaching state current.
///
/// Responsibilities:
///   • Record RPE
///   • Advance the workout sequence (lastCompletedType)
///   • Derive and store the training phase
///   • Track template rotation (recentTemplateIds for WeekResolver)
///   • Mark today's planned day as completed in the active weekly plan
///   • Calibrate vDOT from actual vs expected pace
///   • Save Monday progression evaluation date
///   • Accumulate weeklyCompletedKm (v6)
class EngineRuntime {
  static final EngineMemoryService _memoryService = EngineMemoryService();

  /// Call this from [RunSummaryScreen._finaliseRun()] after saving the run to the DB.
  static Future<void> processRun({
    required double durationMinutes,
    required double speed,
    required DateTime runDate,
    required String workoutType,
    // ── v6: required for km-based completion tracking ─────────────────────
    required double distanceKm,
    int? rpe,
    String? templateId,
    WorkoutIntent? completedIntent,
    double? actualPaceSecondsPerKm,
    double? expectedPaceSecondsPerKm,
    ProgressionDecision? weeklyProgressionDecision,
  }) async {
    try {
      final totalRuns = await _getTotalRunCount();
      final type = WorkoutTypeX.fromString(workoutType);

      var updated = await _memoryService.recordRun(
        workoutType: type,
        rpe: rpe,
        runDate: runDate,
        totalRunCount: totalRuns,
        distanceKm: distanceKm,
        templateId: templateId,
        completedIntent: completedIntent,
      );

      if (updated.activePlan != null) {
        final markedPlan = updated.activePlan!.withDayCompleted(runDate);
        await _memoryService.saveActivePlan(markedPlan);
      }

      // ── vDOT calibration from pace signals ────────────────────────────
      final calibrated = _calibrateVdot(
        current: updated,
        actualPace: actualPaceSecondsPerKm,
        expectedPace: expectedPaceSecondsPerKm,
        rpe: rpe,
        intent: completedIntent,
      );
      if (calibrated != null) {
        updated = calibrated;
        await _memoryService.save(calibrated);
      }

      // ── Weekly: save progression evaluation date ──────────────────────
      if (_shouldEvaluateProgression(updated, runDate)) {
        // Use caller-supplied decision if provided, otherwise derive from
        // the 3-signal spec stored in memory.
        final resolvedDecision = weeklyProgressionDecision ??
            _computeDecisionFromMemory(updated);

        // Fold the weekly training-adaptation signal into the pending nudge so
        // vDOT drifts upward after sustained progress even when the runner hits
        // prescribed paces exactly (pace-only calibration requires outrunning
        // the prescription to fire).
        final decisionNudge = resolvedDecision == ProgressionDecision.progress
            ? 1
            : resolvedDecision == ProgressionDecision.regress
                ? -1
                : 0;

        final pacePending = updated.pendingVdotNudge;
        final totalNudge = (pacePending + decisionNudge).clamp(-3, 3);
        final appliedNudge = totalNudge.clamp(-1, 1);
        final newVdot = (updated.vdotScore + appliedNudge).clamp(30, 85);

        updated = updated.copyWith(
          lastProgressionEvaluationDate: runDate,
          vdotScore: newVdot,
          weeklyProgressionDecision: resolvedDecision,
          vdotIsProvisional: false,
          pendingVdotNudge: 0,
        );

        debugPrint(
          '[EngineRuntime] Weekly eval: vDOT ${updated.vdotScore - appliedNudge} → $newVdot '
          '(pacePending=$pacePending decisionNudge=$decisionNudge applied=$appliedNudge) '
          'progression=${resolvedDecision.name}',
        );

        await _memoryService.save(updated);
        // Keep profiles table vdot_score current so it reflects real fitness
        ProfileService.instance.updateField('vdot_score', newVdot).ignore();
      }

      debugPrint(
        '[EngineRuntime] type=$workoutType rpe=$rpe distanceKm=$distanceKm '
        'weeklyCompletedKm=${updated.weeklyCompletedKm} '
        'completionRate=${updated.weeklyCompletionRate?.toStringAsFixed(2)} '
        'downgrades=${updated.weeklyDowngradeCount} '
        'phase=${updated.currentPhase.name} totalRuns=$totalRuns '
        'vdot=${updated.vdotScore} template=$templateId',
      );
    } catch (e) {
      debugPrint('[EngineRuntime] processRun error: $e');
    }
  }

  // ── vDOT calibration ──────────────────────────────────────────────────────

  static EngineMemory? _calibrateVdot({
    required EngineMemory current,
    required double? actualPace,
    required double? expectedPace,
    required int? rpe,
    required WorkoutIntent? intent,
  }) {
    if (actualPace == null || expectedPace == null) return null;
    if (expectedPace <= 0 || actualPace <= 0) return null;

    // Only calibrate on easy and threshold runs.
    const calibratableIntents = {
      WorkoutIntent.aerobicBase,
      WorkoutIntent.threshold,
    };
    if (intent != null && !calibratableIntents.contains(intent)) return null;

    final paceDelta = expectedPace - actualPace;
    if (paceDelta.abs() < 10) return null;

    int nudge = 0;
    if (paceDelta > 10 && (rpe == null || rpe <= 5)) {
      nudge = 1;
    } else if (paceDelta < -10 && (rpe != null && rpe >= 7)) {
      nudge = -1;
    }

    if (nudge == 0) return null;

    final banked = (current.pendingVdotNudge + nudge).clamp(-3, 3);

    debugPrint(
      '[EngineRuntime] vDOT signal banked: nudge=$nudge '
      'pending=${current.pendingVdotNudge} → $banked '
      '(actualPace=${actualPace.round()} expectedPace=${expectedPace.round()} rpe=$rpe)',
    );

    return current.copyWith(pendingVdotNudge: banked);
  }

  static bool _shouldEvaluateProgression(EngineMemory memory, DateTime today) {
    if (memory.lastProgressionEvaluationDate == null) {
      return memory.totalRunsCompleted >= 3;
    }
    final daysSinceLast =
        today.difference(memory.lastProgressionEvaluationDate!).inDays;
    return daysSinceLast >= 7;
  }

  // ── Progression decision from memory (V1 spec) ───────────────────────────
  //
  // Uses the same 3-signal logic as _progressionProfile in coach_engine_v2:
  //   1. RPE trend   — from recentRpeEntries
  //   2. Completion% — weeklyCompletedKm / weeklyPlannedKm
  //   3. Downgrades  — weeklyDowngradeCount

  static ProgressionDecision _computeDecisionFromMemory(EngineMemory memory) {
    // ── Signal 1: RPE trend ──────────────────────────────────────────────
    final rpeIncreasing = _isRpeTrendIncreasing(memory);
    final rpeStableOrDecreasing = !rpeIncreasing &&
        memory.recentRpeEntries.length >= 2;

    // ── Signal 2: Completion % ───────────────────────────────────────────
    final completionRate = memory.weeklyCompletionRate ?? 1.0;
    final completionGood = completionRate >= 0.85;
    final completionPoor = completionRate < 0.70;

    // ── Signal 3: Downgrade history ──────────────────────────────────────
    final downgrades = memory.weeklyDowngradeCount;
    final mostlyGreen = downgrades <= 1;
    final manyRed = downgrades >= 3;

    // ── Regress ──────────────────────────────────────────────────────────
    if (completionPoor || (rpeIncreasing && manyRed) || downgrades >= 4) {
      return ProgressionDecision.regress;
    }

    // ── Progress ─────────────────────────────────────────────────────────
    if (completionGood && rpeStableOrDecreasing && mostlyGreen) {
      return ProgressionDecision.progress;
    }

    // ── Hold ─────────────────────────────────────────────────────────────
    return ProgressionDecision.hold;
  }

  /// Returns true if the last 3 RPE entries show an upward trend.
  static bool _isRpeTrendIncreasing(EngineMemory memory) {
    final entries = memory.recentRpeEntries;
    if (entries.length < 2) return false;
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final recent = sorted.length > 3 ? sorted.sublist(sorted.length - 3) : sorted;
    if (recent.length < 2) return false;
    // Simple: last value strictly greater than first value in the window
    return recent.last.value > recent.first.value;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<int> _getTotalRunCount() async {
    try {
      final runs = await DatabaseService.instance.getAllRuns();
      return runs.length;
    } catch (_) {
      return 0;
    }
  }
}
