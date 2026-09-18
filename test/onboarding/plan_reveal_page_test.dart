import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/plan_reveal_data.dart';
import 'package:run_app/onboarding/plan_reveal_page.dart';
import 'package:run_app/theme/app_theme.dart';
import 'package:run_app/utils/unit_utils.dart';

final _now = DateTime(2026, 1, 5); // a Monday

OnboardingAnswers _answers({
  int runsPerWeek = 4,
  List<int> selectedDays = const [0, 2, 4, 5],
  int? longRunDayIndex = 5,
  String? raceGoal = 'finish',
}) {
  return OnboardingAnswers(
    goal: 'half_marathon',
    raceName: 'Test Half',
    raceDate: _now.add(const Duration(days: 16 * 7)),
    experienceRaw: 'regular',
    experienceBridged: 'intermediate',
    raceGoalRaw: raceGoal,
    baselineWeeklyKm: 30,
    runsPerWeek: runsPerWeek,
    selectedDays: selectedDays,
    longRunDayIndex: longRunDayIndex,
    paceDistance: 'half',
    paceDistanceKm: 21.0975,
    currentTimeSec: 6600, // 1:50:00
    startDate: _now,
    planWeeks: 16,
    vdot: 44,
    vdotProvisional: false,
  );
}

Widget _host({
  required OnboardingAnswers answers,
  required PlanProjection? projection,
  void Function(PlanEditTarget)? onEdit,
  VoidCallback? onGenerate,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: OPagePlanReveal(
        answers: answers,
        projection: projection,
        onEdit: onEdit ?? (_) {},
        onGenerate: onGenerate ?? () {},
      ),
    ),
  );
}

/// The reveal scrolls, and a ListView only builds what fits. Give the tests a
/// tall viewport so every receipt row is actually laid out and hittable.
Future<void> _pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
}

void main() {
  tearDown(() => UnitUtils.useMilesNotifier.value = false);

  group('OPagePlanReveal', () {
    testWidgets('renders all eight receipt rows', (tester) async {
      final answers = _answers();
      final projection = PlanProjection.build(answers, now: _now);

      await _pumpTall(tester, _host(answers: answers, projection: projection));

      for (final label in const [
        'Goal',
        'Runs per week',
        'Weekly volume',
        'Speed workouts',
        'Available days',
        'Long run day',
        'Long runs',
        'Current fitness',
      ]) {
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'missing receipt row: $label',
        );
      }
    });

    testWidgets('tapping a row reports the right edit target', (tester) async {
      final answers = _answers();
      PlanEditTarget? tapped;

      await _pumpTall(
        tester,
        _host(
          answers: answers,
          projection: PlanProjection.build(answers, now: _now),
          onEdit: (t) => tapped = t,
        ),
      );

      await tester.tap(find.text('Runs per week'));
      await tester.pump();
      expect(tapped, PlanEditTarget.runsPerWeek);

      await tester.tap(find.text('Long run day'));
      await tester.pump();
      expect(tapped, PlanEditTarget.longRunDay);
    });

    testWidgets('derived rows are not tappable', (tester) async {
      final answers = _answers();
      var edits = 0;

      await _pumpTall(
        tester,
        _host(
          answers: answers,
          projection: PlanProjection.build(answers, now: _now),
          onEdit: (_) => edits++,
        ),
      );

      // "Speed workouts" and "Long runs" are computed, never answered.
      await tester.tap(find.text('Speed workouts'));
      await tester.tap(find.text('Long runs'));
      await tester.pump();
      expect(edits, 0);
    });

    testWidgets('the CTA commits the plan', (tester) async {
      final answers = _answers();
      var generated = 0;

      await _pumpTall(
        tester,
        _host(
          answers: answers,
          projection: PlanProjection.build(answers, now: _now),
          onGenerate: () => generated++,
        ),
      );

      await tester.tap(find.text('Start training'));
      await tester.pump();
      expect(generated, 1);
    });

    testWidgets('renders a skeleton, not a crash, without a projection', (
      tester,
    ) async {
      await _pumpTall(tester, _host(answers: _answers(), projection: null));

      expect(tester.takeException(), isNull);
      expect(find.text('Shaping your weeks…'), findsOneWidget);
      // The receipt still stands on its own.
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('Runs per week'), findsOneWidget);
      // Projection-derived rows are absent rather than blank.
      expect(find.text('Weekly volume'), findsNothing);
      expect(find.text('Long runs'), findsNothing);
    });

    testWidgets('typical week strip renders seven days', (tester) async {
      final answers = _answers();

      await _pumpTall(
        tester,
        _host(
          answers: answers,
          projection: PlanProjection.build(answers, now: _now),
        ),
      );

      expect(find.text('A TYPICAL WEEK'), findsOneWidget);
      // Three rest days for a 4-run week.
      expect(find.text('Rest'), findsNWidgets(3));
      expect(find.text('Long'), findsOneWidget);
    });

    testWidgets('honours the miles preference', (tester) async {
      UnitUtils.useMilesNotifier.value = true;
      final answers = _answers();

      await _pumpTall(
        tester,
        _host(
          answers: answers,
          projection: PlanProjection.build(answers, now: _now),
        ),
      );

      expect(find.textContaining('mi/week'), findsOneWidget);
      expect(find.textContaining('km/week'), findsNothing);
    });
  });

  group('receipt content', () {
    test('goal label reads the raw answer, not the bridged intent', () {
      // The old summary bridged five answers down to two, so "finish" and
      // "enjoy" both fell through to a default label.
      expect(goalLabel('pr'), 'Beat my PR');
      expect(goalLabel('target_time'), 'Hit my target time');
      expect(goalLabel('finish'), 'Finish strong');
      expect(goalLabel('enjoy'), 'Enjoy the race');
      expect(goalLabel('undecided'), 'Still deciding');
    });

    test('fitness row carries its provenance', () {
      expect(fitnessLabel(_answers()), 'vDOT 44 · 1:50:00 half');
    });

    test('day list is ordered and abbreviated', () {
      expect(dayListLabel(const [5, 0, 2]), 'Mon · Wed · Sat');
      expect(dayListLabel(const []), 'Not set');
    });

    test('long run day falls back rather than showing an index', () {
      expect(fullDayName(5), 'Saturday');
      final rows = buildReceiptRows(
        _answers(longRunDayIndex: null),
        null,
        useMiles: false,
      );
      final longRun = rows.firstWhere((r) => r.label == 'Long run day');
      expect(longRun.value, 'Not set');
    });
  });
}
