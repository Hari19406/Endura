/// Reactions ("cheers") are now real (activity_reactions), not a local-only
/// toggle: RunFeedCard optimistically flips state + count immediately, then
/// applies whatever the persistence call resolves to — rolling back on `null`
/// (failure). A `reactionToggler` test seam lets these tests control exactly
/// when that call resolves, so the optimistic frame is actually observable
/// (the real SocialService call, with no Supabase session, tends to fail
/// within the same microtask flush as a bare `pump()`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/feed_run.dart';
import 'package:run_app/screens/feed_screen.dart';
import 'package:run_app/theme/app_colors.dart';

FeedRun _run({bool viewerReacted = false, int reactionCount = 0}) => FeedRun(
  runId: 42,
  athleteId: 'a1',
  displayName: 'Runner',
  date: DateTime.utc(2026, 9, 12),
  distanceKm: 6,
  averagePace: '5:20',
  durationSeconds: 1900,
  viewerReacted: viewerReacted,
  reactionCount: reactionCount,
);

Widget _host(
  FeedRun run, {
  required Future<bool?> Function(int, {required bool currentlyReacted})
  toggler,
}) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: Scaffold(
    body: RunFeedCard(run: run, onTapAthlete: () {}, reactionToggler: toggler),
  ),
);

void main() {
  testWidgets(
    'tapping cheer optimistically increments before the network call resolves',
    (tester) async {
      final gate = Completer<bool?>();
      await tester.pumpWidget(
        _host(_run(), toggler: (_, {required currentlyReacted}) => gate.future),
      );

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.text('Be the first to react'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump(); // optimistic frame; the toggle call is still open

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('You reacted'), findsOneWidget);

      gate.complete(true); // persist succeeds
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('You reacted'), findsOneWidget);
    },
  );

  testWidgets('a failed persist rolls the optimistic reaction back', (
    tester,
  ) async {
    final gate = Completer<bool?>();
    await tester.pumpWidget(
      _host(_run(), toggler: (_, {required currentlyReacted}) => gate.future),
    );

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget); // still optimistic

    gate.complete(null); // persist failed
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.text('Be the first to react'), findsOneWidget);
    expect(
      find.textContaining("Couldn't update your reaction"),
      findsOneWidget,
    );
  });

  testWidgets('un-reacting optimistically decrements, then rolls back on failure', (
    tester,
  ) async {
    final gate = Completer<bool?>();
    await tester.pumpWidget(
      _host(
        _run(viewerReacted: true, reactionCount: 4),
        toggler: (_, {required currentlyReacted}) => gate.future,
      ),
    );

    expect(find.text('You + 3 reacted'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    expect(find.text('3 reacted'), findsOneWidget); // optimistic un-react

    gate.complete(null); // persist failed
    await tester.pumpAndSettle();

    // Rolled back to the original reacted state and count.
    expect(find.text('You + 3 reacted'), findsOneWidget);
  });

  testWidgets(
    'against the real SocialService (no Supabase session), the card still '
    'ends up correctly rolled back with an error snackbar',
    (tester) async {
      // No `reactionToggler` override — exercises the real production path.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: Scaffold(body: RunFeedCard(run: _run(), onTapAthlete: () {})),
        ),
      );

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(
        find.textContaining("Couldn't update your reaction"),
        findsOneWidget,
      );
    },
  );
}
