/// CoachEngine — plan-lifecycle bookkeeping only.
///
/// The live per-day "recompute a session on the fly" path (getNextCoachMessage,
/// resolveCurrentWeek, the maintenance recompute, and all their
/// selector/pace/volume plumbing) was removed once the Coach tab started
/// reading today's session straight from the persisted [MaterializedPlan]
/// (see `PlanStore.getTodayDayContext`). What remains is the post-plan state
/// transition, which is pure memory bookkeeping and has no persisted-plan home.
library;

import 'package:flutter/foundation.dart';

import '../services/coach_message_builder.dart' as message;
import '../models/training_phase.dart';
import 'memory/engine_memory.dart';

/// Kept so screens can keep referring to `CoachMessage` unqualified.
typedef CoachMessage = message.CoachMessage;

class PostPlanState {
  final EngineMemory memory;
  final bool justCompleted;
  final bool justEnteredMaintenance;

  const PostPlanState({
    required this.memory,
    this.justCompleted = false,
    this.justEnteredMaintenance = false,
  });
}

class CoachEngine {
  CoachEngine();

  // ── Post-plan ─────────────────────────────────────────────────────────────

  /// Detect plan completion or auto-entry into maintenance and return the
  /// mutated memory. Pure decision + `copyWith` — the caller persists.
  PostPlanState checkAndApplyPostPlanState(EngineMemory memory) {
    final now = DateTime.now();

    if (memory.isInMaintenance) {
      return PostPlanState(memory: memory);
    }

    if (memory.hasRacePlan && memory.planCompletedAt == null) {
      final planWeek = memory.racePlan!.currentWeekNumber(now);
      final totalWeeks = memory.racePlan!.totalWeeks;

      if (planWeek > totalWeeks) {
        final updated = memory.copyWith(
          planCompletedAt: now,
          clearRacePlan: true,
          currentPhase: TrainingPhase.base,
        );
        debugPrint(
          '[CoachEngine] Plan complete — week $planWeek > $totalWeeks',
        );
        return PostPlanState(memory: updated, justCompleted: true);
      }
    }

    if (memory.shouldAutoEnterMaintenance) {
      final maintenanceKm =
          (memory.previousWeekTargetKm ?? memory.baselineWeeklyKm ?? 20.0) *
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
}
