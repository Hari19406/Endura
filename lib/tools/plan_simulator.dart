// ignore_for_file: avoid_print

/// PlanSimulator — Pre-Launch Validation Tool
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:run_app/engines/progression_decision.dart';
import 'package:run_app/engines/core/vdot_calculator.dart';
import 'package:run_app/engines/core/pace_table.dart';
import 'package:run_app/engines/config/workout_template_library.dart';
import 'package:run_app/engines/config/archetype_table.dart';
import 'package:run_app/engines/plan/week_resolver.dart';
import 'package:run_app/engines/memory/engine_memory.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/training_phase.dart';
import 'package:run_app/models/race_plan.dart';

// ============================================================================
// PERSONA
// ============================================================================

class SimPersona {
  final String id;
  final String goalRace;
  final int daysPerWeek;
  final double weeklyKm;
  final String experience;
  final int? prTimeSeconds;
  final String? prDistance;
  final String goalIntent;
  final int planWeeks;
  final List<int>? trainingDays;
  final int longRunDayIndex;

  const SimPersona({
    required this.id,
    required this.goalRace,
    required this.daysPerWeek,
    required this.weeklyKm,
    required this.experience,
    this.prTimeSeconds,
    this.prDistance,
    this.goalIntent = 'improve',
    this.planWeeks = 10,
    this.trainingDays,
    this.longRunDayIndex = 6,
  });

  static SimPersona persona1() => const SimPersona(
    id: 'P1_5K_3day_15km_beginner',
    goalRace: '5k',
    daysPerWeek: 3,
    weeklyKm: 15,
    experience: 'beginner',
    goalIntent: 'finish',
    planWeeks: 8,
    longRunDayIndex: 5,
  );
  static SimPersona persona2() => const SimPersona(
    id: 'P2_5K_4day_25km_intermediate_highRpe',
    goalRace: '5k',
    daysPerWeek: 4,
    weeklyKm: 25,
    experience: 'intermediate',
    goalIntent: 'improve',
    planWeeks: 8,
  );
  static SimPersona persona3() => const SimPersona(
    id: 'P3_10K_5day_40km_intermediate',
    goalRace: '10k',
    daysPerWeek: 5,
    weeklyKm: 40,
    experience: 'intermediate',
    goalIntent: 'improve',
    planWeeks: 10,
  );
  static SimPersona persona4() => const SimPersona(
    id: 'P4_10K_6day_80km_advanced',
    goalRace: '10k',
    daysPerWeek: 6,
    weeklyKm: 80,
    experience: 'advanced',
    goalIntent: 'peak',
    prTimeSeconds: 2280,
    prDistance: '10k',
    planWeeks: 10,
  );
  static SimPersona persona5() => const SimPersona(
    id: 'P5_HM_4day_25km_belowMinViable',
    goalRace: 'half_marathon',
    daysPerWeek: 4,
    weeklyKm: 25,
    experience: 'intermediate',
    goalIntent: 'finish',
    planWeeks: 12,
  );
  static SimPersona persona6() => const SimPersona(
    id: 'P6_HM_5day_60km_advanced',
    goalRace: 'half_marathon',
    daysPerWeek: 5,
    weeklyKm: 60,
    experience: 'advanced',
    goalIntent: 'peak',
    prTimeSeconds: 5400,
    prDistance: 'half',
    planWeeks: 12,
  );
  static SimPersona persona7() => const SimPersona(
    id: 'P7_FM_5day_35km_belowMinViable',
    goalRace: 'marathon',
    daysPerWeek: 5,
    weeklyKm: 35,
    experience: 'intermediate',
    goalIntent: 'finish',
    planWeeks: 12,
  );
  static SimPersona persona8() => const SimPersona(
    id: 'P8_FM_6day_70km_advanced',
    goalRace: 'marathon',
    daysPerWeek: 6,
    weeklyKm: 70,
    experience: 'advanced',
    goalIntent: 'peak',
    prTimeSeconds: 10800,
    prDistance: 'marathon',
    planWeeks: 16,
  );

  static List<SimPersona> allPersonas() => [
    persona1(),
    persona2(),
    persona3(),
    persona4(),
    persona5(),
    persona6(),
    persona7(),
    persona8(),
  ];
}

// ============================================================================
// BEHAVIOR
// ============================================================================

class SimBehavior {
  final String id;
  final double Function(int week, String intent) rpeProvider;
  final double Function(int week, String intent) paceMultiplier;
  final double Function(int week, String intent) skipProbability;

  const SimBehavior({
    required this.id,
    required this.rpeProvider,
    required this.paceMultiplier,
    required this.skipProbability,
  });

