import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine_memory.dart';
import '../../models/workout_type.dart';
import '../../models/training_phase.dart';
import '../../models/weekly_plan.dart';
import '../../models/race_plan.dart';
import '../config/workout_template_library.dart';
import '../../services/engine_state_sync_service.dart';

class EngineMemoryService {
  static const String _key = 'engine_memory_v2';

  Future<EngineMemory> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return defaultSafeMemory();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaultSafeMemory();
      return EngineMemory.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      return defaultSafeMemory();
    }
  }

  Future<void> save(EngineMemory memory, {bool syncToCloud = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(memory.toJson()));
    if (syncToCloud) {
      await EngineStateSyncService.instance.syncEngineMemory(memory);
    }
  }

  Future<EngineMemory> recordRun({
    required WorkoutType workoutType,
    int? rpe,
    required DateTime runDate,
    required int totalRunCount,
    String? templateId,
    WorkoutIntent? completedIntent,
  }) async {
    final current = await load();

    List<RpeEntry> updatedRpe = current.recentRpeEntries;
    if (rpe != null && rpe >= 1 && rpe <= 10) {
      updatedRpe = [
        RpeEntry(value: rpe, date: runDate),
        ...current.recentRpeEntries,
      ].take(5).toList();
    }

    WorkoutType lastNonRecovery =
        current.lastNonRecoveryType ?? current.lastCompletedType;
    if (workoutType != WorkoutType.recovery) {
      lastNonRecovery = workoutType;
    }

    final newPhase = PhaseEngine.fromRunCount(totalRunCount);
    final newWeek = PhaseEngine.weekNumber(totalRunCount);

    final updated = current.copyWith(
      lastCompletedType: workoutType,
      lastNonRecoveryType: lastNonRecovery,
      recentRpeEntries: updatedRpe,
      totalRunsCompleted: totalRunCount,
      currentPhase: newPhase,
      currentWeek: newWeek,
      firstRunDate: current.firstRunDate ?? runDate,
      lastRunDate: runDate,
      lastCompletedTemplateId: templateId,
      lastCompletedWorkoutIntent: completedIntent,
      recentTemplateIds: templateId == null
          ? current.recentTemplateIds
          : current.appendTemplateId(templateId),
    );

    await save(updated);
    return updated;
  }

  Future<void> saveActivePlan(WeeklyPlan plan) async {
    final current = await load();
    await save(current.copyWith(activePlan: plan));
  }

  Future<void> clearActivePlan() async {
    final current = await load();
    await save(current.copyWith(clearActivePlan: true));
  }

  Future<void> saveRacePlan(RacePlan plan) async {
    final current = await load();
    await save(current.copyWith(racePlan: plan));
  }

  Future<void> clearRacePlan() async {
    final current = await load();
    await save(current.copyWith(clearRacePlan: true));
  }

  Future<void> migrateFirstRunDateIfNeeded() async {
    final current = await load();
    if (current.firstRunDate != null) return;
    if (current.lastRunDate == null) return;

    final migrated = current.copyWith(
      firstRunDate: current.lastRunDate,
    );
    await save(migrated, syncToCloud: true);
    debugPrint('[EngineMemoryService] Migrated firstRunDate from lastRunDate');
  }
}
