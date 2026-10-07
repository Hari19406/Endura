/// DatabaseService.getTrendRuns / getBestEffortSeries against real SQLite:
/// Trends reads only the columns it needs (never routes, splits or track
/// samples) and Best Effort progression reads the stored rows as they are.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:run_app/utils/trend_analytics.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Records the `columns` of every `query` and forwards to the real database.
/// Anything else is unimplemented on purpose: the Trends queries must not
/// need it.
class _SpyDb implements Database {
  _SpyDb(this._inner);
  final Database _inner;
  final List<({String table, List<String>? columns})> queries = [];

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    queries.add((table: table, columns: columns));
    return _inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not expected');
}

BestEffortResult _e(DistanceCategory c, int seconds) =>
    BestEffortResult(category: c, elapsedSeconds: seconds);

void main() {
  sqfliteFfiInit();

  late Database db;
  final dbs = DatabaseService.instance;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, _) => DatabaseService.createSchemaForTesting(db),
      ),
    );
    DatabaseService.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseService.useDatabaseForTesting(null);
    await db.close();
  });

  Future<int> insert(
    DateTime date, {
    double km = 5,
    int secs = 1500,
    double elev = 0,
    int? hr,
    bool heavy = false,
  }) => dbs.insertRun(
    RunRecord(
      date: date,
      distanceKm: km,
      averagePace: '5:00',
      durationSeconds: secs,
      routePolyline: heavy ? List.filled(500, '12.9,77.6').join(';') : '',
      elevationGain: elev,
      avgHeartRate: hr,
      splits: heavy
          ? [
              for (var i = 1; i <= 20; i++) {'km': i, 'seconds': 300},
            ]
          : const [],
      trackSamples: heavy
          ? [
              for (var i = 0; i < 400; i++)
                {'t': i * 15, 'd': i * 40.0, 'alt': 10.0, 'hr': 150},
            ]
          : const [],
    ),
  );

  group('getTrendRuns', () {
    test('an empty database gives an empty list', () async {
      expect(await dbs.getTrendRuns(), isEmpty);
    });

    test('returns exactly the trend fields, oldest first', () async {
      await insert(
        DateTime(2026, 9, 10, 7),
        km: 10,
        secs: 3000,
        elev: 85.5,
        hr: 152,
      );
      await insert(DateTime(2026, 9, 1, 7), km: 5, secs: 1500, elev: 12);

      final runs = await dbs.getTrendRuns();
      expect(runs, hasLength(2));
      expect(runs.first.date, DateTime(2026, 9, 1, 7));
      expect(runs.first.distanceKm, 5);
      expect(runs.first.movingTimeSeconds, 1500);
      expect(runs.first.elevationGain, 12);
      expect(runs.last.date, DateTime(2026, 9, 10, 7));
      expect(runs.last.distanceKm, 10);
      expect(runs.last.movingTimeSeconds, 3000);
      expect(runs.last.elevationGain, 85.5);
      expect(runs.last.avgHr, 152);
    });

    test('a run without HR stays null (never defaulted to 0)', () async {
      await insert(DateTime(2026, 9, 1));
      final run = (await dbs.getTrendRuns()).single;
      expect(run.avgHr, isNull);
      expect(TrendAnalytics.hasHr(run), isFalse);
    });

    test('selects only the five required columns, never heavy ones', () async {
      await insert(DateTime(2026, 9, 1), heavy: true, hr: 150);
      final spy = _SpyDb(db);
      DatabaseService.useDatabaseForTesting(spy);

      final runs = await dbs.getTrendRuns();

      expect(runs, hasLength(1));
      expect(spy.queries, hasLength(1));
      final q = spy.queries.single;
      expect(q.table, 'runs');
      expect(q.columns, isNotNull, reason: 'a null column list is SELECT *');
      expect(q.columns!.toSet(), {
        'date',
        'distance_km',
        'duration_seconds',
        'elevation_gain',
        'avg_heart_rate',
      });
      for (final heavy in [
        'route_polyline',
        'splits_json',
        'track_samples_json',
      ]) {
        expect(q.columns, isNot(contains(heavy)));
      }
    });

    test('a deleted run no longer counts', () async {
      final id = await insert(DateTime(2026, 9, 1));
      await insert(DateTime(2026, 9, 2));
      await dbs.deleteRun(id);
      expect(await dbs.getTrendRuns(), hasLength(1));
    });

    test('feeds the analytics end to end', () async {
      await insert(DateTime(2026, 10, 5), km: 5, secs: 1500, hr: 150);
      await insert(DateTime(2026, 10, 6), km: 10, secs: 3300);
      final result = TrendAnalytics.build(
        await dbs.getTrendRuns(),
        TrendRange.weeks8,
        now: DateTime(2026, 10, 7),
      );
      expect(result.summary.runCount, 2);
      expect(result.summary.distanceKm, 15);
      expect(result.summary.paceSecondsPerKm, closeTo(320, 1e-9));
      expect(result.summary.hrRuns, 1);
    });
  });

  group('getBestEffortSeries', () {
    Future<int> runWith(DateTime date, List<BestEffortResult> efforts) async {
      final id = await insert(date);
      await dbs.insertBestEffortsForRun('$id', efforts, recordedAt: date);
      return id;
    }

    test('no efforts at that distance gives an empty series', () async {
      await runWith(DateTime(2026, 9, 1), [_e(DistanceCategory.k1, 300)]);
      expect(await dbs.getBestEffortSeries(DistanceCategory.k5), isEmpty);
    });

    test('returns only the selected distance, oldest first', () async {
      await runWith(DateTime(2026, 9, 10), [
        _e(DistanceCategory.k5, 1450),
        _e(DistanceCategory.k1, 280),
      ]);
      await runWith(DateTime(2026, 9, 1), [_e(DistanceCategory.k5, 1500)]);

      final k5 = await dbs.getBestEffortSeries(DistanceCategory.k5);
      expect(k5.map((p) => p.seconds), [1500, 1450]);
      expect(k5.first.date, DateTime(2026, 9, 1));
      expect(k5.last.date, DateTime(2026, 9, 10));
      final k1 = await dbs.getBestEffortSeries(DistanceCategory.k1);
      expect(k1.map((p) => p.seconds), [280]);
    });

    test('only runs that actually have the effort appear', () async {
      final withEffort = await runWith(DateTime(2026, 9, 1), [
        _e(DistanceCategory.k5, 1500),
      ]);
      await runWith(DateTime(2026, 9, 2), [_e(DistanceCategory.k1, 290)]);
      await insert(DateTime(2026, 9, 3)); // no efforts at all

      final series = await dbs.getBestEffortSeries(DistanceCategory.k5);
      expect(series.map((p) => p.runId), ['$withEffort']);
    });

    test(
      'reads the stored times as they are (no recalculation, no trim)',
      () async {
        for (var i = 0; i < 15; i++) {
          await runWith(DateTime(2026, 1, 1 + i), [
            _e(DistanceCategory.k5, 1700 - i * 7),
          ]);
        }
        final series = await dbs.getBestEffortSeries(DistanceCategory.k5);
        expect(series, hasLength(15)); // the old top-10 cut is gone
        expect(series.map((p) => p.seconds), [
          for (var i = 0; i < 15; i++) 1700 - i * 7,
        ]);
      },
    );

    test('selects only the columns it needs', () async {
      await runWith(DateTime(2026, 9, 1), [_e(DistanceCategory.k5, 1500)]);
      final spy = _SpyDb(db);
      DatabaseService.useDatabaseForTesting(spy);

      await dbs.getBestEffortSeries(DistanceCategory.k5);

      final q = spy.queries.single;
      expect(q.table, 'best_efforts');
      expect(q.columns, isNotNull);
      expect(q.columns!.toSet(), {
        'id',
        'run_id',
        'elapsed_seconds',
        'recorded_at',
      });
    });

    test('deleting a run removes its point', () async {
      final a = await runWith(DateTime(2026, 9, 1), [
        _e(DistanceCategory.k5, 1500),
      ]);
      await runWith(DateTime(2026, 9, 2), [_e(DistanceCategory.k5, 1480)]);
      await dbs.deleteRun(a);
      expect(await dbs.getBestEffortSeries(DistanceCategory.k5), hasLength(1));
    });

    test('progressive PRs flag the record-breaking runs', () async {
      await runWith(DateTime(2026, 9, 1), [_e(DistanceCategory.k5, 1500)]);
      await runWith(DateTime(2026, 9, 8), [_e(DistanceCategory.k5, 1560)]);
      await runWith(DateTime(2026, 9, 15), [_e(DistanceCategory.k5, 1458)]);

      final points = TrendAnalytics.withProgressivePrs(
        await dbs.getBestEffortSeries(DistanceCategory.k5),
      );
      expect(points.map((p) => p.isPr), [true, false, true]);
      // The last PR is the leaderboard's current #1.
      final best = (await dbs.getBestEffortsForCategory(
        DistanceCategory.k5,
        limit: 1,
      )).single;
      expect(points.last.seconds, best.elapsedSeconds);
    });
  });
}