  static SimBehavior compliant() => SimBehavior(
    id: 'compliant',
    rpeProvider: (w, i) => 5.0,
    paceMultiplier: (w, i) => 1.0,
    skipProbability: (w, i) => 0.0,
  );
  static SimBehavior highRpe() => SimBehavior(
    id: 'high_rpe',
    rpeProvider: (w, i) {
      final isQ = i == 'threshold' || i == 'vo2max' || i == 'speed';
      return isQ ? 8.5 : 6.0;
    },
    paceMultiplier: (w, i) => 1.0,
    skipProbability: (w, i) => 0.0,
  );
  static SimBehavior skipper() => SimBehavior(
    id: 'skipper',
    rpeProvider: (w, i) => 5.0,
    paceMultiplier: (w, i) => 1.0,
    skipProbability: (w, i) => 0.30,
  );
  static SimBehavior sandbagger() => SimBehavior(
    id: 'sandbagger',
    rpeProvider: (w, i) => 3.5,
    paceMultiplier: (w, i) => 1.15,
    skipProbability: (w, i) => 0.0,
  );
  static SimBehavior overAchiever() => SimBehavior(
    id: 'over_achiever',
    rpeProvider: (w, i) => 6.5,
    paceMultiplier: (w, i) => 0.88,
    skipProbability: (w, i) => 0.0,
  );
}

// ============================================================================
// LOG STRUCTURES
// ============================================================================

class SimSessionLog {
  final int weekNumber;
  final int dayOfWeek;
  final TrainingPhase phase;
  final String? templateId;
  final String intent;
  final String slotRole;
  final double targetKm;
  final double actualKm;
  final double prescribedPaceSecPerKm;
  final double actualPaceSecPerKm;
  final double? rpe;
  final bool wasSkipped;
  final int vdotBefore;
  final int vdotAfter;

  const SimSessionLog({
    required this.weekNumber,
    required this.dayOfWeek,
    required this.phase,
    required this.intent,
    required this.slotRole,
    required this.targetKm,
    required this.actualKm,
    required this.prescribedPaceSecPerKm,
    required this.actualPaceSecPerKm,
    required this.vdotBefore,
    required this.vdotAfter,
    this.templateId,
    this.rpe,
    this.wasSkipped = false,
  });

  Map<String, dynamic> toJson() => {
    'week': weekNumber,
    'day': _dayName(dayOfWeek),
    'phase': phase.name,
    'templateId': templateId,
    'intent': intent,
    'slot': slotRole,
    'targetKm': _fmt(targetKm),
    'actualKm': _fmt(actualKm),
    'prescribedPace': _fmtPace(prescribedPaceSecPerKm),
    'actualPace': _fmtPace(actualPaceSecPerKm),
    'rpe': rpe,
    'skipped': wasSkipped,
    'vdotBefore': vdotBefore,
    'vdotAfter': vdotAfter,
  };
}

class SimWeekLog {
  final int weekNumber;
  final TrainingPhase phase;
  final double targetKm;
  final double actualKm;
  final List<SimSessionLog> sessions;
  final ProgressionDecision progressionDecision;
  final bool isCutbackWeek;
  final List<String> warnings;

  const SimWeekLog({
    required this.weekNumber,
    required this.phase,
    required this.targetKm,
    required this.actualKm,
    required this.sessions,
    required this.progressionDecision,
    required this.isCutbackWeek,
    this.warnings = const [],
  });

  int get qualityCount =>
      sessions.where((s) => !s.wasSkipped && _isQuality(s.intent)).length;
  bool get hasLongRun =>
      sessions.any((s) => !s.wasSkipped && s.intent == 'endurance');
  double get qualityFraction {
    final total = sessions.where((s) => !s.wasSkipped).length;
    if (total == 0) return 0;
    return qualityCount / total;
  }

  Map<String, dynamic> toJson() => {
    'week': weekNumber,
    'phase': phase.name,
    'isCutback': isCutbackWeek,
    'targetKm': _fmt(targetKm),
    'actualKm': _fmt(actualKm),
    'deviation%': _fmt(
      (actualKm - targetKm) / (targetKm == 0 ? 1 : targetKm) * 100,
    ),
    'qualityFraction': _fmt(qualityFraction),
    'qualityCount': qualityCount,
    'hasLongRun': hasLongRun,
    'progressionDecision': progressionDecision.name,
    'warnings': warnings,
    'sessions': sessions.map((s) => s.toJson()).toList(),
  };
}

class SimLog {
  final SimPersona persona;
  final SimBehavior behavior;
  final DateTime simStartDate;
  final List<SimWeekLog> weeks;
  final int initialVdot;
  final int finalVdot;
  final bool postPlanTriggered;
  final bool celebrationScreenTriggered;
  final bool maintenanceFallbackTriggered;
  final List<String> globalWarnings;

  const SimLog({
    required this.persona,
    required this.behavior,
    required this.simStartDate,
    required this.weeks,
    required this.initialVdot,
    required this.finalVdot,
    required this.postPlanTriggered,
    required this.celebrationScreenTriggered,
    required this.maintenanceFallbackTriggered,
    this.globalWarnings = const [],
  });

