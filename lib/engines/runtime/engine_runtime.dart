import 'package:flutter/foundation.dart';
import '../memory/engine_memory_service.dart';
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
class EngineRuntime {
  static final EngineMemoryService _memoryService = EngineMemoryService();

  /// Call this from [RunScreen._finishRun()] after saving the run to the DB.
  static Future<void> processRun({
    required double durationMinutes,
    required double speed,
    required DateTime runDate,
    required String workoutType,
    int? rpe,
    String? templateId,
    WorkoutIntent? completedIntent,
  }) async {
    try {
      final totalRuns = await _getTotalRunCount();
      final type = WorkoutTypeX.fromString(workoutType);

      final updated = await _memoryService.recordRun(
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

  static Future<int> _getTotalRunCount() async {
    try {
      final runs = await DatabaseService.instance.getAllRuns();
      return runs.length;
    } catch (_) {
      return 0;
    }
  }
}
