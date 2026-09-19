/// Calibration pace for structured sessions: interval / cruise-interval runs
/// are judged on their work reps, not on an average diluted by recovery jogs;
/// continuous runs keep the whole-run pace. The refined pace reaches vDOT
/// calibration through EngineRuntime.processRun.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/memory/engine_memory_service.dart';
import 'package:run_app/engines/runtime/engine_runtime.dart';
import 'package:run_app/engines/runtime/work_pace_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A run as `(seconds, pace s/km)` phases, sampled every 15 s the way the run
/// screen records `{t, d}` track samples.
({List<Map<String, dynamic>> samples, double km, int seconds}) _run(
  List<(int, double)> phases,
) {
  final samples = <Map<String, dynamic>>[];
  var t = 0;
  var d = 0.0;
  for (final (secs, pace) in phases) {
    var left = secs;
    while (left > 0) {
      final step = left >= 15 ? 15 : left;
      t += step;
      d += step / pace * 1000;
      left -= step;
      samples.add({'t': t, 'd': d});
    }
  }
  return (samples: samples, km: d / 1000, seconds: t);
}

/// [reps] work reps of [workKm] at [workPace], each followed by a
/// [recoverySeconds] jog at [recoveryPace] (none after the last rep).
List<(int, double)> _intervalPhases({
  required int reps,
  required double workKm,
  required double workPace,
  required int recoverySeconds,
  required double recoveryPace,
}) => [
  for (var i = 0; i < reps; i++) ...[
    ((workKm * workPace).round(), workPace),
    if (i < reps - 1) (recoverySeconds, recoveryPace),
  ],
];

ResolvedBlock _main({
  double km = 1.0,
  int? reps,
  int? recoverySeconds,
  int min = 265,
  int max = 275,
  bool rpe = false,
}) => ResolvedBlock(
  type: BlockType.main,
  distanceKm: km,
  paceMinSecondsPerKm: min,
  paceMaxSecondsPerKm: max,
  reps: reps,
  recoverySeconds: recoverySeconds,
  isRpeOnly: rpe,
);

