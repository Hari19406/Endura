/// best_efforts storage against a REAL (in-memory) SQLite database created with
/// the app's own schema: every effort is retained, rankings are computed at
/// query time, deleting a run promotes the next-fastest effort, and the
/// rebuild works end to end through the actual DatabaseService.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_rebuild_service.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<Map<String, dynamic>> _samples(double totalM) => [
  for (var d = 50.0; d <= totalM + 1e-9; d += 50) {'t': d / 50 * 15, 'd': d},
];

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

  Future<int> insertRun({
    List<Map<String, dynamic>> samples = const [],
    double km = 6.0,
    DateTime? date,
  }) => dbs.insertRun(
    RunRecord(
      date: date ?? DateTime(2026, 9, 1, 7),
      distanceKm: km,
      averagePace: '5:00',
      durationSeconds: (km * 300).round(),
      routePolyline: '',
      trackSamples: samples,
    ),
  );

  Future<List<Map<String, Object?>>> allRows() =>
      db.query('best_efforts', orderBy: 'id');

  group('schema and basic CRUD (no regression)', () {
    test('the real schema creates the best_efforts and runs tables', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables.map((t) => t['name']).toSet();
      expect(names, containsAll(['runs', 'best_efforts']));
    });

    test('a run round-trips with its track samples', () async {
      final samples = _samples(500);
      final id = await insertRun(samples: samples, km: 0.5);
      expect(id, greaterThan(0));
      final back = (await dbs.getRunById(id))!;
      expect(back.trackSamples.length, samples.length);
      expect(back.distanceKm, 0.5);
    });

    test(
      'insertBestEffort stores a single row and replaces on the same id',
      () async {
        final at = DateTime(2026, 9, 1);
        await dbs.insertBestEffort(
          BestEffortRecord(
            id: '1_k5',
            runId: '1',
            category: DistanceCategory.k5,
            elapsedSeconds: 1500,
            recordedAt: at,
          ),
        );
        await dbs.insertBestEffort(
          BestEffortRecord(
            id: '1_k5',
            runId: '1',
            category: DistanceCategory.k5,
            elapsedSeconds: 1450,
            recordedAt: at,
          ),
        );
        final rows = await dbs.getBestEffortsForCategory(DistanceCategory.k5);
        expect(rows, hasLength(1));
        expect(rows.single.elapsedSeconds, 1450);
      },
    );

    test('getAllRunIds lists every run, oldest first', () async {
      final a = await insertRun();
      final b = await insertRun();
      final c = await insertRun();
      expect(await dbs.getAllRunIds(), [a, b, c]);
    });
  });

  group('all efforts are retained (no top-10 trimming)', () {
    test('fifteen efforts in one category are all kept', () async {
      for (var i = 1; i <= 15; i++) {
        await dbs.insertBestEffortsForRun('$i', [
          _e(DistanceCategory.k5, 1400 + i * 10),
        ], recordedAt: DateTime(2026, 9, i));
      }
      final all = await dbs.getBestEffortsForCategory(
        DistanceCategory.k5,
        limit: null,
      );
      expect(all, hasLength(15));
      expect(await allRows(), hasLength(15));
    });

    test('slower efforts are never deleted when faster ones arrive', () async {
      await dbs.insertBestEffortsForRun('1', [_e(DistanceCategory.k1, 400)]);
      for (var i = 2; i <= 14; i++) {
        await dbs.insertBestEffortsForRun('$i', [
          _e(DistanceCategory.k1, 400 - i * 5),
        ]);
      }
      expect(await allRows(), hasLength(14));
      // The slowest (run 1) is still there.
      expect((await allRows()).any((r) => r['run_id'] == '1'), isTrue);
    });
  });

  group('ranking is computed at query time', () {
    setUp(() async {
      for (var i = 1; i <= 15; i++) {
        await dbs.insertBestEffortsForRun('$i', [
          _e(DistanceCategory.k5, 1400 + i * 10),
          _e(DistanceCategory.k1, 280 + i),
        ], recordedAt: DateTime(2026, 9, i));
      }
    });

    test('the default returns the fastest ten, fastest first', () async {
      final top = await dbs.getBestEffortsForCategory(DistanceCategory.k5);
      expect(top, hasLength(10));
      expect(top.first.elapsedSeconds, 1410);
      expect(top.last.elapsedSeconds, 1500);
      final secs = top.map((r) => r.elapsedSeconds).toList();
      expect(secs, [...secs]..sort());
    });

    test('limit returns just the fastest N', () async {
      final top3 = await dbs.getBestEffortsForCategory(
        DistanceCategory.k5,
        limit: 3,
      );
      expect(top3.map((r) => r.elapsedSeconds), [1410, 1420, 1430]);
    });

    test('limit null returns every row, still ranked', () async {
      final all = await dbs.getBestEffortsForCategory(
        DistanceCategory.k5,
        limit: null,
      );
      expect(all, hasLength(15));
      expect(all.first.elapsedSeconds, 1410);
      expect(all.last.elapsedSeconds, 1550);
    });

    test('categories are ranked independently', () async {
      final k1 = await dbs.getBestEffortsForCategory(DistanceCategory.k1);
      expect(k1.first.elapsedSeconds, 281);
    });

    test(
      'equal times: the earlier effort ranks first, deterministically',
      () async {
        await dbs.insertBestEffortsForRun('late', [
          _e(DistanceCategory.k10, 3000),
        ], recordedAt: DateTime(2026, 10, 1));
        await dbs.insertBestEffortsForRun('early', [
          _e(DistanceCategory.k10, 3000),
        ], recordedAt: DateTime(2026, 8, 1));
        final r = await dbs.getBestEffortsForCategory(DistanceCategory.k10);
        expect(r.map((e) => e.runId), ['early', 'late']);
      },
    );

    test(
      'getAllCategoryPRs returns #1 per category and omits unreached ones',
      () async {
        final prs = await dbs.getAllCategoryPRs();
        expect(prs[DistanceCategory.k5]!.elapsedSeconds, 1410);
        expect(prs[DistanceCategory.k1]!.elapsedSeconds, 281);
        expect(prs.containsKey(DistanceCategory.marathon), isFalse);
      },
    );
  });

  group('deleting the current PR promotes the next-fastest', () {
    test(
      'after deleting the PR run, the second-fastest becomes the PR',
      () async {
        final a = await insertRun();
        final b = await insertRun();
        final c = await insertRun();
        await dbs.insertBestEffortsForRun('$a', [
          _e(DistanceCategory.k5, 1500),
        ]);
        await dbs.insertBestEffortsForRun('$b', [
          _e(DistanceCategory.k5, 1600),
        ]);
        await dbs.insertBestEffortsForRun('$c', [
          _e(DistanceCategory.k5, 1700),
        ]);

        expect(
          (await dbs.getAllCategoryPRs())[DistanceCategory.k5]!.elapsedSeconds,
          1500,
        );

        await dbs.deleteRun(a);

        final top = await dbs.getBestEffortsForCategory(DistanceCategory.k5);
        expect(top.map((r) => r.elapsedSeconds), [1600, 1700]);
        expect(
          (await dbs.getAllCategoryPRs())[DistanceCategory.k5]!.elapsedSeconds,
          1600,
        );
      },
    );

    test(
      'an effort that used to fall outside the top ten is promoted',
      () async {
        // 12 runs; the slowest two would have been trimmed under the old rule.
        final ids = <int>[];
        for (var i = 1; i <= 12; i++) {
          final id = await insertRun();
          ids.add(id);
          await dbs.insertBestEffortsForRun('$id', [
            _e(DistanceCategory.k5, 1400 + i * 10),
          ]);
        }
        // Remove the ten fastest runs: the former #11 and #12 are now #1 and #2.
        for (final id in ids.take(10)) {
          await dbs.deleteRun(id);
        }
        final top = await dbs.getBestEffortsForCategory(DistanceCategory.k5);
        expect(top.map((r) => r.elapsedSeconds), [1510, 1520]);
      },
    );

    test('deleting a run removes only that run\'s efforts', () async {
      final a = await insertRun();
      final b = await insertRun();
      await dbs.insertBestEffortsForRun('$a', [
        _e(DistanceCategory.k1, 300),
        _e(DistanceCategory.k5, 1500),
      ]);
      await dbs.insertBestEffortsForRun('$b', [_e(DistanceCategory.k1, 310)]);
      await dbs.deleteRun(a);
      final rows = await allRows();
      expect(rows, hasLength(1));
      expect(rows.single['run_id'], '$b');
    });
  });

  group('insertBestEffortsForRun replaces a run\'s rows', () {
    test(
      'a recompute swaps the rows and drops categories that no longer qualify',
      () async {
        await dbs.insertBestEffortsForRun('1', [
          _e(DistanceCategory.k1, 300),
          _e(DistanceCategory.k5, 1500),
        ]);
        await dbs.insertBestEffortsForRun('1', [_e(DistanceCategory.k1, 290)]);

        final rows = await allRows();
        expect(rows, hasLength(1));
        expect(rows.single['distance_category'], 'k1');
        expect(rows.single['elapsed_seconds'], 290);
      },
    );

    test(
      'an empty result clears the run\'s rows and leaves other runs alone',
      () async {
        await dbs.insertBestEffortsForRun('1', [_e(DistanceCategory.k1, 300)]);
        await dbs.insertBestEffortsForRun('2', [_e(DistanceCategory.k1, 310)]);
        await dbs.insertBestEffortsForRun('1', const []);
        final rows = await allRows();
        expect(rows.map((r) => r['run_id']), ['2']);
      },
    );

    test('rows use deterministic ids so re-running never duplicates', () async {
      for (var i = 0; i < 3; i++) {
        await dbs.insertBestEffortsForRun('7', [_e(DistanceCategory.k5, 1500)]);
      }
      final rows = await allRows();
      expect(rows, hasLength(1));
      expect(rows.single['id'], '7_k5');
    });

    test('the recorded date is stored with the effort', () async {
      final at = DateTime(2026, 8, 3, 6, 30);
      await dbs.insertBestEffortsForRun('1', [
        _e(DistanceCategory.k5, 1500),
      ], recordedAt: at);
      final r = (await dbs.getBestEffortsForCategory(
        DistanceCategory.k5,
      )).single;
      expect(r.recordedAt, at);
    });
  });

  group('orphan cleanup', () {
    test('removes rows whose run no longer exists, keeps the rest', () async {
      final live = await insertRun();
      await dbs.insertBestEffortsForRun('$live', [
        _e(DistanceCategory.k1, 300),
      ]);
      await dbs.insertBestEffortsForRun('999', [_e(DistanceCategory.k1, 250)]);
      await dbs.insertBestEffortsForRun('1000', [
        _e(DistanceCategory.k5, 1200),
      ]);

      final removed = await dbs.deleteOrphanBestEfforts();

      expect(removed, 2);
      final rows = await allRows();
      expect(rows.map((r) => r['run_id']), ['$live']);
    });

    test('nothing to remove returns 0', () async {
      final live = await insertRun();
      await dbs.insertBestEffortsForRun('$live', [
        _e(DistanceCategory.k1, 300),
      ]);
      expect(await dbs.deleteOrphanBestEfforts(), 0);
    });
  });

  group('rebuild end to end through the real database', () {
    test(
      'recomputes history, fixes stale rows, skips runs without samples',
      () async {
        // Run A: a clean 6 km run that was stored with flawed, trimmed rows.
        final a = await insertRun(samples: _samples(6000), km: 6.0);
        await dbs.insertBestEffort(
          BestEffortRecord(
            id: '${a}_k5',
            runId: '$a',
            category: DistanceCategory.k5,
            elapsedSeconds: 600, // impossible: from a glitch
            recordedAt: DateTime(2026, 9, 1),
          ),
        );
        await dbs.insertBestEffort(
          BestEffortRecord(
            id: '${a}_k10',
            runId: '$a',
            category: DistanceCategory.k10,
            elapsedSeconds: 2500, // a 6 km run has no 10K
            recordedAt: DateTime(2026, 9, 1),
          ),
        );
        // Run B: a clock-stall run whose old row was impossibly fast.
        final b = await insertRun(
          samples: [
            for (var d = 50.0; d <= 1000; d += 50) {'t': d / 50 * 15, 'd': d},
            for (var k = 1; k <= 8; k++) {'t': 300.0, 'd': 1000.0 + k * 150},
            {'t': 800.0, 'd': 2250.0},
            for (var k = 1; k <= 30; k++)
              {'t': 800 + k * 15.0, 'd': 2250.0 + k * 50},
          ],
          km: 3.75,
        );
        await dbs.insertBestEffort(
          BestEffortRecord(
            id: '${b}_k1',
            runId: '$b',
            category: DistanceCategory.k1,
            elapsedSeconds: 30,
            recordedAt: DateTime(2026, 9, 1),
          ),
        );
        // Run C: no track samples (pre-v8 / cloud-restored).
        final c = await insertRun(km: 5.0);
        // An orphan row from a run that no longer exists.
        await dbs.insertBestEffort(
          BestEffortRecord(
            id: '999_k1',
            runId: '999',
            category: DistanceCategory.k1,
            elapsedSeconds: 200,
            recordedAt: DateTime(2026, 9, 1),
          ),
        );

        final result = await BestEffortsRebuildService().rebuild();

        expect(result.runsSeen, 3);
        expect(result.runsProcessed, 2);
        expect(result.runsSkipped, 1);
        expect(result.orphansRemoved, 1);

        final aTop = await dbs.getBestEffortsForCategory(DistanceCategory.k5);
        expect(aTop.single.elapsedSeconds, 1500); // not 600
        expect(
          await dbs.getBestEffortsForCategory(DistanceCategory.k10),
          isEmpty,
        );
        final k1 = await dbs.getBestEffortsForCategory(DistanceCategory.k1);
        expect(k1.map((r) => r.runId).toSet(), {'$a', '$b'});
        expect(
          k1.every((r) => r.elapsedSeconds >= 300),
          isTrue,
          reason: 'no impossible 1K survives the rebuild',
        );
        expect((await allRows()).any((r) => r['run_id'] == '$c'), isFalse);
        expect((await allRows()).any((r) => r['run_id'] == '999'), isFalse);
      },
    );

    test('running the rebuild twice gives an identical table', () async {
      await insertRun(samples: _samples(6000), km: 6.0);
      await insertRun(samples: _samples(3000), km: 3.0);
      await insertRun(km: 5.0);

      await BestEffortsRebuildService().rebuild();
      final first = await allRows();
      await BestEffortsRebuildService().rebuild();
      final second = await allRows();

      expect(second, first);
      expect(first, isNotEmpty);
    });

    test('rebuilt efforts keep every row, with nothing trimmed', () async {
      for (var i = 0; i < 13; i++) {
        await insertRun(
          samples: _samples(2000),
          km: 2.0,
          date: DateTime(2026, 9, 1 + i),
        );
      }
      await BestEffortsRebuildService().rebuild();
      final k1 = await dbs.getBestEffortsForCategory(
        DistanceCategory.k1,
        limit: null,
      );
      expect(k1, hasLength(13)); // would have been 10 under the old trimming
    });
  });
}