  String toJson({bool pretty = true}) {
    final data = {
      'persona': persona.id,
      'behavior': behavior.id,
      'simStartDate': simStartDate.toIso8601String(),
      'initialVdot': initialVdot,
      'finalVdot': finalVdot,
      'postPlanTriggered': postPlanTriggered,
      'celebrationScreenTriggered': celebrationScreenTriggered,
      'maintenanceFallbackTriggered': maintenanceFallbackTriggered,
      'globalWarnings': globalWarnings,
      'mileageCurve': weeks
          .map(
            (w) => {
              'week': w.weekNumber,
              'target': _fmt(w.targetKm),
              'actual': _fmt(w.actualKm),
            },
          )
          .toList(),
      'weeks': weeks.map((w) => w.toJson()).toList(),
    };
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  void printSummary() {
    print('\n══════════════════════════════════════════════════════');
    print('  SIM: ${persona.id}  ×  ${behavior.id}');
    print('══════════════════════════════════════════════════════');
    print('  vDOT: $initialVdot → $finalVdot');
    print(
      '  Weeks: ${weeks.length}  |  post-plan: $postPlanTriggered  |  maintenance: $maintenanceFallbackTriggered',
    );
    if (globalWarnings.isNotEmpty) {
      print('\n  ⚠️  WARNINGS (${globalWarnings.length}):');
      for (final w in globalWarnings) {
        print('     • $w');
      }
    }
    print('\n  Mileage curve:');
    for (final w in weeks) {
      final bar = '█' * (w.actualKm / 5).round();
      final tag = w.isCutbackWeek ? ' [CUTBACK]' : '';
      final warn = w.warnings.isNotEmpty ? ' ⚠' : '';
      print(
        '  W${w.weekNumber.toString().padLeft(2)} '
        '${w.phase.name.padRight(12)} '
        '${_fmt(w.actualKm).padLeft(5)}km$tag$warn',
      );
      print('       $bar');
    }
    print('══════════════════════════════════════════════════════\n');
  }
}

// ============================================================================
// PLAN SIMULATOR
// ============================================================================

class PlanSimulator {
  final math.Random _rng;
  PlanSimulator({int? seed}) : _rng = math.Random(seed ?? 42);

