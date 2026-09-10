/// PlanAdaptationCard — the inline coach banner. Verifies it renders the
/// explanation and that either button removes it from the tree (the screen
/// clears `_adaptationPrompt` on both accept and dismiss).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/plan_adaptation_service.dart' show MissedWindow;
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/widgets/plan_adaptation_card.dart';

/// Mirrors how HomeScreen mounts the card: it lives above the workout card
/// while a prompt exists, and both actions null the prompt.
class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _show = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(
        body: ListView(
          children: [
            if (_show)
              PlanAdaptationCard(
                explanation: 'You were out for 9 days — we rebuild rather than '
                    'resume.',
                window: MissedWindow.extended,
                onReviewAccept: () => setState(() => _show = false),
                onDismiss: () => setState(() => _show = false),
              ),
            const SizedBox(height: 8),
            const Text('TODAY’S WORKOUT'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('renders the coach explanation and both actions', (tester) async {
    await tester.pumpWidget(const _Harness());

    expect(find.textContaining('we rebuild rather than resume'), findsOneWidget);
    expect(find.text('Review & Accept'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('"Review & Accept" removes the banner', (tester) async {
    await tester.pumpWidget(const _Harness());
    expect(find.byType(PlanAdaptationCard), findsOneWidget);

    await tester.tap(find.text('Review & Accept'));
    await tester.pumpAndSettle();

    expect(find.byType(PlanAdaptationCard), findsNothing);
    expect(find.text('TODAY’S WORKOUT'), findsOneWidget);
  });

  testWidgets('"Dismiss" removes the banner', (tester) async {
    await tester.pumpWidget(const _Harness());
    expect(find.byType(PlanAdaptationCard), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.byType(PlanAdaptationCard), findsNothing);
  });

  testWidgets('busy disables both buttons and shows a spinner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: PlanAdaptationCard(
            explanation: 'Saving…',
            window: MissedWindow.moderate,
            busy: true,
            onReviewAccept: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final accept = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final dismiss = tester.widget<TextButton>(find.byType(TextButton));
    expect(accept.onPressed, isNull);
    expect(dismiss.onPressed, isNull);
  });
}
