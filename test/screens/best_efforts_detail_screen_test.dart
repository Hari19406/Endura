/// BestEffortsDetailScreen — tab bar renders every benchmark distance and
/// the screen degrades to an empty state when the DB has no rows for the
/// selected category (exercised here since sqflite isn't wired up under
/// flutter_test — DatabaseService's own try/catch makes that equivalent to
/// "no data yet", same as a fresh install).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/screens/best_efforts_detail_screen.dart';
import 'package:run_app/services/athlete_physiology.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/database_service.dart';

Widget _host({
  DistanceCategory initial = DistanceCategory.k5,
  Map<DistanceCategory, List<BestEffortRecord>> entriesByCategory = const {},
}) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: BestEffortsDetailScreen(
    initialCategory: initial,
    loadEntries: (category) async => entriesByCategory[category] ?? const [],
    loadRun: (id) async => null,
  ),
);

void main() {
  testWidgets('renders a tab for every benchmark distance', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final category in DistanceCategory.values) {
      expect(find.text(category.label), findsOneWidget);
    }
  });

  testWidgets('shows an empty state for the initial category when no efforts exist', (
    tester,
  ) async {
    await tester.pumpWidget(_host(initial: DistanceCategory.k5));
    await tester.pumpAndSettle();

    expect(find.textContaining('No efforts recorded yet for 5K'), findsOneWidget);
  });

  testWidgets('switching tabs updates the empty-state message to the new category', (
    tester,
  ) async {
    await tester.pumpWidget(_host(initial: DistanceCategory.k5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marathon'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No efforts recorded yet for Marathon'),
      findsOneWidget,
    );
  });

  testWidgets('renders a ranked leaderboard row and opens its run on tap', (
    tester,
  ) async {
    final fixtureRun = RunRecord(
      id: 42,
      distanceKm: 5.2,
      averagePace: '4:45',
      durationSeconds: 1500,
      date: DateTime(2026, 8, 1),
      routePolyline: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: BestEffortsDetailScreen(
          initialCategory: DistanceCategory.k5,
          loadEntries: (category) async => category == DistanceCategory.k5
              ? [
                  BestEffortRecord(
                    id: '42_k5',
                    runId: '42',
                    category: DistanceCategory.k5,
                    elapsedSeconds: 1500,
                    recordedAt: DateTime(2026, 8, 1),
                  ),
                ]
              : const [],
          loadRun: (id) async => id == 42 ? fixtureRun : null,
          loadMaxHr: () async => MaxHrResolution.fallback,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('25:00'), findsOneWidget); // formatted elapsed time
    expect(find.text('1'), findsOneWidget); // gold rank badge

    await tester.tap(find.text('25:00'));
    await tester.pumpAndSettle();

    // Navigated into ActivityDetailScreen for the fixture run.
    expect(find.text('25:00'), findsNothing);
  });
}