  Future<SimLog> run({
    required SimPersona persona,
    required SimBehavior behavior,
  }) async {
    final simStart = _nearestMonday(DateTime(2025, 3, 3));
    final trainingDays =
        persona.trainingDays ??
        _defaultTrainingDays(persona.daysPerWeek, persona.longRunDayIndex);

    final raceDate = simStart.add(Duration(days: persona.planWeeks * 7));
    final racePlan = RacePlanBuilder.build(
      currentWeeklyKm: persona.weeklyKm,
      goalRace: persona.goalRace,
      raceDate: raceDate,
      experienceLevel: persona.experience,
      now: simStart,
    );

    EngineMemory memory = _bootstrapMemory(persona, racePlan);
    final initialVdot = memory.vdotScore;

    final weekLogs = <SimWeekLog>[];
    final globalWarnings = <String>[];
    bool postPlanTriggered = false;
    bool celebrationTriggered = false;
    bool maintenanceTriggered = false;
    final recentRpes = <double>[];
    var ladderPositions = <String, int>{};

    // Taper week counter — resets when plan completes.
    var taperWeekCount = 0;

    for (int weekNum = 1; weekNum <= persona.planWeeks + 2; weekNum++) {
      final weekStart = simStart.add(Duration(days: (weekNum - 1) * 7));

      final post = _checkPostPlan(memory, weekStart);
      if (post.justCompleted) {
        postPlanTriggered = true;
        celebrationTriggered = true;
        memory = post.memory;
        taperWeekCount = 0; // reset on plan completion
        print('[Sim] W$weekNum: Plan complete → celebration triggered');
      }
      if (post.justEnteredMaintenance) {
        maintenanceTriggered = true;
        memory = post.memory;
        print('[Sim] W$weekNum: Auto-entered maintenance');
      }
      if (weekNum > persona.planWeeks + 1 && memory.isInMaintenance) break;

      final isCutback = weekNum % 4 == 0;
      final (
        targetKm,
        phase,
        slots,
        updatedLadder,
        resolvedEffectiveKm,
      ) = _resolveWeek(
        memory: memory,
        trainingDays: trainingDays,
        weekNum: weekNum,
        weekStart: weekStart,
        isCutback: isCutback,
        persona: persona,
        ladderPositions: ladderPositions,
        taperWeekCount: taperWeekCount,
      );
      ladderPositions = updatedLadder;

      // Increment taper counter after resolve so W1 taper uses taperWeekCount=1.
      if (phase == TrainingPhase.taper) taperWeekCount++;

      final priorTemplateIds = List<String>.from(memory.recentTemplateIds);
      final sessionLogs = <SimSessionLog>[];
      double weekActualKm = 0;
      final weekTemplateIds = <String>[];

      for (final slot in slots) {
        final skipProb = behavior.skipProbability(weekNum, slot.intent);
        final skipped = _rng.nextDouble() < skipProb;
        final vdotBefore = memory.vdotScore;

        if (skipped) {
          sessionLogs.add(
            SimSessionLog(
              weekNumber: weekNum,
              dayOfWeek: slot.dayOfWeek,
              phase: phase,
              templateId: slot.templateId,
              intent: slot.intent,
              slotRole: slot.slotRole,
              targetKm: slot.targetKm,
              actualKm: 0,
              prescribedPaceSecPerKm: slot.prescribedPace,
              actualPaceSecPerKm: 0,
              vdotBefore: vdotBefore,
              vdotAfter: vdotBefore,
              wasSkipped: true,
            ),
          );
          continue;
        }

        final rpe = behavior.rpeProvider(weekNum, slot.intent);
        final actualPace =
            slot.prescribedPace * behavior.paceMultiplier(weekNum, slot.intent);
        final actualKm = slot.targetKm;

        weekActualKm += actualKm;
        if (slot.templateId != null) weekTemplateIds.add(slot.templateId!);
        recentRpes.insert(0, rpe);
        if (recentRpes.length > 10) recentRpes.removeLast();

        final vdotAfter = _nudgeVdot(
          vdot: vdotBefore,
          actualPace: actualPace,
          prescribedPace: slot.prescribedPace,
          rpe: rpe,
          intent: slot.intent,
        );

        final sessionDate = weekStart.add(Duration(days: slot.dayOfWeek));
        final newRpeEntry = RpeEntry(value: rpe.round(), date: sessionDate);
        memory = memory.copyWith(
          vdotScore: vdotAfter,
          vdotIsProvisional: false,
          lastRunDate: sessionDate,
          lastCompletedTemplateId: slot.templateId,
          totalRunsCompleted: memory.totalRunsCompleted + 1,
          recentTemplateIds: _updateRecentTemplates(
            memory.recentTemplateIds,
            slot.templateId,
          ),
          recentRpeEntries: [newRpeEntry, ...memory.recentRpeEntries.take(9)],
        );

        sessionLogs.add(
          SimSessionLog(
            weekNumber: weekNum,
            dayOfWeek: slot.dayOfWeek,
            phase: phase,
            templateId: slot.templateId,
            intent: slot.intent,
            slotRole: slot.slotRole,
            targetKm: slot.targetKm,
            actualKm: actualKm,
            prescribedPaceSecPerKm: slot.prescribedPace,
            actualPaceSecPerKm: actualPace,
            rpe: rpe,
            vdotBefore: vdotBefore,
            vdotAfter: vdotAfter,
          ),
        );
      }

      memory = memory.copyWith(
        previousWeekTargetKm: targetKm,
        currentWeek: weekNum + 1,
      );

      final weekWarnings = _auditWeek(
        weekNum: weekNum,
        targetKm: targetKm,
        actualKm: weekActualKm,
        sessions: sessionLogs,
        isCutback: isCutback,
        phase: phase,
        templateIds: weekTemplateIds,
        persona: persona,
        priorTemplateIds: priorTemplateIds,
        previousWeekActualKm: weekLogs.isNotEmpty
            ? weekLogs.last.actualKm
            : null,
        trainingDays: trainingDays,
        resolvedEffectiveKm: resolvedEffectiveKm,
      );
      globalWarnings.addAll(weekWarnings.map((w) => 'W$weekNum: $w'));

      final decision = _deriveProgressionDecision(recentRpes);
      weekLogs.add(
        SimWeekLog(
          weekNumber: weekNum,
          phase: phase,
          targetKm: targetKm,
          actualKm: weekActualKm,
          sessions: sessionLogs,
          progressionDecision: decision,
          isCutbackWeek: isCutback,
          warnings: weekWarnings,
        ),
      );
    }

    _auditGlobal(
      weeks: weekLogs,
      persona: persona,
      globalWarnings: globalWarnings,
    );

    return SimLog(
      persona: persona,
      behavior: behavior,
      simStartDate: simStart,
      weeks: weekLogs,
      initialVdot: initialVdot,
      finalVdot: memory.vdotScore,
      postPlanTriggered: postPlanTriggered,
      celebrationScreenTriggered: celebrationTriggered,
      maintenanceFallbackTriggered: maintenanceTriggered,
      globalWarnings: globalWarnings,
    );
  }

  Future<List<SimLog>> runAll({
    List<SimPersona>? personas,
    List<SimBehavior>? behaviors,
  }) async {
    final ps = personas ?? SimPersona.allPersonas();
    final bs =
        behaviors ??
        [
          SimBehavior.compliant(),
          SimBehavior.skipper(),
          SimBehavior.sandbagger(),
          SimBehavior.overAchiever(),
        ];
    final logs = <SimLog>[];
    for (final p in ps) {
      for (final b in bs) {
        print('\n▶ Running ${p.id} × ${b.id}');
        final log = await run(persona: p, behavior: b);
        logs.add(log);
        log.printSummary();
      }
    }
    return logs;
  }

