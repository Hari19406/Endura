/// The Best Efforts card on ActivityDetailScreen: the efforts a run achieved,
/// each with its rank and the all-time best for comparison. The card renders
/// stored Best Efforts (never recalculates), so the chain tests below go
/// analyzeRun → real SQLite → getRunBestEfforts → ActivityDetail → widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/models/feed_run.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<Map<String, dynamic>> _samples(double totalM) => [
  for (var d = 50.0; d <= totalM + 1e-9; d += 50) {'t': d / 50 * 15, 'd': d},
];

RunRecord _record({
  int? id,
  double km = 6.0,
  List<Map<String, dynamic>>? samples,
}) => RunRecord(
  id: id,
  date: DateTime(2026, 9, 20, 7),
  distanceKm: km,
  averagePace: '5:00',
  durationSeconds: (km * 300).round(),
  routePolyline: '',
  trackSamples: samples ?? _samples(km * 1000),
);

RunBestEffort _effort(
  DistanceCategory c,
  int seconds, {
  required int rank,
  required int best,
  int total = 6,
}) => RunBestEffort(
  category: c,
  elapsedSeconds: seconds,
  rank: rank,
  totalEfforts: total,
  bestSeconds: best,
);

ActivityDetail _detail(List<RunBestEffort> efforts, {RunRecord? record}) =>
    ActivityDetail.fromRunRecord(
      record ?? _record(),
      runnerName: 'x',
      bestEfforts: efforts,
    );

Widget _host(ActivityDetail a) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: ActivityDetailScreen(activity: a),
);

void _surface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 4000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _row(DistanceCategory c) => find.byKey(Key('best-effort-row-${c.name}'));
Finder _inRow(DistanceCategory c, String text) =>
    find.descendant(of: _row(c), matching: find.text(text));

