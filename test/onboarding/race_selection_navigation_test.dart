// Regression test for a reported bug: after picking a race from "Upcoming
// race", onboarding was said to bounce back to the previous page and loop.
//
// This drives the REAL OnboardingScreen end to end through the manual
// "Don't see your race?" entry path, so it needs no Supabase mocking (the
// live-race list itself does hit Supabase, but RaceService.upcomingRaces
// already catches and returns [] when unconfigured — see
// lib/services/race_service.dart). Deliberately not a browser/visual check —
// this asserts on the actual page reached, which a screenshot can't do
// reliably.
//
// NOTE: OnboardingScreen runs a perpetually-repeating AnimationController
// (`_loopCtrl..repeat()`) for a background loop effect, so `pumpAndSettle()`
// never settles here — it waits for ALL animations to finish, which this one
// never does. Every wait below uses explicit `pump(duration)` calls instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_screen.dart';

const _goalTitle = 'What are you\ntraining for?';
const _racePickerTitle = 'What race are\nyou running?';
const _pastMonthTitle = 'How much have you\nrun in the past month?';
const _raceGoalTitle = "What do you want\nfrom race day?";
const _runsPerWeekTitle = 'How many days a\nweek can you run?';

Future<void> _settle(WidgetTester tester) async {
  // Covers the 320ms page-slide animation plus the async RaceService call
  // (which resolves near-instantly to [] without Supabase configured) with
  // headroom, without waiting on the infinite loop animation.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('selecting a race via manual entry advances past the race picker '
      'and does not bounce back to the goal page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onComplete: () {})),
    );
    await _settle(tester);

    // Start: the goal page.
    expect(find.text(_goalTitle), findsOneWidget);

    // Open the race funnel.
    await tester.tap(find.text('Upcoming race'));
    await _settle(tester); // 320ms page slide + Supabase call

    expect(find.text(_racePickerTitle), findsOneWidget);
    expect(find.text(_goalTitle), findsNothing);

    // Skip the (empty, since Supabase isn't configured in tests) live
    // list and use manual entry instead — this exercises the exact same
    // onSelect + onAdvance callback pair the real list rows use.
    await tester.tap(find.text("Don't see your race?"));
    await tester.pump();

    expect(find.text('Add your race'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Regression Test Marathon');
    await tester.pump();

    await tester.tap(find.text('FM')); // marathon distance chip
    await tester.pump();

    await tester.tap(find.text('Pick a date'));
    await _settle(tester); // date picker dialog opens

    // Accept the picker's default date — 70 days out, i.e. 10 weeks,
    // which is not short-notice for a marathon (minimum 8), so this run
    // never touches the interception sheet.
    await tester.tap(find.text('OK'));
    await _settle(tester);

    expect(find.text('Use this race'), findsOneWidget);
    await tester.tap(find.text('Use this race'));
    await _settle(tester);

    // The bug report: this used to land back on the goal page instead of
    // advancing to the next question. Assert forward progress, not just
    // that the race picker itself is gone.
    expect(find.text(_goalTitle), findsNothing);
    expect(find.text(_racePickerTitle), findsNothing);
    expect(
      find.textContaining('experience?'),
      findsOneWidget,
      reason: 'expected to land on the experience question, not loop back',
    );

    // Confirm it actually stays put — a further settle should not
    // silently walk it back to page 0, which is what "keeps looping"
    // would look like.
    await _settle(tester);
    expect(find.textContaining('experience?'), findsOneWidget);
    expect(find.text(_goalTitle), findsNothing);

    // ── Continue through Experience → PastMonth → RaceGoal → RunsPerWeek ──
    // The requested slice: every one of these Continue taps crosses the same
    // _showTopBar/_showBottom-driven PageView as the race-picker step above.
    await tester.tap(find.text('Regular runner'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.text(_pastMonthTitle), findsOneWidget);
    await tester.tap(find.text('25–50 km'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.text(_raceGoalTitle), findsOneWidget);
    // 'finish' keeps _needsTargetTime false, so _next() skips OPage.targetTime
    // entirely and lands directly on runsPerWeek — the exact requested slice.
    await tester.tap(find.text('Just complete it'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.text(_runsPerWeekTitle), findsOneWidget);
    expect(find.text('YOUR PLAN AT A GLANCE'), findsOneWidget);
    expect(find.text(_raceGoalTitle), findsNothing);
  });
}
