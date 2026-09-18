/// The "Train for your first …" options on the onboarding goal page are now
/// first-class selectable goals — not "Coming soon" placeholders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_pages.dart';
import 'package:run_app/onboarding/onboarding_screen.dart';

Widget _host({
  String? selected,
  VoidCallback? onOpenRaceFunnel,
  void Function(String)? onSelectFirstTimer,
}) => MaterialApp(
  home: Scaffold(
    body: OPageGoal(
      selected: selected,
      onOpenRaceFunnel: onOpenRaceFunnel ?? () {},
      onSelectFirstTimer: onSelectFirstTimer ?? (_) {},
    ),
  ),
);

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('all four first-time race options are shown', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());

    expect(find.text('Train for your first 5K'), findsOneWidget);
    expect(find.text('Train for your first 10K'), findsOneWidget);
    expect(find.text('Train for your first half'), findsOneWidget);
    expect(find.text('Train for your first marathon'), findsOneWidget);
  });

  testWidgets('tapping a first-time option reports its distance key, no '
      '"coming soon"', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_host(onSelectFirstTimer: picked.add));

    await tester.tap(find.text('Train for your first 10K'));
    await tester.pump();

    expect(picked, ['10k']);
    expect(find.textContaining('coming soon'), findsNothing);
  });

  testWidgets('a first-time row renders selected when its distance is the goal', (
    tester,
  ) async {
    await tester.pumpWidget(_host(selected: 'half_marathon'));
    // The "first half" row shows a check mark once its distance is the goal.
    expect(find.byIcon(Icons.check), findsWidgets);
  });

  testWidgets('OnboardingScreen: picking "first 5K" skips the race picker, '
      'experience and race-goal questions (weekly volume is still asked)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onComplete: () {})),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('What are you\ntraining for?'), findsOneWidget);

    await tester.tap(find.text('Train for your first 5K'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Skipped questions are not on screen …
    expect(find.textContaining('experience?'), findsNothing);
    expect(find.text('What do you want\nfrom race day?'), findsNothing);
    expect(find.text('What race are\nyou running?'), findsNothing);
    expect(find.textContaining('coming soon'), findsNothing);

    // … and the wizard has landed on the first question it still asks.
    expect(
      find.text('How much do you run\nin a typical week?'),
      findsOneWidget,
    );

    // No exception was thrown reaching here.
    expect(tester.takeException(), isNull);
  });
}
