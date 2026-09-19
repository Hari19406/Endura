/// Every share template lays out without overflow — including the barcode
/// (scaled to card width) and the brand footer — at the fixed 360x640 card
/// size and when the preview is shrunk into a small viewport.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/widgets/run_share_card.dart';

final _data = ShareRunData(
  distanceKm: 42.19,
  averagePace: '5:12',
  durationSeconds: 3 * 3600 + 42 * 60 + 10,
  date: DateTime(2026, 9, 20),
  workoutType: 'long',
  gpsPoints: const [
    {'lat': 18.52, 'lng': 73.85},
    {'lat': 18.53, 'lng': 73.86},
  ],
  useMiles: true,
);

void main() {
  for (final t in ShareCardTemplate.values) {
    testWidgets('${t.name} lays out without overflow in a small viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FittedBox(
                child: RunShareCard(data: _data, template: t),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
