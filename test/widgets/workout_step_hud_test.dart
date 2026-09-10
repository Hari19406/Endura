/// WorkoutStepHud — the in-run interval HUD. Verifies step labelling, the
/// pace-verdict colour logic, and manual "Next Step" advance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/widgets/workout_step_hud.dart';

const _blocks = <ResolvedBlock>[
  ResolvedBlock(
    type: BlockType.warmup,
    distanceKm: 2,
    paceMinSecondsPerKm: 330,
    paceMaxSecondsPerKm: 360,
  ),
  ResolvedBlock(
    type: BlockType.main,
    distanceKm: 1,
    paceMinSecondsPerKm: 240,
    paceMaxSecondsPerKm: 250,
    reps: 4,
    label: '1 km rep',
  ),
  ResolvedBlock(
    type: BlockType.cooldown,
    distanceKm: 1.5,
    paceMinSecondsPerKm: 330,
    paceMaxSecondsPerKm: 360,
  ),
];

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: Scaffold(body: child),
);

void main() {
  group('stepPaceVerdict', () {
    const work = ResolvedBlock(
      type: BlockType.main,
      distanceKm: 1,
      paceMinSecondsPerKm: 240,
      paceMaxSecondsPerKm: 250,
    );

    test('inside the window', () {
      expect(stepPaceVerdict(work, 245), StepPaceVerdict.inside);
    });
    test('a little faster than the window → surging', () {
      expect(stepPaceVerdict(work, 232), StepPaceVerdict.surging);
    });
    test('a little slower than the window → easing', () {
      expect(stepPaceVerdict(work, 262), StepPaceVerdict.easing);
    });
    test('well off the window → off', () {
      expect(stepPaceVerdict(work, 300), StepPaceVerdict.off);
      expect(stepPaceVerdict(work, 200), StepPaceVerdict.off);
    });
    test('no reading / RPE-only → none', () {
      expect(stepPaceVerdict(work, null), StepPaceVerdict.none);
      expect(stepPaceVerdict(work, 0), StepPaceVerdict.none);
      const rpe = ResolvedBlock(
        type: BlockType.main,
        distanceKm: 1,
        paceMinSecondsPerKm: 0,
        paceMaxSecondsPerKm: 0,
        isRpeOnly: true,
      );
      expect(stepPaceVerdict(rpe, 245), StepPaceVerdict.none);
    });
  });

  testWidgets('initialises on the first step with its target and pace', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        WorkoutStepHud(
          stepIndex: 0,
          blocks: _blocks,
          rollingPaceSecPerKm: 345,
          onNextStep: () {},
        ),
      ),
    );

    expect(find.textContaining('Step 1 of 3'), findsOneWidget);
    expect(find.textContaining('Warm-up'), findsOneWidget);
    expect(find.textContaining('Target 5:30–6:00/km'), findsOneWidget);
    expect(find.text('Next Step'), findsOneWidget);
    expect(find.textContaining('On target'), findsOneWidget); // 345 ∈ [330,360]
  });

  testWidgets('"Next Step" fires the callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        WorkoutStepHud(
          stepIndex: 0,
          blocks: _blocks,
          rollingPaceSecPerKm: null,
          onNextStep: () => taps++,
        ),
      ),
    );
    await tester.tap(find.text('Next Step'));
    expect(taps, 1);
  });

  testWidgets('the last step hides "Next Step"', (tester) async {
    await tester.pumpWidget(
      _host(
        WorkoutStepHud(
          stepIndex: 2,
          blocks: _blocks,
          rollingPaceSecPerKm: 340,
          onNextStep: () {},
        ),
      ),
    );
    expect(find.textContaining('Step 3 of 3'), findsOneWidget);
    expect(find.text('Next Step'), findsNothing);
  });
}
