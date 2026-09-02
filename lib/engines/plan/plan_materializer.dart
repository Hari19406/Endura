/// PlanMaterializer — turns a RacePlan skeleton into a full MaterializedPlan:
/// every week resolved through WeekResolver, every workout resolved through
/// WorkoutResolver with real paces. Runs at plan creation and on any input
/// change; completed weeks from a prior plan are carried over frozen.
library;

import '../config/archetype_table.dart' show ExperienceLevel;
import '../config/workout_template_library.dart';
import '../core/pace_table.dart';
import '../core/vdot_calculator.dart' show PRDistance;
import '../../models/race_plan.dart';
import '../../models/training_phase.dart';
import 'materialized_plan.dart';
import 'week_resolver.dart';
import 'workout_resolver.dart';

class PlanMaterializer {
  final WeekResolver _weekResolver;
  final WorkoutResolver _workoutResolver;

  const PlanMaterializer({
    WeekResolver? weekResolver,
    WorkoutResolver? workoutResolver,
  }) : _weekResolver = weekResolver ?? const WeekResolver(),
       _workoutResolver = workoutResolver ?? const WorkoutResolver();

  static const int _recentTemplateCap = 14;

  MaterializedPlan materialize({
    required RacePlan skeleton,
    required List<int> trainingDayIndices,
    required int? longRunDayIndex,
    required RaceDistance raceDistance,
    required ExperienceLevel experienceLevel,
    required int vdot,
    required String inputsFingerprint,
    MaterializedPlan? previous,
    DateTime? now,
  }) {
    final builtAt = (now ?? DateTime.now()).toUtc();
    final planId =
        previous?.planId ??
        'plan_${skeleton.createdAt.millisecondsSinceEpoch}';

    final ladderState = <String, int>{...?previous?.ladderState};
    var sessionProgress = <String, int>{...?previous?.sessionProgress};
    final recentTemplateIds = <String>[];

    final paceTable = PaceTable(vdot.clamp(30, 85));
    final resolverContext = ResolverContext(
      paceTable: paceTable,
      goalRaceDistance: _toPrDistance(raceDistance),
      goalRaceTimeSeconds: null,
    );
    final experienceStr = _experienceStr(experienceLevel);

    final weeks = <MaterializedWeek>[];
    var taperWeekCount = 0;

    for (final target in skeleton.weeks) {
      final weekNumber = target.week;
      final phase = target.phase;
      final isCutback = weekNumber % 4 == 0;

      // Carry a completed week over untouched.
      final prior = previous?.weekByNumber(weekNumber);
      if (prior != null && prior.isFrozen) {
        weeks.add(prior);
        if (phase == TrainingPhase.taper) taperWeekCount++;
        continue;
      }

      final taperWeekNumber =
          phase == TrainingPhase.taper ? taperWeekCount + 1 : 1;

      final resolution = _weekResolver.resolve(
        weekTarget: target,
        trainingDayIndices: trainingDayIndices,
        raceDistance: raceDistance,
        phase: phase,
        experienceLevel: experienceLevel,
        currentWeeklyKm: target.targetKm,
        longRunDayIndex: longRunDayIndex,
        weekNumber: weekNumber,
        recentTemplateIds: List<String>.from(recentTemplateIds),
        isCutbackWeek: isCutback,
        taperWeekNumber: taperWeekNumber,
        ladderPositions: ladderState,
        sessionProgress: sessionProgress,
      );

      ladderState.addAll(resolution.updatedLadderPositions);
      sessionProgress = Map<String, int>.from(resolution.updatedSessionProgress);
      if (phase == TrainingPhase.taper) taperWeekCount++;

      final days = <MaterializedDay>[];
      for (final slot in resolution.days) {
        if (slot.isRest || slot.templateId == null) {
          days.add(
            MaterializedDay(
              weekday: slot.weekday,
              slot: _mapSlot(slot.slotType),
            ),
          );
          continue;
        }

        final template = WorkoutLibrary.byId(slot.templateId!);
        ResolvedWorkout? workout;
        if (template != null) {
          final totalKm =
              slot.distanceKm ??
              (resolution.targetKm /
                  resolution.days.where((d) => d.isTraining).length);
          workout = _workoutResolver.resolveTemplate(
            template: template,
            variant: WorkoutLibrary.getVariant(template, phase),
            totalDistanceKm: totalKm,
            resolverContext: resolverContext,
            phase: phase,
            intent: slot.intent ?? template.intent,
            experienceLevel: experienceStr,
          );
          recentTemplateIds.add(template.id);
          while (recentTemplateIds.length > _recentTemplateCap) {
            recentTemplateIds.removeAt(0);
          }
        }

        days.add(
          MaterializedDay(
            weekday: slot.weekday,
            slot: _mapSlot(slot.slotType),
            intent: slot.intent,
            templateId: slot.templateId,
            progressionStep: slot.progressionStep,
            workout: workout,
          ),
        );
      }

      weeks.add(
        MaterializedWeek(
          weekNumber: weekNumber,
          phase: phase,
          targetKm: resolution.targetKm,
          isCutback: isCutback,
          isFrozen: false,
          days: days,
        ),
      );
    }

    return MaterializedPlan(
      planId: planId,
      builtAt: builtAt,
      builtFromVdot: vdot.clamp(30, 85),
      inputsFingerprint: inputsFingerprint,
      weeks: weeks,
      ladderState: Map.unmodifiable(ladderState),
      sessionProgress: Map.unmodifiable(sessionProgress),
    );
  }

  // ── mapping helpers ──────────────────────────────────────────────────────

  static MaterializedSlot _mapSlot(SlotType s) => switch (s) {
    SlotType.easy => MaterializedSlot.easy,
    SlotType.quality1 => MaterializedSlot.quality1,
    SlotType.quality2 => MaterializedSlot.quality2,
    SlotType.longRun => MaterializedSlot.longRun,
    SlotType.mediumLong => MaterializedSlot.mediumLong,
    SlotType.rest => MaterializedSlot.rest,
  };

  static PRDistance _toPrDistance(RaceDistance r) => switch (r) {
    RaceDistance.fiveK => PRDistance.fiveK,
    RaceDistance.tenK => PRDistance.tenK,
    RaceDistance.halfMarathon => PRDistance.halfMarathon,
    RaceDistance.marathon => PRDistance.marathon,
  };

  static String _experienceStr(ExperienceLevel e) => switch (e) {
    ExperienceLevel.beginner => 'beginner',
    ExperienceLevel.intermediate => 'intermediate',
    ExperienceLevel.advanced => 'advanced',
  };
}
