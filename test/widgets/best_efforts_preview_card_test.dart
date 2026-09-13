import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:run_app/widgets/best_efforts_preview_card.dart';

Widget _host(
  Map<DistanceCategory, BestEffortRecord> bestEfforts, {
  void Function(DistanceCategory)? onCategoryTap,
  VoidCallback? onSeeAll,
}) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: Scaffold(
    body: BestEffortsPreviewCard(
      bestEfforts: bestEfforts,
      onCategoryTap: onCategoryTap ?? (_) {},
      onSeeAll: onSeeAll ?? () {},
      formatDate: (d) => '${d.day}/${d.month}',
    ),
  ),
);

BestEffortRecord _record(DistanceCategory category, int seconds) =>
    BestEffortRecord(
      id: 'r_${category.name}',
      runId: '1',
      category: category,
      elapsedSeconds: seconds,
      recordedAt: DateTime(2026, 9, 1),
    );

void main() {
  testWidgets('shows placeholders for categories with no recorded effort', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('--:--'), findsNWidgets(4)); // k1, mi1, k5, k10 preview
    expect(find.text('BEST EFFORTS'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('renders a formatted time for categories with a PR', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host({
        DistanceCategory.k5: _record(DistanceCategory.k5, 1425), // 23:45
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('23:45'), findsOneWidget);
    // The other 3 preview slots remain unset.
    expect(find.text('--:--'), findsNWidgets(3));
  });

  testWidgets('tapping a category tile calls onCategoryTap with it', (
    tester,
  ) async {
    DistanceCategory? tapped;
    await tester.pumpWidget(
      _host(
        {DistanceCategory.k1: _record(DistanceCategory.k1, 240)},
        onCategoryTap: (c) => tapped = c,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('4:00')); // the k1 tile's formatted time
    await tester.pump();

    expect(tapped, DistanceCategory.k1);
  });

  testWidgets('tapping "See all" invokes onSeeAll', (tester) async {
    var seeAllTapped = false;
    await tester.pumpWidget(
      _host(const {}, onSeeAll: () => seeAllTapped = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('See all'));
    await tester.pump();

    expect(seeAllTapped, isTrue);
  });
}
