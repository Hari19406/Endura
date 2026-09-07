// Widget tests for the comments sheet + its entry point on RunFeedCard.
//
// SocialService talks to the Supabase singleton, which isn't initialised in a
// plain widget test — fetchComments/postComment catch that and return
// empty/null, so these tests deterministically exercise the empty state and the
// optimistic-insert-then-rollback path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:run_app/models/feed_run.dart';
import 'package:run_app/screens/feed_screen.dart';
import 'package:run_app/theme/app_theme.dart';
import 'package:run_app/widgets/run_comments_sheet.dart';

FeedRun _feedRun({int commentCount = 0}) => FeedRun(
  runId: 42,
  athleteId: 'user-b',
  displayName: 'Bee Runner',
  date: DateTime.utc(2026, 9, 1, 7),
  distanceKm: 4.85,
  averagePace: '5:15',
  durationSeconds: 1528,
  elevationGain: 11,
  workoutType: 'easy',
  commentCount: commentCount,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('sheet shows the empty state, header and composer', (
    tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showRunCommentsSheet(context, runId: 42),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Comments'), findsOneWidget);
    expect(
      find.text('No comments yet.\nBe the first to leave one!'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
  });

  testWidgets('send with a failed post rolls back and keeps the draft', (
    tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showRunCommentsSheet(context, runId: 42),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Nice pace!');
    await tester.tap(find.byIcon(Icons.send_rounded));

    // post fails (no Supabase) → rollback + snackbar + draft restored.
    // Explicit pumps rather than pumpAndSettle (SnackBar auto-dismiss timer).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text("Couldn't post your comment."), findsOneWidget);
    // The composer keeps the text so the user can retry.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Nice pace!',
    );
    // No persisted comment tile — still the empty state.
    expect(
      find.text('No comments yet.\nBe the first to leave one!'),
      findsOneWidget,
    );
  });

  testWidgets('RunFeedCard comment button opens the sheet', (tester) async {
    await _pump(
      tester,
      ListView(
        children: [
          RunFeedCard(run: _feedRun(commentCount: 2), onTapAthlete: () {}),
        ],
      ),
    );

    // The card renders the "2" badge over the comment icon.
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Comments'), findsOneWidget);
  });
}
