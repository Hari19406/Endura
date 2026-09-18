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

  group('fromFeedRun splits + synthetic elevation/pace trace', () {
    test('builds KmSplits from the raw uploaded splits', () {
      final run = FeedRun(
        runId: 901,
        athleteId: 'a1',
        displayName: 'Runner',
        date: DateTime.utc(2026, 9, 1),
        distanceKm: 2,
        averagePace: '5:00',
        durationSeconds: 600,
        elevationGain: 12,
        splits: const [
          {'km': 1, 'seconds': 300, 'elev': -3.0, 'hr': 148},
          {'km': 2, 'seconds': 300, 'elev': 5.0, 'hr': 152},
        ],
      );
      final a = ActivityDetail.fromFeedRun(run);

      expect(a.splits, hasLength(2));
      expect(a.splits[0].paceSeconds, 300);
      expect(a.splits[0].elevationChangeM, -3.0);
      expect(a.splits[0].avgHr, 148);
      expect(a.anySplitHasElevation, isTrue);
      expect(a.anySplitHasHr, isTrue);
    });

    test(
      'synthesises a coarse elevation trace (cumulative per-split delta) so '
      'hasElevationData is true and the chart can render',
      () {
        final run = FeedRun(
          runId: 902,
          athleteId: 'a1',
          displayName: 'Runner',
          date: DateTime.utc(2026, 9, 1),
          distanceKm: 3,
          averagePace: '5:00',
          durationSeconds: 900,
          elevationGain: 20,
          splits: const [
            {'km': 1, 'seconds': 300, 'elev': 10.0},
            {'km': 2, 'seconds': 300, 'elev': -4.0},
            {'km': 3, 'seconds': 300, 'elev': 8.0},
          ],
        );
        final a = ActivityDetail.fromFeedRun(run);

        expect(a.hasElevationData, isTrue);
        // Baseline sample + one per split.
        expect(a.telemetrySeries, hasLength(4));
        expect(a.telemetrySeries[0].elevationM, 0);
        expect(a.telemetrySeries[1].elevationM, 10.0);
        expect(a.telemetrySeries[2].elevationM, 6.0); // 10 - 4
        expect(a.telemetrySeries[3].elevationM, 14.0); // 6 + 8
      },
    );

    test(
      'synthesises a pace trace from each split\'s own pace, so '
      'hasPaceSeries is true',
      () {
        final run = FeedRun(
          runId: 903,
          athleteId: 'a1',
          displayName: 'Runner',
          date: DateTime.utc(2026, 9, 1),
          distanceKm: 2,
          averagePace: '5:00',
          durationSeconds: 600,
          splits: const [
            {'km': 1, 'seconds': 295},
            {'km': 2, 'seconds': 305},
          ],
        );
        final a = ActivityDetail.fromFeedRun(run);

        expect(a.hasPaceSeries, isTrue);
        final paces = a.telemetrySeries
            .map((s) => s.paceSeconds)
            .whereType<int>()
            .toList();
        expect(paces, [295, 305]);
      },
    );

    test('no splits at all → empty splits and telemetry, as before', () {
      final run = FeedRun(
        runId: 904,
        athleteId: 'a1',
        displayName: 'Runner',
        date: DateTime.utc(2026, 9, 1),
        distanceKm: 5,
        averagePace: '5:00',
        durationSeconds: 1500,
      );
      final a = ActivityDetail.fromFeedRun(run);

      expect(a.splits, isEmpty);
      expect(a.telemetrySeries, isEmpty);
      expect(a.hasElevationData, isFalse);
      expect(a.hasPaceSeries, isFalse);
    });

    test(
      'splits with no elevation data at all leave elevationM null '
      'throughout (nothing to accumulate) rather than a flat-0 fake profile',
      () {
        final run = FeedRun(
          runId: 905,
          athleteId: 'a1',
          displayName: 'Runner',
          date: DateTime.utc(2026, 9, 1),
          distanceKm: 2,
          averagePace: '5:00',
          durationSeconds: 600,
          splits: const [
            {'km': 1, 'seconds': 300},
            {'km': 2, 'seconds': 300},
          ],
        );
        final a = ActivityDetail.fromFeedRun(run);

        expect(a.telemetrySeries.every((s) => s.elevationM == null), isTrue);
        expect(a.hasElevationData, isFalse);
      },
    );

    test('a malformed split entry (missing km/seconds) is skipped', () {
      final run = FeedRun(
        runId: 906,
        athleteId: 'a1',
        displayName: 'Runner',
        date: DateTime.utc(2026, 9, 1),
        distanceKm: 2,
        averagePace: '5:00',
        durationSeconds: 600,
        splits: const [
          {'km': 1, 'seconds': 300},
          {'seconds': 300}, // missing km
          {'km': 3}, // missing seconds
        ],
      );
      final a = ActivityDetail.fromFeedRun(run);
      expect(a.splits, hasLength(1));
    });
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
