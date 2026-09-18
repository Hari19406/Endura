/// PlanMaterializationCoordinator — the one place onboarding, settings edits,
/// and CoachEngine go through to (re)build and persist the materialised plan.
/// Maps the app's string inputs to engine enums, computes the fingerprint,
/// runs PlanMaterializer, and writes to PlanStore.
library;

import '../config/archetype_table.dart' show ExperienceLevel;
import '../config/workout_template_library.dart' show RaceDistance;
import '../../models/race_plan.dart';
import 'materialized_plan.dart';
import 'plan_materializer.dart';
import 'plan_store.dart';

class PlanMaterializationCoordinator {
  static final PlanMaterializationCoordinator instance =
      PlanMaterializationCoordinator._();
  PlanMaterializationCoordinator._();

  final PlanMaterializer _materializer = const PlanMaterializer();

  /// Build the full plan from [skeleton] + inputs, save it, return it.
  /// Pass [previous] (from PlanStore.load) so completed weeks stay frozen.
  Future<MaterializedPlan> buildAndStore({
    required RacePlan skeleton,
    required List<int> trainingDayIndices,
    required int? longRunDayIndex,
    required String goalRace,
    required String experienceLevel,
    required int vdot,
    int? goalTimeSeconds,
    MaterializedPlan? previous,
  }) async {
    final plan = _build(
      skeleton: skeleton,
      trainingDayIndices: trainingDayIndices,
      longRunDayIndex: longRunDayIndex,
      goalRace: goalRace,
      experienceLevel: experienceLevel,
      vdot: vdot,
      goalTimeSeconds: goalTimeSeconds,
      previous: previous,
    );
    await PlanStore.instance.save(plan);
    return plan;
  }

  /// Same build as [buildAndStore], but awaits the cloud write and hands back
  /// its outcome so the caller can surface a retry. Used by onboarding's plan
  /// build screen, which must know whether the plan reached Supabase.
  Future<({MaterializedPlan plan, PlanSyncOutcome sync})> buildAndPersist({
    required RacePlan skeleton,
    required List<int> trainingDayIndices,
    required int? longRunDayIndex,
    required String goalRace,
    required String experienceLevel,
    required int vdot,
    int? goalTimeSeconds,
    MaterializedPlan? previous,
  }) async {
    final plan = _build(
      skeleton: skeleton,
      trainingDayIndices: trainingDayIndices,
      longRunDayIndex: longRunDayIndex,
      goalRace: goalRace,
      experienceLevel: experienceLevel,
      vdot: vdot,
      goalTimeSeconds: goalTimeSeconds,
      previous: previous,
    );
    final sync = await PlanStore.instance.saveAndSync(plan);
    return (plan: plan, sync: sync);
  }

  MaterializedPlan _build({
    required RacePlan skeleton,
    required List<int> trainingDayIndices,
    required int? longRunDayIndex,
    required String goalRace,
    required String experienceLevel,
    required int vdot,
    int? goalTimeSeconds,
    MaterializedPlan? previous,
  }) {
    return _materializer.materialize(
      skeleton: skeleton,
      trainingDayIndices: trainingDayIndices,
      longRunDayIndex: longRunDayIndex,
      raceDistance: raceDistanceFrom(goalRace),
      experienceLevel: experienceLevelFrom(experienceLevel),
      vdot: vdot,
      inputsFingerprint: fingerprint(
        goalRace: goalRace,
        raceDate: skeleton.raceDate,
        trainingDays: trainingDayIndices,
        longRunDayIndex: longRunDayIndex,
        experienceLevel: experienceLevel,
        goalTimeSeconds: goalTimeSeconds,
      ),
      previous: previous,
    );
  }

  /// Reload from PlanStore, keep frozen weeks, re-resolve the rest, save.
  /// Returns null when there is no skeleton to build from.
  Future<MaterializedPlan?> recompute({
    required RacePlan? skeleton,
    required List<int> trainingDayIndices,
    required int? longRunDayIndex,
    required String goalRace,
    required String experienceLevel,
    required int vdot,
    int? goalTimeSeconds,
  }) async {
    if (skeleton == null) return null;
    final previous = await PlanStore.instance.load();
    return buildAndStore(
      skeleton: skeleton,
      trainingDayIndices: trainingDayIndices,
      longRunDayIndex: longRunDayIndex,
      goalRace: goalRace,
      experienceLevel: experienceLevel,
      vdot: vdot,
      goalTimeSeconds: goalTimeSeconds,
      previous: previous,
    );
  }

  // ── mapping ──────────────────────────────────────────────────────────────

  static RaceDistance raceDistanceFrom(String goalRace) => switch (goalRace) {
    '5k' || '5K' => RaceDistance.fiveK,
    '10k' || '10K' => RaceDistance.tenK,
    'half_marathon' || 'half' => RaceDistance.halfMarathon,
    'marathon' || 'full' || 'full_marathon' => RaceDistance.marathon,
    _ => RaceDistance.tenK,
  };

  static ExperienceLevel experienceLevelFrom(String level) => switch (level) {
    'beginner' => ExperienceLevel.beginner,
    'advanced' => ExperienceLevel.advanced,
    _ => ExperienceLevel.intermediate,
  };

  static String fingerprint({
    required String goalRace,
    required DateTime raceDate,
    required List<int> trainingDays,
    required int? longRunDayIndex,
    required String experienceLevel,
    int? goalTimeSeconds,
  }) {
    final days = ([...trainingDays]..sort()).join(',');
    final date =
        '${raceDate.year}-${raceDate.month.toString().padLeft(2, '0')}-'
        '${raceDate.day.toString().padLeft(2, '0')}';
    return '$goalRace|$date|$days|${longRunDayIndex ?? -1}|'
        '$experienceLevel|${goalTimeSeconds ?? 0}';
  }
}