  // ============================================================================
  // ENGINE WIRING
  // ============================================================================

  EngineMemory _bootstrapMemory(SimPersona persona, RacePlan racePlan) {
    final int vdot;
    if (persona.prTimeSeconds != null && persona.prDistance != null) {
      final km = _prDistanceToKm(persona.prDistance!);
      vdot = vdotFromPr(
        prTimeSeconds: persona.prTimeSeconds!,
        prDistanceKm: km,
        confidence: PrConfidence.high,
      ).clamp(30, 85);
    } else {
      vdot = switch (persona.experience) {
        'advanced' => 52,
        'intermediate' => 42,
        _ => 32,
      };
    }

    return EngineMemory(
      vdotScore: vdot,
      vdotIsProvisional: persona.prTimeSeconds == null,
      racePlan: racePlan,
      currentPhase: TrainingPhase.base,
      currentWeek: 1,
      totalRunsCompleted: 0,
      baselineWeeklyKm: persona.weeklyKm,
      previousWeekTargetKm: persona.weeklyKm,
      recentTemplateIds: const [],
      recentRpeEntries: const [],
      longRunDayIndex: persona.longRunDayIndex,
    );
  }

  (double, TrainingPhase, List<_SimSlot>, Map<String, int>, double)
  _resolveWeek({
    required EngineMemory memory,
    required List<int> trainingDays,
    required int weekNum,
    required DateTime weekStart,
    required bool isCutback,
    required SimPersona persona,
    Map<String, int> ladderPositions = const {},
    int taperWeekCount = 0,
  }) {
    final midWeek = weekStart.add(const Duration(days: 3));
    TrainingPhase phase = TrainingPhase.base;
    double targetKm = persona.weeklyKm;

    if (memory.isInMaintenance) {
      phase = TrainingPhase.maintenance;
      targetKm = (memory.baselineWeeklyKm ?? persona.weeklyKm) * 0.85;
    } else if (memory.hasRacePlan) {
      final raceWeek = memory.racePlan!.currentWeek(midWeek);
      if (raceWeek != null) {
        phase = raceWeek.phase;
        targetKm = raceWeek.targetKm;
      }
    }

    // WeekResolver owns both the cutback 0.70 multiplier and the taper multiplier.
    // Pass the un-reduced targetKm; WeekResolver applies the appropriate reduction.

    // Taper week number: how many taper weeks have elapsed so far + 1.
    // taperWeekCount is incremented after resolve, so first taper week = 1.
    final taperWeekNumber = phase == TrainingPhase.taper
        ? taperWeekCount + 1
        : 1;

    final experienceLevel = switch (persona.experience) {
      'advanced' => ExperienceLevel.advanced,
      'intermediate' => ExperienceLevel.intermediate,
      _ => ExperienceLevel.beginner,
    };

    final resolution = const WeekResolver().resolve(
      weekTarget: WeekTarget(
        week: weekNum,
        phase: phase,
        targetKm: targetKm,
        longRunKm: targetKm * 0.30,
        qualityCount: isCutback ? 1 : 2,
        hasLongRun: true,
        keySession: 'quality',
      ),
      trainingDayIndices: trainingDays,
      raceDistance: _mapGoalRace(persona.goalRace),
      phase: phase,
      weekNumber: weekNum,
      recentTemplateIds: memory.recentTemplateIds,
      isCutbackWeek: isCutback,
      longRunDayIndex: persona.longRunDayIndex,
      experienceLevel: experienceLevel,
      currentWeeklyKm: targetKm,
      ladderPositions: ladderPositions,
      taperWeekNumber: taperWeekNumber,
    );

    final trainingSlots = resolution.days.where((d) => d.isTraining).toList();
    final slots = <_SimSlot>[];
    // resolution.targetKm already has cutback/taper multiplier applied.
    final effectiveKm = resolution.targetKm;

    for (final day in trainingSlots) {
      final slotKm = day.distanceKm ?? (effectiveKm / trainingSlots.length);
      final prescribedPace = _paceForIntent(
        day.intent?.name ?? 'aerobicBase',
        memory.vdotScore,
      );

      slots.add(
        _SimSlot(
          dayOfWeek: day.weekday,
          intent: day.intent?.name ?? 'aerobicBase',
          slotRole: day.slotType.name,
          templateId: day.templateId,
          targetKm: _fmt2(slotKm),
          prescribedPace: prescribedPace,
        ),
      );
    }

    return (
      targetKm,
      phase,
      slots,
      resolution.updatedLadderPositions,
      effectiveKm,
    );
  }

