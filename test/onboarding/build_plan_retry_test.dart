/// OPageBuildPlan — the "building your plan" screen must not silently swallow a
/// failed cloud save. When onComplete reports failure it shows a retry
/// affordance; retrying re-runs the save; "Continue anyway" lets the user in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_pages.dart';

Widget _host({
  required Future<bool> Function() onComplete,
  required VoidCallback onContinueAnyway,
}) => MaterialApp(
  home: Scaffold(
    body: OPageBuildPlan(
      firstName: 'you',
      goal: '10k',
      onComplete: onComplete,
      onContinueAnyway: onContinueAnyway,
    ),
  ),
);

void main() {
  testWidgets('a failed save surfaces retry + continue, and retry re-runs it', (
    tester,
  ) async {
    var calls = 0;
    var continued = false;

    await tester.pumpWidget(
      _host(
        onComplete: () async {
          calls++;
          return calls > 1; // first attempt fails, second succeeds
        },
        onContinueAnyway: () => continued = true,
      ),
    );

    // Let the build animation run out and the first save resolve.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls, 1);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Continue anyway'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls, 2);
    // Second attempt returned true → parent navigates, retry UI is torn down.
    expect(find.text('Try again'), findsNothing);
    expect(continued, isFalse);
  });

  testWidgets('"Continue anyway" invokes the parent callback', (tester) async {
    var continued = false;

    await tester.pumpWidget(
      _host(
        onComplete: () async => false, // always fails
        onContinueAnyway: () => continued = true,
      ),
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Continue anyway'), findsOneWidget);
    await tester.tap(find.text('Continue anyway'));
    await tester.pump();

    expect(continued, isTrue);
  });

  testWidgets('a successful save shows no retry affordance', (tester) async {
    await tester.pumpWidget(
      _host(onComplete: () async => true, onContinueAnyway: () {}),
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Try again'), findsNothing);
    expect(find.text('Continue anyway'), findsNothing);
  });
}
