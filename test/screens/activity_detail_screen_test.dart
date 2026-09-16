/// ActivityDetailScreen — hydration from both real sources (feed + local
/// RunRecord), graceful chart fallbacks, and the comments-id resolution that
/// keeps a locally-recorded run's comments pointed at the right cloud row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/unit_utils.dart';

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

/// A ~2 km run with a steady 300 s/km pace, split into two km buckets, with a
/// matching telemetry trace so `splitsForDisplay` can properly re-bucket into
/// miles rather than falling back.
ActivityDetail _activityWithSplits() {
  final samples = <TelemetrySample>[
    for (var i = 0; i <= 20; i++)
      TelemetrySample(distanceKm: i * 0.1, paceSeconds: 300),
  ];
  return ActivityDetail(
    runId: 88,
    runIdIsCloud: true,
    runnerName: 'Test Runner',
    timestamp: DateTime(2026, 9, 12, 6),
    source: 'Endura Tracker',
    location: '',
    title: 'Easy Run',
    distanceKm: 2.0,
    avgPace: '5:00',
    movingTime: const Duration(minutes: 10),
    avgGapPace: '5:05',
    splits: const [
      KmSplit(km: 1, paceSeconds: 300),
      KmSplit(km: 2, paceSeconds: 300),
    ],
    telemetrySeries: samples,
    hrZones: const [],
  );
}

/// A ~3 km run whose middle split has a corrupt (zero) duration — the kind of
/// row a duplicate GPS timestamp at a km boundary could produce before the
/// resilience fix — with a telemetry trace too sparse to re-bucket from, so
/// splitsForDisplay's healing (not the mile re-bucketer) is what's on test.
ActivityDetail _activityWithInvalidSplit() => ActivityDetail(
  runId: 99,
  runIdIsCloud: true,
  runnerName: 'Test Runner',
  timestamp: DateTime(2026, 9, 16, 6),
  source: 'Endura Tracker',
  location: '',
  title: 'Easy Run',
  distanceKm: 3.0,
  avgPace: '5:00',
  movingTime: const Duration(seconds: 900), // 15:00 total moving time
  splits: const [
    KmSplit(km: 1, paceSeconds: 300),
    KmSplit(km: 2, paceSeconds: 0), // corrupt — duplicate-timestamp artifact
    KmSplit(km: 3, paceSeconds: 300),
  ],
  telemetrySeries: const [],
  hrZones: const [],
);

/// The summary grid / GAP block render their big value+unit pairs as a single
/// `RichText` (value + a `TextSpan` unit suffix), not separate `Text`
/// widgets — `find.text`/`textContaining` can't see into it, so check the
/// flattened plain text of every mounted `RichText` instead.
bool _anyRichTextContains(WidgetTester tester, String needle) => tester
    .widgetList<RichText>(find.byType(RichText))
    .any((w) => w.text.toPlainText().contains(needle));

Widget _host(ActivityDetail a, {ValueChanged<bool>? onReactedChanged}) =>
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: ActivityDetailScreen(
        activity: a,
        onReactedChanged: onReactedChanged,
      ),
    );

void main() {
  tearDown(() => UnitUtils.useMilesNotifier.value = false);

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

  testWidgets(
    'reacting fires onReactedChanged — optimistically true, then false when '
    'the persist call fails (no Supabase session in this test)',
    (tester) async {
      final reported = <bool>[];
      await tester.pumpWidget(
        _host(_minimalCloudActivity(), onReactedChanged: reported.add),
      );
      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();

      // RunFeedCard's own reaction test covers the intermediate optimistic
      // frame deterministically (via a controllable toggler seam); here it's
      // enough that both the optimistic call and the rollback correction fire.
      expect(reported, [true, false]);
      expect(find.text('React'), findsOneWidget);
    },
  );

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

  group('unit-preference conversion', () {
    testWidgets(
      'summary grid + GAP block render in km by default',
      (tester) async {
        await tester.pumpWidget(_host(_activityWithSplits()));
        await tester.pumpAndSettle();

        expect(_anyRichTextContains(tester, '2.00'), isTrue); // DISTANCE
        expect(_anyRichTextContains(tester, ' km'), isTrue);
        expect(_anyRichTextContains(tester, '5:00'), isTrue); // PACE
        expect(_anyRichTextContains(tester, '/km'), isTrue);
        expect(find.text('KILOMETRE SPLITS'), findsOneWidget);
        // Split rows still show plain km-denominated pace text.
        expect(find.text('5:00'), findsWidgets);
      },
    );

    testWidgets(
      'flipping to miles live converts distance, pace, GAP and re-buckets '
      'the splits — with no manual refresh',
      (tester) async {
        await tester.pumpWidget(_host(_activityWithSplits()));
        await tester.pumpAndSettle();

        UnitUtils.useMilesNotifier.value = true;
        await tester.pumpAndSettle();

        // 2 km × 0.621371 ≈ 1.24 mi.
        expect(_anyRichTextContains(tester, '1.24'), isTrue);
        expect(_anyRichTextContains(tester, ' mi'), isTrue);
        // 5:00/km × 1.609344 ≈ 8:03/mi.
        expect(_anyRichTextContains(tester, '8:03'), isTrue);
        expect(_anyRichTextContains(tester, '/mi'), isTrue);
        expect(_anyRichTextContains(tester, '/km'), isFalse);

        // Splits card re-bucketed into miles, not just relabelled km rows.
        expect(find.text('MILE SPLITS'), findsOneWidget);
        expect(find.text('KILOMETRE SPLITS'), findsNothing);
        expect(find.text('MI'), findsOneWidget); // column header
        // First full-mile bucket at a steady 300 s/km ≈ 8:03/mi.
        expect(find.text('8:03'), findsWidgets);

        // Flip back — everything reverts.
        UnitUtils.useMilesNotifier.value = false;
        await tester.pumpAndSettle();
        expect(_anyRichTextContains(tester, '2.00'), isTrue);
        expect(find.text('KILOMETRE SPLITS'), findsOneWidget);
      },
    );
  });

  group('split resilience', () {
    testWidgets(
      'a corrupt (zero-duration) split never renders as an impossible '
      '0:00 pace — it is healed from the run\'s remaining moving time',
      (tester) async {
        await tester.pumpWidget(_host(_activityWithInvalidSplit()));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // 15:00 total - (5:00 + 5:00) good splits = 5:00 left for the bad one.
        expect(find.text('5:00'), findsWidgets);
        expect(find.text('0:00'), findsNothing);
      },
    );
  });
}
