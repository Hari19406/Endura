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
  static const String _updatedAtKey = 'engine_memory_v2_updated_at';

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

  /// Local last-write timestamp, used to decide (against the cloud's
  /// `updatedAt`) which copy is newer when reconciling across devices.
  Future<DateTime?> loadUpdatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_updatedAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> save(EngineMemory memory, {bool syncToCloud = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(memory.toJson()));
    await prefs.setString(_updatedAtKey, DateTime.now().toUtc().toIso8601String());
    if (syncToCloud) {
      await EngineStateSyncService.instance.syncEngineMemory(memory);
    }
  }

  Future<EngineMemory> recordRun({
    required WorkoutType workoutType,
    int? rpe,
    required DateTime runDate,
    required int totalRunCount,
    // ── v6: km-based completion tracking ─────────────────────────────────
    required double distanceKm,
    String? templateId,
    WorkoutIntent? completedIntent,
  }) async {
    final current = await load();

    // ── RPE entries ───────────────────────────────────────────────────────
    List<RpeEntry> updatedRpe = current.recentRpeEntries;
    if (rpe != null && rpe >= 1 && rpe <= 10) {
      updatedRpe = [
        RpeEntry(value: rpe, date: runDate),
        ...current.recentRpeEntries,
      ].take(5).toList();
    }

    // ── Last non-recovery type ────────────────────────────────────────────
    WorkoutType lastNonRecovery =
        current.lastNonRecoveryType ?? current.lastCompletedType;
    if (workoutType != WorkoutType.recovery) {
      lastNonRecovery = workoutType;
    }

    // ── Weekly reset check: if today is a new week, reset counters ────────
    // A new week starts on Monday. If lastRunDate was in a previous week,
    // reset weeklyCompletedKm so stale km don't carry over.
    EngineMemory base = current;
    final now = runDate;
    final lastRun = current.lastRunDate;
    if (lastRun != null) {
      final lastMonday = _mondayOf(lastRun);
      final thisMonday = _mondayOf(now);
      if (thisMonday.isAfter(lastMonday)) {
        // New week — reset counters (rollover evaluation happens separately
        // via applyWeekRollover; here we just clear stale weekly data).
        base = current.copyWith(
          weeklyCompletedKm: 0.0,
          weeklyDowngradeCount: 0,
        );
        debugPrint('[EngineMemoryService] New week detected — resetting weekly counters');
      }
    }

    // ── Accumulate completed km ───────────────────────────────────────────
    final updated = base.copyWith(
      lastCompletedType: workoutType,
      lastNonRecoveryType: lastNonRecovery,
      recentRpeEntries: updatedRpe,
      totalRunsCompleted: totalRunCount,
      currentPhase: PhaseEngine.fromRunCount(totalRunCount),
      firstRunDate: current.firstRunDate ?? runDate,
      lastRunDate: runDate,
      lastCompletedTemplateId: templateId,
      lastCompletedWorkoutIntent: completedIntent,
      recentTemplateIds: templateId == null
          ? current.recentTemplateIds
          : current.appendTemplateId(templateId),
      // v6: accumulate this run's distance into the weekly total
      weeklyCompletedKm: base.weeklyCompletedKm + distanceKm,
    );

    await save(updated);
    return updated;
  }

  /// Call this when a pre-run check results in a workout downgrade
  /// (poor sleep OR leg pain → PreRunScaler reduces the workout).
  /// Increments weeklyDowngradeCount for the progression engine.
  Future<void> recordPreRunDowngrade() async {
    final current = await load();
    final updated = current.copyWith(
      weeklyDowngradeCount: current.weeklyDowngradeCount + 1,
    );
    await save(updated);
    debugPrint('[EngineMemoryService] Pre-run downgrade recorded (total: ${updated.weeklyDowngradeCount})');
  }

  /// Call every Monday (or on first run of the week after a week boundary)
  /// to evaluate last week's progression decision and set weeklyPlannedKm
  /// for the new week.
  ///
  /// [nextWeekPlannedKm] — sum of slot distances from WeekResolver for the
  /// upcoming week. Pass 0 if unknown; it will be updated on first run.
  Future<EngineMemory> applyWeekRollover({
    required double nextWeekPlannedKm,
  }) async {
    final current = await load();
    final updated = current.copyWith(
      previousWeekTargetKm: current.weeklyPlannedKm > 0
          ? current.weeklyPlannedKm
          : current.previousWeekTargetKm,
      weeklyPlannedKm: nextWeekPlannedKm,
      weeklyCompletedKm: 0.0,
      weeklyDowngradeCount: 0,
      lastProgressionEvaluationDate: DateTime.now(),
    );
    await save(updated);
    debugPrint('[EngineMemoryService] Week rollover applied — nextWeekPlannedKm: $nextWeekPlannedKm');
    return updated;
  }

  /// Set weeklyPlannedKm at the start of a week from WeekResolver slot sum.
  /// Call once per week when the week resolution is first computed.
  Future<void> setWeeklyPlannedKm(double plannedKm) async {
    final current = await load();
    if (current.weeklyPlannedKm == plannedKm) return; // already set
    final updated = current.copyWith(weeklyPlannedKm: plannedKm);
    await save(updated);
    debugPrint('[EngineMemoryService] weeklyPlannedKm set to $plannedKm');
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the Monday midnight of the week containing [date].
  DateTime _mondayOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }
}