import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/volume_model.dart';
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;
import 'package:run_app/models/plan_config_state.dart';
import 'package:run_app/onboarding/onboarding_pages.dart' show OPageWeeklyVolume;

void main() {
  group('weekly-volume tiers', () {
    test('are the six clean km/week personas, each with a round baseline', () {
      final keys = OPageWeeklyVolume.tiers.map((t) => t.$1).toList();
      final baselines = OPageWeeklyVolume.tiers.map((t) => t.$4).toList();
      expect(keys, ['none', 'low', 'moderate', 'base', 'high', 'veryHigh']);
      expect(baselines, [0, 15, 25, 40, 60, 75]);
      // labels are km/week ranges, not month totals
      for (final t in OPageWeeklyVolume.tiers) {
        expect(t.$2, contains('km/week'));
        expect(t.$3, isNotEmpty); // persona line
      }
    });
  });

  group('tier → OPagePlanReveal initial weeklyVolumeRange', () {
    PlanConfigState configFor(double baselineKm) => PlanConfigState.fromInputs(
      goalType: PlanGoalType.half,
      experience: ExperienceLevel.intermediate,
      vDOT: 46,
      runsPerWeek: 4,
      longRunDay: 6,
      availableDays: const {1, 3, 5, 6},
      durationWeeks: 14,
      currentWeeklyKm: baselineKm,
    );

    test('"Solid training base" (40 km) seeds the slider floor at ~40', () {
      final cfg = configFor(40);
      expect(cfg.weeklyVolumeRange.start, 40);
      // peak comes straight from VolumeModel, above the floor
      expect(cfg.weeklyVolumeRange.end, greaterThan(40));
      expect(
        cfg.weeklyVolumeRange.end,
        VolumeModel.onboardingRange(
          race: RaceDistance.halfMarathon,
          experience: ExperienceLevel.intermediate,
          days: 4,
        ).max,
      );
    });

    test('"I haven\'t been running" (0 km) is floored to min-viable', () {
      final cfg = configFor(0);
      expect(
        cfg.weeklyVolumeRange.start,
        VolumeModel.minViableKm(RaceDistance.halfMarathon),
      );
    });

    test('every tier yields a valid non-inverted range within the safe cap', () {
      for (final t in OPageWeeklyVolume.tiers) {
        final cfg = configFor(t.$4);
        expect(cfg.weeklyVolumeRange.start,
            lessThanOrEqualTo(cfg.weeklyVolumeRange.end));
        expect(cfg.weeklyVolumeRange.end,
            lessThanOrEqualTo(VolumeModel.safeCapKm(RaceDistance.halfMarathon)));
      }
    });
  });

  group('first-timer tier cap', () {
    testWidgets('hides tiers above 25 km/week', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OPageWeeklyVolume(
              selectedKey: null,
              maxBaselineKm: OPageWeeklyVolume.firstTimerMaxBaselineKm,
              onSelect: (_, __) {},
            ),
          ),
        ),
      );
      expect(find.text('20–35 km/week'), findsOneWidget);
      expect(find.text('35–50 km/week'), findsNothing);
      expect(find.text('50–70 km/week'), findsNothing);
      expect(find.text('70+ km/week'), findsNothing);
    });
  });

  group('distance gating of the weekly-volume tiers', () {
    Future<void> pump(WidgetTester tester, String goal, {double? max}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OPageWeeklyVolume(
                selectedKey: null,
                goal: goal,
                minBaselineKm: OPageWeeklyVolume.minBaselineFor(goal),
                maxBaselineKm: max,
                onSelect: (_, __) {},
              ),
            ),
          ),
        );

    test('minimum baselines per distance', () {
      expect(OPageWeeklyVolume.minBaselineFor('5k'), 0);
      expect(OPageWeeklyVolume.minBaselineFor('10k'), 0);
      expect(OPageWeeklyVolume.minBaselineFor('half_marathon'), 15);
      expect(OPageWeeklyVolume.minBaselineFor('marathon'), 25);
      expect(OPageWeeklyVolume.lowestTierFor('half_marathon'), ('low', 15.0));
      expect(OPageWeeklyVolume.lowestTierFor('marathon'), ('moderate', 25.0));
    });

    testWidgets('5K and 10K keep the 0 km tier', (tester) async {
      for (final g in const ['5k', '10k']) {
        await pump(tester, g);
        expect(find.text('0 km/week'), findsOneWidget, reason: g);
        expect(find.textContaining('running base'), findsNothing);
      }
    });

    testWidgets('half marathon hides 0 km and shows the base note', (
      tester,
    ) async {
      await pump(tester, 'half_marathon');
      expect(find.text('0 km/week'), findsNothing);
      expect(find.text('10–20 km/week'), findsOneWidget);
      expect(
        find.textContaining('at least 15 km/week'),
        findsOneWidget,
      );
    });

    testWidgets('marathon hides 0 and 15 km', (tester) async {
      await pump(tester, 'marathon');
      expect(find.text('0 km/week'), findsNothing);
      expect(find.text('10–20 km/week'), findsNothing);
      expect(find.text('20–35 km/week'), findsOneWidget);
      expect(find.textContaining('at least 25 km/week'), findsOneWidget);
    });

    testWidgets('first-timer half offers 15 and 25 only', (tester) async {
      await pump(tester, 'half_marathon', max: 25);
      expect(find.text('10–20 km/week'), findsOneWidget);
      expect(find.text('20–35 km/week'), findsOneWidget);
      expect(find.text('0 km/week'), findsNothing);
      expect(find.text('35–50 km/week'), findsNothing);
    });
  });
}
