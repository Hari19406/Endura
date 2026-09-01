import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/plan_runway.dart';
import 'package:run_app/onboarding/short_notice_sheet.dart';

/// Opens the sheet and hands back whatever it resolves to.
Future<ShortNoticeChoice?> _open(
  WidgetTester tester, {
  String goal = 'marathon',
  int weeks = 5,
  String raceName = 'Chicago Marathon',
}) async {
  ShortNoticeChoice? result;
  var opened = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                opened = true;
                result = await showShortNoticeSheet(
                  context,
                  raceName: raceName,
                  goal: goal,
                  runway: PlanRunway.resolve(
                    goal: goal,
                    weeksAvailable: weeks,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(opened, isTrue);
  return result;
}

void main() {
  testWidgets('states the runway plainly and offers both paths', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('SHORT NOTICE'), findsOneWidget);
    expect(find.text('That is 5 weeks away'), findsOneWidget);

    // The coaching truth: sharpening is possible, building is not.
    expect(find.textContaining('sharpen up and taper'), findsOneWidget);
    expect(find.textContaining('not enough to build new endurance'),
        findsOneWidget);
    expect(find.textContaining('16-week build'), findsOneWidget);

    // Interception, never a wall — the way out is present and secondary.
    expect(find.text('Pick a race further out'), findsOneWidget);
    expect(find.text('Train for it anyway'), findsOneWidget);
  });

  testWidgets('names the race the athlete actually chose', (tester) async {
    await _open(tester, raceName: 'Berlin Marathon');
    expect(find.textContaining('Berlin Marathon'), findsOneWidget);
  });

  testWidgets('reads naturally when the race is next week', (tester) async {
    await _open(tester, weeks: 1);
    expect(find.text('That race is next week'), findsOneWidget);
    expect(find.text('That is 1 weeks away'), findsNothing);
  });

  testWidgets('adapts the distance and recommended length', (tester) async {
    await _open(tester, goal: '5k', weeks: 2);
    expect(find.textContaining('5K'), findsOneWidget);
    expect(find.textContaining('8-week build'), findsOneWidget);
  });

  testWidgets('choosing another race reports pickAnother', (tester) async {
    ShortNoticeChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showShortNoticeSheet(
                  context,
                  raceName: 'Chicago Marathon',
                  goal: 'marathon',
                  runway: PlanRunway.resolve(
                    goal: 'marathon',
                    weeksAvailable: 5,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick a race further out'));
    await tester.pumpAndSettle();

    expect(result, ShortNoticeChoice.pickAnother);
  });

  testWidgets('continuing anyway reports continueAnyway', (tester) async {
    ShortNoticeChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showShortNoticeSheet(
                  context,
                  raceName: 'Chicago Marathon',
                  goal: 'marathon',
                  runway: PlanRunway.resolve(
                    goal: 'marathon',
                    weeksAvailable: 5,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Train for it anyway'));
    await tester.pumpAndSettle();

    expect(result, ShortNoticeChoice.continueAnyway);
  });
}
