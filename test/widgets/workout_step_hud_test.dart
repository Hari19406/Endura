/// WorkoutStepHud — the in-run interval HUD. Verifies step labelling, the
/// pace-verdict colour logic, and manual "Next Step" advance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/unit_utils.dart';
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

/// Mirrors run_screen.dart's own `UnitUtils.useMilesNotifier` listener: reads
/// the live preference and rebuilds the HUD, exactly as the real active-run
/// screen does while a run is in progress.
class _LiveUnitHud extends StatefulWidget {
  final int stepIndex;
  final List<ResolvedBlock> blocks;
  final int? rollingPaceSecPerKm;
  const _LiveUnitHud({
    required this.stepIndex,
    required this.blocks,
    required this.rollingPaceSecPerKm,
  });

  @override
  State<_LiveUnitHud> createState() => _LiveUnitHudState();
}

class _LiveUnitHudState extends State<_LiveUnitHud> {
  late bool _useMiles = UnitUtils.useMilesNotifier.value;

  @override
  void initState() {
    super.initState();
    UnitUtils.useMilesNotifier.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() => _useMiles = UnitUtils.useMilesNotifier.value);
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkoutStepHud(
    stepIndex: widget.stepIndex,
    blocks: widget.blocks,
    rollingPaceSecPerKm: widget.rollingPaceSecPerKm,
    onNextStep: () {},
    useMiles: _useMiles,
  );
}

void main() {
  tearDown(() => UnitUtils.useMilesNotifier.value = false);

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

  group('unit-preference conversion', () {
    // 1 km work rep, target 4:00–4:10/km, rolling pace 240 s/km (4:00/km).
    const workBlock = ResolvedBlock(
      type: BlockType.main,
      distanceKm: 1,
      paceMinSecondsPerKm: 240,
      paceMaxSecondsPerKm: 250,
      label: '1 km rep',
    );

    testWidgets('miles mode converts both the target window and rolling pace', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          WorkoutStepHud(
            stepIndex: 0,
            blocks: const [workBlock],
            rollingPaceSecPerKm: 245, // inside the window, not on a boundary
            onNextStep: () {},
            useMiles: true,
          ),
        ),
      );

      // Target: 240/250 s/km × 1.609344 ≈ 386/402 s/mi = 6:26–6:42/mi.
      expect(find.textContaining('Target 6:26–6:42/mi'), findsOneWidget);
      // Rolling: 245 s/km × 1.609344 ≈ 394 s/mi = 6:34.
      expect(find.textContaining('6:34'), findsOneWidget);
      expect(find.textContaining('/mi'), findsWidgets);
      expect(find.textContaining('/km'), findsNothing);
      // 1 km rep, displayed in miles: 1 × 0.621371 ≈ 0.6 mi.
      expect(find.textContaining('0.6 mi'), findsOneWidget);
    });

    testWidgets(
      'the pace-verdict comparison itself never changes with the display '
      'unit — only the label text does',
      (tester) async {
        // Rolling pace exactly on the (canonical km) target → "On target" in
        // both unit modes, even though the printed numbers differ.
        for (final useMiles in [false, true]) {
          await tester.pumpWidget(
            _host(
              WorkoutStepHud(
                stepIndex: 0,
                blocks: const [workBlock],
                rollingPaceSecPerKm: 245,
                onNextStep: () {},
                useMiles: useMiles,
              ),
            ),
          );
          expect(find.textContaining('On target'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'flipping the live unit preference mid-run updates the HUD '
      'immediately, with no rebuild/refresh needed from the caller',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const _LiveUnitHud(
              stepIndex: 0,
              blocks: [workBlock],
              rollingPaceSecPerKm: 245, // inside the window, not on a boundary
            ),
          ),
        );

        // Starts in km (the app default).
        expect(find.textContaining('/km'), findsWidgets);
        expect(find.textContaining('/mi'), findsNothing);
        expect(find.textContaining('4:05'), findsOneWidget); // 245s → 4:05

        // The runner flips Settings → Miles mid-run.
        UnitUtils.useMilesNotifier.value = true;
        await tester.pump();

        expect(find.textContaining('/mi'), findsWidgets);
        expect(find.textContaining('/km'), findsNothing);
        expect(find.textContaining('6:34'), findsOneWidget); // 245s/km → 6:34/mi

        // And back to km.
        UnitUtils.useMilesNotifier.value = false;
        await tester.pump();

        expect(find.textContaining('/km'), findsWidgets);
        expect(find.textContaining('4:05'), findsOneWidget);
      },
    );
  });
}
