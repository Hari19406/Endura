/// Endura Coaching Engine Simulation
/// Simulates 3 archetypes x 8 weeks to validate:
///   - Volume progression (3:1 cycle)
///   - Workout intent variety
///   - Pace zone correctness
///   - Cutback week triggers

import '../lib/engines/config/workout_template_library.dart';
import '../lib/engines/core/pace_table.dart';
import '../lib/engines/core/vdot_calculator.dart';
import '../lib/engines/plan/volume_calculator.dart';
import '../lib/engines/planner/race_plan_builder.dart';
import '../lib/models/race_plan.dart';
import '../lib/models/training_phase.dart';

class Archetype {
  final String name;
  final String experienceLevel;
  final String goalRace;
  final int prTimeSeconds;
  final PRDistance prDistance;
  final double weeklyKm;
  final int runsPerWeek;

  const Archetype({
    required this.name,
    required this.experienceLevel,
    required this.goalRace,
    required this.prTimeSeconds,
    required this.prDistance,
    required this.weeklyKm,
    required this.runsPerWeek,
  });
}

void main() {
  const archetypes = [
    Archetype(
      name: 'Beginner 5K',
      experienceLevel: 'beginner',
      goalRace: '5k',
      prTimeSeconds: 35 * 60,
      prDistance: PRDistance.fiveK,
      weeklyKm: 15,
      runsPerWeek: 3,
    ),
    Archetype(
      name: 'Intermediate 10K',
      experienceLevel: 'intermediate',
      goalRace: '10k',
      prTimeSeconds: 50 * 60,
      prDistance: PRDistance.tenK,
      weeklyKm: 30,
      runsPerWeek: 4,
    ),
    Archetype(
      name: 'Advanced Half Marathon',
      experienceLevel: 'advanced',
      goalRace: 'half_marathon',
      prTimeSeconds: 95 * 60,
      prDistance: PRDistance.halfMarathon,
      weeklyKm: 55,
      runsPerWeek: 5,
    ),
  ];

  for (final arch in archetypes) {
    _simulateArchetype(arch);
  }
}

void _simulateArchetype(Archetype arch) {
  print('\n${'=' * 70}');
  print('ARCHETYPE: ${arch.name}');
  print('${'=' * 70}');

  final vdot = vdotFromPr(
    prTimeSeconds: arch.prTimeSeconds,
    prDistanceKm: arch.prDistance.distanceKm,
    confidence: PrConfidence.high,
  );
  final paceTable = PaceTable(vdot);
  final goalRaceDistance = _goalToPrDistance(arch.goalRace);
  final goalRacePace = paceTable.resolveGoalPace(
    raceDistance: goalRaceDistance,
    targetTimeSeconds: arch.prTimeSeconds,
  );

  print(
    'vDOT: $vdot | Goal pace: ${goalRacePace.formattedTarget} '
    '| PR: ${_fmtDuration(arch.prTimeSeconds)} for ${arch.prDistance.name}',
  );
  print(
    'Easy: ${paceTable.resolve(PaceZone.aerobicEasy).formatted}  '
    '| Tempo: ${paceTable.resolve(PaceZone.tempo).formatted}  '
    '| VO2: ${paceTable.resolve(PaceZone.vo2Intervals).formatted}',
  );

  final now = DateTime(2025, 1, 6);
  final raceDate = now.add(const Duration(days: 84));
  final plan = RacePlanBuilder.build(
    currentWeeklyKm: arch.weeklyKm,
    goalRace: arch.goalRace,
    raceDate: raceDate,
    experienceLevel: arch.experienceLevel,
    now: now,
  );

  final peakKm = plan.weeks
      .map((week) => week.targetKm)
      .reduce((a, b) => a > b ? a : b);
  print(
    '\nRace plan: ${plan.totalWeeks} weeks | '
    'Start: ${arch.weeklyKm} km/wk | '
    'Peak: ${peakKm.toStringAsFixed(1)} km/wk',
  );

  print('\n${'-' * 70}');
  print('WEEK-BY-WEEK PROGRESSION');
  print('${'-' * 70}');

  const volCalc = VolumeCalculator();
  double prevVolume = arch.weeklyKm;
  final intentLog = <String, int>{};

  for (var w = 0; w < plan.totalWeeks && w < 8; w++) {
    final weekTarget = plan.weeks[w];
    final isCutback = (w + 1) % 4 == 0;

    print(
      '\n  Week ${w + 1} | ${weekTarget.phase.name.toUpperCase()} | '
      'Target: ${weekTarget.targetKm.toStringAsFixed(1)} km | '
      '${isCutback ? "CUTBACK" : ""}',
    );

    double weekTotal = 0;
    final weekIntents = <String>[];

    for (var dayIdx = 0; dayIdx < arch.runsPerWeek; dayIdx++) {
      final role = _dayRole(dayIdx, arch.runsPerWeek, weekTarget);
      final intent = _roleToIntent(role, weekTarget.phase, arch.goalRace);
      final intentName = intent.name;

      weekIntents.add(intentName);
      intentLog[intentName] = (intentLog[intentName] ?? 0) + 1;

      final candidates = WorkoutLibrary.forSlot(
        intent: intent,
        raceDistance: _goalToRaceDistance(arch.goalRace),
        phase: weekTarget.phase,
      );

      if (candidates.isEmpty) {
        print(
          '    Day ${dayIdx + 1}: No template for '
          '$intentName in ${weekTarget.phase.name}',
        );
        continue;
      }

      final template = candidates[dayIdx % candidates.length];
      final variant = WorkoutLibrary.getVariant(template, weekTarget.phase);
      final dist = volCalc.calculateWorkoutDistance(
        weeklyTargetKm: weekTarget.targetKm,
        template: template,
        raceDistance: _goalToRaceDistance(arch.goalRace),
        phase: weekTarget.phase,
        dayRole: role,
        variant: variant,
        longestRecentRunKm: weekTarget.longRunKm > 0
            ? weekTarget.longRunKm
            : arch.weeklyKm * 0.35,
        experienceLevel: arch.experienceLevel,
      );
      weekTotal += dist;

      final paceStr = _displayPaceForTemplate(
        template: template,
        paceTable: paceTable,
        goalRaceDistance: goalRaceDistance,
        goalRaceTimeSeconds: arch.prTimeSeconds,
      );

      print(
        '    Day ${dayIdx + 1}: ${template.name.padRight(25)} '
        '${dist.toStringAsFixed(1).padLeft(4)} km  @ $paceStr',
      );
    }

    final volumeDelta = weekTotal - prevVolume;
    final deltaStr = volumeDelta >= 0
        ? '+${volumeDelta.toStringAsFixed(1)}'
        : volumeDelta.toStringAsFixed(1);
    print(
      '    -- Week total: ${weekTotal.toStringAsFixed(1)} km '
      '($deltaStr from prev) | Sessions: ${weekIntents.join(', ')}',
    );

    if (!isCutback && weekTotal < prevVolume * 0.85 && w > 0) {
      print('    WARNING: Volume dropped unexpectedly (not a cutback week)');
    }
    if (isCutback && weekTotal > prevVolume * 0.90) {
      print('    WARNING: Cutback week did not reduce volume enough');
    }

    prevVolume = weekTotal;
  }

  print('\n${'-' * 70}');
  print('INTENT DISTRIBUTION (8 weeks)');
  print('${'-' * 70}');
  intentLog.forEach((intent, count) {
    final bar = '#' * count;
    print('  ${intent.padRight(20)} $bar ($count sessions)');
  });

  print('\n${'-' * 70}');
  print('PACE SANITY CHECKS');
  print('${'-' * 70}');
  final easy = paceTable.resolve(PaceZone.aerobicEasy);
  final tempo = paceTable.resolve(PaceZone.tempo);
  final vo2 = paceTable.resolve(PaceZone.vo2Intervals);

  _check('Easy slower than tempo', easy.minSecondsPerKm > tempo.maxSecondsPerKm);
  _check('Tempo slower than VO2', tempo.minSecondsPerKm > vo2.maxSecondsPerKm);
  _check(
    'Easy pace reasonable (4:00-9:00/km)',
    easy.minSecondsPerKm >= 240 && easy.maxSecondsPerKm <= 540,
  );
  _check(
    'VO2 pace reasonable (<4:30/km for non-beginner or <5:30 for beginner)',
    vo2.maxSecondsPerKm <= (arch.experienceLevel == 'beginner' ? 330 : 270),
  );
}

