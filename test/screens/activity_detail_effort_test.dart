/// The combined PACE · HR · ELEVATION card, and the data-quality handling of
/// the existing pace / HR / elevation charts (validity rules, line breaks at
/// GPS/time gaps).
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/models/feed_run.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:run_app/utils/unit_utils.dart';

const _c = AppColors.light;

/// 2 km at 5:00/km, a sample every 50 m / 15 s. HR climbs 140 + i; altitude
/// climbs at 5%. Any of the three can be switched off; [mutate] edits a
/// sample map before it is stored.
List<Map<String, dynamic>> _samples({
  bool hr = true,
  bool alt = true,
  bool time = true,
  int count = 41,
  void Function(int i, Map<String, dynamic> m)? mutate,
}) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    final m = <String, dynamic>{
      if (time) 't': i * 15.0,
      'd': i * 50.0,
      'pace': 300.0,
      if (hr) 'hr': 140 + i,
      if (alt) 'alt': 100.0 + i * 2.5,
    };
    mutate?.call(i, m);
    out.add(m);
  }
  return out;
}

RunRecord _record(List<Map<String, dynamic>> samples) => RunRecord(
  date: DateTime(2026, 9, 20, 7),
  distanceKm: 2.0,
  averagePace: '5:00',
  durationSeconds: 600,
  routePolyline: '',
  workoutType: 'easy',
  splits: const [
    {'km': 1, 'seconds': 300},
    {'km': 2, 'seconds': 300},
  ],
  trackSamples: samples,
);

ActivityDetail _detail(List<Map<String, dynamic>> samples) =>
    ActivityDetail.fromRunRecord(_record(samples), runnerName: 'x');

Widget _host(ActivityDetail a) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: ActivityDetailScreen(activity: a),
);

/// A tall surface so every card of the screen is laid out and tappable.
void _surface(WidgetTester tester, {double width = 800}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 4000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// flutter_test draws text in the wide "Ahem" font, so unrelated, existing
/// rows (the social pills, the HR caption) overflow at 360 px even though they
/// fit with a real font. Collect overflow errors so a narrow-screen test can
/// assert that THIS card's layout is clean without being failed by those.
List<String> _captureOverflows() {
  final overflows = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) {
      overflows.add(details.toString());
    } else {
      original?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = original);
  return overflows;
}

bool _fromEffortCard(String report) => report.contains('_EffortCard');

Finder get _effortChart => find.byKey(const Key('effort-chart'));
Finder get _readout => find.byKey(const Key('effort-readout'));

LineChart _effortLineChart(WidgetTester tester) => tester.widget<LineChart>(
  find.descendant(of: _effortChart, matching: find.byType(LineChart)),
);

/// Colours of the lines actually drawn in the combined chart.
Set<Color> _drawnColors(WidgetTester tester) => {
  for (final b in _effortLineChart(tester).data.lineBarsData)
    if (b.color != null && b.color != Colors.transparent) b.color!,
};

Finder _inReadout(String text) =>
    find.descendant(of: _readout, matching: find.text(text));

