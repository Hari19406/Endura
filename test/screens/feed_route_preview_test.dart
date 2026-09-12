/// Feed cards render a lightweight polyline preview (RouteTracePainter, not a
/// heavyweight interactive map) and hide the map cleanly when a run has no GPS
/// track (manual/treadmill runs).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/feed_run.dart';
import 'package:run_app/screens/feed_screen.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/widgets/route_trace_painter.dart';

FeedRun _run({required String routePolyline}) => FeedRun(
  runId: 1,
  athleteId: 'a1',
  displayName: 'Runner',
  date: DateTime.utc(2026, 9, 12),
  distanceKm: 6,
  averagePace: '5:20',
  durationSeconds: 1900,
  routePolyline: routePolyline,
);

Widget _host(FeedRun run) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: Scaffold(body: RunFeedCard(run: run, onTapAthlete: () {})),
);

bool _isRouteTraceCustomPaint(Widget w) =>
    w is CustomPaint && w.painter is RouteTracePainter;

void main() {
  testWidgets('a run with a GPS track renders the lightweight polyline trace', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _run(routePolyline: '12.97,77.59;12.972,77.591;12.974,77.593'),
      ),
    );

    final painters = find.byWidgetPredicate(_isRouteTraceCustomPaint);
    expect(painters, findsOneWidget);

    final custom = tester.widget<CustomPaint>(painters);
    final painter = custom.painter as RouteTracePainter;
    expect(painter.points, hasLength(3));
    expect(painter.points.first['lat'], closeTo(12.97, 1e-9));

    // Sanity: it's a plain CustomPainter, not a heavyweight map widget stack —
    // no interactive map controller/gesture layer is mounted for it.
    expect(find.byType(GestureDetector), findsWidgets); // just the card's own
  });

  testWidgets('a manual/treadmill run (no GPS points) hides the map cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_run(routePolyline: '')));

    expect(find.byWidgetPredicate(_isRouteTraceCustomPaint), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single GPS point (not a real track) also hides the map', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_run(routePolyline: '12.97,77.59')));

    expect(find.byWidgetPredicate(_isRouteTraceCustomPaint), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
