/// ActivityDetailScreen's "Share Run" action opens the branded, shareable run
/// card (route polyline + distance/time/pace overlay) via the same
/// showRunShareSheet the post-run summary uses — not a plain text share.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/widgets/run_share_card.dart';

ActivityDetail _activity() => ActivityDetail(
  runId: 5,
  runIdIsCloud: true,
  runnerName: 'Priya',
  timestamp: DateTime(2026, 9, 12, 7),
  source: 'Endura Tracker',
  location: 'Pune',
  title: 'Tempo Run',
  distanceKm: 9.5,
  avgPace: '4:55',
  movingTime: const Duration(minutes: 46, seconds: 30),
  workoutType: 'tempo',
  routePoints: const [
    {'lat': 18.52, 'lng': 73.85},
    {'lat': 18.521, 'lng': 73.852},
  ],
  splits: const [],
  telemetrySeries: const [],
  hrZones: const [],
);

Widget _host() => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: ActivityDetailScreen(activity: _activity()),
);

void main() {
  testWidgets('the app-bar share icon opens the branded share card', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump(); // sheet animation start
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(RunShareCard), findsWidgets);
  });

  testWidgets('the "Share" social pill opens the same branded card', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    await tester.tap(find.text('Share'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(RunShareCard), findsWidgets);
  });
}
