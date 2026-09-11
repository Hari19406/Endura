/// Tapping a feed card must open ActivityDetailScreen hydrated with THAT
/// activity's own stats and route polyline — not a placeholder/mock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/feed_run.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/screens/feed_screen.dart';
import 'package:run_app/theme/app_colors.dart';

FeedRun _run({
  int runId = 501,
  double distanceKm = 8.42,
  int commentCount = 2,
}) => FeedRun(
  runId: runId,
  athleteId: 'athlete-1',
  displayName: 'Priya Shenoy',
  date: DateTime.utc(2026, 9, 10, 6, 30),
  distanceKm: distanceKm,
  averagePace: '5:12',
  durationSeconds: 2554,
  workoutType: 'tempo',
  routePolyline: '12.97,77.59;12.972,77.591;12.974,77.593',
  commentCount: commentCount,
);

Widget _host(FeedRun run) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: Scaffold(
    body: RunFeedCard(run: run, onTapAthlete: () {}),
  ),
);

void main() {
  testWidgets(
    'tapping the card pushes ActivityDetailScreen with this run\'s stats and polyline',
    (tester) async {
      final run = _run();
      await tester.pumpWidget(_host(run));

      await tester.tap(find.byType(RunFeedCard));
      await tester.pumpAndSettle();

      final screen = tester.widget<ActivityDetailScreen>(
        find.byType(ActivityDetailScreen),
      );
      final activity = screen.activity;

      expect(activity.distanceKm, run.distanceKm);
      expect(activity.avgPace, run.averagePace);
      expect(activity.runId, run.runId);
      expect(activity.runIdIsCloud, isTrue);
      expect(activity.routePoints, hasLength(3));
      expect(activity.routePoints.first['lat'], closeTo(12.97, 1e-9));
      expect(activity.commentCount, run.commentCount);
    },
  );

  testWidgets(
    'reacting inside the detail screen updates the card immediately on return',
    (tester) async {
      await tester.pumpWidget(_host(_run()));

      // Card starts un-reacted.
      expect(find.text('Be the first to react'), findsOneWidget);

      await tester.tap(find.byType(RunFeedCard));
      await tester.pumpAndSettle();

      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();
      expect(find.text('Reacted'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Back on the card — its own social bar reflects the change immediately,
      // via onReactedChanged, without needing a pop-result round trip.
      expect(find.text('You reacted'), findsOneWidget);
    },
  );
}
