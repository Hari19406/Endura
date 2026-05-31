/// WeekResolver — assigns a WorkoutIntent and template to every day of the week.
library;

import '../config/workout_template_library.dart';
import '../../models/training_phase.dart';
import '../../models/race_plan.dart';

enum SlotType { easy, quality1, quality2, longRun, rest }

class DaySlot {
  final int weekday;
  final SlotType slotType;
  final WorkoutIntent? intent;
  final String? templateId;
  final bool isRest;
  final String label;

  const DaySlot({
    required this.weekday,
    required this.slotType,
    this.intent,
    this.templateId,
    this.isRest = false,
    this.label = '',
  });

  bool get isTraining => !isRest;
  bool get isQuality =>
      intent == WorkoutIntent.vo2max ||
      intent == WorkoutIntent.threshold ||
      intent == WorkoutIntent.speed ||
      intent == WorkoutIntent.raceSpecific;
  bool get isLongRun => intent == WorkoutIntent.endurance;
  bool get isHard => isQuality || isLongRun;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String get dayName => _dayNames[weekday];

  @override
  String toString() => isRest
      ? '$dayName: REST'
      : '$dayName: ${intent?.name ?? "??"} [${templateId ?? "??"}] ($label)';
}

class WeekResolution {
  final List<DaySlot> days;
  final int weekNumber;
  final TrainingPhase phase;
  final double targetKm;
  final double weekPercentageSum;

  const WeekResolution({
    required this.days,
    required this.weekNumber,
    required this.phase,
    required this.targetKm,
    this.weekPercentageSum = 1.0,
  });

  DaySlot? slotFor(int weekday) {
    if (weekday < 0 || weekday > 6) return null;
    return days[weekday];
  }

  WorkoutIntent? intentForToday(DateTime now) {
    final slot = slotFor(now.weekday - 1);
    if (slot == null || slot.isRest) return null;
    return slot.intent;
  }

  String? templateIdForToday(DateTime now) {
    final slot = slotFor(now.weekday - 1);
    if (slot == null || slot.isRest) return null;
    return slot.templateId;
  }

  int get trainingDayCount => days.where((d) => d.isTraining).length;
  int get qualityCount => days.where((d) => d.isQuality).length;
  bool get hasLongRun => days.any((d) => d.isLongRun);

  List<String> get allTemplateIds =>
      days.where((d) => d.templateId != null).map((d) => d.templateId!).toList();
}

class WeekResolver {
  const WeekResolver();

  WeekResolution resolve({
    required WeekTarget weekTarget,
    required List<int> trainingDayIndices,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
    int? longRunDayIndex,
    int weekNumber = 1,
    List<String> recentTemplateIds = const [],
    bool isCutbackWeek = false,
  }) {
    final sorted = List<int>.from(trainingDayIndices)..sort();
    final n = sorted.length;

    if (n == 0) {
      return WeekResolution(
        days: List.generate(
          7,
          (i) => DaySlot(weekday: i, slotType: SlotType.rest, isRest: true, label: 'rest'),
        ),
        weekNumber: weekTarget.week,
        phase: phase,
        targetKm: weekTarget.targetKm,
        weekPercentageSum: 1.0,
      );
    }

    final lrDay = (longRunDayIndex != null && sorted.contains(longRunDayIndex))
        ? longRunDayIndex
        : sorted.last;

    final qualityIntents = _qualityIntents(raceDistance: raceDistance, phase: phase);
    final slotMap = _anchoredPattern(sorted: sorted, lrDay: lrDay, isCutbackWeek: isCutbackWeek);

    final slots = <DaySlot>[];

    for (int weekday = 0; weekday < 7; weekday++) {
      final slotType = slotMap[weekday] ?? SlotType.rest;

      if (slotType == SlotType.rest) {
        slots.add(DaySlot(weekday: weekday, slotType: SlotType.rest, isRest: true, label: 'rest'));
        continue;
      }

      final intent = _intentForSlot(slotType, qualityIntents);
      final templateId = _pickTemplate(
        intent: intent,
        slotType: slotType,
        raceDistance: raceDistance,
        phase: phase,
        weekNumber: weekNumber,
        recentTemplateIds: recentTemplateIds,
      );

      slots.add(DaySlot(
        weekday: weekday,
        slotType: slotType,
        intent: intent,
        templateId: templateId,
        label: _labelForSlot(slotType),
      ));
    }

    _log('WEEK RESOLVED', {
      'weekNumber': weekNumber,
      'phase': phase.name,
      'dayCount': n,
      'lrDay': lrDay,
      'isCutback': isCutbackWeek,
      'slots': slots
          .where((s) => s.isTraining)
          .map((s) => '${s.dayName}: ${s.intent?.name} [${s.templateId}]')
          .join(', '),
    });

    final weekPercentageSum = slots
        .where((s) => s.isTraining && s.templateId != null)
        .map((s) => WorkoutLibrary.byId(s.templateId!)?.recommendedPercentage ?? 0.0)
        .fold(0.0, (sum, p) => sum + p);

    return WeekResolution(
      days: slots,
      weekNumber: weekTarget.week,
      phase: phase,
      targetKm: weekTarget.targetKm,
      weekPercentageSum: weekPercentageSum > 0 ? weekPercentageSum : 1.0,
    );
  }