ResolvedBlock _block(BlockType type, {double km = 2}) => ResolvedBlock(
  type: type,
  distanceKm: km,
  paceMinSecondsPerKm: 330,
  paceMaxSecondsPerKm: 360,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('interval session', () {
    // 5 × 1 km @ 4:30 with 2:00 jogs @ 7:00.
    final run = _run(
      _intervalPhases(
        reps: 5,
        workKm: 1,
        workPace: 270,
        recoverySeconds: 120,
        recoveryPace: 420,
      ),
    );
    final blocks = [_main(reps: 5, recoverySeconds: 120)];

    test('recognised as a recovery-structured session', () {
      expect(WorkPaceCalculator.hasRecoveryStructure(blocks), isTrue);
      expect(WorkPaceCalculator.plannedWorkKm(blocks), 5.0);
    });

    test('work pace is ~4:30/km, not the diluted whole-run average', () {
      final overall = run.seconds / run.km;
      expect(overall, greaterThan(290), reason: 'jogs drag the average down');

      final pace = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: blocks,
        trackSamples: run.samples,
        distanceKm: run.km,
        durationSeconds: run.seconds,
      )!;
      expect(pace, closeTo(270, 2));
    });

    test('walking rests are excluded too', () {
      final walk = _run(
        _intervalPhases(
          reps: 5,
          workKm: 1,
          workPace: 270,
          recoverySeconds: 90,
          recoveryPace: 720, // 12:00/km walk
        ),
      );
      final pace = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: blocks,
        trackSamples: walk.samples,
        distanceKm: walk.km,
        durationSeconds: walk.seconds,
      )!;
      expect(pace, closeTo(270, 2));
    });

    test('a warm-up jog inside the sampled run is left out', () {
      final withWarmup = _run([
        (600, 390), // 10 min easy jog before the reps
        ..._intervalPhases(
          reps: 5,
          workKm: 1,
          workPace: 270,
          recoverySeconds: 120,
          recoveryPace: 420,
        ),
      ]);
      final pace = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: blocks,
        trackSamples: withWarmup.samples,
        distanceKm: withWarmup.km,
        durationSeconds: withWarmup.seconds,
      )!;
      expect(pace, closeTo(270, 2));
    });

    test('a GPS glitch segment is ignored', () {
      final glitched = [
        ...run.samples,
      ];
      // A 15 s stretch covering 400 m — 0:37/km, not humanly possible.
      final last = glitched.last;
      glitched.add({
        't': (last['t'] as int) + 15,
        'd': (last['d'] as double) + 400,
      });
      final pace = WorkPaceCalculator.fromTrackSamples(
        samples: glitched,
        workDistanceKm: 5,
      )!;
      expect(pace, closeTo(270, 2));
    });

    test('cruise intervals (3 × 1.6 km, 60 s jogs) use work pace as well', () {
      final cruise = _run(
        _intervalPhases(
          reps: 3,
          workKm: 1.6,
          workPace: 300,
          recoverySeconds: 60,
          recoveryPace: 390,
        ),
      );
      final pace = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: [_main(km: 1.6, reps: 3, recoverySeconds: 60, min: 295, max: 305)],
        trackSamples: cruise.samples,
        distanceKm: cruise.km,
        durationSeconds: cruise.seconds,
      )!;
      expect(pace, closeTo(300, 2));
    });

    test('explicit recovery blocks between main blocks also count', () {
      final ladder = [
        _main(km: 1),
        _block(BlockType.recovery, km: 0.4),
        _main(km: 1),
      ];
      expect(WorkPaceCalculator.hasRecoveryStructure(ladder), isTrue);
      expect(WorkPaceCalculator.plannedWorkKm(ladder), 2.0);
    });
  });

  group('falls back to the whole-run pace', () {
    final steady = _run([(2400, 330)]); // 40 min @ 5:30
    final overall = steady.seconds / steady.km;

    test('a continuous tempo block', () {
      final pace = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: [_main(km: 6, min: 315, max: 325)],
        trackSamples: steady.samples,
        distanceKm: steady.km,
        durationSeconds: steady.seconds,
      );
      expect(pace, closeTo(overall, 1e-9));
    });

    test('a steady easy run with warm-up / cool-down blocks', () {
      final pace = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: [
          _block(BlockType.warmup),
          _main(km: 6, min: 330, max: 360),
          _block(BlockType.cooldown),
        ],
        trackSamples: steady.samples,
        distanceKm: steady.km,
        durationSeconds: steady.seconds,
      );
      expect(pace, closeTo(overall, 1e-9));
    });

    test('a free run (no blocks)', () {
      expect(
        WorkPaceCalculator.actualPaceSecPerKm(
          blocks: null,
          trackSamples: steady.samples,
          distanceKm: steady.km,
          durationSeconds: steady.seconds,
        ),
        closeTo(overall, 1e-9),
      );
    });

    test('an interval session with no track samples', () {
      final pace = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: [_main(reps: 5, recoverySeconds: 120)],
        trackSamples: const [],
        distanceKm: 6.1,
        durationSeconds: 1830,
      );
      expect(pace, closeTo(1830 / 6.1, 1e-9));
    });

    test('an interval session whose samples cover under half the work', () {
      // 1.5 km sampled against 5 km of planned work.
      final short = _run([(400, 270)]);
      final pace = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: [_main(reps: 5, recoverySeconds: 120)],
        trackSamples: short.samples,
        distanceKm: 6.1,
        durationSeconds: 1830,
      );
      expect(pace, closeTo(1830 / 6.1, 1e-9));
    });

    test('an RPE-only session', () {
      final blocks = [_main(reps: 6, recoverySeconds: 90, rpe: true)];
      expect(WorkPaceCalculator.hasRecoveryStructure(blocks), isFalse);
    });

    test('no distance → no pace', () {
      expect(
        WorkPaceCalculator.actualPaceSecPerKm(
          blocks: null,
          trackSamples: const [],
          distanceKm: 0,
          durationSeconds: 100,
        ),
        isNull,
      );
    });
  });

  group('reaches vDOT calibration', () {
    // Plan expects 4:30 work pace (270 midpoint).
    Future<int> nudge({
      required double actual,
      required int rpe,
    }) async {
      SharedPreferences.setMockInitialValues({});
      await EngineRuntime.processRun(
        durationMinutes: 30,
        speed: 3.3,
        runDate: DateTime(2026, 9, 20, 7),
        workoutType: 'tempo',
        distanceKm: 6,
        rpe: rpe,
        completedIntent: WorkoutIntent.threshold,
        actualPaceSecondsPerKm: actual,
        expectedPaceSecondsPerKm: 270,
      );
      return (await EngineMemoryService().load()).pendingVdotNudge;
    }

    test('hitting the target with hard effort no longer reads as too slow', () async {
      final run = _run(
        _intervalPhases(
          reps: 5,
          workKm: 1,
          workPace: 270,
          recoverySeconds: 120,
          recoveryPace: 420,
        ),
      );
      final diluted = run.seconds / run.km;
      final work = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: [_main(reps: 5, recoverySeconds: 120)],
        trackSamples: run.samples,
        distanceKm: run.km,
        durationSeconds: run.seconds,
      )!;

      // Before: the blended pace is 28 s/km slow, at RPE 8 → false -1.
      expect(await nudge(actual: diluted, rpe: 8), -1);
      // After: right on target → no nudge.
      expect(await nudge(actual: work, rpe: 8), 0);
    });

    test('genuinely faster work reps bank +1 the average would have hidden', () async {
      final run = _run(
        _intervalPhases(
          reps: 5,
          workKm: 1,
          workPace: 255, // 4:15 — 15 s/km quicker than planned
          recoverySeconds: 120,
          recoveryPace: 420,
        ),
      );
      final diluted = run.seconds / run.km;
      final work = WorkPaceCalculator.actualPaceSecPerKm(
        blocks: [_main(reps: 5, recoverySeconds: 120)],
        trackSamples: run.samples,
        distanceKm: run.km,
        durationSeconds: run.seconds,
      )!;

      expect(await nudge(actual: diluted, rpe: 5), 0);
      expect(await nudge(actual: work, rpe: 5), 1);
    });
  });
}
