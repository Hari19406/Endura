/// WorkoutStepTimeline — verifies a structured Quality workout renders its step
/// breakdown with VDOT-derived pace bands, phase labels and coaching cues.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/core/vdot_calculator.dart' show pacesFor;
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/widgets/workout_step_timeline.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

ResolvedBlock _block({
  required BlockType type,
  required double km,
  required (int, int) pace,
  int? reps,
  int? recoverySeconds,
  bool rpeOnly = false,
}) =>
    ResolvedBlock(
      type: type,
      distanceKm: km,
      paceMinSecondsPerKm: pace.$1,
      paceMaxSecondsPerKm: pace.$2,
      reps: reps,
      recoverySeconds: recoverySeconds,
      isRpeOnly: rpeOnly,
    );

/// A VO2-max interval session baked from [vdot]: warm-up, 5 × 1 km @ I-pace,
/// cool-down — the shape PlanMaterializer produces for a quality day.
ResolvedWorkout _vo2Workout(int vdot) {
  final p = pacesFor(vdot);
  return ResolvedWorkout(
    templateId: 'vo2_1000',
    name: '5 × 1 km',
    intent: WorkoutIntent.vo2max,
    phase: TrainingPhase.build,
    blocks: [
      _block(type: BlockType.warmup, km: 2.0, pace: p.ePaceSecPerKm),
      _block(
        type: BlockType.main,
        km: 1.0,
        pace: p.iPaceSecPerKm,
        reps: 5,
        recoverySeconds: 90,
      ),
      _block(type: BlockType.cooldown, km: 1.5, pace: p.ePaceSecPerKm),
    ],
  );
}

String _paceWindow((int, int) band) {
  String fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  final lo = (band.$1 / 5).round() * 5;
  final hi = (band.$2 / 5).round() * 5;
  return lo == hi ? '${fmt(lo)} /km' : '${fmt(lo)} – ${fmt(hi)} /km';
}

void main() {
  group('StepPaceBand.forBlock', () {
    test('threshold work → a T-pace window', () {
      final b = _block(
        type: BlockType.main,
        km: 2.0,
        pace: (350, 360),
        reps: 3,
      );
      final band = StepPaceBand.forBlock(b, WorkoutIntent.threshold);
      expect(band.zone, 'Threshold');
      expect(band.value, '5:50 – 6:00 /km');
      expect(band.effortOnly, isFalse);
    });

    test('VO2 work → an I-pace window', () {
      final band = StepPaceBand.forBlock(
        _block(type: BlockType.main, km: 1.0, pace: (248, 262), reps: 5),
        WorkoutIntent.vo2max,
      );
      expect(band.zone, 'VO2 / Interval');
      expect(band.value, '4:10 – 4:20 /km'); // 248→250, 262→260
      expect(band.effortOnly, isFalse);
    });

    test('easy warm-up → a ceiling, never a hard target', () {
      final band = StepPaceBand.forBlock(
        _block(type: BlockType.warmup, km: 2.0, pace: (372, 430)),
        WorkoutIntent.vo2max,
      );
      expect(band.zone, 'Easy');
      expect(band.value, '≤ 6:10 /km'); // 372 → 370
      expect(band.effortOnly, isFalse);
    });

    test('recovery jog is by feel', () {
      final band = StepPaceBand.forBlock(
        _block(type: BlockType.recovery, km: 0.4, pace: (400, 500)),
        WorkoutIntent.vo2max,
      );
      expect(band.effortOnly, isTrue);
      expect(band.value.toLowerCase(), contains('jog'));
    });

    test('RPE-only strides → "Fast & relaxed", no numbers', () {
      final band = StepPaceBand.forBlock(
        _block(
          type: BlockType.main,
          km: 0.1,
          pace: (0, 0),
          reps: 6,
          rpeOnly: true,
        ),
        WorkoutIntent.speed,
      );
      expect(band.zone, 'Strides');
      expect(band.value, 'Fast & relaxed strides');
      expect(band.effortOnly, isTrue);
    });

    test('effortBased plan → conversational cue instead of a pace window', () {
      final band = StepPaceBand.forBlock(
        _block(type: BlockType.main, km: 2.0, pace: (350, 360), reps: 3),
        WorkoutIntent.threshold,
        effortBased: true,
      );
      expect(band.effortOnly, isTrue);
      expect(band.value, isNot(contains('/km')));
    });
  });

  group('WorkoutStepTimeline widget', () {
    testWidgets('a Quality workout shows its steps with VDOT pace bands', (
      tester,
    ) async {
      const vdot = 50;
      await tester.pumpWidget(_wrap(
        WorkoutStepTimeline(workout: _vo2Workout(vdot)),
      ));

      expect(tester.takeException(), isNull);

      // Phase timeline
      expect(find.text('WARMUP'), findsOneWidget);
      expect(find.text('INTERVAL'), findsOneWidget);
      expect(find.text('COOLDOWN'), findsOneWidget);

      // Quantity for the rep block
      expect(find.text('5 × 1.0 km'), findsOneWidget);

      // Pace badge matches the plan's baked I-pace for this VDOT
      final iBand = pacesFor(vdot).iPaceSecPerKm;
      expect(
        find.textContaining('VO2 / Interval · ${_paceWindow(iBand)}'),
        findsOneWidget,
      );

      // Recovery + a coaching cue
      expect(find.textContaining('1:30 recovery'), findsOneWidget);
      expect(find.textContaining('Even splits'), findsOneWidget);
    });

    testWidgets('effortBased hides numeric targets', (tester) async {
      await tester.pumpWidget(_wrap(
        WorkoutStepTimeline(workout: _vo2Workout(45), effortBased: true),
      ));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('/km'), findsNothing);
      expect(find.textContaining('controlled'), findsWidgets);
    });

    testWidgets('empty workout degrades gracefully', (tester) async {
      await tester.pumpWidget(_wrap(
        const WorkoutStepTimeline(
          workout: ResolvedWorkout(
            templateId: 'rest',
            name: 'Rest',
            intent: WorkoutIntent.aerobicBase,
            phase: TrainingPhase.base,
            blocks: [],
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('rest day'), findsOneWidget);
    });
  });
}
