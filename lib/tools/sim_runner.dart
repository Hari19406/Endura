// ignore_for_file: avoid_print

/// Run this with:
///
///   flutter run -t lib/tools/sim_runner.dart --dart-define-from-file=dart_defines.env
///
/// Or as a pure Dart script (no Flutter deps):
///
///   dart run lib/tools/sim_runner.dart
///
/// Output goes to stdout. Pipe to a file for inspection:
///
///   flutter run -t lib/tools/sim_runner.dart 2>/dev/null | tee sim_output.json
///
library;

import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:run_app/tools/plan_simulator.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final mode = 'all';

  print('═══════════════════════════════════════════════════════════');
  print('  ENDURA PLAN SIMULATOR');
  print('  Mode: $mode');
  print('═══════════════════════════════════════════════════════════\n');

  final sim = PlanSimulator(seed: 42); // fixed seed for reproducibility

  switch (mode) {
    case 'baseline':
      // Step 1: run persona 3 (the "normal" case) first to validate basics
      final log = await sim.run(
        persona: SimPersona.persona3(),
        behavior: SimBehavior.compliant(),
      );
      log.printSummary();
      _writeJson('sim_baseline.json', log.toJson());

    case 'all':
      // Step 2: run all 8 personas × 4 behaviors = 32 simulations
      final logs = await sim.runAll();
      await _writeSummaryReport(logs);

    case 'persona':
      // Run a single persona by number: dart run sim_runner.dart persona 5
      final num = args.length > 1 ? int.tryParse(args[1]) ?? 3 : 3;
      final persona = _personaByNumber(num);
      final log = await sim.run(
        persona: persona,
        behavior: SimBehavior.compliant(),
      );
      log.printSummary();
      _writeJson('sim_p$num.json', log.toJson());

    case 'skipper':
      // All personas with skipper behavior
      for (final p in SimPersona.allPersonas()) {
        final log = await sim.run(persona: p, behavior: SimBehavior.skipper());
        log.printSummary();
      }

    default:
      print('Unknown mode: $mode');
      print('Usage: dart run sim_runner.dart [baseline|all|persona N|skipper]');
      exit(1);
  }

  print('\n✓ Simulation complete.');
}

SimPersona _personaByNumber(int n) => switch (n) {
      1 => SimPersona.persona1(),
      2 => SimPersona.persona2(),
      4 => SimPersona.persona4(),
      5 => SimPersona.persona5(),
      6 => SimPersona.persona6(),
      7 => SimPersona.persona7(),
      8 => SimPersona.persona8(),
      _ => SimPersona.persona3(), // default to baseline
    };

Future<void> _writeJson(String filename, String json) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(json);
    print('  → Written to ${file.path}');
  } catch (e) {
    print('  → Could not write file ($e)');
  }
}

Future<void> _writeSummaryReport(List<SimLog> logs) async {
  // One-line summary per run, plus global warning counts
  print('\n╔══════════════════════════════════════════════════════════════╗');
  print('║  FULL RUN SUMMARY                                            ║');
  print('╠══════════════════════════════════════════════════════════════╣');

  int totalWarnings = 0;
  for (final log in logs) {
    final warnCount = log.globalWarnings.length;
    totalWarnings += warnCount;
    final flag = warnCount > 0 ? '⚠️ ' : '✓  ';
    print('║ $flag ${log.persona.id.padRight(38)} '
        'vDOT ${log.initialVdot}→${log.finalVdot}  '
        'W:$warnCount ║');
  }

  print('╠══════════════════════════════════════════════════════════════╣');
  print('║  Total warnings across all runs: $totalWarnings');
  print('╚══════════════════════════════════════════════════════════════╝\n');

  // Write each log to disk
  for (final log in logs) {
    final safe = log.persona.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    await _writeJson('sim_${safe}_${log.behavior.id}.json', log.toJson());
  }

  // Consolidated warnings file
  final allWarnings = logs
      .expand((l) => l.globalWarnings.map((w) => '${l.persona.id}: $w'))
      .toList();

  if (allWarnings.isNotEmpty) {
    final warningText = allWarnings.join('\n');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/sim_warnings.txt');
      await file.writeAsString(warningText);
      print('  → All warnings written to ${file.path}');
    } catch (_) {
      print('\nWARNINGS:\n$warningText');
    }
  }
}