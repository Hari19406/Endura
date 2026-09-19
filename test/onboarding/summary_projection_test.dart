import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/core/vdot_calculator.dart';
import 'package:run_app/onboarding/onboarding_pages.dart';

Widget _welcome({
  required int seconds,
  required double km,
  String goal = '10k',
  String level = 'beginner',
  int weeks = 12,
  bool estimate = false,
}) => MaterialApp(
  home: Scaffold(
    body: OPageWelcome(
      firstName: 'Runner',
      goal: goal,
      vdot: 33,
      planWeeks: weeks,
      experienceLevel: level,
      currentTimeSec: seconds,
      timeIsEstimate: estimate,
      paceDistanceKm: km,
      runsPerWeek: 4,
      baselineWeeklyKm: 25,
      raceDate: null,
      onContinue: () {},
    ),
  ),
);

Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(w);
}

void main() {
  group('summary card projections', () {
    testWidgets('a 1:02:00 10K gives a real start, a real delta and equivalent '
        'race chips', (tester) async {
      await _pump(tester, _welcome(seconds: 3720, km: 10));

      // Starting time is shown, not "--:--".
      expect(find.text('from 1:02:00 today'), findsOneWidget);
      expect(find.textContaining('--:--'), findsNothing);

      // Improvement delta is negative (faster) and not "+0s".
      final delta = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((d) => RegExp(r'^-\d+m( \d+s)?$').hasMatch(d),
              orElse: () => '');
      expect(delta, isNotEmpty, reason: 'expected a "-Xm Ys" improvement chip');
      expect(find.text('+0s'), findsNothing);

      // The other three distances each get a real time.
      for (final label in const ['5K', 'Half', 'Marathon']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('10K'), findsWidgets); // goal badge only, not a chip
    });

    testWidgets('an estimated (placeholder) time says so', (tester) async {
      await _pump(tester, _welcome(seconds: 3720, km: 10, estimate: true));
      expect(find.text('from ~1:02:00 today (estimate)'), findsOneWidget);
    });

    test('projection math: projected VDOT is higher, times are ordered', () {
      // Riegel-equivalent times grow with distance, and the plan improves them.
      final start = vdotRawFromPerformance(timeSeconds: 3720, distanceKm: 10)!;
      expect(start, inInclusiveRange(30.0, 33.0));
      final faster = secondsForVdot(start + 3, 10);
      expect(faster, lessThan(3720));
      // round trip
      expect(secondsForVdot(start, 10), inInclusiveRange(3715, 3725));
    });

    testWidgets('a marathon goal from 4:45:00 shows chips for 5K/10K/Half', (
      tester,
    ) async {
      await _pump(
        tester,
        _welcome(seconds: 17100, km: 42.195, goal: 'marathon', weeks: 16),
      );
      expect(find.text('from 4:45:00 today'), findsOneWidget);
      expect(find.textContaining('--:--'), findsNothing);
      for (final label in const ['5K', '10K', 'Half']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });
  });
}
