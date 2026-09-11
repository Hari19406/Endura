/// ActivityDetailScreen — hydration from both real sources (feed + local
/// RunRecord), graceful chart fallbacks, and the comments-id resolution that
/// keeps a locally-recorded run's comments pointed at the right cloud row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/theme/app_colors.dart';

ActivityDetail _minimalCloudActivity() => ActivityDetail(
  runId: 77,
  runIdIsCloud: true,
  runnerName: 'Test Runner',
  timestamp: DateTime(2026, 9, 10, 6),
  source: 'Endura Tracker',
  location: '',
  title: 'Easy Run',
  distanceKm: 6.0,
  avgPace: '5:30',
  movingTime: const Duration(minutes: 33),
  splits: const [],
  telemetrySeries: const [],
  hrZones: const [],
  // No route, no splits, no telemetry, no HR — every optional section must
  // hide cleanly instead of overflowing.
);

ActivityDetail _localActivity() => ActivityDetail(
  runId: 4, // a local SQLite id — NOT a Supabase runs.id
  runIdIsCloud: false,
  runnerName: 'You',
  timestamp: DateTime(2026, 9, 10, 6),
  source: 'Endura Tracker',
  location: '',
  title: 'Tempo Run',
  distanceKm: 10.0,
  avgPace: '4:50',
  movingTime: const Duration(minutes: 48),
  splits: const [],
  telemetrySeries: const [],
  hrZones: const [],
);

Widget _host(ActivityDetail a, {ValueChanged<bool>? onReactedChanged}) =>
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: ActivityDetailScreen(
        activity: a,
        onReactedChanged: onReactedChanged,
      ),
    );

void main() {
  testWidgets('a run with no optional data renders without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_minimalCloudActivity()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Chart / zone sections are all omitted (the summary grid's own "PACE"
    // label is expected and unrelated to the PACE *chart* card).
    expect(find.text('KILOMETRE SPLITS'), findsNothing);
    expect(find.text('ELEVATION PROFILE'), findsNothing);
    expect(find.text('HEART RATE & ZONES'), findsNothing);
    expect(find.text('CADENCE'), findsNothing);
  });

  testWidgets('reacting fires onReactedChanged immediately', (tester) async {
    bool? reported;
    await tester.pumpWidget(
      _host(_minimalCloudActivity(), onReactedChanged: (v) => reported = v),
    );
    await tester.tap(find.text('React'));
    await tester.pump();
    expect(reported, isTrue);
    expect(find.text('Reacted'), findsOneWidget);
  });

  testWidgets(
    'a cloud-linked run opens comments with its own runId (no resolution needed)',
    (tester) async {
      await tester.pumpWidget(_host(_minimalCloudActivity()));
      await tester.tap(find.text('Comment'));
      await tester.pumpAndSettle();

      // The sheet opened (didn't fall back to the "not available" snackbar).
      expect(
        find.text("Comments aren't available for this run yet."),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a local-only run with no signed-in Supabase user cannot resolve a cloud '
    'id, and tells the athlete comments aren\'t available yet',
    (tester) async {
      await tester.pumpWidget(_host(_localActivity()));
      await tester.tap(find.text('Comment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text("Comments aren't available for this run yet."),
        findsOneWidget,
      );
    },
  );
}
