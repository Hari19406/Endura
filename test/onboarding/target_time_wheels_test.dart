import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_pages.dart';

(int, int, int) _wheels(WidgetTester tester) {
  final c = tester
      .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
      .map((p) => p.scrollController! as FixedExtentScrollController)
      .toList();
  expect(c.length, 3);
  return (c[0].selectedItem, c[1].selectedItem, c[2].selectedItem);
}

void main() {
  testWidgets('target-time wheels follow an external value change without '
      'reporting it as an edit', (tester) async {
    int? seconds = 1800; // 0:30:00
    final edits = <int>[];
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return OPageTargetTime(
                mode: TargetTimeMode.finish,
                goal: 'marathon',
                seconds: seconds,
                onChanged: edits.add,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_wheels(tester), (0, 30, 0));

    // e.g. the goal flips from "target finish" to "time to beat".
    update(() => seconds = 4 * 3600 + 45 * 60);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_wheels(tester), (4, 45, 0));
    expect(edits, isEmpty, reason: 'a programmatic jump is not a user edit');

    // A real scroll still reports.
    await tester.drag(find.byType(CupertinoPicker).at(1), const Offset(0, -88));
    await tester.pump(const Duration(milliseconds: 500));
    expect(edits, isNotEmpty);
  });
}
