import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_screen.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// (hours, minutes, seconds) the three drums are actually resting on.
(int, int, int) _wheels(WidgetTester tester) {
  final pickers = tester
      .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
      .map((p) => (p.scrollController! as FixedExtentScrollController))
      .toList();
  expect(pickers.length, 3);
  return (
    pickers[0].selectedItem,
    pickers[1].selectedItem,
    pickers[2].selectedItem,
  );
}

void main() {
  testWidgets('the wheels follow the distance pill, matching the summary text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onComplete: () {})),
    );
    await _settle(tester);

    // First marathon → weekly volume → runs → days → long-run day → time.
    await tester.tap(find.text('Train for your first marathon'));
    await _settle(tester);
    await tester.tap(find.text('20–35 km/week'));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Continue'));
      await _settle(tester);
    }
    expect(find.text("What's your\ncurrent race time?"), findsOneWidget);

    // Marathon default: 4h 45m 00s — label AND wheels.
    expect(find.textContaining('04h 45m 00s', findRichText: true), findsOneWidget);
    expect(_wheels(tester), (4, 45, 0));

    // Switching pills moves the wheels with the label.
    await tester.tap(find.text('10K'));
    await _settle(tester);
    expect(find.textContaining('01h 02m 00s', findRichText: true), findsOneWidget);
    expect(_wheels(tester), (1, 2, 0));

    await tester.tap(find.text('5K'));
    await _settle(tester);
    expect(find.textContaining('00h 30m 00s', findRichText: true), findsOneWidget);
    expect(_wheels(tester), (0, 30, 0));

    await tester.tap(find.text('Half'));
    await _settle(tester);
    expect(find.textContaining('02h 18m 00s', findRichText: true), findsOneWidget);
    expect(_wheels(tester), (2, 18, 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching pills without touching a wheel keeps the VDOT '
      'provisional; scrolling a wheel makes it real', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onComplete: () {})),
    );
    await _settle(tester);

    ({int vdot, bool provisional}) vdot() =>
        (tester.state(find.byType(OnboardingScreen)) as dynamic).debugVdot
            as ({int vdot, bool provisional});

    await tester.tap(find.text('Train for your first marathon'));
    await _settle(tester);
    await tester.tap(find.text('20–35 km/week'));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Continue'));
      await _settle(tester);
    }
    expect(vdot().provisional, isTrue);

    for (final pill in const ['5K', '10K', 'Marathon', 'Half']) {
      await tester.tap(find.text(pill));
      await _settle(tester);
      expect(vdot().provisional, isTrue, reason: 'after switching to $pill');
      expect(vdot().vdot, inInclusiveRange(32, 35), reason: pill);
    }

    // Actually scrolling a wheel is a real edit: no longer provisional.
    await tester.drag(find.byType(CupertinoPicker).at(1), const Offset(0, -88));
    await _settle(tester);
    expect(vdot().provisional, isFalse);
  });
}
