// ignore_for_file: avoid_print

/// Phase 0 — behaviour lock (golden characterization test).
///
/// Freezes the FULL plan the engine produces for every simulator persona under
/// compliant behaviour: week × day × {phase, slot, intent, templateId,
/// distance, prescribed pace}. Any change to session construction shows up as a
/// line-level diff against `goldens/plan_output.txt`.
///
///   * output identical  → the change was structurally safe
///   * output differs     → inspect the diff; if intended, regenerate the
///                          golden (see below) and commit it as the record of
///                          what changed
///
/// Regenerate:  UPDATE_GOLDENS=1 flutter test test/engines/plan_simulator_audit_test.dart
///
/// `skipper` / `sandbagger` / `over_achiever` still run in the wider suite for
/// crash-safety; only the compliant structural output is pinned here.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/tools/plan_simulator.dart';

const _goldenPath = 'test/engines/goldens/plan_output.txt';

void main() {
  test('compliant plan output matches the golden', () async {
    final logs = await PlanSimulator(seed: 42).runAll(
      behaviors: [SimBehavior.compliant()],
    );

    final actual = _render(logs);
    final file = File(_goldenPath);
    final update = Platform.environment['UPDATE_GOLDENS'] == '1';

    if (update || !file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(actual);
      print(
        update
            ? 'Golden regenerated: $_goldenPath'
            : 'Golden created: $_goldenPath (first run)',
      );
      return;
    }

    final expected = file.readAsStringSync();
    if (actual == expected) return;

    // Show the first divergence to make the failure actionable.
    final a = actual.split('\n');
    final e = expected.split('\n');
    final diffs = <String>[];
    for (var i = 0; i < a.length || i < e.length; i++) {
      final al = i < a.length ? a[i] : '<eof>';
      final el = i < e.length ? e[i] : '<eof>';
      if (al != el) {
        diffs.add('  line ${i + 1}:\n    golden: $el\n    actual: $al');
        if (diffs.length >= 15) break;
      }
    }
    fail(
      'Plan output changed vs golden ($_goldenPath).\n'
      'If intended: UPDATE_GOLDENS=1 flutter test ${_goldenPath.replaceFirst('goldens/plan_output.txt', '')}'
      'plan_simulator_audit_test.dart\n'
      'First divergences:\n${diffs.join('\n')}',
    );
  });
}

String _render(List<SimLog> logs) {
  final buf = StringBuffer();
  final sorted = [...logs]..sort((x, y) => x.persona.id.compareTo(y.persona.id));

  for (final log in sorted) {
    buf.writeln('=== ${log.persona.id} ===');
    for (final week in log.weeks) {
      buf.writeln(
        'W${week.weekNumber} ${week.phase.name}'
        '${week.isCutbackWeek ? ' [cutback]' : ''} '
        'target=${week.targetKm.toStringAsFixed(1)}km',
      );
      for (final s in week.sessions) {
        buf.writeln(
          '  ${_day(s.dayOfWeek)} ${s.slotRole.padRight(10)} '
          '${s.intent.padRight(12)} '
          '${(s.templateId ?? '-').padRight(24)} '
          '${s.targetKm.toStringAsFixed(1).padLeft(5)}km '
          '@ ${_pace(s.prescribedPaceSecPerKm)}',
        );
      }
    }
    buf.writeln();
  }
  return buf.toString();
}

String _day(int i) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i % 7];

String _pace(double secPerKm) {
  if (secPerKm <= 0) return 'rpe';
  final s = secPerKm.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}/km';
}
