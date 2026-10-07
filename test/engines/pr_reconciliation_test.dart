/// Best Efforts is the single source for standard-distance PRs. PREngine (You
/// tab, own profile), RunAggregates (public profile columns) and the Best
/// Efforts screens must never disagree, and unrelated metrics (longest run,
/// best average pace, totals) must be unchanged.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/pr_engine.dart';
import 'package:run_app/engines/run_aggregates.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

BestEffortRecord _record(
  DistanceCategory c,
  int seconds, {
  DateTime? at,
  String runId = '1',
}) => BestEffortRecord(
  id: '${runId}_${c.name}',
  runId: runId,
  category: c,
  elapsedSeconds: seconds,
  recordedAt: at ?? DateTime(2026, 9, 1),
);

Run _run(double km, int seconds, {DateTime? date}) => Run(
  distanceKm: km,
  durationSeconds: seconds,
  date: date ?? DateTime(2026, 9, 1),
);

BestEffortResult _e(DistanceCategory c, int seconds) =>
    BestEffortResult(category: c, elapsedSeconds: seconds);

void main() {
  sqfliteFfiInit();

  group('PREngine: standard distances come from Best Efforts', () {
    final efforts = {
      DistanceCategory.k5: _record(
        DistanceCategory.k5,
        1458,
        at: DateTime(2026, 8, 3),
      ),
      DistanceCategory.k10: _record(DistanceCategory.k10, 3010),
      DistanceCategory.half: _record(DistanceCategory.half, 6600),
      DistanceCategory.marathon: _record(DistanceCategory.marathon, 14400),
    };

    test('5K / 10K / half / marathon are the Best Effort times', () {
      final pr = PREngine([_run(6, 1800)], bestEfforts: efforts).calculate();
      expect(pr.best5K!.value, '24:18');
      expect(pr.best10K!.value, '50:10');
      expect(pr.bestHalf!.value, '1:50:00');
      expect(pr.bestMarathon!.value, '4:00:00');
    });

    test('the date is the effort\'s and the pace is derived from it', () {
      final pr = PREngine([_run(6, 1800)], bestEfforts: efforts).calculate();
      expect(pr.best5K!.setOn, DateTime(2026, 8, 3));
      // 1458 s over 5 km = 291.6 s/km = 4:52
      expect(pr.best5K!.unit, '4:52 /km');
    });

    test('labels are unchanged', () {
      final pr = PREngine([_run(6, 1800)], bestEfforts: efforts).calculate();
      expect(pr.best5K!.label, 'Best 5K');
      expect(pr.best10K!.label, 'Best 10K');
      expect(pr.bestHalf!.label, 'Best half');
      expect(pr.bestMarathon!.label, 'Best marathon');
    });

    test('there is no whole-run projection: no Best Effort means no PR', () {
      // Fast long runs that the OLD rule would have projected into PRs.
      final pr = PREngine([
        _run(5.2, 1400),
        _run(11, 3000),
        _run(22, 6000),
        _run(43, 13000),
      ]).calculate();
      expect(pr.best5K, isNull);
      expect(pr.best10K, isNull);
      expect(pr.bestHalf, isNull);
      expect(pr.bestMarathon, isNull);
    });

    test('a distance without a Best Effort is simply absent', () {
      final pr = PREngine(
        [_run(6, 1800)],
        bestEfforts: {DistanceCategory.k5: efforts[DistanceCategory.k5]!},
      ).calculate();
      expect(pr.best5K, isNotNull);
      expect(pr.best10K, isNull);
      expect(pr.allEntries.map((e) => e.label), [
        'Best 5K',
        'Best avg pace',
        'Longest run',
      ]);
    });

    test('longest run and best average pace are unchanged by Best Efforts', () {
      final runs = [
        _run(5, 1500, date: DateTime(2026, 9, 1)),
        _run(12, 3300, date: DateTime(2026, 9, 2)), // longest, 4:35/km avg
        _run(3, 780, date: DateTime(2026, 9, 3)), // fastest avg: 4:20/km
      ];
      final without = PREngine(runs).calculate();
      final withBe = PREngine(runs, bestEfforts: efforts).calculate();

      expect(withBe.longestRun.value, without.longestRun.value);
      expect(withBe.longestRun.value, '12.0');
      expect(withBe.longestRun.setOn, DateTime(2026, 9, 2));
      expect(withBe.bestAvgPace.value, without.bestAvgPace.value);
      expect(withBe.bestAvgPace.value, '4:20');
      expect(withBe.bestAvgPace.setOn, DateTime(2026, 9, 3));
    });

    test(
      'with no runs there are no PRs and the placeholders are unchanged',
      () {
        final pr = PREngine(const []).calculate();
        expect(pr.best5K, isNull);
        expect(pr.bestAvgPace.value, '--:--');
        expect(pr.longestRun.value, '0.0');
      },
    );
  });

  group('RunAggregates and PREngine report the same PRs', () {
    test('the same Best Efforts give the same 5K / 10K / half in both', () {
      final efforts = {
        DistanceCategory.k5: _record(DistanceCategory.k5, 1458),
        DistanceCategory.k10: _record(DistanceCategory.k10, 3010),
        DistanceCategory.half: _record(DistanceCategory.half, 6600),
      };
      final runs = [
        RunRecord(
          date: DateTime(2026, 9, 1),
          distanceKm: 22,
          averagePace: '5:00',
          durationSeconds: 6900,
          routePolyline: '',
        ),
      ];
      final agg = RunAggregates.fromRuns(runs, bestEfforts: efforts);
      final pr = PREngine([_run(22, 6900)], bestEfforts: efforts).calculate();

      String clock(int s) => BestEffortsService.formatElapsed(s);
      expect(clock(agg.best5kSeconds!), pr.best5K!.value);
      expect(clock(agg.best10kSeconds!), pr.best10K!.value);
      expect(clock(agg.bestHalfMarathonSeconds!), pr.bestHalf!.value);
    });

    test('neither invents a PR the other lacks', () {
      final runs = [
        RunRecord(
          date: DateTime(2026, 9, 1),
          distanceKm: 22,
          averagePace: '5:00',
          durationSeconds: 6600,
          routePolyline: '',
        ),
      ];
      final agg = RunAggregates.fromRuns(runs);
      final pr = PREngine([_run(22, 6600)]).calculate();
      expect(agg.best5kSeconds, isNull);
      expect(pr.best5K, isNull);
      expect(agg.bestHalfMarathonSeconds, isNull);
      expect(pr.bestHalf, isNull);
    });
  });

  group('one source of truth, end to end (real SQLite)', () {
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

    Future<int> storeRun(List<BestEffortResult> efforts, {int day = 1}) async {
      final id = await dbs.insertRun(
        RunRecord(
          date: DateTime(2026, 9, day),
          distanceKm: 11,
          averagePace: '5:00',
          durationSeconds: 3300,
          routePolyline: '',
        ),
      );
      await dbs.insertBestEffortsForRun(
        '$id',
        efforts,
        recordedAt: DateTime(2026, 9, day),
      );
      return id;
    }

    /// Every PR view, computed the way the app does, from the database.
    Future<({int? board, int? you, int? aggregate, int? badge})> views(
      DistanceCategory c,
      int badgeRunId,
    ) async {
      final prs = await dbs.getAllCategoryPRs();
      final runs = await dbs.getAllRuns();
      final pr = PREngine([
        for (final r in runs)
          Run(
            distanceKm: r.distanceKm,
            durationSeconds: r.durationSeconds,
            date: r.date,
          ),
      ], bestEfforts: prs).calculate();
      final agg = RunAggregates.fromRuns(runs, bestEfforts: prs);

      final board = await dbs.getBestEffortsForCategory(c, limit: 1);
      final entry = switch (c) {
        DistanceCategory.k5 => pr.best5K,
        DistanceCategory.k10 => pr.best10K,
        _ => null,
      };
      int? parse(String? v) {
        if (v == null) return null;
        final parts = v.split(':').map(int.parse).toList();
        return parts.length == 3
            ? parts[0] * 3600 + parts[1] * 60 + parts[2]
            : parts[0] * 60 + parts[1];
      }

      final badges = await dbs.getRunBestEfforts('$badgeRunId');
      final mine = badges.where((b) => b.category == c).toList();
      return (
        board: board.isEmpty ? null : board.first.elapsedSeconds,
        you: parse(entry?.value),
        aggregate: switch (c) {
          DistanceCategory.k5 => agg.best5kSeconds,
          DistanceCategory.k10 => agg.best10kSeconds,
          _ => null,
        },
        badge: mine.isEmpty ? null : mine.first.bestSeconds,
      );
    }

    test(
      'leaderboard, You tab, profile columns and run badge all agree',
      () async {
        final a = await storeRun([
          _e(DistanceCategory.k5, 1500),
          _e(DistanceCategory.k10, 3100),
        ], day: 1);
        await storeRun([
          _e(DistanceCategory.k5, 1458),
          _e(DistanceCategory.k10, 3010),
        ], day: 2);

        for (final c in [DistanceCategory.k5, DistanceCategory.k10]) {
          final v = await views(c, a);
          expect(v.board, isNotNull);
          expect(v.you, v.board, reason: '${c.label}: You tab vs leaderboard');
          expect(
            v.aggregate,
            v.board,
            reason: '${c.label}: profile vs leaderboard',
          );
          expect(
            v.badge,
            v.board,
            reason: '${c.label}: run badge vs leaderboard',
          );
        }
        expect((await views(DistanceCategory.k5, a)).board, 1458);
      },
    );

    test(
      'deleting the current PR promotes the next-fastest in every view',
      () async {
        final slow = await storeRun([_e(DistanceCategory.k5, 1600)], day: 1);
        final mid = await storeRun([_e(DistanceCategory.k5, 1500)], day: 2);
        final pr = await storeRun([_e(DistanceCategory.k5, 1458)], day: 3);

        expect((await views(DistanceCategory.k5, slow)).board, 1458);

        await dbs.deleteRun(pr);

        final v = await views(DistanceCategory.k5, slow);
        expect(v.board, 1500);
        expect(v.you, 1500);
        expect(v.aggregate, 1500);
        expect(v.badge, 1500);
        final promoted = (await dbs.getRunBestEfforts('$mid')).single;
        expect(promoted.isPr, isTrue);
      },
    );

    test(
      'deleting the only effort removes the PR everywhere (no fallback)',
      () async {
        final only = await storeRun([_e(DistanceCategory.k5, 1500)]);
        final other = await storeRun([_e(DistanceCategory.k1, 300)], day: 2);
        await dbs.deleteRun(only);

        final v = await views(DistanceCategory.k5, other);
        expect(v.board, isNull);
        expect(v.you, isNull);
        expect(v.aggregate, isNull);
      },
    );

    test('unrelated aggregates are untouched by the PR source', () async {
      await storeRun([_e(DistanceCategory.k5, 1500)]);
      await storeRun([_e(DistanceCategory.k5, 1458)], day: 2);
      final runs = await dbs.getAllRuns();
      final prs = await dbs.getAllCategoryPRs();

      final withBe = RunAggregates.fromRuns(runs, bestEfforts: prs);
      final without = RunAggregates.fromRuns(runs);
      expect(withBe.totalRuns, 2);
      expect(withBe.totalDistanceMeters, 22000);
      expect(withBe.totalMovingSeconds, 6600);
      expect(withBe.totalRuns, without.totalRuns);
      expect(withBe.totalDistanceMeters, without.totalDistanceMeters);
      expect(withBe.totalMovingSeconds, without.totalMovingSeconds);
      expect(withBe.totalElevationMeters, without.totalElevationMeters);
    });
  });
}
