/// AdaptationCoordinator — the integration point for the closed-loop adaptation.
/// Loads the persisted plan + run history + the athlete's config, hands them to
/// the pure [PlanAdaptation.reconcile], and persists the result.
///
/// STATUS: intentionally **unwired**. The Coach tab currently reads the stored
/// MaterializedPlan verbatim — no automatic reshuffles. This coordinator and
/// [PlanAdaptation] are kept, tested, and ready for a future milestone that
/// turns adaptation on (e.g. behind an explicit "adjust my plan" action).
library;

import 'package:flutter/foundation.dart';

import '../../models/plan_config_state.dart';
import '../../services/training_days_service.dart';
import '../../utils/database_service.dart' show loadSavedRuns;
import '../../utils/stats.dart' show RunHistory;
import '../config/archetype_table.dart' show ExperienceLevel;
import '../config/workout_template_library.dart' show WorkoutIntent;
import '../memory/engine_memory.dart';
import '../memory/engine_memory_service.dart';
import 'materialized_plan.dart';
import 'plan_adaptation.dart';
import 'plan_store.dart';

class AdaptationCoordinator {
  AdaptationCoordinator._();
  static final AdaptationCoordinator instance = AdaptationCoordinator._();

  bool _running = false;

  /// Reconcile the persisted plan against reality as of [asOfDate] (default
  /// now). Returns the entries that were applied (empty when nothing changed).
  /// Never throws — failures are logged and swallowed.
  Future<List<AdaptationLogEntry>> reconcileNow({DateTime? asOfDate}) async {
    if (_running) return const [];
    _running = true;
    try {
      final plan = await PlanStore.instance.load();
      if (plan == null || plan.weeks.isEmpty) return const [];

      final memory = await EngineMemoryService().load();
      final config = await _buildConfig(memory);
      if (config == null) return const [];

      final history = await _history();

      final result = PlanAdaptation.reconcile(
        plan: plan,
        history: history,
        config: config,
        asOfDate: asOfDate ?? DateTime.now(),
      );

      if (result.changed) {
        await PlanStore.instance.save(result.plan);
        for (final e in result.applied) {
          debugPrint('[Adaptation] ${e.reason}: ${e.summary}');
        }
      }
      return result.applied;
    } catch (e, s) {
      debugPrint('[AdaptationCoordinator] reconcile failed: $e\n$s');
      return const [];
    } finally {
      _running = false;
    }
  }

  // ── Build the config the pure engine needs from persisted state ──────────

  Future<PlanConfigState?> _buildConfig(EngineMemory memory) async {
    final racePlan = memory.racePlan;
    if (racePlan == null) return null;

    final days = await TrainingDaysService.loadOrDefault(4);
    final available = days.isEmpty
        ? <int>{2, 4, 6, 7}
        : days.map((d) => (d + 1).clamp(1, 7)).toSet();

    try {
      return PlanConfigState.fromInputs(
        goalType: PlanGoalType.fromGoalRaceKey(racePlan.goalRace),
        experience: _experience(racePlan.experienceLevel),
        vDOT: memory.vdotScore.toDouble(),
        runsPerWeek: available.length.clamp(2, 7),
        longRunDay: ((memory.longRunDayIndex ?? 6) + 1).clamp(1, 7),
        availableDays: available,
        durationWeeks: racePlan.weeks.length.clamp(3, 20),
      );
    } catch (_) {
      return null;
    }
  }

  static ExperienceLevel _experience(String s) => switch (s) {
        'advanced' => ExperienceLevel.advanced,
        'intermediate' => ExperienceLevel.intermediate,
        _ => ExperienceLevel.beginner,
      };

  Future<List<RunSession>> _history() async {
    final List<RunHistory> runs = await loadSavedRuns();
    return [
      for (final r in runs)
        RunSession(
          date: r.date,
          distanceKm: r.distance,
          intent: _intentFor(r.workoutType),
          paceSecPerKm: _paceToSec(r.averagePace),
          rpe: r.rpe,
        ),
    ];
  }

  static WorkoutIntent? _intentFor(String? workoutType) => switch (workoutType) {
        'easy' || 'recovery' => WorkoutIntent.aerobicBase,
        'tempo' => WorkoutIntent.threshold,
        'interval' => WorkoutIntent.vo2max,
        'long' => WorkoutIntent.endurance,
        _ => null,
      };

  static int? _paceToSec(String pace) {
    final parts = pace.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m == null || s == null) return null;
    return m * 60 + s;
  }
}
