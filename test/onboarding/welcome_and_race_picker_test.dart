import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_pages.dart';
import 'package:run_app/services/race_service.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(child));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('OPageRacePicker — races available immediately', () {
    testWidgets('shows preset races on the first frame, no spinner', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(390, 1600),
        OPageRacePicker(
          raceName: null,
          raceDate: null,
          goal: 'half_marathon',
          onSelect:
              ({id, required name, city, required date, distanceKey}) {},
          onClose: () {},
          onAdvance: () {},
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      // a well-known preset half marathon is on screen straight away
      expect(find.text('Philadelphia Half Marathon'), findsOneWidget);
    });

    testWidgets('the popular-race fallback is non-empty and covers HM + M', (
      tester,
    ) async {
      final races = RaceService.instance.popularRaces;
      expect(races, isNotEmpty);
      expect(races.every((r) => r.raceDate.isAfter(DateTime.now())), isTrue);
      final hasHalf = races.any((r) => r.distanceLabel == 'Half Marathon');
      final hasFull = races.any((r) => r.distanceLabel == 'Marathon');
      expect(hasHalf && hasFull, isTrue);
    });
  });

  group('OPageWelcome — no overflow, clean hierarchy', () {
    Widget welcome() => OPageWelcome(
      firstName: 'Runner',
      goal: 'half_marathon',
      vdot: 44,
      planWeeks: 14,
      experienceLevel: 'intermediate',
      currentTimeSec: 118 * 60, // 1:58:00
      paceDistanceKm: 21.0975,
      runsPerWeek: 4,
      baselineWeeklyKm: 30,
      raceDate: DateTime.now().add(const Duration(days: 14 * 7)),
      onContinue: () {},
    );

    testWidgets('renders without overflow on a narrow phone', (tester) async {
      await _pumpAt(tester, const Size(340, 2400), welcome());
      expect(tester.takeException(), isNull);
      expect(find.text('PROJECTED FINISH'), findsOneWidget);
    });

    testWidgets('renders without overflow on a large phone', (tester) async {
      await _pumpAt(tester, const Size(480, 2400), welcome());
      expect(tester.takeException(), isNull);
    });

    testWidgets('hero shows the plan-details chip row', (tester) async {
      await _pumpAt(tester, const Size(390, 2200), welcome());
      expect(find.text('14 weeks'), findsOneWidget);
      expect(find.text('4 runs/week'), findsOneWidget);
      expect(find.textContaining('km/wk'), findsOneWidget);
      // the overwhelming 4-row matrix is gone
      expect(find.text('ALSO WITHIN REACH'), findsOneWidget);
      expect(find.text('Current'), findsNothing);
    });
  });
}
