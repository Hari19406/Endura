import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_screen.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a first marathon offers 16, 18 and 20-week runways', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onComplete: () {})),
    );
    await _settle(tester);

    await tester.tap(find.text('Train for your first marathon'));
    await _settle(tester);
    await tester.tap(find.text('20–35 km/week'));
    await tester.pump();

    // weekly volume → runs → days → long-run day → current time → plan start
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Continue'));
      await _settle(tester);
    }

    expect(find.text('When do you want\nto start?'), findsOneWidget);
    expect(find.text('16 wk'), findsOneWidget);
    expect(find.text('18 wk'), findsOneWidget);
    expect(find.text('20 wk'), findsOneWidget);

    // Picking one selects exactly that runway.
    await tester.tap(find.text('18 wk'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
