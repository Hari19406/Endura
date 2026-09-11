/// ActivityDetail.runIdIsCloud — distinguishes a Supabase runs.id (Feed path)
/// from a local SQLite id (You/History path), which the comments flow needs to
/// resolve before using. Also covers the comment-count override used to keep a
/// feed card's locally-bumped count in sync when it re-opens the detail screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/models/feed_run.dart';
import 'package:run_app/utils/database_service.dart';

void main() {
  test('fromFeedRun marks the id as cloud (it is runs.id)', () {
    final run = FeedRun(
      runId: 900,
      athleteId: 'a1',
      displayName: 'Runner',
      date: DateTime.utc(2026, 9, 1),
      distanceKm: 5,
      averagePace: '5:00',
      durationSeconds: 1500,
      commentCount: 3,
    );
    final a = ActivityDetail.fromFeedRun(run);
    expect(a.runId, 900);
    expect(a.runIdIsCloud, isTrue);
    expect(a.commentCount, 3);
  });

  test('fromFeedRun honours a commentCountOverride', () {
    final run = FeedRun(
      runId: 900,
      athleteId: 'a1',
      displayName: 'Runner',
      date: DateTime.utc(2026, 9, 1),
      distanceKm: 5,
      averagePace: '5:00',
      durationSeconds: 1500,
      commentCount: 3,
    );
    final a = ActivityDetail.fromFeedRun(run, commentCountOverride: 7);
    expect(a.commentCount, 7);
  });

  test('fromRunRecord marks the id as local, not cloud', () {
    final record = RunRecord(
      id: 12,
      distanceKm: 8,
      averagePace: '5:10',
      durationSeconds: 2400,
      date: DateTime(2026, 9, 1),
      routePolyline: '',
    );
    final a = ActivityDetail.fromRunRecord(record, runnerName: 'You');
    expect(a.runId, 12);
    expect(a.runIdIsCloud, isFalse);
  });
}
