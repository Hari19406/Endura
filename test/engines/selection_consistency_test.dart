/// Phase 6a — the shown workout must be the workout the plan chose.
///
/// SessionSelector / WorkoutResolver now honour SelectionContext.plannedTemplateId
/// instead of re-picking a template with their own rotation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/core/pace_table.dart';
import 'package:run_app/engines/core/vdot_calculator.dart' show PRDistance;
import 'package:run_app/engines/daily/dynamic_scaler.dart' show ScalingSignals;
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_materializer.dart';
import 'package:run_app/engines/plan/session_selector.dart';
import 'package:run_app/engines/plan/workout_resolver.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/race_plan.dart';
import 'package:run_app/models/training_phase.dart';

void main() {
  const selector = SessionSelector();

  SelectionContext ctx({
    required WorkoutIntent intent,
    required String? plannedTemplateId,
    RaceDistance race = RaceDistance.tenK,
    TrainingPhase phase = TrainingPhase.build,
  }) => SelectionContext(
    raceDistance: race,
    phase: phase,
    readiness: SelectorReadiness.green,
    daysPerWeek: 5,
    trainingDayIndices: const [0, 2, 4, 6],
    todayDayIndex: 2,
    plannedIntent: intent,
    plannedDistanceKm: 8,
    plannedTemplateId: plannedTemplateId,
  );

  test('a valid planned template is used verbatim', () {
    final s = selector.select(
      ctx(intent: WorkoutIntent.vo2max, plannedTemplateId: 'vo2_1000'),
    );
    expect(s, isNotNull);
    expect(s!.template.id, 'vo2_1000');
  });

  test('planned long-run template is honoured', () {
    final s = selector.select(
      ctx(
        intent: WorkoutIntent.endurance,
        plannedTemplateId: 'long_progression',
        phase: TrainingPhase.build,
      ),
    );
    expect(s!.template.id, 'long_progression');
  });

  test('an invalid planned template falls back without crashing', () {
    final s = selector.select(
      ctx(
        intent: WorkoutIntent.vo2max,
        plannedTemplateId: 'not_a_real_template',
      ),
    );
    expect(s, isNotNull);
    expect(s!.template.intent, WorkoutIntent.vo2max);
  });

  test('no planned template → selector still picks something sensible', () {
    final s = selector.select(
      ctx(intent: WorkoutIntent.threshold, plannedTemplateId: null),
    );
    expect(s, isNotNull);
    expect(s!.template.intent, WorkoutIntent.threshold);
  });

  test(
    'end-to-end: every materialised training day resolves back to its own '
    'template through WorkoutResolver',
    () {
      final now = DateTime(2026, 3, 2);
      final RacePlan skeleton = RacePlanBuilder.build(
        currentWeeklyKm: 50,
        goalRace: '10k',
        raceDate: now.add(const Duration(days: 70)),
        experienceLevel: 'intermediate',
        now: now,
      );
      final plan = const PlanMaterializer().materialize(
        skeleton: skeleton,
        trainingDayIndices: const [0, 2, 4, 6],
        longRunDayIndex: 6,
        raceDistance: RaceDistance.tenK,
        experienceLevel: ExperienceLevel.intermediate,
        vdot: 48,
        inputsFingerprint: 'fp',
      );

      final resolver = const WorkoutResolver();
      final resolverContext = ResolverContext(
        paceTable: PaceTable(48),
        goalRaceDistance: PRDistance.tenK,
      );

      for (final week in plan.weeks) {
        for (final day in week.days.where((d) => !d.isRest)) {
          final result = resolver.resolve(
            selectionContext: SelectionContext(
              raceDistance: RaceDistance.tenK,
              phase: week.phase,
              readiness: SelectorReadiness.green,
              daysPerWeek: 4,
              trainingDayIndices: const [0, 2, 4, 6],
              todayDayIndex: day.weekday,
              plannedIntent: day.intent,
              plannedDistanceKm: day.workout?.totalDistanceKm,
              plannedTemplateId: day.templateId,
              weekNumber: week.weekNumber,
            ),
            resolverContext: resolverContext,
            scalingSignals: const ScalingSignals(),
          );
          expect(
            result.workout?.templateId,
            day.templateId,
            reason: 'W${week.weekNumber} day ${day.weekday}',
          );
        }
      }
    },
  );
}