DayRole _dayRole(int pos, int total, WeekTarget week) {
  if (pos == total - 1 && week.hasLongRun) return DayRole.longRun;
  if (week.qualityCount >= 1 && pos == 0) return DayRole.primaryQuality;
  if (week.qualityCount >= 2 && pos == 2) return DayRole.secondaryQuality;
  return DayRole.easyRun;
}

WorkoutIntent _roleToIntent(
  DayRole role,
  TrainingPhase phase,
  String goalRace,
) {
  return switch (role) {
    DayRole.longRun => WorkoutIntent.endurance,
    DayRole.primaryQuality => phase == TrainingPhase.base
        ? WorkoutIntent.threshold
        : (goalRace == '5k' || goalRace == '10k')
            ? WorkoutIntent.vo2max
            : WorkoutIntent.threshold,
    DayRole.secondaryQuality => phase == TrainingPhase.base
        ? WorkoutIntent.threshold
        : WorkoutIntent.vo2max,
    DayRole.easyRun => WorkoutIntent.aerobicBase,
    DayRole.recovery => WorkoutIntent.recovery,
  };
}

String _displayPaceForTemplate({
  required WorkoutTemplate template,
  required PaceTable paceTable,
  required PRDistance goalRaceDistance,
  required int goalRaceTimeSeconds,
}) {
  final mainBlocks = template.blocks.where((block) => block.type == BlockType.main);
  if (mainBlocks.isEmpty) return '-';

  final zone = mainBlocks.first.paceZone;
  try {
    if (_isGoalPaceZone(zone)) {
      return paceTable
          .resolveGoalPace(
            raceDistance: goalRaceDistance,
            targetTimeSeconds: goalRaceTimeSeconds,
          )
          .formatted;
    }
    return paceTable.resolve(zone).formatted;
  } catch (_) {
    return 'tempo fallback';
  }
}

bool _isGoalPaceZone(PaceZone zone) {
  return zone == PaceZone.goalPace ||
      zone == PaceZone.raceSimulation ||
      zone == PaceZone.dressRehearsal;
}

RaceDistance _goalToRaceDistance(String goalRace) => switch (goalRace) {
      '5k' => RaceDistance.fiveK,
      '10k' => RaceDistance.tenK,
      'half_marathon' => RaceDistance.halfMarathon,
      'marathon' => RaceDistance.marathon,
      _ => RaceDistance.fiveK,
    };

PRDistance _goalToPrDistance(String goalRace) => switch (goalRace) {
      '5k' => PRDistance.fiveK,
      '10k' => PRDistance.tenK,
      'half_marathon' => PRDistance.halfMarathon,
      'marathon' => PRDistance.marathon,
      _ => PRDistance.fiveK,
    };

String _fmtDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

void _check(String label, bool pass) {
  print('  ${pass ? 'PASS' : 'FAIL'} $label');
}
