import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/onboarding/onboarding_pages.dart';
import 'package:run_app/onboarding/volume_guidance.dart';

void main() {
  test('half and full marathons never recommend fewer than 4 days', () {
    for (final goal in const ['half_marathon', 'marathon']) {
      for (final base in const [0.0, 15.0, 30.0, 50.0]) {
        final g = VolumeGuidance.resolve(
          goal: goal,
          experienceBridged: 'intermediate',
          baselineWeeklyKm: base,
          selectedRuns: 4,
        );
        expect(
          g.recommendedRuns,
          greaterThanOrEqualTo(g.maxRuns < 4 ? g.maxRuns : 4),
          reason: '$goal base=$base -> ${g.recommendedRuns}',
        );
      }
    }
  });

  test('feedback follows the selection relative to the recommendation', () {
    String f(int sel) => OPageRunsPerWeek.feedbackFor(
      selected: sel,
      recommended: 4,
      goal: '10k',
    );
    expect(f(4), OPageRunsPerWeek.rationaleFor('10k', 4));
    expect(f(3), contains('each run gets longer'));
    expect(f(5), contains('less recovery'));
  });

  testWidgets('hero shows the recommendation and the picker selects a day', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OPageRunsPerWeek(
            runsPerWeek: 4,
            baselineWeeklyKm: 20,
            goal: '10k',
            experienceBridged: 'intermediate',
            onChanged: (n) => picked = n,
          ),
        ),
      ),
    );
    expect(find.text('RECOMMENDED'), findsOneWidget);
    expect(find.textContaining('days per week'), findsWidgets);
    await tester.tap(find.text('3').first);
    expect(picked, 3);
  });
}
