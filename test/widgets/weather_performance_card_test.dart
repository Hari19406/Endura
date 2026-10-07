/// WeatherPerformanceCard: empty and thin-data states, the temperature /
/// humidity / HR charts, heat impact, conditions, units and honest wording.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/weather_service.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/weather_analytics.dart';
import 'package:run_app/widgets/weather_performance_card.dart';

WeatherRun _run(
  double temp, {
  int humidity = 50,
  WeatherCondition condition = WeatherCondition.clear,
  int secs = 3300, // 330 s/km over 10 km
  int? hr,
}) => WeatherRun(
  tempC: temp,
  humidityPercent: humidity,
  condition: condition,
  distanceKm: 10,
  movingTimeSeconds: secs,
  avgHr: hr,
);

List<WeatherRun> _many(
  int n,
  double temp, {
  int secs = 3300,
  int humidity = 50,
  int? hr,
  WeatherCondition condition = WeatherCondition.clear,
}) => [
  for (var i = 0; i < n; i++)
    _run(temp, secs: secs, humidity: humidity, hr: hr, condition: condition),
];

Future<void> _pump(
  WidgetTester tester,
  List<WeatherRun> runs, {
  bool useMiles = false,
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
          child: WeatherPerformanceCard(runs: runs, useMiles: useMiles),
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

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

List<FlSpot> _spots(WidgetTester tester) => tester
    .widget<LineChart>(find.byType(LineChart))
    .data
    .lineBarsData
    .first
    .spots;

void main() {
  group('empty and thin data', () {
    testWidgets('no weather runs: a clean empty state, no controls', (
      tester,
    ) async {
      await _pump(tester, const []);
      expect(find.byKey(const Key('weather-empty')), findsOneWidget);
      expect(
        find.text(
          'Keep running with weather enabled to build your weather history.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LineChart), findsNothing);
      expect(find.byKey(const Key('weather-view-tempPace')), findsNothing);
    });

    testWidgets('a few runs: counts them and explains why nothing is charted', (
      tester,
    ) async {
      await _pump(tester, [_run(22), _run(22)]);
      expect(_text(tester, 'weather-run-count'), '2 runs with weather');
      expect(find.byKey(const Key('weather-chart-empty')), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      expect(find.byKey(const Key('weather-heat-impact')), findsNothing);
      expect(find.byKey(const Key('weather-heat-pending')), findsOneWidget);
    });

    testWidgets('a single run is singular', (tester) async {
      await _pump(tester, [_run(22)]);
      expect(_text(tester, 'weather-run-count'), '1 run with weather');
    });

    testWidgets('one comparable band is not a comparison', (tester) async {
      await _pump(tester, [..._many(6, 22), ..._many(2, 32)]);
      expect(find.byKey(const Key('weather-chart-empty')), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });
  });

  group('temperature vs pace', () {
    final runs = [
      ..._many(3, 12, secs: 3600), // 360 s/km
      ..._many(3, 22, secs: 3300), // 330 s/km
    ];

    testWidgets('plots the comparable bands, faster higher, others as gaps', (
      tester,
    ) async {
      await _pump(tester, runs);
      final spots = _spots(tester);
      expect(spots, hasLength(5)); // one slot per temperature band
      final real = {
        for (final s in spots)
          if (!s.x.isNaN) s.x.toInt(): s.y,
      };
      expect(real.keys.toSet(), {0, 2}); // <15° and 20–25°
      expect(real[0], -360);
      expect(real[2], -330);
      expect(real[2]!, greaterThan(real[0]!)); // faster plots higher
      expect(spots.where((s) => s.x.isNaN), hasLength(3));
    });

    testWidgets('says that higher is faster and what is left out', (
      tester,
    ) async {
      await _pump(tester, runs);
      expect(_text(tester, 'weather-chart-note'), contains('higher is faster'));
      expect(
        _text(tester, 'weather-chart-note'),
        contains('fewer than 3 runs'),
      );
    });

    testWidgets('has no HR view without HR data', (tester) async {
      await _pump(tester, runs);
      expect(find.byKey(const Key('weather-view-tempHr')), findsNothing);
      expect(find.byKey(const Key('weather-view-tempPace')), findsOneWidget);
      expect(
        find.byKey(const Key('weather-view-humidityPace')),
        findsOneWidget,
      );
    });
  });

  group('humidity vs pace', () {
    testWidgets('switches to the humidity bands', (tester) async {
      await _pump(tester, [
        ..._many(3, 20, humidity: 35, secs: 3300),
        ..._many(3, 20, humidity: 85, secs: 3600),
      ]);
      await _tap(tester, 'weather-view-humidityPace');
      final spots = _spots(tester);
      expect(spots, hasLength(4)); // one slot per humidity band
      final real = {
        for (final s in spots)
          if (!s.x.isNaN) s.x.toInt(): s.y,
      };
      expect(real, {0: -330, 3: -360});
    });
  });

  group('temperature vs HR', () {
    final runs = [..._many(3, 12, hr: 140), ..._many(3, 22, hr: 152)];

    testWidgets('appears once two bands have enough HR runs', (tester) async {
      await _pump(tester, runs);
      expect(find.byKey(const Key('weather-view-tempHr')), findsOneWidget);
    });

    testWidgets('plots average HR (not negated) and skips bands without HR', (
      tester,
    ) async {
      await _pump(tester, [...runs, ..._many(4, 32)]); // 30°+: runs, no HR
      await _tap(tester, 'weather-view-tempHr');
      final real = {
        for (final s in _spots(tester))
          if (!s.x.isNaN) s.x.toInt(): s.y,
      };
      expect(real, {0: 140, 2: 152});
      expect(_text(tester, 'weather-chart-note'), contains('with HR'));
    });

    testWidgets('runs without HR are not counted as zero', (tester) async {
      await _pump(tester, [
        ..._many(3, 12, hr: 140),
        ..._many(3, 22, hr: 152),
        ..._many(9, 22), // lots of 20–25° runs without HR
      ]);
      await _tap(tester, 'weather-view-tempHr');
      final real = {
        for (final s in _spots(tester))
          if (!s.x.isNaN) s.x.toInt(): s.y,
      };
      expect(real[2], 152);
    });
  });

  group('heat impact', () {
    testWidgets('states the observed difference with sample sizes', (
      tester,
    ) async {
      await _pump(tester, [
        ..._many(6, 22, secs: 3300),
        ..._many(5, 32, secs: 3450),
      ]);
      final text = _text(tester, 'weather-heat-impact-text');
      expect(text, contains('30°+'));
      expect(text, contains('about 15 s/km slower than at 20–25°'));
      expect(text, contains('5 vs 6 runs'));
    });

    testWidgets('is not generated from a handful of runs', (tester) async {
      await _pump(tester, [..._many(6, 22), ..._many(2, 32)]);
      expect(find.byKey(const Key('weather-heat-impact')), findsNothing);
      expect(find.byKey(const Key('weather-heat-pending')), findsOneWidget);
    });

    testWidgets('a faster hot pace is reported as faster', (tester) async {
      await _pump(tester, [
        ..._many(5, 22, secs: 3300),
        ..._many(5, 32, secs: 3200),
      ]);
      expect(
        _text(tester, 'weather-heat-impact-text'),
        contains('about 10 s/km faster than at 20–25°'),
      );
    });

    testWidgets('a negligible difference says similar, not slower', (
      tester,
    ) async {
      await _pump(tester, [
        ..._many(5, 22, secs: 3300),
        ..._many(5, 32, secs: 3315),
      ]);
      final text = _text(tester, 'weather-heat-impact-text');
      expect(text, contains('similar'));
      expect(text, isNot(contains('slower')));
    });

    testWidgets('never claims causation', (tester) async {
      await _pump(tester, [
        ..._many(6, 22, secs: 3300),
        ..._many(5, 32, secs: 3450),
      ]);
      expect(find.textContaining('not proof'), findsOneWidget);
      expect(find.textContaining('because'), findsNothing);
      expect(find.textContaining('caused by'), findsNothing);
    });
  });

  group('weather conditions', () {
    testWidgets('shows only conditions that have data', (tester) async {
      await _pump(tester, [
        ..._many(10, 20, condition: WeatherCondition.clear),
        ..._many(2, 20, condition: WeatherCondition.rain),
      ]);
      expect(find.byKey(const Key('weather-condition-clear')), findsOneWidget);
      expect(find.byKey(const Key('weather-condition-rain')), findsOneWidget);
      expect(find.byKey(const Key('weather-condition-snow')), findsNothing);
      expect(find.byKey(const Key('weather-condition-fog')), findsNothing);
      expect(find.byKey(const Key('weather-condition-cloudy')), findsNothing);
    });

    testWidgets('pace is shown only for conditions with enough runs', (
      tester,
    ) async {
      await _pump(tester, [
        ..._many(10, 20, condition: WeatherCondition.clear),
        ..._many(2, 20, condition: WeatherCondition.rain),
      ]);
      expect(
        find.descendant(
          of: find.byKey(const Key('weather-condition-clear')),
          matching: find.text('Clear · 10 runs · 5:30 /km'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('weather-condition-rain')),
          matching: find.text('Rain · 2 runs'),
        ),
        findsOneWidget,
      );
    });
  });

  group('km / miles', () {
    final runs = [
      ..._many(6, 22, secs: 3300),
      ..._many(5, 32, secs: 3450),
      ..._many(3, 12, secs: 3600),
    ];

    testWidgets('pace and the heat difference follow the unit', (tester) async {
      await _pump(tester, runs, useMiles: true);
      // 15 s/km ≈ 24 s/mi
      expect(_text(tester, 'weather-heat-impact-text'), contains('24 s/mi'));
      // 47850 s / 140 km = 341.8 s/km ≈ 9:10 /mi
      expect(find.textContaining('Clear · 14 runs · 9:10 /mi'), findsOneWidget);
    });

    testWidgets('the plotted pace is per mile', (tester) async {
      await _pump(tester, runs, useMiles: true);
      final real = [
        for (final s in _spots(tester))
          if (!s.x.isNaN) s.y,
      ];
      // 330 s/km → 531.1 s/mi plotted negated; 360 → 579.4.
      expect(real, contains(closeTo(-330 * 1.609344, 1e-6)));
      expect(real, contains(closeTo(-360 * 1.609344, 1e-6)));
    });

    testWidgets('kilometres by default', (tester) async {
      await _pump(tester, runs);
      expect(find.textContaining('Clear · 14 runs · 5:42 /km'), findsOneWidget);
      expect(_text(tester, 'weather-heat-impact-text'), contains('15 s/km'));
    });
  });
}