void main() {
  tearDown(() => UnitUtils.useMilesNotifier.value = false);

  group('visibility', () {
    testWidgets('appears with pace + HR + elevation data', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PACE · HR · ELEVATION'), findsOneWidget);
      expect(find.byKey(const Key('effort-chip-pace')), findsOneWidget);
      expect(find.byKey(const Key('effort-chip-hr')), findsOneWidget);
      expect(find.byKey(const Key('effort-chip-elevation')), findsOneWidget);
      expect(
        find.text('Touch and drag across the chart to compare'),
        findsOneWidget,
      );
    });

    testWidgets('appears with just two channels, offering only those', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples(alt: false))));
      await tester.pumpAndSettle();

      expect(find.text('PACE · HR · ELEVATION'), findsOneWidget);
      expect(find.byKey(const Key('effort-chip-elevation')), findsNothing);
      expect(find.byKey(const Key('effort-chip-hr')), findsOneWidget);
    });

    testWidgets('hides with only one channel', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples(hr: false, alt: false))));
      await tester.pumpAndSettle();
      expect(find.text('PACE · HR · ELEVATION'), findsNothing);
    });

    testWidgets('hides when there is no clock, even with three channels', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples(time: false))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('PACE · HR · ELEVATION'), findsNothing);
    });

    testWidgets('hides when HR is entirely invalid (and so is one channel)', (
      tester,
    ) async {
      _surface(tester);
      final a = _detail(
        _samples(alt: false, mutate: (i, m) => m['hr'] = 20), // all < 30
      );
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();
      expect(find.text('PACE · HR · ELEVATION'), findsNothing);
    });

    testWidgets('Feed runs hide the card', (tester) async {
      _surface(tester);
      final run = FeedRun.fromRows({
        'id': 42,
        'user_id': 'athlete-1',
        'distance_km': 3.0,
        'average_pace': '5:00',
        'duration_seconds': 900,
        'date': '2026-09-18T06:00:00.000Z',
        'splits': [
          {'km': 1, 'seconds': 300, 'elev': 4.0, 'hr': 148},
          {'km': 2, 'seconds': 305, 'elev': -2.0, 'hr': 152},
          {'km': 3, 'seconds': 295, 'elev': 6.0, 'hr': 155},
        ],
      }, null);
      final a = ActivityDetail.fromFeedRun(run);
      expect(a.effort.hasPace, isTrue); // the data exists...
      expect(a.hasEffortChart, isFalse); // ...but there is no clock
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('PACE · HR · ELEVATION'), findsNothing);
      // The existing Feed pace card still renders.
      expect(find.text('PACE'), findsWidgets);
    });
  });

  group('toggles', () {
    testWidgets('all channels are drawn on a wide screen', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();
      expect(_drawnColors(tester), {
        _c.chartAccent,
        _c.hrAccent,
        _c.cadenceAccent,
      });
    });

    testWidgets('HR uses the dedicated hrAccent token, not danger', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();
      final colors = _drawnColors(tester);
      expect(colors.contains(_c.hrAccent), isTrue);
      expect(colors.contains(_c.danger), isFalse);
    });

    testWidgets('tapping a chip hides and re-shows that channel', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('effort-chip-hr')));
      await tester.pumpAndSettle();
      expect(_drawnColors(tester), {_c.chartAccent, _c.cadenceAccent});

      await tester.tap(find.byKey(const Key('effort-chip-elevation')));
      await tester.pumpAndSettle();
      expect(_drawnColors(tester), {_c.chartAccent});

      await tester.tap(find.byKey(const Key('effort-chip-hr')));
      await tester.pumpAndSettle();
      expect(_drawnColors(tester), {_c.chartAccent, _c.hrAccent});
    });

    testWidgets('the last visible channel cannot be switched off', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples(alt: false))));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('effort-chip-hr')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('effort-chip-pace')));
      await tester.pumpAndSettle();
      expect(_drawnColors(tester), {_c.chartAccent}); // pace stays on
    });

    testWidgets('a narrow screen starts with two channels', (tester) async {
      _surface(tester, width: 360);
      final overflows = _captureOverflows();
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();
      expect(overflows.where(_fromEffortCard), isEmpty);
      expect(_drawnColors(tester), {_c.chartAccent, _c.hrAccent});
    });

    testWidgets('on a narrow screen a third channel replaces the oldest', (
      tester,
    ) async {
      _surface(tester, width: 360);
      final overflows = _captureOverflows();
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('effort-chip-elevation')));
      await tester.pumpAndSettle();
      // Pace (switched on first) is dropped; HR and elevation remain.
      expect(_drawnColors(tester), {_c.hrAccent, _c.cadenceAccent});

      // The readout (five cells in a 280 px card) must not overflow either.
      await tester.tapAt(tester.getCenter(_effortChart));
      await tester.pumpAndSettle();
      expect(overflows.where(_fromEffortCard), isEmpty);
    });
  });

  group('shared cursor and readout', () {
    testWidgets('tapping shows every channel\'s value at that distance', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();

      // Centre of the plot = 1.00 km = sample 20: HR 160, 5:00/km, 150 m.
      await tester.tapAt(tester.getCenter(_effortChart));
      await tester.pumpAndSettle();

      expect(
        find.text('Touch and drag across the chart to compare'),
        findsNothing,
      );
      expect(_inReadout('1.00'), findsOneWidget);
      expect(_inReadout('5:00'), findsOneWidget);
      expect(_inReadout('160'), findsOneWidget);
      expect(_inReadout('150'), findsOneWidget);
      // 5% climb.
      final grade = tester.widget<Text>(
        find.descendant(of: _readout, matching: find.textContaining('%')),
      );
      expect(grade.data, startsWith('+5.'));
    });

    testWidgets('the cursor draws a vertical line and a dot per channel', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();
      expect(
        _effortLineChart(tester).data.extraLinesData.verticalLines,
        isEmpty,
      );

      await tester.tapAt(tester.getCenter(_effortChart));
      await tester.pumpAndSettle();

      final data = _effortLineChart(tester).data;
      expect(data.extraLinesData.verticalLines, hasLength(1));
      expect(data.extraLinesData.verticalLines.single.x, closeTo(1.0, 1e-9));
      final dots = data.lineBarsData.where((b) => b.spots.length == 1);
      expect(dots, hasLength(3)); // pace, HR, elevation
    });

    testWidgets('dragging moves the cursor and updates the readout', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();

      final box = tester.getRect(_effortChart);
      await tester.tapAt(Offset(box.left + box.width * 0.25, box.center.dy));
      await tester.pumpAndSettle();
      expect(_inReadout('0.50'), findsOneWidget);
      expect(_inReadout('150'), findsWidgets); // HR 150 at sample 10

      final gesture = await tester.startGesture(
        Offset(box.left + box.width * 0.25, box.center.dy),
      );
      await gesture.moveBy(Offset(box.width * 0.5, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_inReadout('1.50'), findsOneWidget); // 0.25 + 0.5 of 2 km
      expect(_inReadout('170'), findsOneWidget); // HR at sample 30
    });

    testWidgets('missing channels at the cursor show a dash, not a number', (
      tester,
    ) async {
      _surface(tester);
      final a = _detail(
        _samples(
          mutate: (i, m) {
            if (i >= 18 && i <= 22) m.remove('hr'); // HR dropout around 1 km
          },
        ),
      );
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();

      await tester.tapAt(tester.getCenter(_effortChart)); // sample 20
      await tester.pumpAndSettle();
      expect(_inReadout('—'), findsOneWidget);
      expect(_inReadout('5:00'), findsOneWidget);
    });

    testWidgets('readout and axis follow the miles preference', (tester) async {
      UnitUtils.useMilesNotifier.value = true;
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();

      await tester.tapAt(tester.getCenter(_effortChart));
      await tester.pumpAndSettle();
      // 300 s/km * 1.609344 = 483 s/mi = 8:03
      expect(_inReadout('8:03'), findsOneWidget);
      expect(
        find.descendant(of: _readout, matching: find.text('MI')),
        findsOneWidget,
      );
    });
  });

  group('existing charts: validity and gaps', () {
    /// Every drawn line group of [color] across all charts on the screen.
    Map<Color, List<int>> barsByColor(WidgetTester tester) {
      final out = <Color, List<int>>{};
      for (final chart in tester.widgetList<LineChart>(
        find.byType(LineChart),
      )) {
        final counts = <Color, int>{};
        for (final b in chart.data.lineBarsData) {
          final col = b.color;
          if (col == null || col == Colors.transparent) continue;
          counts[col] = (counts[col] ?? 0) + 1;
        }
        counts.forEach((k, v) => out.putIfAbsent(k, () => []).add(v));
      }
      return out;
    }

    /// A 3-minute hole after sample 20: 50 m covered in 180 s.
    List<Map<String, dynamic>> gapped() => _samples(
      mutate: (i, m) {
        if (i > 20) m['t'] = (m['t'] as double) + 165; // +165 s after sample 20
      },
    );

    testWidgets('lines break at a >60 s gap instead of bridging it', (
      tester,
    ) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(gapped())));
      await tester.pumpAndSettle();

      final byColor = barsByColor(tester);
      // Every pace / HR / elevation line is drawn as TWO runs, in the
      // combined chart and in each individual card.
      for (final color in [
        _c.chartAccent, // pace
        _c.hrAccent, // HR (combined)
        _c.danger, // HR (existing HR card)
        _c.cadenceAccent, // elevation
      ]) {
        expect(byColor[color], isNotNull, reason: 'no chart drew $color');
        for (final n in byColor[color]!) {
          expect(n, 2, reason: 'a line of $color was not broken at the gap');
        }
      }
    });

    testWidgets('a continuous run draws each line as one run', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_host(_detail(_samples())));
      await tester.pumpAndSettle();
      final byColor = barsByColor(tester);
      for (final n in byColor[_c.chartAccent]!) {
        expect(n, 1);
      }
      for (final n in byColor[_c.danger]!) {
        expect(n, 1);
      }
    });

    testWidgets('invalid pace, HR and 0.0 altitude are not plotted', (
      tester,
    ) async {
      _surface(tester);
      final a = _detail(
        _samples(
          mutate: (i, m) {
            if (i == 10) m['hr'] = 255; // strap spike
            if (i == 11) m['hr'] = 10;
            if (i == 12) m['pace'] = 40.0; // 0:40/km GPS jump
            if (i == 13) m['pace'] = 5000.0; // standing still
            if (i == 14) m['alt'] = 0.0; // altitude unavailable
            if (i == 15) m['alt'] = 0.0;
          },
        ),
      );
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final chart in tester.widgetList<LineChart>(
        find.byType(LineChart),
      )) {
        for (final bar in chart.data.lineBarsData) {
          // HR cards: bpm values plotted in absolute units (not normalised).
          if (bar.color == _c.danger) {
            for (final s in bar.spots) {
              expect(s.y, inInclusiveRange(30, 230));
              expect(s.y, isNot(255));
            }
          }
          // Pace card (negated sec/km): only valid paces.
          if (bar.color == _c.chartAccent && chart.data.maxY > 5) {
            for (final s in bar.spots) {
              expect(-s.y, inInclusiveRange(120, 1800));
            }
          }
          // Elevation card: no 0.0 cliffs (real altitude is ~100-200 m).
          if (bar.color == _c.cadenceAccent && chart.data.maxY > 5) {
            for (final s in bar.spots) {
              expect(s.y, greaterThan(50));
            }
          }
        }
      }
    });

    testWidgets('the HR chart axis is not stretched by an invalid spike', (
      tester,
    ) async {
      _surface(tester);
      final a = _detail(
        _samples(
          mutate: (i, m) {
            if (i == 5) m['hr'] = 250;
          },
        ),
      );
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();

      // Valid HR tops out at 180; the HR card's y-range is peak + 8.
      final hrChart = tester
          .widgetList<LineChart>(find.byType(LineChart))
          .firstWhere(
            (ch) => ch.data.lineBarsData.any((b) => b.color == _c.danger),
          );
      expect(hrChart.data.maxY, lessThan(200));
    });

    testWidgets('the pace and elevation cards disappear if nothing is valid', (
      tester,
    ) async {
      _surface(tester);
      final a = _detail(
        _samples(
          mutate: (i, m) {
            m['pace'] = 50.0; // all invalid
            m['alt'] = 0.0; // all unavailable
          },
        ),
      );
      await tester.pumpWidget(_host(a));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ELEVATION PROFILE'), findsNothing);
      expect(a.hasPaceSeries, isFalse);
      expect(a.hasElevationData, isFalse);
    });
  });
}
