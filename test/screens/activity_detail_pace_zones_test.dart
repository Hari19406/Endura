/// The Pace Zones card on ActivityDetailScreen, and the fromRunRecord wiring
/// that feeds it from `TelemetrySample.paceSeconds`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:run_app/utils/pace_analytics.dart';
import 'package:run_app/utils/unit_utils.dart';

final _config = PaceZoneConfig(cutoffsSecPerKm: [420, 360, 330, 300], vdot: 42);

Map<String, dynamic> _s(num t, num d, num? pace) => {
  't': t,
  'd': d,
  'pace': pace,
};

RunRecord _run(List<Map<String, dynamic>> samples) => RunRecord(
  date: DateTime(2026, 9, 20, 7),
  distanceKm: 1.0,
  averagePace: '6:00',
  durationSeconds: 360,
  routePolyline: '',
  workoutType: 'easy',
  trackSamples: samples,
);

// 60 s easy (7:30), 60 s marathon-zone (6:30), 30 s threshold, last borrows.
final _samples = [
  _s(0, 0, 450),
  _s(20, 44, 450),
  _s(40, 89, 450),
  _s(60, 134, 390),
  _s(90, 215, 390),
  _s(120, 296, 345),
  _s(150, 390, 345),
];

Widget _host(ActivityDetail a) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: ActivityDetailScreen(activity: a),
);

ActivityDetail _detail({PaceZoneConfig? config}) =>
    ActivityDetail.fromRunRecord(
      _run(_samples),
      runnerName: 'x',
      paceZoneConfig: config,
    );

void main() {
  tearDown(() => UnitUtils.useMilesNotifier.value = false);

  group('ActivityDetail.fromRunRecord wiring', () {
    test('builds zones from sample pace and timestamps', () {
      final a = _detail(config: _config);
      expect(a.paceZones, hasLength(5));
      expect(a.paceZonesVdot, 42);
      expect(a.paceZones[0].durationSeconds, 60); // 450 for 3 intervals of 20 s
      expect(a.paceZones[1].durationSeconds, 60); // 390 for 20 s + 30 s + ...
    });

    test('no zone config: no pace zones', () {
      final a = _detail();
      expect(a.paceZones, isEmpty);
      expect(a.paceZonesVdot, isNull);
    });

    test('a run with no pace samples has no pace zones', () {
      final a = ActivityDetail.fromRunRecord(
        _run([_s(0, 0, null), _s(15, 40, null)]),
        runnerName: 'x',
        paceZoneConfig: _config,
      );
      expect(a.paceZones, isEmpty);
    });

    test('an old run with no timestamps still gets zones', () {
      final a = ActivityDetail.fromRunRecord(
        _run([
          {'d': 0, 'pace': 450},
          {'d': 50, 'pace': 390},
        ]),
        runnerName: 'x',
        paceZoneConfig: _config,
      );
      expect(a.paceZones, isNotEmpty);
      expect(a.paceZones[0].durationSeconds, 15);
      expect(a.paceZones[1].durationSeconds, 15);
    });
  });

  group('Pace Zones card', () {
    testWidgets('shows five zones with ranges, time and percentage', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_detail(config: _config)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PACE ZONES'), findsOneWidget);
      expect(find.textContaining('from vDOT 42'), findsOneWidget);
      for (final label in [
        'Easy',
        'Marathon',
        'Threshold',
        'Interval',
        'Repetition',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 200);
        expect(find.text(label), findsOneWidget);
      }
      for (final z in ['Z1', 'Z2', 'Z3', 'Z4', 'Z5']) {
        expect(find.text(z), findsWidgets);
      }
      // Open ends and a closed range, in min/km.
      expect(find.text('7:00+'), findsOneWidget);
      expect(find.text('6:00–7:00'), findsOneWidget);
      expect(find.text('<5:00'), findsOneWidget);
    });

    testWidgets('ranges convert to min/mile when miles are selected', (
      tester,
    ) async {
      UnitUtils.useMilesNotifier.value = true;
      await tester.pumpWidget(_host(_detail(config: _config)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Easy'), 200);

      // 420 s/km * 1.609344 = 676 s/mi -> 11:16.
      expect(find.text('11:16+'), findsOneWidget);
      expect(find.textContaining('/mi'), findsWidgets);
    });

    testWidgets('is hidden when the run has no pace zones', (tester) async {
      await tester.pumpWidget(_host(_detail()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PACE ZONES'), findsNothing);
    });
  });
}
