/// ManagePlanScreen — "Remove Plan" is the athlete-facing entry point for the
/// plan reset/teardown flow: switching race distance or resetting training
/// after injury shouldn't require reinstalling the app. Verifies the confirm
/// dialog's safety copy, that confirming tears down both EngineMemory's
/// racePlan/materializedPlanId AND the PlanStore materialised plan (so a
/// stale plan can't resurface on Home/PlanOverview), and that cancelling
/// leaves everything untouched.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:run_app/engines/memory/engine_memory.dart';
import 'package:run_app/engines/memory/engine_memory_service.dart';
import 'package:run_app/engines/plan/materialized_plan.dart';
import 'package:run_app/engines/plan/plan_store.dart';
import 'package:run_app/models/race_plan.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/screens/manage_plan_screen.dart';
import 'package:run_app/theme/app_colors.dart';

RacePlan _racePlan() => RacePlan(
  goalRace: '10k',
  raceDate: DateTime(2026, 12, 1),
  createdAt: DateTime(2026, 9, 1),
  startingWeeklyKm: 25,
  experienceLevel: 'intermediate',
  weeks: const [],
);

MaterializedPlan _materializedPlan() => MaterializedPlan(
  planId: '10k-plan-1',
  builtAt: DateTime(2026, 9, 1),
  builtFromVdot: 45,
  inputsFingerprint: 'fp',
  weeks: [
    MaterializedWeek(
      weekNumber: 1,
      phase: TrainingPhase.build,
      targetKm: 25,
      isCutback: false,
      isFrozen: false,
      days: [
        for (var i = 0; i < 7; i++)
          MaterializedDay(weekday: i, slot: MaterializedSlot.rest),
      ],
    ),
  ],
);

Future<void> _seedActivePlan() async {
  await EngineMemoryService().save(
    EngineMemory(racePlan: _racePlan(), materializedPlanId: '10k-plan-1'),
    syncToCloud: false,
  );
  await PlanStore.instance.save(_materializedPlan());
}

/// Mounts ManagePlanScreen behind a real push (not as MaterialApp.home) so
/// its "Cancel"/pop-back-to-Home behaviour matches how home_screen.dart
/// actually opens it.
Widget _host(VoidCallback? onPlanChanged) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManagePlanScreen(onPlanChanged: onPlanChanged),
          ),
        ),
        child: const Text('open manage plan'),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The Danger Zone's own trigger button sits below the fold in the test
  /// viewport (the redesigned screen is tall) — scroll it into view before
  /// tapping. Its label is "Remove Plan", the same label the confirmation
  /// sheet's own button uses once open, so callers disambiguate with `.last`.
  Future<void> openConfirmSheet(WidgetTester tester) async {
    final trigger = find.text('Remove Plan');
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the confirm sheet tells the athlete their run history stays safe',
    (tester) async {
      await _seedActivePlan();
      await tester.pumpWidget(_host(null));
      await tester.tap(find.text('open manage plan'));
      await tester.pumpAndSettle();

      await openConfirmSheet(tester);

      expect(
        find.textContaining('past logged runs will stay safe'),
        findsOneWidget,
      );
    },
  );

  testWidgets('cancelling the confirm sheet leaves the plan untouched', (
    tester,
  ) async {
    await _seedActivePlan();
    await tester.pumpWidget(_host(null));
    await tester.tap(find.text('open manage plan'));
    await tester.pumpAndSettle();

    await openConfirmSheet(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect((await EngineMemoryService().load()).hasRacePlan, isTrue);
    expect(await PlanStore.instance.load(), isNotNull);
    // Still on ManagePlanScreen, not popped.
    expect(find.text('Manage Plan'), findsOneWidget);
  });

  testWidgets(
    'confirming Remove Plan tears down both EngineMemory and the '
    'PlanStore materialised plan, then returns to the caller',
    (tester) async {
      await _seedActivePlan();
      var notified = false;
      await tester.pumpWidget(_host(() => notified = true));
      await tester.tap(find.text('open manage plan'));
      await tester.pumpAndSettle();

      await openConfirmSheet(tester);
      // Two "Remove Plan" labels are now on screen — the Danger Zone's own
      // trigger underneath, and the sheet's confirm button on top; the sheet
      // one is the one added last.
      await tester.tap(find.text('Remove Plan').last);
      await tester.pumpAndSettle();

      expect(notified, isTrue);
      // Popped back to the caller.
      expect(find.text('open manage plan'), findsOneWidget);
      expect(find.text('Manage Plan'), findsNothing);

      final after = await EngineMemoryService().load();
      expect(after.hasRacePlan, isFalse);
      expect(after.materializedPlanId, isNull);
      // The materialised plan itself is gone too — a stale plan must not be
      // readable by Home/PlanOverview's own direct PlanStore.load() calls.
      expect(await PlanStore.instance.load(), isNull);
    },
  );
}