  Map<int, SlotType> _anchoredPattern({
    required List<int> sorted,
    required int lrDay,
    required bool isCutbackWeek,
  }) {
    final result = <int, SlotType>{};
    result[lrDay] = SlotType.longRun;

    final before = sorted.where((d) => d < lrDay).toList().reversed.toList();
    final after  = sorted.where((d) => d > lrDay).toList();

    final queue = <int>[];
    final maxLen = before.length > after.length ? before.length : after.length;
    for (int i = 0; i < maxLen; i++) {
      if (i < after.length)  queue.add(after[i]);
      if (i < before.length) queue.add(before[i]);
    }

    for (int pos = 0; pos < queue.length; pos++) {
      final day = queue[pos];
      SlotType slot;
      if (pos == 0 || pos == 1) {
        slot = SlotType.easy;
      } else if (pos == 2) {
        slot = SlotType.quality1;
      } else if (pos == 3) {
        slot = SlotType.easy;
      } else if (pos == 4) {
        slot = isCutbackWeek ? SlotType.easy : SlotType.quality2;
      } else {
        slot = SlotType.easy;
      }
      result[day] = slot;
    }

    return result;
  }

  ({WorkoutIntent q1, WorkoutIntent q2}) _qualityIntents({
    required RaceDistance raceDistance,
    required TrainingPhase phase,
  }) {
    if (phase == TrainingPhase.maintenance) {
      return (q1: WorkoutIntent.threshold, q2: WorkoutIntent.aerobicBase);
    }
    if (phase == TrainingPhase.base) {
      return (q1: WorkoutIntent.threshold, q2: WorkoutIntent.threshold);
    }
    if (phase == TrainingPhase.taper) {
      return (q1: WorkoutIntent.threshold, q2: WorkoutIntent.threshold);
    }
    return switch (raceDistance) {
      RaceDistance.fiveK        => (q1: WorkoutIntent.vo2max,     q2: WorkoutIntent.threshold),
      RaceDistance.tenK         => (q1: WorkoutIntent.vo2max,     q2: WorkoutIntent.threshold),
      RaceDistance.halfMarathon => (q1: WorkoutIntent.threshold,  q2: WorkoutIntent.vo2max),
      RaceDistance.marathon     => (q1: WorkoutIntent.threshold,  q2: WorkoutIntent.vo2max),
    };
  }

  WorkoutIntent _intentForSlot(
    SlotType slot,
    ({WorkoutIntent q1, WorkoutIntent q2}) qualityIntents,
  ) {
    return switch (slot) {
      SlotType.easy     => WorkoutIntent.aerobicBase,
      SlotType.quality1 => qualityIntents.q1,
      SlotType.quality2 => qualityIntents.q2,
      SlotType.longRun  => WorkoutIntent.endurance,
      SlotType.rest     => WorkoutIntent.recovery,
    };
  }

  String _labelForSlot(SlotType slot) {
    return switch (slot) {
      SlotType.easy     => 'easy',
      SlotType.quality1 => 'quality 1',
      SlotType.quality2 => 'quality 2',
      SlotType.longRun  => 'long run',
      SlotType.rest     => 'rest',
    };
  }

  String? _pickTemplate({
    required WorkoutIntent intent,
    required SlotType slotType,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
    required int weekNumber,
    required List<String> recentTemplateIds,
  }) {
    var candidates = WorkoutLibrary.forSlot(
      intent: intent,
      raceDistance: raceDistance,
      phase: phase,
    );

    if (candidates.isEmpty && phase == TrainingPhase.maintenance) {
      candidates = WorkoutLibrary.forSlot(
        intent: intent,
        raceDistance: raceDistance,
        phase: TrainingPhase.base,
      );
    }

    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first.id;

    final fresh = candidates.where((t) => !recentTemplateIds.contains(t.id)).toList();

    // ── DEBUG: log pool details for quality slots ─────────────────────────
    assert(() {
      if (intent != WorkoutIntent.aerobicBase && intent != WorkoutIntent.recovery) {
        // ignore: avoid_print
        print('[WeekResolver] TEMPLATE_POOL'
            '\n  week: $weekNumber'
            '\n  intent: ${intent.name}'
            '\n  phase: ${phase.name}'
            '\n  race: ${raceDistance.name}'
            '\n  pool(${candidates.length}): ${candidates.map((t) => t.id).join(', ')}'
            '\n  recent: ${recentTemplateIds.take(6).join(', ')}'
            '\n  fresh(${fresh.length}): ${fresh.map((t) => t.id).join(', ')}');
      }
      return true;
    }());

    if (fresh.isNotEmpty) {
      final seed = weekNumber * 7 + slotType.index;
      final picked = fresh[seed % fresh.length].id;
      assert(() {
        if (intent != WorkoutIntent.aerobicBase && intent != WorkoutIntent.recovery) {
          // ignore: avoid_print
          print('[WeekResolver]   → picked: $picked (seed=$seed, idx=${seed % fresh.length})');
        }
        return true;
      }());
      return picked;
    }

    // All templates used recently — pick the one used longest ago.
    final ranked = List<WorkoutTemplate>.from(candidates);
    ranked.sort((a, b) {
      final idxA = recentTemplateIds.indexOf(a.id);
      final idxB = recentTemplateIds.indexOf(b.id);
      if (idxA == -1) return -1;
      if (idxB == -1) return 1;
      return idxA.compareTo(idxB);
    });

    assert(() {
      if (intent != WorkoutIntent.aerobicBase && intent != WorkoutIntent.recovery) {
        // ignore: avoid_print
        print('[WeekResolver]   → ALL EXHAUSTED — picking least recent: ${ranked.first.id}');
      }
      return true;
    }());

    return ranked.first.id;
  }

  void _log(String tag, Map<String, dynamic> data) {
    assert(() {
      final entries = data.entries.map((e) => '  ${e.key}: ${e.value}').join('\n');
      // ignore: avoid_print
      print('[WeekResolver] $tag\n$entries');
      return true;
    }());
  }
}