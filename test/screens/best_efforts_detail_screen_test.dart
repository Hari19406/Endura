/// BestEffortsDetailScreen — tab bar renders every benchmark distance and
/// the screen degrades to an empty state when the DB has no rows for the
/// selected category (exercised here since sqflite isn't wired up under
/// flutter_test — DatabaseService's own try/catch makes that equivalent to
/// "no data yet", same as a fresh install).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/screens/best_efforts_detail_screen.dart';
import 'package:run_app/services/athlete_physiology.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:run_app/widgets/ambient_scaffold.dart';
import 'package:run_app/widgets/best_effort_rank_badge.dart';

Widget _host({
  DistanceCategory initial = DistanceCategory.k5,
  Map<DistanceCategory, List<BestEffortRecord>> entriesByCategory = const {},
}) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: BestEffortsDetailScreen(
    initialCategory: initial,
    loadEntries: (category) async => entriesByCategory[category] ?? const [],
    loadRun: (id) async => null,
    loadRunBestEfforts: (_) async => const [],
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
          loadPaceZones: () async => null,
          loadRunBestEfforts: (_) async => const [],
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

  group('design system (Phase 2)', () {
    BestEffortRecord rec(String run, int seconds) => BestEffortRecord(
      id: '${run}_k5',
      runId: run,
      category: DistanceCategory.k5,
      elapsedSeconds: seconds,
      recordedAt: DateTime(2026, 8, int.parse(run)),
    );

    Widget hostWith(
      List<BestEffortRecord> entries, {
      Future<List<RunBestEffort>> Function(String runId)? loadRunBestEfforts,
      RunRecord? run,
    }) => MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: BestEffortsDetailScreen(
        initialCategory: DistanceCategory.k5,
        loadEntries: (c) async => c == DistanceCategory.k5 ? entries : const [],
        loadRun: (id) async => run,
        loadMaxHr: () async => MaxHrResolution.fallback,
        loadPaceZones: () async => null,
        loadRunBestEfforts: loadRunBestEfforts ?? (_) async => const [],
      ),
    );

    testWidgets('uses the shared AmbientScaffold with a transparent app bar', (
      tester,
    ) async {
      await tester.pumpWidget(hostWith([rec('1', 1500)]));
      await tester.pumpAndSettle();

      expect(find.byType(AmbientScaffold), findsOneWidget);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.transparent);
      expect(appBar.elevation, 0);
      final scaffold = tester.widget<AmbientScaffold>(
        find.byType(AmbientScaffold),
      );
      expect(scaffold.extendBodyBehindAppBar, isTrue);
    });

    testWidgets('the first row clears the transparent header', (tester) async {
      await tester.pumpWidget(hostWith([rec('1', 1500)]));
      await tester.pumpAndSettle();

      final tabBarBottom = tester.getBottomLeft(find.byType(TabBar)).dy;
      final firstRowTop = tester.getTopLeft(find.byType(BestEffortRankBadge)).dy;
      expect(firstRowTop, greaterThan(tabBarBottom));
    });

    testWidgets('leaderboard rows are 10px cards with the token surface and border', (
      tester,
    ) async {
      await tester.pumpWidget(hostWith([rec('1', 1500)]));
      await tester.pumpAndSettle();

      final decoration = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere(
            (d) =>
                d.color == AppColors.light.surface &&
                d.borderRadius == BorderRadius.circular(10),
          );
      expect(decoration.border, Border.all(color: AppColors.light.border));
    });

    testWidgets('ranks use the shared badge: medals for the top three', (
      tester,
    ) async {
      await tester.pumpWidget(
        hostWith([
          rec('1', 1450),
          rec('2', 1500),
          rec('3', 1550),
          rec('4', 1600),
        ]),
      );
      await tester.pumpAndSettle();

      final badges = tester
          .widgetList<BestEffortRankBadge>(find.byType(BestEffortRankBadge))
          .toList();
      expect(badges.map((b) => b.rank), [1, 2, 3, 4]);
      final colors = tester
          .widgetList<CircleAvatar>(find.byType(CircleAvatar))
          .map((a) => a.backgroundColor)
          .toList();
      expect({colors[0], colors[1], colors[2]}.length, 3);
      expect(colors[3], AppColors.light.background);
    });

    testWidgets('renders a ranked row for every effort the query returns', (
      tester,
    ) async {
      // A tall window so the lazily-built list lays out all ten rows.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        hostWith([for (var i = 1; i <= 10; i++) rec('$i', 1400 + i * 10)]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BestEffortRankBadge), findsNWidgets(10));
    });

    testWidgets('opening a run passes its efforts, ranks and best to Activity Detail', (
      tester,
    ) async {
      final run = RunRecord(
        id: 42,
        distanceKm: 5.2,
        averagePace: '4:45',
        durationSeconds: 1500,
        date: DateTime(2026, 8, 1),
        routePolyline: '',
      );
      String? askedFor;
      await tester.pumpWidget(
        hostWith(
          [
            BestEffortRecord(
              id: '42_k5',
              runId: '42',
              category: DistanceCategory.k5,
              elapsedSeconds: 1500,
              recordedAt: DateTime(2026, 8, 1),
            ),
          ],
          run: run,
          loadRunBestEfforts: (runId) async {
            askedFor = runId;
            return const [
              RunBestEffort(
                category: DistanceCategory.k5,
                elapsedSeconds: 1500,
                rank: 2,
                totalEfforts: 4,
                bestSeconds: 1458,
              ),
            ];
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('25:00'));
      await tester.pumpAndSettle();

      expect(askedFor, '42');
      expect(find.byType(ActivityDetailScreen), findsOneWidget);
      expect(find.text('BEST EFFORTS'), findsOneWidget);
      expect(find.text('2nd'), findsOneWidget);
      expect(find.text('Best 24:18 \u00b7 +0:42'), findsOneWidget);
    });
  });
}
