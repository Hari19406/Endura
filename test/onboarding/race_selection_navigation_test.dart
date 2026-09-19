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
const _weeklyVolumeTitle = 'How much do you run\nin a typical week?';
const _raceGoalTitle = "What do you want\nfrom race day?";
const _runsPerWeekTitle = 'How often do you\nwant to run?';

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

    expect(find.text(_raceGoalTitle), findsOneWidget);
    // 'finish' keeps _needsTargetTime false, so _next() skips OPage.targetTime
    // and lands on weekly volume, which now follows the goal/target steps.
    await tester.tap(find.text('Just complete it'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.text(_weeklyVolumeTitle), findsOneWidget);
    await tester.tap(find.text('20–35 km/week'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.text(_runsPerWeekTitle), findsOneWidget);
    expect(find.text('YOUR PLAN AT A GLANCE'), findsOneWidget);
    expect(find.text(_raceGoalTitle), findsNothing);
  });

  // Race-picker route of the tier gating: a 5K runner picks the 0 km tier, goes
  // back and re-picks a longer distance through Upcoming race. The half
  // marathon / marathon need a base, so the selection is lifted to the
  // distance's lowest tier and the 0 km row disappears.
  for (final (chip, minLabel, note) in const [
    ('HM', '10–20 km/week', 'at least 15 km/week'),
    ('FM', '20–35 km/week', 'at least 25 km/week'),
  ]) {
    testWidgets('race picker: switching 5K/0 km to $chip lifts the tier', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // The picker keeps its manual-entry form (name, date) when the athlete
      // comes back to it, so only fill in what is still missing.
      Future<void> addRace(String distChip) async {
        if (find.text("Don't see your race?").evaluate().isNotEmpty) {
          await tester.tap(find.text("Don't see your race?"));
          await tester.pump();
        }
        if (find.text('Pick a date').evaluate().isNotEmpty) {
          await tester.enterText(find.byType(TextField), 'Switch Test Race');
          await tester.pump();
          await tester.tap(find.text('Pick a date'));
          await _settle(tester);
          await tester.tap(find.text('OK'));
          await _settle(tester);
        }
        await tester.tap(find.text(distChip));
        await tester.pump();
        await tester.tap(find.text('Use this race'));
        await _settle(tester);
      }

      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onComplete: () {})),
      );
      await _settle(tester);

      // 5K race → experience → race goal → weekly volume, pick 0 km.
      await tester.tap(find.text('Upcoming race'));
      await _settle(tester);
      await addRace('5K');
      await tester.tap(find.text('Regular runner'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      await tester.tap(find.text('Just complete it'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      expect(find.text(_weeklyVolumeTitle), findsOneWidget);
      expect(find.text('0 km/week'), findsOneWidget);
      await tester.tap(find.text('0 km/week'));
      await tester.pump();

      // Back to the race picker (weekly volume → race goal → experience →
      // race picker), and pick a longer race.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await _settle(tester);
      }
      await addRace(chip);

      // Forward again to weekly volume.
      await tester.tap(find.text('Regular runner'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      await tester.tap(find.text('Just complete it'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await _settle(tester);

      expect(find.text(_weeklyVolumeTitle), findsOneWidget);
      expect(find.text('0 km/week'), findsNothing);
      expect(find.text(minLabel), findsOneWidget);
      expect(find.textContaining(note), findsOneWidget);
      // The old 0 km pick was lifted onto the lowest allowed tier, so exactly
      // one row shows as selected without the athlete touching anything.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
