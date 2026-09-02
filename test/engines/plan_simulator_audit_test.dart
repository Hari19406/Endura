// ignore_for_file: avoid_print

/// Phase 0 — behaviour lock for the session-construction rework.
///
/// The durable contract today: for a runner who follows the plan (compliant),
/// sandbags, or over-achieves, the simulator raises ZERO structural warnings.
/// Only the `skipper` behaviour trips the audit, and those warnings are the
/// adaptive-progression reshaping this rework is meant to clean up — they are
/// recorded as a ceiling (count per persona), not pinned exactly.
///
/// When a later phase intentionally moves these numbers, update the maps in the
/// same commit and say why.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/tools/plan_simulator.dart';

void main() {
  test('non-skipper behaviours raise no simulator warnings', () async {
    final logs = await PlanSimulator(seed: 42).runAll();

    final offenders = <String>[];
    for (final log in logs) {
      if (log.behavior.id == 'skipper') continue;
      if (log.globalWarnings.isNotEmpty) {
        offenders.add(
          '${log.persona.id} × ${log.behavior.id}:\n    '
          '${log.globalWarnings.join('\n    ')}',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'compliant/sandbagger/over_achiever must stay clean:\n'
          '${offenders.join('\n')}',
    );
  });

  test('skipper warning counts stay within the locked ceiling', () async {
    final logs = await PlanSimulator(seed: 42).runAll();

    final actual = <String, int>{};
    for (final log in logs) {
      if (log.behavior.id != 'skipper') continue;
      actual[log.persona.id] = log.globalWarnings.length;
    }

    print('\n===== SKIPPER WARNING COUNTS =====');
    actual.forEach((k, v) => print('  $k: $v'));
    print('=================================\n');

    for (final entry in actual.entries) {
      final ceiling = _skipperCeiling[entry.key];
      expect(
        ceiling,
        isNotNull,
        reason: 'No ceiling recorded for ${entry.key} — add it to _skipperCeiling',
      );
      expect(
        entry.value,
        lessThanOrEqualTo(ceiling!),
        reason: '${entry.key} skipper warnings went UP (${entry.value} > $ceiling)',
      );
    }
  });
}

/// Ceiling (not exact) for `skipper` global-warning count per persona.
/// Recorded from the pre-rework run on seed 42. Later phases should drive
/// these DOWN; tighten the numbers when they drop.
const Map<String, int> _skipperCeiling = {
  'P1_5K_3day_15km_beginner': 21,
  'P2_5K_4day_25km_intermediate_highRpe': 15,
  'P3_10K_5day_40km_intermediate': 17,
  'P4_10K_6day_80km_advanced': 16,
  'P5_HM_4day_25km_belowMinViable': 19,
  'P6_HM_5day_60km_advanced': 16,
  'P7_FM_5day_35km_belowMinViable': 21,
  'P8_FM_6day_70km_advanced': 25,
};
