/// FeedRun.fromRows — splits parsing from the `runs.splits` jsonb column.
/// Tolerant of null/missing/malformed shapes so one bad row can't blank the
/// whole feed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/feed_run.dart';

Map<String, dynamic> _runRow({dynamic splits, bool includeSplitsKey = true}) => {
  'id': 42,
  'user_id': 'athlete-1',
  'distance_km': 5.0,
  'average_pace': '5:00',
  'duration_seconds': 1500,
  'date': '2026-09-18T06:00:00.000Z',
  if (includeSplitsKey) 'splits': splits,
};

void main() {
  test('parses a well-formed splits array', () {
    final run = FeedRun.fromRows(
      _runRow(
        splits: [
          {'km': 1, 'seconds': 300, 'elev': -2.0, 'hr': 148},
          {'km': 2, 'seconds': 305},
        ],
      ),
      null,
    );

    expect(run.splits, hasLength(2));
    expect(run.splits[0], {'km': 1, 'seconds': 300, 'elev': -2.0, 'hr': 148});
    expect(run.splits[1], {'km': 2, 'seconds': 305});
  });

  test('defaults to an empty list when the column is absent (older rows)', () {
    final run = FeedRun.fromRows(
      _runRow(includeSplitsKey: false),
      null,
    );
    expect(run.splits, isEmpty);
  });

  test('defaults to an empty list when the column is explicitly null', () {
    final run = FeedRun.fromRows(_runRow(splits: null), null);
    expect(run.splits, isEmpty);
  });

  test('ignores non-map entries in a malformed array rather than throwing', () {
    final run = FeedRun.fromRows(
      _runRow(
        splits: [
          {'km': 1, 'seconds': 300},
          'not a map',
          42,
        ],
      ),
      null,
    );
    expect(run.splits, hasLength(1));
  });

  test('an unexpected (non-list) value is treated as no splits', () {
    final run = FeedRun.fromRows(_runRow(splits: 'garbage'), null);
    expect(run.splits, isEmpty);
  });
}
