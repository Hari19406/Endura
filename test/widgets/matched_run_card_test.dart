import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/matched_run_comparison.dart';
import 'package:run_app/widgets/matched_run_card.dart';

MatchedRunSummary _run({
  int? id,
  DateTime? date,
  double km = 5.0,
  int seconds = 1500,
  int? pace = 300,
  Map<int, int> splits = const {},
  int? hr,
  int? gap,
}) => MatchedRunSummary(
  id: id,
  date: date ?? DateTime(2026, 9, 1),
  distanceKm: km,
  durationSeconds: seconds,
  paceSecPerKm: pace,
  splitSeconds: splits,
  avgHr: hr,
  gapSecPerKm: gap,
);

Widget _host(MatchedRunsResult? result, {bool miles = false}) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.dark]),
  home: Scaffold(
    body: SingleChildScrollView(
      child: MatchedRunCard(avgPace: '5:42', result: result, useMiles: miles),
    ),
  ),
);

final _today = _run(date: DateTime(2026, 10, 7), seconds: 1710, pace: 342);

void main() {
  testWidgets('hidden when there is no match', (t) async {
    await t.pumpWidget(_host(null));
    expect(find.byKey(const Key('matched-run-card')), findsNothing);
    await t.pumpWidget(_host(MatchedRunsResult.build(_today, const [])));
    expect(find.byKey(const Key('matched-run-card')), findsNothing);
  });

  testWidgets('shows the match count and today pace', (t) async {
    final result = MatchedRunsResult.build(_today, [
      _run(id: 1, date: DateTime(2026, 9, 1)),
      _run(id: 2, date: DateTime(2026, 9, 8)),
      _run(id: 3, date: DateTime(2026, 9, 15)),
    ]);
    await t.pumpWidget(_host(result));
    expect(find.text('MATCHED ROUTE'), findsOneWidget);
    expect(find.text('3 previous runs on this route'), findsOneWidget);
    expect(find.text('5:42/km'), findsOneWidget);
  });

  testWidgets('singular count wording', (t) async {
    final result = MatchedRunsResult.build(_today, [_run(id: 1)]);
    await t.pumpWidget(_host(result));
    expect(find.text('1 previous run on this route'), findsOneWidget);
  });

  testWidgets('says faster when today beat the previous run', (t) async {
    final result = MatchedRunsResult.build(_today, [
      _run(id: 1, seconds: 1758, pace: 351),
    ]);
    await t.pumpWidget(_host(result));
    expect(find.text('0:48 faster than your previous run'), findsOneWidget);
  });

  testWidgets('says slower when today was behind the previous run', (t) async {
    final result = MatchedRunsResult.build(_today, [
      _run(id: 1, seconds: 1680, pace: 336),
    ]);
    await t.pumpWidget(_host(result));
    expect(find.text('0:30 slower than your previous run'), findsOneWidget);
  });

  testWidgets('falls back to a pace headline when distances differ', (
    t,
  ) async {
    final result = MatchedRunsResult.build(_today, [
      _run(id: 1, km: 4.8, seconds: 1560, pace: 352),
    ]);
    await t.pumpWidget(_host(result));
    expect(
      find.text('0:10/km faster than your previous run'),
      findsOneWidget,
    );
  });

  testWidgets('HR and GAP rows are absent unless both runs have data', (
    t,
  ) async {
    final without = MatchedRunsResult.build(_today, [_run(id: 1, hr: 150)]);
    await t.pumpWidget(_host(without));
    expect(find.text('Avg HR'), findsNothing);
    expect(find.text('GAP'), findsNothing);

    final today = _run(
      date: DateTime(2026, 10, 7),
      seconds: 1710,
      pace: 342,
      hr: 148,
      gap: 335,
    );
    final both = MatchedRunsResult.build(today, [
      _run(id: 1, hr: 152, gap: 340),
    ]);
    await t.pumpWidget(_host(both));
    expect(find.text('Avg HR'), findsOneWidget);
    expect(find.text('GAP'), findsOneWidget);
  });

  testWidgets('per-km split chips render for shared kilometres', (t) async {
    final today = _run(date: DateTime(2026, 10, 7), splits: {1: 340, 2: 345});
    final result = MatchedRunsResult.build(today, [
      _run(id: 1, splits: {1: 350, 2: 340, 3: 300}),
    ]);
    await t.pumpWidget(_host(result));
    expect(find.byKey(const Key('matched-split-1')), findsOneWidget);
    expect(find.byKey(const Key('matched-split-2')), findsOneWidget);
    expect(find.byKey(const Key('matched-split-3')), findsNothing);
  });
}
