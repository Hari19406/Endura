import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/screens/race_history_screen.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/observed_performance.dart';
import 'package:run_app/utils/race_history.dart';
import 'package:run_app/utils/split_strategy.dart';
import 'package:run_app/widgets/observed_performance_card.dart';
import 'package:run_app/widgets/split_strategy_card.dart';

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.dark]),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

SplitStrategyAnalysis _analysis(List<int> secs) => SplitStrategies.analyze([
  for (var i = 0; i < secs.length; i++) KmSplit(km: i + 1, paceSeconds: secs[i]),
])!;

final _now = DateTime(2026, 10, 7);

void main() {
  group('SplitStrategyCard', () {
    testWidgets('negative split with both halves and the difference', (t) async {
      await t.pumpWidget(
        _host(SplitStrategyCard(analysis: _analysis([282, 282, 275, 275]))),
      );
      expect(find.text('Negative Split'), findsOneWidget);
      expect(find.text('4:42/km'), findsOneWidget);
      expect(find.text('4:35/km'), findsOneWidget);
      expect(find.text('7 sec/km faster'), findsOneWidget);
      expect(find.byKey(const Key('split-strategy-fade')), findsNothing);
    });

    testWidgets('positive split with fade', (t) async {
      await t.pumpWidget(
        _host(SplitStrategyCard(analysis: _analysis([300, 300, 330, 330]))),
      );
      expect(find.text('Positive Split'), findsOneWidget);
      expect(find.text('30 sec/km slower'), findsOneWidget);
      expect(find.byKey(const Key('split-strategy-fade')), findsOneWidget);
    });

    testWidgets('converts to miles', (t) async {
      await t.pumpWidget(
        _host(
          SplitStrategyCard(
            analysis: _analysis([300, 300, 300, 300]),
            useMiles: true,
          ),
        ),
      );
      expect(find.text('Even Split'), findsOneWidget);
      expect(find.text('8:03/mi'), findsNWidgets(2));
    });
  });

  group('ObservedPerformanceCard', () {
    testWidgets('shows predictions beside actual bests, labelled observed', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          ObservedPerformanceCard(
            now: _now,
            loadEfforts: (_) async => [
              ObservedEffort(
                category: DistanceCategory.k5,
                seconds: 20 * 60 + 18,
                date: DateTime(2026, 9, 20),
              ),
            ],
            bests: const {DistanceCategory.k5: 1205},
            onRaceHistory: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('CURRENT PERFORMANCE'), findsOneWidget);
      expect(
        find.textContaining('Observed from your recent Best Efforts'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('observed-row-k5')), findsOneWidget);
      expect(find.byKey(const Key('observed-row-k10')), findsOneWidget);
      expect(find.byKey(const Key('observed-row-half')), findsNothing);
      expect(find.byKey(const Key('observed-row-marathon')), findsNothing);
      expect(find.text('20:18'), findsOneWidget);
      expect(find.text('Best 20:05'), findsOneWidget);
    });

    testWidgets('insufficient data shows an empty message, not predictions', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          ObservedPerformanceCard(
            now: _now,
            loadEfforts: (_) async => const [],
            onRaceHistory: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('observed-performance-empty')), findsOneWidget);
      expect(find.byKey(const Key('observed-row-k5')), findsNothing);
    });

    testWidgets('race history row is tappable', (t) async {
      var tapped = false;
      await t.pumpWidget(
        _host(
          ObservedPerformanceCard(
            now: _now,
            loadEfforts: (_) async => const [],
            onRaceHistory: () => tapped = true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('observed-performance-race-history')));
      expect(tapped, isTrue);
    });
  });

  group('RaceHistoryScreen', () {
    Widget screen(List<RaceRun> races) => MaterialApp(
      theme: ThemeData(extensions: const [AppColors.dark]),
      home: RaceHistoryScreen(loadRaces: () async => races, useMiles: false),
    );

    testWidgets('empty state when no race is marked', (t) async {
      await t.pumpWidget(screen(const []));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('race-history-empty')), findsOneWidget);
      expect(find.textContaining('mark it as a race'), findsOneWidget);
    });

    testWidgets('lists races by distance with the change vs the previous', (
      t,
    ) async {
      await t.pumpWidget(
        screen([
          RaceRun(
            id: 1,
            date: DateTime(2026, 3, 1),
            distanceKm: 5.0,
            durationSeconds: 1260,
          ),
          RaceRun(
            id: 2,
            date: DateTime(2026, 9, 1),
            distanceKm: 5.0,
            durationSeconds: 1218,
          ),
        ]),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('race-group-k5')), findsOneWidget);
      expect(find.byKey(const Key('race-group-k10')), findsNothing);
      expect(find.text('20:18'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text('−0:42'), findsOneWidget);
      expect(find.text('First race'), findsOneWidget);
      expect(find.byKey(const Key('race-history-empty')), findsNothing);
    });
  });
}