void main() {
  sqfliteFfiInit();

  group('rank labels', () {
    test('PR, 2nd, 3rd, then ordinals with the 11th-13th exceptions', () {
      String l(int r) => BestEffortsService.rankLabel(r);
      expect(
        [l(1), l(2), l(3), l(4), l(5)],
        ['PR', '2nd', '3rd', '4th', '5th'],
      );
      expect([l(11), l(12), l(13)], ['11th', '12th', '13th']);
      expect([l(21), l(22), l(23), l(24)], ['21st', '22nd', '23rd', '24th']);
      expect(
        [l(101), l(111), l(112), l(121)],
        ['101st', '111th', '112th', '121st'],
      );
    });

    test('RunBestEffort derives PR status and the gap to the best', () {
      final pr = _effort(DistanceCategory.k5, 1458, rank: 1, best: 1458);
      final third = _effort(DistanceCategory.k5, 1500, rank: 3, best: 1458);
      expect(pr.isPr, isTrue);
      expect(pr.secondsOffBest, 0);
      expect(pr.rankLabel, 'PR');
      expect(third.isPr, isFalse);
      expect(third.secondsOffBest, 42);
      expect(third.rankLabel, '3rd');
    });
  });

  group('the card', () {
    testWidgets('an eligible run shows each effort with time and rank', (
      tester,
    ) async {
      _surface(tester);
      final a = _detail([
        _effort(DistanceCategory.k5, 1458, rank: 1, best: 1458), // 24:18
        _effort(DistanceCategory.mi1, 452, rank: 2, best: 440), // 7:32
        _effort(DistanceCategory.k3, 842, rank: 5, best: 800), // 14:02
      ]);
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('BEST EFFORTS'), findsOneWidget);

      expect(_inRow(DistanceCategory.k5, '5K'), findsOneWidget);
      expect(_inRow(DistanceCategory.k5, '24:18'), findsOneWidget);
      expect(_inRow(DistanceCategory.k5, 'PR'), findsOneWidget);

      expect(_inRow(DistanceCategory.mi1, '1 mi'), findsOneWidget);
      expect(_inRow(DistanceCategory.mi1, '7:32'), findsOneWidget);
      expect(_inRow(DistanceCategory.mi1, '2nd'), findsOneWidget);

      expect(_inRow(DistanceCategory.k3, '3K'), findsOneWidget);
      expect(_inRow(DistanceCategory.k3, '14:02'), findsOneWidget);
      expect(_inRow(DistanceCategory.k3, '5th'), findsOneWidget);
    });

    testWidgets('the all-time best is shown for comparison', (tester) async {
      _surface(tester);
      final a = _detail([
        _effort(DistanceCategory.k5, 1458, rank: 1, best: 1458),
        _effort(DistanceCategory.mi1, 452, rank: 2, best: 440),
        _effort(DistanceCategory.k3, 842, rank: 5, best: 800),
      ]);
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();

      // The PR is the best, so it says so rather than comparing with itself.
      expect(_inRow(DistanceCategory.k5, 'All-time best'), findsOneWidget);
      // Others show the best and how far off it they were.
      expect(_inRow(DistanceCategory.mi1, 'Best 7:20 · +0:12'), findsOneWidget);
      expect(_inRow(DistanceCategory.k3, 'Best 13:20 · +0:42'), findsOneWidget);
    });

    testWidgets('hour-long efforts use h:mm:ss', (tester) async {
      _surface(tester);
      final a = _detail([
        _effort(DistanceCategory.half, 5400, rank: 1, best: 5400), // 1:30:00
      ]);
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();
      expect(_inRow(DistanceCategory.half, '1:30:00'), findsOneWidget);
    });

    testWidgets('only the distances the run achieved are listed', (
      tester,
    ) async {
      _surface(tester);
      final a = _detail([
        _effort(DistanceCategory.k1, 300, rank: 1, best: 300),
        _effort(DistanceCategory.k3, 900, rank: 2, best: 880),
      ]);
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();

      expect(_row(DistanceCategory.k1), findsOneWidget);
      expect(_row(DistanceCategory.k3), findsOneWidget);
      for (final c in [
        DistanceCategory.k5,
        DistanceCategory.k10,
        DistanceCategory.half,
        DistanceCategory.marathon,
        DistanceCategory.m400,
        DistanceCategory.mi1,
      ]) {
        expect(_row(c), findsNothing, reason: '${c.label} should be hidden');
      }
    });

    testWidgets('efforts keep distance order as given', (tester) async {
      _surface(tester);
      final a = _detail([
        _effort(DistanceCategory.k1, 300, rank: 1, best: 300),
        _effort(DistanceCategory.k5, 1500, rank: 1, best: 1500),
      ]);
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();
      final y1 = tester.getTopLeft(_row(DistanceCategory.k1)).dy;
      final y5 = tester.getTopLeft(_row(DistanceCategory.k5)).dy;
      expect(y1, lessThan(y5));
    });

    testWidgets('a run with no Best Efforts shows no card and no error', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(const [])));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('BEST EFFORTS'), findsNothing);
      expect(find.byType(Row).evaluate().isNotEmpty, isTrue); // screen rendered
    });

    testWidgets('Feed runs (someone else\'s activity) show no card', (
      tester,
    ) async {
      _surface(tester);
      final run = FeedRun.fromRows({
        'id': 42,
        'user_id': 'athlete-1',
        'distance_km': 5.0,
        'average_pace': '5:00',
        'duration_seconds': 1500,
        'date': '2026-09-18T06:00:00.000Z',
        'splits': [
          for (var k = 1; k <= 5; k++) {'km': k, 'seconds': 300},
        ],
      }, null);
      final a = ActivityDetail.fromFeedRun(run);
      expect(a.bestEfforts, isEmpty);
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();
      expect(find.text('BEST EFFORTS'), findsNothing);
    });

    testWidgets('rank badges: medals for the top three, neutral after', (
      tester,
    ) async {
      _surface(tester);
      final a = _detail([
        _effort(DistanceCategory.k1, 300, rank: 1, best: 300),
        _effort(DistanceCategory.mi1, 490, rank: 2, best: 480),
        _effort(DistanceCategory.k3, 900, rank: 3, best: 880),
        _effort(DistanceCategory.k5, 1500, rank: 4, best: 1400),
      ]);
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();

      Color badgeColor(DistanceCategory c) => tester
          .widget<CircleAvatar>(
            find.descendant(of: _row(c), matching: find.byType(CircleAvatar)),
          )
          .backgroundColor!;
      final gold = badgeColor(DistanceCategory.k1);
      final silver = badgeColor(DistanceCategory.mi1);
      final bronze = badgeColor(DistanceCategory.k3);
      final fourth = badgeColor(DistanceCategory.k5);
      expect({gold, silver, bronze}.length, 3); // three distinct medals
      expect(fourth, AppColors.light.background); // neutral token after 3rd
    });
  });

  group('chain: analyzeRun → SQLite → ranking → card', () {
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

    /// Inserts a run, stores its Best Efforts through the canonical path, and
    /// returns its id.
    Future<int> storeRun(double km, {DateTime? date, double stepS = 15}) async {
      final samples = [
        for (var d = 50.0; d <= km * 1000 + 1e-9; d += 50)
          {'t': d / 50 * stepS, 'd': d},
      ];
      final id = await dbs.insertRun(
        RunRecord(
          date: date ?? DateTime(2026, 9, 1),
          distanceKm: km,
          averagePace: '5:00',
          durationSeconds: (km * 1000 / 50 * stepS).round(),
          routePolyline: '',
          trackSamples: samples,
        ),
      );
      final results = BestEffortsService.analyzeRun(
        samples,
        finalDistanceMeters: km * 1000,
        finalSeconds: km * 1000 / 50 * stepS,
      );
      await dbs.insertBestEffortsForRun(
        '$id',
        results,
        recordedAt: date ?? DateTime(2026, 9, 1),
      );
      return id;
    }

    Future<ActivityDetail> openRun(int id) async {
      final record = (await dbs.getRunById(id))!;
      final efforts = await dbs.getRunBestEfforts('$id');
      return ActivityDetail.fromRunRecord(
        record,
        runnerName: 'x',
        bestEfforts: efforts,
      );
    }

    testWidgets('distances longer than the run are hidden', (tester) async {
      _surface(tester);
      final detail = await tester.runAsync(() async {
        final id = await storeRun(3.2); // a 3.2 km run
        return openRun(id);
      });
      await tester.pumpWidget(_host(detail!));
      await tester.pumpAndSettle();

      for (final c in [
        DistanceCategory.m400,
        DistanceCategory.k1,
        DistanceCategory.mi1,
        DistanceCategory.k3,
      ]) {
        expect(_row(c), findsOneWidget, reason: '${c.label} was covered');
      }
      for (final c in [
        DistanceCategory.k5,
        DistanceCategory.k10,
        DistanceCategory.half,
        DistanceCategory.marathon,
      ]) {
        expect(
          _row(c),
          findsNothing,
          reason: '${c.label} is longer than the run',
        );
      }
    });

    testWidgets('shows the achieved time from the stored efforts', (
      tester,
    ) async {
      _surface(tester);
      final detail = await tester.runAsync(() async {
        final id = await storeRun(6.0); // steady 5:00/km
        return openRun(id);
      });
      await tester.pumpWidget(_host(detail!));
      await tester.pumpAndSettle();

      expect(_inRow(DistanceCategory.k1, '5:00'), findsOneWidget);
      expect(_inRow(DistanceCategory.k5, '25:00'), findsOneWidget);
      expect(_inRow(DistanceCategory.k5, 'PR'), findsOneWidget);
    });

    testWidgets(
      'PR / 2nd / 3rd are correct across runs, with the best for comparison',
      (tester) async {
        _surface(tester);
        // Five 6 km runs at different paces; 5K times 24:10 / 24:50 / 25:30 /
        // 26:10 / 26:50 (stepS 14.5, 14.9, 15.3, 15.7, 16.1).
        final ids = await tester.runAsync(() async {
          final out = <int>[];
          var day = 1;
          for (final stepS in [14.5, 14.9, 15.3, 15.7, 16.1]) {
            out.add(
              await storeRun(6.0, date: DateTime(2026, 9, day++), stepS: stepS),
            );
          }
          return out;
        });

        final third = await tester.runAsync(() => openRun(ids![2]));
        await tester.pumpWidget(_host(third!));
        await tester.pumpAndSettle();
        expect(_inRow(DistanceCategory.k5, '3rd'), findsOneWidget);
        expect(_inRow(DistanceCategory.k5, '25:30'), findsOneWidget);
        expect(
          _inRow(DistanceCategory.k5, 'Best 24:10 · +1:20'),
          findsOneWidget,
        );

        final first = await tester.runAsync(() => openRun(ids![0]));
        await tester.pumpWidget(_host(first!));
        await tester.pumpAndSettle();
        expect(_inRow(DistanceCategory.k5, 'PR'), findsOneWidget);
        expect(_inRow(DistanceCategory.k5, 'All-time best'), findsOneWidget);

        final second = await tester.runAsync(() => openRun(ids![1]));
        await tester.pumpWidget(_host(second!));
        await tester.pumpAndSettle();
        expect(_inRow(DistanceCategory.k5, '2nd'), findsOneWidget);
      },
    );

    testWidgets('deleting the PR run promotes the next-fastest effort', (
      tester,
    ) async {
      _surface(tester);
      final ids = await tester.runAsync(() async {
        final a = await storeRun(6.0, date: DateTime(2026, 9, 1), stepS: 14.5);
        final b = await storeRun(6.0, date: DateTime(2026, 9, 2), stepS: 15.0);
        return [a, b];
      });
      final before = await tester.runAsync(() => openRun(ids![1]));
      await tester.pumpWidget(_host(before!));
      await tester.pumpAndSettle();
      expect(_inRow(DistanceCategory.k5, '2nd'), findsOneWidget);

      await tester.runAsync(() => dbs.deleteRun(ids![0]));
      final after = await tester.runAsync(() => openRun(ids![1]));
      await tester.pumpWidget(_host(after!));
      await tester.pumpAndSettle();
      expect(_inRow(DistanceCategory.k5, 'PR'), findsOneWidget);
      expect(_inRow(DistanceCategory.k5, 'All-time best'), findsOneWidget);
    });

    testWidgets('a run whose efforts were all rejected shows no card', (
      tester,
    ) async {
      _surface(tester);
      // A 6 km run whose clock stalled: no window passes validation at 5K+,
      // and the run is stored with no rows at all.
      final detail = await tester.runAsync(() async {
        final id = await dbs.insertRun(
          _record(km: 0.3, samples: _samples(300)),
        );
        return openRun(id); // 300 m: shorter than every benchmark
      });
      await tester.pumpWidget(_host(detail!));
      await tester.pumpAndSettle();
      expect(detail.bestEfforts, isEmpty);
      expect(find.text('BEST EFFORTS'), findsNothing);
    });
  });
}
