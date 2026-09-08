import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/plan_config_state.dart';
import 'package:run_app/onboarding/plan_reveal_data.dart';
import 'package:run_app/onboarding/plan_reveal_page.dart';
import 'package:run_app/utils/unit_utils.dart';

final _now = DateTime(2026, 1, 5); // a Monday

OnboardingAnswers _answers() => OnboardingAnswers(
  goal: 'half_marathon',
  raceName: 'Test Half',
  raceDate: _now.add(const Duration(days: 16 * 7)),
  experienceRaw: 'regular',
  experienceBridged: 'intermediate',
  raceGoalRaw: 'finish',
  pastMonthKm: 130,
  baselineWeeklyKm: 30,
  runsPerWeek: 4,
  selectedDays: const [0, 2, 4, 5],
  longRunDayIndex: 5,
  paceDistance: 'half',
  paceDistanceKm: 21.0975,
  currentTimeSec: 6600,
  startDate: _now,
  planWeeks: 16,
  vdot: 44,
  vdotProvisional: false,
);

Widget _host({
  required OnboardingAnswers answers,
  ValueChanged<PlanConfigState>? onConfigChanged,
}) => MaterialApp(
  home: Scaffold(
    body: OPagePlanReveal(
      answers: answers,
      projection: PlanProjection.build(answers, now: _now),
      onEdit: (_) {},
      onGenerate: () {},
      onConfigChanged: onConfigChanged,
    ),
  ),
);

Future<void> _pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => UnitUtils.useMilesNotifier.value = false);

  group('fine-tune controls', () {
    testWidgets('renders the three sliders, the switch and the preview card', (
      tester,
    ) async {
      await _pumpTall(tester, _host(answers: _answers()));

      expect(find.text('FINE-TUNE'), findsOneWidget);
      expect(find.byType(RangeSlider), findsNWidgets(2)); // weekly + long run
      expect(find.byType(Slider), findsOneWidget); // runs per week
      expect(find.text('Gradual start'), findsOneWidget);
      expect(find.text('PREVIEW YOUR NEXT WEEK'), findsOneWidget);
      expect(
        find.textContaining('updates as you tune above'),
        findsOneWidget,
      );
    });

    testWidgets('toggling Gradual start reports the tuned config', (
      tester,
    ) async {
      PlanConfigState? reported;
      await _pumpTall(
        tester,
        _host(answers: _answers(), onConfigChanged: (c) => reported = c),
      );

      await tester.tap(find.text('Gradual start'));
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported!.gradualStart, isTrue);
    });

    testWidgets('dragging the runs-per-week slider changes runsPerWeek', (
      tester,
    ) async {
      PlanConfigState? reported;
      await _pumpTall(
        tester,
        _host(answers: _answers(), onConfigChanged: (c) => reported = c),
      );

      await tester.drag(find.byType(Slider), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported!.runsPerWeek, lessThan(4));
      expect(reported!.runsPerWeek, greaterThanOrEqualTo(2));
    });

    testWidgets('dragging a range slider reports a tuned config', (
      tester,
    ) async {
      var calls = 0;
      await _pumpTall(
        tester,
        _host(answers: _answers(), onConfigChanged: (_) => calls++),
      );

      await tester.drag(find.byType(RangeSlider).first, const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(calls, greaterThan(0));
    });

    testWidgets('the preview still renders after tuning (no rebuild crash)', (
      tester,
    ) async {
      await _pumpTall(tester, _host(answers: _answers()));

      await tester.tap(find.text('Gradual start'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(find.text('PREVIEW YOUR NEXT WEEK'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
