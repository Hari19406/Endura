// ignore_for_file: avoid_print

/// Pure-Dart sim entry point — no Flutter / path_provider.
/// Run with:
///   dart run lib/tools/dart_sim_runner.dart
library;

import 'package:run_app/tools/plan_simulator.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════════════');
  print('  ENDURA PLAN SIMULATOR  (dart run)');
  print('  Mode: all  — 8 personas × 4 behaviors');
  print('═══════════════════════════════════════════════════════════\n');

  final sim = PlanSimulator(seed: 42);
  final logs = await sim.runAll();

  print('\n╔══════════════════════════════════════════════════════════════╗');
  print('║  FULL RUN SUMMARY                                            ║');
  print('╠══════════════════════════════════════════════════════════════╣');

  int totalWarnings = 0;
  for (final log in logs) {
    final warnCount = log.globalWarnings.length;
    totalWarnings += warnCount;
    final flag = warnCount > 0 ? '⚠️ ' : '✓  ';
    print(
      '║ $flag ${log.persona.id.padRight(38)} '
      'vDOT ${log.initialVdot}→${log.finalVdot}  '
      'W:$warnCount ║',
    );
  }

  print('╠══════════════════════════════════════════════════════════════╣');
  print('║  Total warnings across all runs: $totalWarnings              ║');
  print('╚══════════════════════════════════════════════════════════════╝\n');

  if (totalWarnings == 0) {
    print('✓ All 32 simulations passed with zero warnings.');
  } else {
    print('⚠️  Warnings found — see per-run output above.');
  }
}
