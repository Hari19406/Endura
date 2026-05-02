import 'package:flutter/foundation.dart';
import '../memory/engine_memory_service.dart';
import '../memory/engine_memory.dart';
import '../config/workout_template_library.dart';
import '../../models/workout_type.dart';
import '../../utils/database_service.dart';

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
class EngineRuntime {
  static final EngineMemoryService _memoryService = EngineMemoryService();

  /// Call this from [RunSummaryScreen._finaliseRun()] after saving the run to the DB.
  static Future<void> processRun({
    required double durationMinutes,
    required double speed,
    required DateTime runDate,
    required String workoutType,
    int? rpe,
    String? templateId,
    WorkoutIntent? completedIntent,
    double? actualPaceSecondsPerKm,
    double? expectedPaceSecondsPerKm,
  }) async {
    try {
      final totalRuns = await _getTotalRunCount();
      final type = WorkoutTypeX.fromString(workoutType);

      var updated = await _memoryService.recordRun(
        workoutType: type,
        rpe: rpe,
        runDate: runDate,
        totalRunCount: totalRuns,
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

      // ── Monday: save progression evaluation date ──────────────────────
      if (_shouldEvaluateProgression(updated, runDate)) {
        final pendingNudge = updated.pendingVdotNudge;
        final appliedNudge = pendingNudge.clamp(-1, 1);
        final newVdot = (updated.vdotScore + appliedNudge).clamp(30, 85);

        updated = updated.copyWith(
          lastProgressionEvaluationDate: runDate,
          vdotScore: newVdot,
          vdotIsProvisional: false,
          pendingVdotNudge: 0,
        );

        debugPrint(
          '[EngineRuntime] Weekly vDOT apply: ${updated.vdotScore - appliedNudge} → $newVdot '
          '(pending=$pendingNudge applied=$appliedNudge)',
        );

        await _memoryService.save(updated);
      }

      debugPrint(
        '[EngineRuntime] type=$workoutType rpe=$rpe '
        'phase=${updated.currentPhase.name} totalRuns=$totalRuns '
        'vdot=${updated.vdotScore} template=$templateId '
        'rotationSize=${updated.recentTemplateIds.length}',
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
    // Interval pace is too variable. Long run pace is effort-capped.
    const calibratableIntents = {
      WorkoutIntent.aerobicBase,
      WorkoutIntent.threshold,
    };
    if (intent != null && !calibratableIntents.contains(intent)) return null;

    // Faster than expected = positive delta. Slower = negative.
    final paceDelta = expectedPace - actualPace;

    // Ignore differences under 10 sec/km — noise.
    if (paceDelta.abs() < 10) return null;

    // RPE cross-check:
    //   nudge up only if faster AND effort was Easy(3) or Fine(5)
    //   nudge down only if slower AND effort was Hard(7) or Too Hard(9)
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
      '(actualPace=${actualPace.round()} expectedPace=${expectedPace.round()} '
      'rpe=$rpe)',
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