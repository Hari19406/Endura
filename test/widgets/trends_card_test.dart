/// TrendsCard: range and metric switching, empty and partial-data states,
/// HR coverage, km / miles, and Best Effort progression with PR markers.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/trend_analytics.dart';
import 'package:run_app/widgets/trends_card.dart';

final _now = DateTime(2026, 10, 7, 12); // Wednesday; week starts 2026-10-05

TrendRun _run(
  DateTime date, {
  double km = 10,
  int secs = 3000,
  double elev = 0,
  int? hr,
}) => TrendRun(
  date: date,
  distanceKm: km,
  movingTimeSeconds: secs,
  elevationGain: elev,
  avgHr: hr,
);

BestEffortPoint _point(String id, DateTime date, int seconds) =>
    BestEffortPoint(id: id, runId: id, date: date, seconds: seconds);

/// A run this week and an older one only the longer ranges reach.
List<TrendRun> get _twoRuns => [
  _run(DateTime(2026, 10, 5), km: 10, secs: 3000, elev: 100), // 5:00 /km
  _run(DateTime(2026, 3, 1), km: 20, secs: 6000, elev: 200), // 5:00 /km
];

Future<void> _pump(
  WidgetTester tester, {
  required List<TrendRun> runs,
  bool useMiles = false,
  BestEffortSeriesLoader? loader,
  TrendMetric metric = TrendMetric.distance,
  TrendRange range = TrendRange.weeks8,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TrendsCard(
            runs: runs,
            useMiles: useMiles,
            now: _now,
            initialMetric: metric,
            initialRange: range,
            loadBestEfforts: loader ?? (_) async => const [],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

String _headline(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('trends-headline'))).data!;

LineChartData _line(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

void main() {
  group('range switching', () {
    testWidgets('defaults to 8W and shows the range selector', (tester) async {
      await _pump(tester, runs: _twoRuns);
      for (final label in ['8W', '6M', '1Y', 'All']) {
        expect(find.byKey(Key('trends-range-$label')), findsOneWidget);
      }
      expect(_headline(tester), '10.0 km'); // only this week's run
    });

    testWidgets('each range changes what is totalled', (tester) async {
      await _pump(tester, runs: _twoRuns);
      expect(_headline(tester), '10.0 km'); // 8W

      await _tap(tester, 'trends-range-6M'); // 26 weeks: March is out
      expect(_headline(tester), '10.0 km');

      await _tap(tester, 'trends-range-1Y');
      expect(_headline(tester), '30.0 km');

      await _tap(tester, 'trends-range-All');
      expect(_headline(tester), '30.0 km');

      await _tap(tester, 'trends-range-8W');
      expect(_headline(tester), '10.0 km');
    });

    testWidgets('the chart bucket count follows the range', (tester) async {
      await _pump(tester, runs: _twoRuns);
      int bars() =>
          tester.widget<BarChart>(find.byType(BarChart)).data.barGroups.length;
      expect(bars(), 8);
      await _tap(tester, 'trends-range-6M');
      expect(bars(), 26);
      await _tap(tester, 'trends-range-1Y');
      expect(bars(), 12);
    });

    testWidgets('delta vs the previous period shows, and is hidden on All', (
      tester,
    ) async {
      await _pump(
        tester,
        runs: [
          _run(DateTime(2026, 10, 5), km: 15),
          _run(DateTime(2026, 7, 1), km: 10), // inside previous 8 weeks
        ],
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('trends-delta'))).data,
        '▲ 50% vs previous 8 weeks',
      );
      await _tap(tester, 'trends-range-All');
      expect(find.byKey(const Key('trends-delta')), findsNothing);
    });

    testWidgets('no delta when the previous period had nothing to compare', (
      tester,
    ) async {
      await _pump(tester, runs: [_run(DateTime(2026, 10, 5))]);
      expect(find.byKey(const Key('trends-delta')), findsNothing);
    });
  });

  group('metric switching', () {
    testWidgets('each metric shows its own headline', (tester) async {
      await _pump(tester, runs: _twoRuns, range: TrendRange.year1);

      await _tap(tester, 'trends-metric-time');
      expect(_headline(tester), '2h 30m');
      await _tap(tester, 'trends-metric-runs');
      expect(_headline(tester), '2 runs');
      await _tap(tester, 'trends-metric-elevation');
      expect(_headline(tester), '300 m');
      await _tap(tester, 'trends-metric-pace');
      expect(_headline(tester), '5:00 /km');
      await _tap(tester, 'trends-metric-distance');
      expect(_headline(tester), '30.0 km');
    });

    testWidgets('totals are bars; pace and HR are lines', (tester) async {
      await _pump(tester, runs: [_run(DateTime(2026, 10, 5), hr: 150)]);
      expect(find.byType(BarChart), findsOneWidget);
      await _tap(tester, 'trends-metric-pace');
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
      await _tap(tester, 'trends-metric-heartRate');
      expect(find.byType(LineChart), findsOneWidget);
      await _tap(tester, 'trends-metric-runs');
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('faster pace plots higher', (tester) async {
      await _pump(
        tester,
        metric: TrendMetric.pace,
        runs: [
          _run(DateTime(2026, 10, 5), km: 10, secs: 3000), // 5:00 /km
          _run(DateTime(2026, 9, 28), km: 10, secs: 3600), // 6:00 /km
        ],
      );
      final spots = _line(
        tester,
      ).lineBarsData.first.spots.where((s) => !s.x.isNaN).toList();
      final thisWeek = spots.firstWhere((s) => s.x == 7);
      final lastWeek = spots.firstWhere((s) => s.x == 6);
      expect(thisWeek.y, greaterThan(lastWeek.y));
    });

    testWidgets('weekly pace is time ÷ distance across the window', (
      tester,
    ) async {
      await _pump(
        tester,
        metric: TrendMetric.pace,
        runs: [
          _run(DateTime(2026, 10, 5), km: 5, secs: 1500), // 300
          _run(DateTime(2026, 10, 6), km: 10, secs: 3300), // 330
        ],
      );
      expect(_headline(tester), '5:20 /km'); // 320, not the 5:15 mean
    });
  });

  group('empty and partial data', () {
    testWidgets('no runs: a clean empty state, no controls', (tester) async {
      await _pump(tester, runs: const []);
      expect(find.byKey(const Key('trends-empty')), findsOneWidget);
      expect(find.textContaining('logged a run'), findsOneWidget);
      expect(find.byKey(const Key('trends-range-8W')), findsNothing);
      expect(find.byType(BarChart), findsNothing);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('runs exist but none in the period: says so, keeps controls', (
      tester,
    ) async {
      await _pump(tester, runs: [_run(DateTime(2024, 1, 5))]);
      expect(find.byKey(const Key('trends-no-data')), findsOneWidget);
      expect(find.text('No runs in this period.'), findsOneWidget);
      expect(find.byKey(const Key('trends-range-All')), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
      await _tap(tester, 'trends-range-All');
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('pace with no valid data shows a dash, not zero', (
      tester,
    ) async {
      await _pump(
        tester,
        metric: TrendMetric.pace,
        runs: [_run(DateTime(2026, 10, 5), km: 0, secs: 0)],
      );
      expect(_headline(tester), '—');
      expect(find.text('No pace data in this period.'), findsOneWidget);
    });
  });

  group('partial HR coverage', () {
    testWidgets('shows "N of M runs" and averages only runs with HR', (
      tester,
    ) async {
      await _pump(
        tester,
        metric: TrendMetric.heartRate,
        runs: [
          _run(DateTime(2026, 10, 5), secs: 3600, hr: 150),
          _run(DateTime(2026, 10, 6), secs: 1800, hr: 168),
          _run(DateTime(2026, 10, 7), secs: 5000), // no HR source
        ],
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('trends-hr-coverage'))).data,
        '2 of 3 runs with heart rate',
      );
      // (150·3600 + 168·1800) / 5400 = 156 — the no-HR run is not a zero.
      expect(_headline(tester), '156 bpm');
    });

    testWidgets('weeks without HR are gaps in the line, never interpolated', (
      tester,
    ) async {
      await _pump(
        tester,
        metric: TrendMetric.heartRate,
        runs: [
          _run(DateTime(2026, 8, 18), hr: 140), // first week
          _run(DateTime(2026, 10, 5), hr: 160), // last week
          _run(DateTime(2026, 9, 14)), // a middle week with no HR
        ],
      );
      final spots = _line(tester).lineBarsData.first.spots;
      expect(spots, hasLength(8));
      expect(spots.where((s) => s.x.isNaN), hasLength(6));
      final real = spots.where((s) => !s.x.isNaN).map((s) => s.y).toList();
      expect(real, [140, 160]);
    });

    testWidgets('no HR at all: 0 of M, a dash and an honest message', (
      tester,
    ) async {
      await _pump(
        tester,
        metric: TrendMetric.heartRate,
        runs: [_run(DateTime(2026, 10, 5)), _run(DateTime(2026, 10, 6))],
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('trends-hr-coverage'))).data,
        '0 of 2 runs with heart rate',
      );
      expect(_headline(tester), '—');
      expect(find.text('No heart-rate data in this period.'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('coverage follows the selected range', (tester) async {
      await _pump(
        tester,
        metric: TrendMetric.heartRate,
        runs: [
          _run(DateTime(2026, 10, 5), hr: 150),
          _run(DateTime(2026, 3, 1)), // outside 8W, no HR
        ],
      );
      Text coverage() =>
          tester.widget<Text>(find.byKey(const Key('trends-hr-coverage')));
      expect(coverage().data, '1 of 1 runs with heart rate');
      await _tap(tester, 'trends-range-1Y');
      expect(coverage().data, '1 of 2 runs with heart rate');
    });

    testWidgets('the HR delta only appears when both periods have HR', (
      tester,
    ) async {
      await _pump(
        tester,
        metric: TrendMetric.heartRate,
        runs: [
          _run(DateTime(2026, 10, 5), hr: 150),
          _run(DateTime(2026, 7, 1), hr: 144),
        ],
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('trends-delta'))).data,
        '+6 bpm vs previous 8 weeks',
      );
    });
  });

  group('km / miles', () {
    testWidgets('distance is shown in the chosen unit', (tester) async {
      await _pump(tester, runs: _twoRuns, range: TrendRange.year1);
      expect(_headline(tester), '30.0 km');
      await _pump(
        tester,
        runs: _twoRuns,
        range: TrendRange.year1,
        useMiles: true,
      );
      expect(_headline(tester), '18.6 mi');
    });

    testWidgets('the bar heights are in miles too', (tester) async {
      await _pump(tester, runs: _twoRuns, useMiles: true);
      final groups = tester
          .widget<BarChart>(find.byType(BarChart))
          .data
          .barGroups;
      expect(groups.last.barRods.single.toY, closeTo(6.21371, 1e-4));
    });

    testWidgets('pace is per mile in miles mode', (tester) async {
      await _pump(
        tester,
        runs: _twoRuns,
        metric: TrendMetric.pace,
        useMiles: true,
      );
      expect(_headline(tester), '8:03 /mi'); // 300 s/km × 1.609344
    });

    testWidgets('switching the unit updates a card that is already shown', (
      tester,
    ) async {
      await _pump(tester, runs: _twoRuns, range: TrendRange.year1);
      expect(_headline(tester), '30.0 km');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrendsCard(
                runs: _twoRuns,
                useMiles: true,
                now: _now,
                loadBestEfforts: (_) async => const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_headline(tester), '18.6 mi');
    });

    testWidgets('elevation stays in metres in both units', (tester) async {
      await _pump(
        tester,
        runs: _twoRuns,
        metric: TrendMetric.elevation,
        useMiles: true,
      );
      expect(_headline(tester), '100 m');
    });
  });

  group('Best Effort progression', () {
    final k5 = [
      _point('a', DateTime(2026, 8, 20), 1500),
      _point('b', DateTime(2026, 9, 3), 1560), // slower: not a PR
      _point('c', DateTime(2026, 9, 24), 1458), // PR
    ];

    testWidgets('defaults to 5K, loads it, and shows the best time', (
      tester,
    ) async {
      final asked = <DistanceCategory>[];
      await _pump(
        tester,
        runs: _twoRuns,
        loader: (c) async {
          asked.add(c);
          return c == DistanceCategory.k5 ? k5 : const [];
        },
      );
      expect(asked, isEmpty, reason: 'nothing is loaded until it is shown');

      await _tap(tester, 'trends-metric-bestEffort');

      expect(asked, [DistanceCategory.k5]);
      expect(_headline(tester), '24:18');
      expect(
        tester.widget<Text>(find.byKey(const Key('trends-be-summary'))).data,
        '3 efforts · 2 PRs in this period',
      );
    });

    testWidgets('PR points are marked separately from every effort', (
      tester,
    ) async {
      await _pump(tester, runs: _twoRuns, loader: (_) async => k5);
      await _tap(tester, 'trends-metric-bestEffort');

      final bars = _line(tester).lineBarsData;
      expect(bars, hasLength(2));
      expect(bars[0].spots, hasLength(3)); // every effort
      expect(bars[1].spots, hasLength(2)); // PRs only
      // Faster plots higher: the PR dots sit at -1500 and -1458.
      expect(bars[1].spots.map((s) => s.y), [-1500, -1458]);
      expect(find.byKey(const Key('trends-be-legend')), findsOneWidget);
    });

    testWidgets('only the points the loader returned are shown', (
      tester,
    ) async {
      await _pump(
        tester,
        runs: _twoRuns,
        loader: (_) async => [_point('only', DateTime(2026, 9, 1), 1500)],
      );
      await _tap(tester, 'trends-metric-bestEffort');
      final bars = _line(tester).lineBarsData;
      expect(bars[0].spots, hasLength(1));
      expect(bars[1].spots, hasLength(1)); // the first effort is the PR
    });

    testWidgets('the distance selector loads and shows that distance', (
      tester,
    ) async {
      final asked = <DistanceCategory>[];
      await _pump(
        tester,
        runs: _twoRuns,
        loader: (c) async {
          asked.add(c);
          return switch (c) {
            DistanceCategory.k5 => k5,
            DistanceCategory.k10 => [_point('t', DateTime(2026, 9, 10), 3000)],
            _ => const [],
          };
        },
      );
      await _tap(tester, 'trends-metric-bestEffort');
      expect(_headline(tester), '24:18');

      await _tap(tester, 'trends-be-category-k10');
      expect(asked, [DistanceCategory.k5, DistanceCategory.k10]);
      expect(_headline(tester), '50:00');
      expect(
        tester.widget<Text>(find.byKey(const Key('trends-be-summary'))).data,
        '1 effort · 1 PR in this period',
      );

      await _tap(tester, 'trends-be-category-k5'); // cached: no second load
      expect(asked, [DistanceCategory.k5, DistanceCategory.k10]);
      expect(_headline(tester), '24:18');
    });

    testWidgets('no historical efforts: an appropriate empty state', (
      tester,
    ) async {
      await _pump(tester, runs: _twoRuns, loader: (_) async => const []);
      await _tap(tester, 'trends-metric-bestEffort');
      expect(find.byKey(const Key('trends-be-empty')), findsOneWidget);
      expect(find.textContaining('No 5K efforts yet'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      // Other distances can be tried from the same state.
      await _tap(tester, 'trends-be-category-mi1');
      expect(find.textContaining('No 1 mi efforts yet'), findsOneWidget);
    });

    testWidgets('efforts only outside the range: says so for the period', (
      tester,
    ) async {
      await _pump(
        tester,
        runs: _twoRuns,
        loader: (_) async => [_point('old', DateTime(2025, 1, 1), 1500)],
      );
      await _tap(tester, 'trends-metric-bestEffort');
      expect(find.text('No 5K efforts in this period.'), findsOneWidget);
      await _tap(tester, 'trends-range-All');
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('PR marks come from the full history, not just the range', (
      tester,
    ) async {
      await _pump(
        tester,
        runs: _twoRuns,
        loader: (_) async => [
          _point('old', DateTime(2025, 1, 1), 1300), // fast, long ago
          _point('new', DateTime(2026, 9, 20), 1500), // slower: not a PR
        ],
      );
      await _tap(tester, 'trends-metric-bestEffort');
      expect(
        tester.widget<Text>(find.byKey(const Key('trends-be-summary'))).data,
        '1 effort · 0 PRs in this period',
      );
      expect(_line(tester).lineBarsData[1].spots, isEmpty);

      await _tap(tester, 'trends-range-All');
      expect(
        tester.widget<Text>(find.byKey(const Key('trends-be-summary'))).data,
        '2 efforts · 1 PR in this period',
      );
    });

    testWidgets('a failing loader shows the empty state instead of crashing', (
      tester,
    ) async {
      await _pump(
        tester,
        runs: _twoRuns,
        loader: (_) async => throw StateError('db closed'),
      );
      await _tap(tester, 'trends-metric-bestEffort');
      expect(find.byKey(const Key('trends-be-empty')), findsOneWidget);
    });

    testWidgets('reloaded runs refresh the efforts', (tester) async {
      var calls = 0;
      Future<List<BestEffortPoint>> loader(DistanceCategory _) async {
        calls++;
        return k5;
      }

      Widget host(List<TrendRun> runs) => MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrendsCard(
              runs: runs,
              useMiles: false,
              now: _now,
              loadBestEfforts: loader,
              initialMetric: TrendMetric.bestEffort,
            ),
          ),
        ),
      );
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 2400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(_twoRuns));
      await tester.pumpAndSettle();
      expect(calls, 1);

      await tester.pumpWidget(host([..._twoRuns]));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  });
}