  ({EngineMemory memory, bool justCompleted, bool justEnteredMaintenance})
  _checkPostPlan(EngineMemory memory, DateTime weekStart) {
    if (memory.isInMaintenance) {
      return (
        memory: memory,
        justCompleted: false,
        justEnteredMaintenance: false,
      );
    }
    if (memory.hasRacePlan && memory.planCompletedAt == null) {
      if (!weekStart.isBefore(memory.racePlan!.raceDate)) {
        return (
          memory: memory.copyWith(
            planCompletedAt: weekStart,
            clearRacePlan: true,
            currentPhase: TrainingPhase.base,
          ),
          justCompleted: true,
          justEnteredMaintenance: false,
        );
      }
    }
    if (memory.shouldAutoEnterMaintenance) {
      final km =
          (memory.previousWeekTargetKm ?? memory.baselineWeeklyKm ?? 20.0) *
          0.85;
      return (
        memory: memory.copyWith(
          isInMaintenance: true,
          currentPhase: TrainingPhase.maintenance,
          baselineWeeklyKm: km,
          previousWeekTargetKm: km,
        ),
        justCompleted: false,
        justEnteredMaintenance: true,
      );
    }
    return (
      memory: memory,
      justCompleted: false,
      justEnteredMaintenance: false,
    );
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  int _nudgeVdot({
    required int vdot,
    required double actualPace,
    required double prescribedPace,
    required double rpe,
    required String intent,
  }) {
    final calibrating =
        intent == 'threshold' ||
        intent == 'vo2max' ||
        intent == 'endurance' ||
        intent == 'aerobicBase';
    if (!calibrating) return vdot;
    final ratio = prescribedPace > 0 ? actualPace / prescribedPace : 1.0;
    if (ratio <= 0.97 && rpe <= 6.0) return (vdot + 1).clamp(30, 85);
    if (ratio >= 1.08 && rpe >= 7.5) return (vdot - 1).clamp(30, 85);
    return vdot;
  }

  ProgressionDecision _deriveProgressionDecision(List<double> recentRpes) {
    if (recentRpes.length < 3) return ProgressionDecision.hold;
    final avg =
        recentRpes.take(5).reduce((a, b) => a + b) / recentRpes.take(5).length;
    if (avg >= 7.5) return ProgressionDecision.regress;
    if (avg <= 5.0) return ProgressionDecision.progress;
    return ProgressionDecision.hold;
  }

  List<String> _updateRecentTemplates(List<String> current, String? id) {
    if (id == null) return current;
    return [id, ...current.where((t) => t != id)].take(14).toList();
  }

  double _paceForIntent(String intent, int vdot) {
    final table = PaceTable(vdot.clamp(30, 85));
    final zone = switch (intent) {
      'threshold' => PaceZone.tempo,
      'vo2max' => PaceZone.vo2Intervals,
      'speed' => PaceZone.speedReps,
      'raceSpecific' => PaceZone.marathonPace,
      'endurance' => PaceZone.aerobicEasy,
      'recovery' => PaceZone.easyRecovery,
      _ => PaceZone.aerobicEasy,
    };
    return table.resolve(zone).targetPace.toDouble();
  }

  List<int> _defaultTrainingDays(int count, int longRunDay) {
    final result = <int>[longRunDay];
    final remaining = [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
    ].where((d) => d != longRunDay).toList();
    final step = remaining.length / (count - 1);
    for (int i = 0; i < count - 1; i++) {
      result.add(remaining[(i * step).round().clamp(0, remaining.length - 1)]);
    }
    return result..sort();
  }

  RaceDistance _mapGoalRace(String goalRace) => switch (goalRace) {
    '5k' => RaceDistance.fiveK,
    '10k' => RaceDistance.tenK,
    'half_marathon' => RaceDistance.halfMarathon,
    'marathon' => RaceDistance.marathon,
    _ => RaceDistance.fiveK,
  };

  double _prDistanceToKm(String d) => switch (d) {
    '5k' => 5.0,
    '10k' => 10.0,
    'half' => 21.0975,
    'marathon' => 42.195,
    _ => 5.0,
  };

  DateTime _nearestMonday(DateTime date) =>
      date.subtract(Duration(days: date.weekday - 1));

  double _fmt2(double v) => (v * 100).round() / 100;

  // ============================================================================
  // EXPECTED COMPOSITION HELPERS
  // ============================================================================

  // Cyclic-rank pattern: Q1 at rank 1, Q2 at rank 3.
  // Exception: if the rank-3 day is immediately before the LR day (offset +6),
  // it is protected to Easy — same pre-LR buffer rule as WeekResolver.
  int _expectedQualityCount5Day(SimPersona persona, List<int> trainingDays) {
    final lrDay = persona.longRunDayIndex;
    final remaining = trainingDays.where((d) => d != lrDay).toList()
      ..sort((a, b) => ((a - lrDay + 7) % 7).compareTo((b - lrDay + 7) % 7));
    if (remaining.length >= 4) {
      final rank3Offset = (remaining[3] - lrDay + 7) % 7;
      if (rank3Offset == 6) return 1;
    }
    return 2;
  }

  int _expectedEasyCount5Day(SimPersona persona, List<int> trainingDays) =>
      5 - 1 - _expectedQualityCount5Day(persona, trainingDays);

  // ============================================================================
  // AUDIT
  // ============================================================================

  List<String> _auditWeek({
    required int weekNum,
    required double targetKm,
    required double actualKm,
    required List<SimSessionLog> sessions,
    required bool isCutback,
    required TrainingPhase phase,
    required List<String> templateIds,
    required List<String> priorTemplateIds,
    required SimPersona persona,
    required List<int> trainingDays,
    double? previousWeekActualKm,
    double? resolvedEffectiveKm,
  }) {
    final warnings = <String>[];
    final completed = sessions.where((s) => !s.wasSkipped).toList();

    // ── Volume ────────────────────────────────────────────────────────────
    if (weekNum == 1 &&
        (actualKm - persona.weeklyKm).abs() > persona.weeklyKm * 0.20) {
      warnings.add(
        'VOLUME: Week 1 ${_fmt(actualKm)}km deviates >20% from baseline ${_fmt(persona.weeklyKm)}km',
      );
    }
    if (isCutback && previousWeekActualKm != null && previousWeekActualKm > 0) {
      // Use the engine's resolved effective km (post-0.70 multiplier) rather
      // than the floor-inflated actual total. Session floors (LR ≥ 8km) can
      // push actual above the cutback target even when the engine applied the
      // reduction correctly — that's expected and not a real warning.
      final volumeToCheck = resolvedEffectiveKm ?? actualKm;
      if (volumeToCheck > previousWeekActualKm * 0.80) {
        warnings.add(
          'CUTBACK: Volume ${_fmt(actualKm)}km not reduced enough vs prev week ${_fmt(previousWeekActualKm)}km (should be ≤80%)',
        );
      }
    }

    // ── Distribution ──────────────────────────────────────────────────────
    final total = completed.length;
    final qFrac = total == 0
        ? 0.0
        : completed.where((s) => _isQuality(s.intent)).length / total;
    if (qFrac > 0.40) {
      warnings.add(
        'DISTRIBUTION: Quality fraction ${_fmt(qFrac * 100)}% > 40%',
      );
    }
    if (!completed.any((s) => s.intent == 'endurance') &&
        total >= 3 &&
        phase != TrainingPhase.taper) {
      warnings.add('DISTRIBUTION: No long run this week');
    }

    // ── Template rotation ─────────────────────────────────────────────────
    for (final id in templateIds) {
      final template = WorkoutLibrary.byId(id);
      if (template == null) continue;
      if (template.intent == WorkoutIntent.aerobicBase) continue;
      // Ladder intents cycle by design — repeat within 2 weeks is expected.
      if (_ladderIntents.contains(template.intent.name)) continue;
      final poolSize = WorkoutLibrary.forSlot(
        intent: template.intent,
        raceDistance: _mapGoalRace(persona.goalRace),
        phase: phase,
      ).length;
      if (poolSize >= 3 && priorTemplateIds.contains(id)) {
        warnings.add('SELECTION: Template $id repeated within 2-week window');
      }
    }

    // ── Volume hog — exempt taper (long run naturally >40% of reduced week) ──
    if (actualKm > 0 && phase != TrainingPhase.taper) {
      for (final s in completed) {
        final volThreshold = persona.daysPerWeek <= 3
            ? 0.55
            : (persona.daysPerWeek <= 4 ? 0.50 : 0.40);
        if (s.actualKm / actualKm > volThreshold) {
          warnings.add(
            'DISTRIBUTION: ${s.intent} on ${_dayName(s.dayOfWeek)} is ${_fmt(s.actualKm / actualKm * 100)}% of week',
          );
        }
      }
    }

    // ── Phase-specific ────────────────────────────────────────────────────
    if (phase == TrainingPhase.base &&
        completed.any((s) => s.intent == 'raceSpecific')) {
      warnings.add('PACE: raceSpecific session in base phase');
    }

    // ── Structure checks ──────────────────────────────────────────────────

    // 1. L lands on the correct day
    final longRunSessions = completed
        .where((s) => s.intent == 'endurance')
        .toList();
    if (longRunSessions.isNotEmpty) {
      final lrActualDay = longRunSessions.first.dayOfWeek;
      if (lrActualDay != persona.longRunDayIndex) {
        warnings.add(
          'STRUCTURE: Long run on ${_dayName(lrActualDay)} '
          'but expected ${_dayName(persona.longRunDayIndex)} (longRunDayIndex=${persona.longRunDayIndex})',
        );
      }
    }

    // 2. No Q adjacent to L
    final lrDay = persona.longRunDayIndex;
    for (final s in completed) {
      if (!_isQuality(s.intent)) continue;
      final diff = (s.dayOfWeek - lrDay).abs();
      if (diff == 1) {
        warnings.add(
          'STRUCTURE: Quality ${s.intent} on ${_dayName(s.dayOfWeek)} '
          'is adjacent to long run day ${_dayName(lrDay)}',
        );
      }
    }

    // 3. No Q adjacent to Q
    final qualitySessions =
        completed.where((s) => _isQuality(s.intent)).toList()
          ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
    for (int i = 1; i < qualitySessions.length; i++) {
      final diff =
          qualitySessions[i].dayOfWeek - qualitySessions[i - 1].dayOfWeek;
      if (diff == 1) {
        warnings.add(
          'STRUCTURE: Quality sessions on '
          '${_dayName(qualitySessions[i - 1].dayOfWeek)} and '
          '${_dayName(qualitySessions[i].dayOfWeek)} are adjacent — no E buffer',
        );
      }
    }

    // 4. Composition correct — skip cutback and taper weeks
    if (!isCutback &&
        phase != TrainingPhase.taper &&
        longRunSessions.isNotEmpty) {
      final eCount = completed.where((s) => s.intent == 'aerobicBase').length;
      final qCount = completed.where((s) => _isQuality(s.intent)).length;
      final lCount = completed.where((s) => s.intent == 'endurance').length;

      final expected = switch (persona.daysPerWeek) {
        3 => (e: 1, q: 1, l: 1),
        4 => (e: 2, q: 1, l: 1),
        5 => (
          e: _expectedEasyCount5Day(persona, trainingDays),
          q: _expectedQualityCount5Day(persona, trainingDays),
          l: 1,
        ),
        6 => (e: 3, q: 2, l: 1),
        7 => (e: 4, q: 2, l: 1),
        _ => (e: 0, q: 0, l: 0),
      };

      if (eCount != expected.e ||
          qCount != expected.q ||
          lCount != expected.l) {
        warnings.add(
          'STRUCTURE: Composition E:$eCount Q:$qCount L:$lCount '
          '— expected E:${expected.e} Q:${expected.q} L:${expected.l} '
          'for ${persona.daysPerWeek}-day runner',
        );
      }
    }

    // 5. Cutback: Q1 retained, Q2 dropped
    if (isCutback && longRunSessions.isNotEmpty) {
      final qCount = completed.where((s) => _isQuality(s.intent)).length;
      if (qCount > 1) {
        warnings.add(
          'STRUCTURE: Cutback week has $qCount quality sessions — expected max 1',
        );
      }
      if (qCount == 0 && persona.daysPerWeek >= 3) {
        warnings.add(
          'STRUCTURE: Cutback week has 0 quality sessions — Q1 should be retained',
        );
      }
    }

    return warnings;
  }

  void _auditGlobal({
    required List<SimWeekLog> weeks,
    required SimPersona persona,
    required List<String> globalWarnings,
  }) {
    for (int i = 1; i < weeks.length; i++) {
      final prev = weeks[i - 1];
      final curr = weeks[i];
      if (prev.targetKm <= 0 || curr.isCutbackWeek || prev.isCutbackWeek) {
        continue;
      }
      final inc = (curr.targetKm - prev.targetKm) / prev.targetKm;
      if (inc > 0.12) {
        globalWarnings.add(
          'VOLUME: W${curr.weekNumber} jumped ${_fmt(inc * 100)}% — potential 10% rule violation',
        );
      }
    }
    for (final w in weeks) {
      if (w.weekNumber % 4 == 0 && !w.isCutbackWeek) {
        globalWarnings.add(
          'PROGRESSION: W${w.weekNumber} should be cutback (3:1 cycle)',
        );
      }
    }
    for (final w in weeks) {
      for (final s in w.sessions) {
        if ((s.vdotAfter - s.vdotBefore).abs() > 2) {
          globalWarnings.add(
            'VDOT: W${w.weekNumber} ${s.intent} jumped vDOT ${s.vdotBefore}→${s.vdotAfter}',
          );
        }
      }
    }
  }
}

// ============================================================================
// INTERNAL
// ============================================================================

class _SimSlot {
  final int dayOfWeek;
  final String intent;
  final String slotRole;
  final String? templateId;
  final double targetKm;
  final double prescribedPace;

  const _SimSlot({
    required this.dayOfWeek,
    required this.intent,
    required this.slotRole,
    required this.targetKm,
    required this.prescribedPace,
    this.templateId,
  });
}

bool _isQuality(String intent) =>
    intent == 'threshold' ||
    intent == 'vo2max' ||
    intent == 'speed' ||
    intent == 'raceSpecific';

// Ladder intents cycle by design — repeat within 2-week window is expected.
const _ladderIntents = {'endurance', 'threshold', 'vo2max', 'raceSpecific'};

String _dayName(int i) =>
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i.clamp(0, 6)];

String _fmt(double v) => v.toStringAsFixed(1);

String _fmtPace(double s) {
  if (s <= 0) return '--';
  return '${s ~/ 60}:${(s % 60).round().toString().padLeft(2, '0')}/km';
}
