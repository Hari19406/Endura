import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/core/vdot_calculator.dart';
import 'package:run_app/engines/memory/engine_memory.dart';
import 'package:run_app/engines/memory/engine_memory_service.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/utils/observed_performance.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 7);

ObservedEffort _e(DistanceCategory c, int seconds, {int daysAgo = 10}) =>
    ObservedEffort(
      category: c,
      seconds: seconds,
      date: _now.subtract(Duration(days: daysAgo)),
    );

void main() {
  group('Best Effort -> observed VDOT', () {
    test('uses the existing Daniels maths', () {
      final e = _e(DistanceCategory.k5, 20 * 60 + 18);
      expect(
        e.vdot,
        vdotRawFromPerformance(timeSeconds: 1218, distanceKm: 5),
      );
      expect(e.vdot, closeTo(48.6, 0.5));
    });

    test('observedVdot is the best usable effort', () {
      final v = ObservedPerformance.observedVdot([
        _e(DistanceCategory.k5, 20 * 60 + 18),
        _e(DistanceCategory.k10, 50 * 60), // slower fitness
      ], now: _now);
      expect(v, _e(DistanceCategory.k5, 20 * 60 + 18).vdot);
    });

    test('efforts under 3K and older than a year are ignored', () {
      expect(
        ObservedPerformance.observedVdot([
          _e(DistanceCategory.k1, 200),
          _e(DistanceCategory.m400, 80),
          _e(DistanceCategory.mi1, 360),
          _e(DistanceCategory.k5, 1200, daysAgo: 400),
        ], now: _now),
        isNull,
      );
    });
  });

  group('observed VDOT -> predicted race times', () {
    test('a 5K effort predicts 5K (itself), 10K and nothing longer', () {
      final preds = ObservedPerformance.predict([
        _e(DistanceCategory.k5, 20 * 60 + 18),
      ], now: _now);
      expect(preds.map((p) => p.category), [
        DistanceCategory.k5,
        DistanceCategory.k10,
      ]);
      // The 5K prediction is the effort itself (inverse of the same maths).
      expect(preds.first.predictedSeconds, closeTo(1218, 1));
      // A 20:18 5K is roughly a 42:xx 10K on Daniels' equivalence.
      expect(preds[1].predictedSeconds, inInclusiveRange(41 * 60, 44 * 60));
      expect(preds[1].basedOn.category, DistanceCategory.k5);
    });

    test('a 10K effort supports 5K, 10K and half but not the marathon', () {
      final preds = ObservedPerformance.predict([
        _e(DistanceCategory.k10, 42 * 60 + 30),
      ], now: _now);
      expect(preds.map((p) => p.category), [
        DistanceCategory.k5,
        DistanceCategory.k10,
        DistanceCategory.half,
      ]);
      expect(preds[1].predictedSeconds, closeTo(42 * 60 + 30, 1));
      expect(
        preds[2].predictedSeconds,
        inInclusiveRange(93 * 60, 97 * 60),
      ); // ~1:34-1:35 half
    });

    test('a half marathon effort supports the marathon', () {
      final preds = ObservedPerformance.predict([
        _e(DistanceCategory.half, 95 * 60),
      ], now: _now);
      expect(
        preds.map((p) => p.category),
        contains(DistanceCategory.marathon),
      );
    });

    test('the highest-VDOT supporting effort wins per distance', () {
      final fast = _e(DistanceCategory.k5, 19 * 60);
      final slow = _e(DistanceCategory.k10, 45 * 60);
      final preds = ObservedPerformance.predict([slow, fast], now: _now);
      final tenK = preds.firstWhere((p) => p.category == DistanceCategory.k10);
      expect(tenK.basedOn.category, DistanceCategory.k5);
    });

    test('predictions are deterministic', () {
      final efforts = [_e(DistanceCategory.k5, 1200)];
      expect(
        ObservedPerformance.predict(efforts, now: _now)
            .map((p) => p.predictedSeconds)
            .toList(),
        ObservedPerformance.predict(efforts, now: _now)
            .map((p) => p.predictedSeconds)
            .toList(),
      );
    });
  });

  group('insufficient Best Effort data', () {
    test('no efforts -> no predictions', () {
      expect(ObservedPerformance.predict(const [], now: _now), isEmpty);
    });

    test('only short efforts -> no predictions', () {
      expect(
        ObservedPerformance.predict([
          _e(DistanceCategory.m400, 80),
          _e(DistanceCategory.k1, 220),
          _e(DistanceCategory.mi1, 360),
        ], now: _now),
        isEmpty,
      );
    });

    test('only stale efforts -> no predictions', () {
      expect(
        ObservedPerformance.predict([
          _e(DistanceCategory.k5, 1200, daysAgo: 366),
        ], now: _now),
        isEmpty,
      );
    });

    test('a 3K effort alone does not predict a half or marathon', () {
      final preds = ObservedPerformance.predict([
        _e(DistanceCategory.k3, 11 * 60),
      ], now: _now);
      expect(preds.map((p) => p.category), [DistanceCategory.k5]);
    });
  });

  group('separation from the Training Engine', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('computing predictions leaves the stored plan vDOT untouched', () async {
      final service = EngineMemoryService();
      await service.save(
        EngineMemory(vdotScore: 44, vdotIsProvisional: false),
        syncToCloud: false,
      );

      // Efforts far faster than a vDOT of 44 would suggest.
      final preds = ObservedPerformance.predict([
        _e(DistanceCategory.k10, 38 * 60),
      ], now: _now);
      ObservedPerformance.observedVdot([
        _e(DistanceCategory.k10, 38 * 60),
      ], now: _now);
      expect(preds, isNotEmpty);

      final reloaded = await service.load();
      expect(reloaded.vdotScore, 44);
      expect(reloaded.vdotIsProvisional, isFalse);
    });

    test('the two models can disagree without either moving', () {
      final planVdot = 44;
      final planTenK = secondsForVdot(planVdot.toDouble(), 10);
      final observed = ObservedPerformance.predict([
        _e(DistanceCategory.k10, 42 * 60 + 30),
      ], now: _now).firstWhere((p) => p.category == DistanceCategory.k10);
      expect(observed.predictedSeconds, lessThan(planTenK));
      expect(planVdot, 44); // nothing was fed back
    });

    test('the analytics sources never import the training engine', () {
      const forbidden = [
        'engine_memory',
        'engine_runtime',
        'plan_store',
        'plan_adaptation',
        'workout_selector',
        'pace_table',
        'vdot_adaptation_guard',
      ];
      for (final path in const [
        'lib/utils/observed_performance.dart',
        'lib/utils/split_strategy.dart',
        'lib/utils/race_history.dart',
      ]) {
        final src = File(path).readAsStringSync();
        final imports = RegExp(r"^import .*$", multiLine: true)
            .allMatches(src)
            .map((m) => m.group(0)!)
            .toList();
        for (final word in forbidden) {
          expect(
            imports.where((i) => i.contains(word)),
            isEmpty,
            reason: '$path imports $word',
          );
        }
      }
    });
  });
}
