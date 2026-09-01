import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:run_app/screens/history_tab.dart';
import 'package:run_app/theme/app_theme.dart';
import 'package:run_app/utils/database_service.dart';

RunRecord _run({
  required int id,
  required double km,
  required DateTime date,
  required String type,
  int? rpe,
  double elevation = 0,
  String polyline = '',
}) => RunRecord(
  id: id,
  distanceKm: km,
  averagePace: '5:00',
  durationSeconds: (km * 300).round(),
  date: date,
  routePolyline: polyline,
  workoutType: type,
  rpe: rpe,
  elevationGain: elevation,
);

/// Ordered `date DESC`, matching what `getAllRuns()` hands the tab.
final _records = <RunRecord>[
  _run(id: 1, km: 10, date: DateTime(2026, 9, 1), type: 'easy'),
  _run(
    id: 2,
    km: 8,
    date: DateTime(2026, 8, 20),
    type: 'tempo',
    rpe: 7,
    elevation: 120,
    polyline: '12.97,77.59;12.98,77.60;12.99,77.61',
  ),
  _run(id: 3, km: 20, date: DateTime(2026, 8, 10), type: 'long'),
  _run(id: 4, km: 6, date: DateTime(2026, 7, 15), type: 'tempo'),
];

Future<void> _pump(
  WidgetTester tester, {
  List<RunRecord>? records,
  void Function(RunRecord)? onOpenRun,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: HistoryTab(
          records: records ?? _records,
          onRefresh: () async {},
          onOpenRun: onOpenRun ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('HistoryTab summary header', () {
    testWidgets('shows lifetime totals across every run', (tester) async {
      await _pump(tester);

      expect(find.text('LIFETIME'), findsOneWidget);
      // 10 + 8 + 20 + 6 = 44.0 km
      expect(find.text('44.0'), findsOneWidget);
      expect(find.textContaining('4 runs'), findsWidgets);
    });

    testWidgets('recomputes against the active filter', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Tempo'));
      await tester.pumpAndSettle();

      expect(find.text('TEMPOS'), findsOneWidget);
      expect(find.text('LIFETIME'), findsNothing);
      // Only the two tempo runs: 8 + 6 = 14.0 km
      expect(find.text('14.0'), findsOneWidget);
    });
  });

  group('HistoryTab grouping and filtering', () {
    testWidgets('groups runs under month headers', (tester) async {
      await _pump(tester);

      expect(find.text('SEPTEMBER 2026'), findsOneWidget);
      expect(find.text('AUGUST 2026'), findsOneWidget);
      expect(find.text('JULY 2026'), findsOneWidget);
    });

    testWidgets('filtering drops non-matching runs and their months', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.text('Tempo'));
      await tester.pumpAndSettle();

      // September held only the easy run, so its header goes away entirely.
      expect(find.text('SEPTEMBER 2026'), findsNothing);
      expect(find.text('AUGUST 2026'), findsOneWidget);
      expect(find.text('JULY 2026'), findsOneWidget);
      expect(find.text('TEMPO'), findsNWidgets(2));
      expect(find.text('EASY RUN'), findsNothing);
    });

    testWidgets('offers a way out of an empty filtered state', (tester) async {
      await _pump(
        tester,
        records: [_run(id: 1, km: 10, date: DateTime(2026, 9, 1), type: 'easy')],
      );

      await tester.tap(find.text('Intervals'));
      await tester.pumpAndSettle();

      expect(find.text('No intervals yet'), findsOneWidget);
      expect(find.text('Clear filter'), findsOneWidget);

      await tester.tap(find.text('Clear filter'));
      await tester.pumpAndSettle();

      expect(find.text('LIFETIME'), findsOneWidget);
      expect(find.text('EASY RUN'), findsOneWidget);
    });
  });

  group('HistoryTab card routing', () {
    // Guards the regression the old implementation was open to: the History
    // tab used to pair `_runRecords[i]` with `_runHistory[i]` positionally,
    // which silently mismatched once the list was grouped or filtered.
    testWidgets('opens the run whose card was tapped, while filtered', (
      tester,
    ) async {
      RunRecord? opened;
      await _pump(tester, onOpenRun: (r) => opened = r);

      await tester.tap(find.text('Tempo'));
      await tester.pumpAndSettle();

      // Second tempo card in the filtered list — id 4, not id 2.
      await tester.tap(find.text('6.0 km'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.id, 4);
      expect(opened!.workoutType, 'tempo');
      expect(opened!.date, DateTime(2026, 7, 15));
    });

    testWidgets('opens the correct run from an unfiltered list', (
      tester,
    ) async {
      RunRecord? opened;
      await _pump(tester, onOpenRun: (r) => opened = r);

      await tester.tap(find.text('20.0 km'));
      await tester.pumpAndSettle();

      expect(opened?.id, 3);
      expect(opened?.workoutType, 'long');
    });
  });

  group('HistoryTab empty history', () {
    testWidgets('shows the no-runs state and no filter chrome', (tester) async {
      await _pump(tester, records: const []);

      expect(find.text('No runs yet'), findsOneWidget);
      expect(find.text('Your first run will show here'), findsOneWidget);
      expect(find.text('LIFETIME'), findsNothing);
      expect(find.text('Tempo'), findsNothing);
    });
  });
}
