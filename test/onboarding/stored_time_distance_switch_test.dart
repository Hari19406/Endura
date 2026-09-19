// Regression: re-onboarding restored the athlete's previous real time (a 10K in
// 43:00) and then kept showing "00h 43m 00s" after they picked a marathon,
// because a "touched" time was never reset on a distance change.
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

int _seconds(WidgetTester tester) {
  final c = tester
      .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
      .map((p) => (p.scrollController! as FixedExtentScrollController)
          .selectedItem)
      .toList();
  expect(c.length, 3);
  return c[0] * 3600 + c[1] * 60 + c[2];
}

void main() {
  testWidgets('a stored 10K time does not follow the athlete to a marathon', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'pace_distance': '10k',
      'pace_hours': 0,
      'pace_minutes': 43,
      'pace_seconds': 0,
      'engine_memory_v2': jsonEncode({
        'vdotScore': 46,
        'vdotIsProvisional': false,
      }),
    });
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(shortenedMode: true, onComplete: () {}),
      ),
    );
    await _settle(tester);

    // Re-plan flow starts at the race picker: add a marathon.
    await tester.tap(find.text("Don't see your race?"));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Regression Marathon');
    await tester.pump();
    await tester.tap(find.text('FM'));
    await tester.pump();
    await tester.tap(find.text('Pick a date'));
    await _settle(tester);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    await tester.tap(find.text('Use this race'));
    await _settle(tester);

    // Walk forward to the current-time page.
    await tester.tap(find.text('Regular runner'));
    await tester.pump();
    var guard = 0;
    while (find.textContaining("current race time?").evaluate().isEmpty &&
        guard++ < 12) {
      if (find.text('Just complete it').evaluate().isNotEmpty) {
        await tester.tap(find.text('Just complete it'));
        await tester.pump();
      }
      if (find.text('20–35 km/week').evaluate().isNotEmpty) {
        await tester.tap(find.text('20–35 km/week'));
        await tester.pump();
      }
      // Re-plan starts with no long-run day chosen; pick one when asked.
      if (find.text('Saturday').evaluate().isNotEmpty) {
        await tester.tap(find.text('Saturday'));
        await tester.pump();
      }
      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').replaceAll(r'\n', ' '))
          .where((d) => d.endsWith('?'))
          .toList();
      // ignore: avoid_print
      print('LOOP $guard $titles');
      await tester.tap(find.text('Continue'));
      await _settle(tester);
    }
    expect(find.text("What's your\ncurrent race time?"), findsOneWidget);

    // Marathon → its own default (17100 s), NOT the stored 43 minutes.
    expect(_seconds(tester), 17100);
    expect(find.textContaining('04h 45m 00s', findRichText: true),
        findsOneWidget);

    // The stored 10K result is still there for the 10K pill.
    await tester.tap(find.text('10K'));
    await _settle(tester);
    expect(_seconds(tester), 43 * 60);
  });
}
