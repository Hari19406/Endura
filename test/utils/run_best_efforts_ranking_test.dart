/// DatabaseService.getRunBestEfforts — per-run efforts with their rank among
/// ALL retained efforts and the current all-time best, against real SQLite.
/// The rank must always equal the effort's position on the leaderboard
/// (getBestEffortsForCategory), ties included.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  Future<int> run() => dbs.insertRun(
    RunRecord(
      date: DateTime(2026, 9, 1),
      distanceKm: 6,
      averagePace: '5:00',
      durationSeconds: 1800,
      routePolyline: '',
    ),
  );

  group('rank, total and all-time best', () {
    test(
      'rank is the position among every retained effort at that distance',
      () async {
        final ids = <int>[];
        for (final secs in [1500, 1450, 1600, 1550]) {
          final id = await run();
          ids.add(id);
          await dbs.insertBestEffortsForRun('$id', [
            _e(DistanceCategory.k5, secs),
          ], recordedAt: DateTime(2026, 9, ids.length));
        }
        // Fastest first: 1450 (run 2), 1500 (run 1), 1550 (run 4), 1600 (run 3).
        Future<RunBestEffort> of(int id) async =>
            (await dbs.getRunBestEfforts('$id')).single;

        expect((await of(ids[1])).rank, 1);
        expect((await of(ids[0])).rank, 2);
        expect((await of(ids[3])).rank, 3);
        expect((await of(ids[2])).rank, 4);
      },
    );

    test('carries the total count and the current all-time best', () async {
      final a = await run();
      final b = await run();
      await dbs.insertBestEffortsForRun('$a', [_e(DistanceCategory.k5, 1450)]);
      await dbs.insertBestEffortsForRun('$b', [_e(DistanceCategory.k5, 1500)]);

      final e = (await dbs.getRunBestEfforts('$b')).single;
      expect(e.totalEfforts, 2);
      expect(e.bestSeconds, 1450);
      expect(e.secondsOffBest, 50);
      expect(e.isPr, isFalse);

      final pr = (await dbs.getRunBestEfforts('$a')).single;
      expect(pr.isPr, isTrue);
      expect(pr.bestSeconds, 1450);
      expect(pr.secondsOffBest, 0);
    });

    test('ranks are per distance, not across distances', () async {
      final a = await run();
      final b = await run();
      await dbs.insertBestEffortsForRun('$a', [
        _e(DistanceCategory.k1, 300),
        _e(DistanceCategory.k5, 1600),
      ]);
      await dbs.insertBestEffortsForRun('$b', [
        _e(DistanceCategory.k1, 290),
        _e(DistanceCategory.k5, 1700),
      ]);
      final efforts = await dbs.getRunBestEfforts('$b');
      final k1 = efforts.firstWhere((e) => e.category == DistanceCategory.k1);
      final k5 = efforts.firstWhere((e) => e.category == DistanceCategory.k5);
      expect(k1.rank, 1); // run b has the best 1K...
      expect(k5.rank, 2); // ...but the second-best 5K
    });

    test(
      'returns only the distances the run achieved, in distance order',
      () async {
        final id = await run();
        await dbs.insertBestEffortsForRun('$id', [
          _e(DistanceCategory.k10, 3000),
          _e(DistanceCategory.k1, 300),
          _e(DistanceCategory.k5, 1500),
        ]);
        final efforts = await dbs.getRunBestEfforts('$id');
        expect(efforts.map((e) => e.category), [
          DistanceCategory.k1,
          DistanceCategory.k5,
          DistanceCategory.k10,
        ]);
      },
    );

    test(
      'an unknown run, or a run with no efforts, gives an empty list',
      () async {
        final id = await run();
        expect(await dbs.getRunBestEfforts('$id'), isEmpty);
        expect(await dbs.getRunBestEfforts('999'), isEmpty);
      },
    );
  });

  group('deterministic tie-breaking (same ordering as the leaderboard)', () {
    test('equal times: the earlier effort ranks first', () async {
      await dbs.insertBestEffortsForRun('late', [
        _e(DistanceCategory.k10, 3000),
      ], recordedAt: DateTime(2026, 10, 1));
      await dbs.insertBestEffortsForRun('early', [
        _e(DistanceCategory.k10, 3000),
      ], recordedAt: DateTime(2026, 8, 1));
      expect((await dbs.getRunBestEfforts('early')).single.rank, 1);
      expect((await dbs.getRunBestEfforts('late')).single.rank, 2);
    });

    test('equal time and date: id order decides, consistently', () async {
      final at = DateTime(2026, 9, 1);
      for (final id in ['c', 'a', 'b']) {
        await dbs.insertBestEffortsForRun(id, [
          _e(DistanceCategory.k5, 1500),
        ], recordedAt: at);
      }
      expect((await dbs.getRunBestEfforts('a')).single.rank, 1);
      expect((await dbs.getRunBestEfforts('b')).single.rank, 2);
      expect((await dbs.getRunBestEfforts('c')).single.rank, 3);
    });

    test('no two efforts ever share a rank, even with tied times', () async {
      for (var i = 0; i < 6; i++) {
        await dbs.insertBestEffortsForRun('r$i', [
          _e(DistanceCategory.k5, 1500),
        ], recordedAt: DateTime(2026, 9, 1));
      }
      final ranks = <int>[];
      for (var i = 0; i < 6; i++) {
        ranks.add((await dbs.getRunBestEfforts('r$i')).single.rank);
      }
      expect(ranks.toSet().length, 6);
      expect(ranks..sort(), [1, 2, 3, 4, 5, 6]);
    });

    test(
      'the rank always equals the leaderboard position (randomised)',
      () async {
        final rng = math.Random(7);
        for (var i = 0; i < 30; i++) {
          await dbs.insertBestEffortsForRun('run$i', [
            for (final c in [
              DistanceCategory.k1,
              DistanceCategory.k5,
              DistanceCategory.k10,
            ])
              if (rng.nextBool()) _e(c, 200 + rng.nextInt(40) * 5), // many ties
          ], recordedAt: DateTime(2026, 1, 1 + rng.nextInt(60)));
        }
        for (final c in DistanceCategory.values) {
          final board = await dbs.getBestEffortsForCategory(c, limit: null);
          for (var pos = 0; pos < board.length; pos++) {
            final mine = (await dbs.getRunBestEfforts(
              board[pos].runId,
            )).firstWhere((e) => e.category == c);
            expect(
              mine.rank,
              pos + 1,
              reason: '${c.label} ${board[pos].runId}',
            );
            expect(mine.totalEfforts, board.length);
            expect(mine.bestSeconds, board.first.elapsedSeconds);
          }
        }
      },
    );
  });

  group('deleting a run re-ranks the rest', () {
    test('the next-fastest becomes the PR and later ranks move up', () async {
      final ids = <int>[];
      for (final secs in [1450, 1500, 1550, 1600]) {
        final id = await run();
        ids.add(id);
        await dbs.insertBestEffortsForRun('$id', [
          _e(DistanceCategory.k5, secs),
        ], recordedAt: DateTime(2026, 9, ids.length));
      }
      Future<int> rankOf(int id) async =>
          (await dbs.getRunBestEfforts('$id')).single.rank;

      expect([for (final id in ids) await rankOf(id)], [1, 2, 3, 4]);

      await dbs.deleteRun(ids[0]); // delete the current PR

      expect(await dbs.getRunBestEfforts('${ids[0]}'), isEmpty);
      expect([for (final id in ids.skip(1)) await rankOf(id)], [1, 2, 3]);
      final promoted = (await dbs.getRunBestEfforts('${ids[1]}')).single;
      expect(promoted.isPr, isTrue);
      expect(promoted.bestSeconds, 1500);
    });

    test(
      'deleting a mid-ranked run only moves the efforts behind it',
      () async {
        final ids = <int>[];
        for (final secs in [1450, 1500, 1550, 1600]) {
          final id = await run();
          ids.add(id);
          await dbs.insertBestEffortsForRun('$id', [
            _e(DistanceCategory.k5, secs),
          ], recordedAt: DateTime(2026, 9, ids.length));
        }
        await dbs.deleteRun(ids[1]);
        Future<int> rankOf(int id) async =>
            (await dbs.getRunBestEfforts('$id')).single.rank;
        expect(await rankOf(ids[0]), 1);
        expect(await rankOf(ids[2]), 2);
        expect(await rankOf(ids[3]), 3);
      },
    );
  });

  group('storage is unchanged by ranking', () {
    test('reading ranks never writes or removes rows', () async {
      final id = await run();
      await dbs.insertBestEffortsForRun('$id', [
        _e(DistanceCategory.k1, 300),
        _e(DistanceCategory.k5, 1500),
      ]);
      final before = await db.query('best_efforts', orderBy: 'id');
      await dbs.getRunBestEfforts('$id');
      await dbs.getRunBestEfforts('$id');
      expect(await db.query('best_efforts', orderBy: 'id'), before);
    });
  });
}
