/// WeekResolver — assigns a WorkoutIntent and template to every day of the week,
/// then sizes each training slot (absorber model: quality read, long anchored,
/// easy absorbs the remainder).
///
/// CHANGE (V1 Adaptation System): ladder-aware template selection.
///   _pickTemplate now reads ladderPositions from EngineMemory to select the
///   appropriate rung of the threshold / VO2 / raceSpecific ladder instead of
///   pure rotation-seed picking.
///
/// Ladders (index 0 = easiest):
///   threshold:    [cruise_intervals_400, cruise_intervals_800,
///                  cruise_intervals_mile, tempo_continuous]
///   vo2max:       [vo2_600, vo2_classic, vo2_1000]
///   raceSpecific: [race_gp_intervals, race_simulation, race_dress_rehearsal]
///
/// Non-ladder intents (aerobicBase, endurance, speed, recovery) continue to
/// use rotation-seed picking — they have no meaningful progression ordering.
///
/// Ladder index is clamped to the available candidates for the current
/// race/phase context, so a high stored index never causes an out-of-bounds
/// or picks a template that isn't applicable.
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

  /// Total session distance in km, sized by WeekResolver's absorber pass.
  /// Null until sizing runs (e.g. rest days, or pre-sizing construction).
  final double? distanceKm;

  const DaySlot({
    required this.weekday,
    required this.slotType,
    this.intent,
    this.templateId,
    this.isRest = false,
    this.label = '',
    this.distanceKm,
  });

  /// Returns a copy of this slot with [km] as its sized distance.
  DaySlot withDistance(double km) => DaySlot(
        weekday: weekday,
        slotType: slotType,
        intent: intent,
        templateId: templateId,
        isRest: isRest,
        label: label,
        distanceKm: km,
      );

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

// ============================================================================
// LADDER DEFINITIONS
// ============================================================================

/// Ordered template ids for each ladder, index 0 = easiest rung.
/// Only intents with a meaningful progression order have a ladder.
/// Other intents (aerobicBase, endurance, speed, recovery) use rotation.
const Map<WorkoutIntent, List<String>> _ladderTemplateIds = {
  WorkoutIntent.threshold: [
    'cruise_intervals_400',
    'cruise_intervals_800',
    'cruise_intervals_mile',
    'tempo_continuous',
  ],
  WorkoutIntent.vo2max: [
    'vo2_600',
    'vo2_classic',
    'vo2_1000',
  ],
  WorkoutIntent.raceSpecific: [
    'race_gp_intervals',
    'race_simulation',
    'race_dress_rehearsal',
  ],
};

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
    String experienceLevel = 'intermediate',
    // Ladder positions from EngineMemory.ladderPositions.
    // Key = WorkoutIntent.name, value = current rung index (0-based).
    Map<String, int> ladderPositions = const {},
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
        ladderPositions: ladderPositions,
      );

      slots.add(DaySlot(
        weekday: weekday,
        slotType: slotType,
        intent: intent,
        templateId: templateId,
        label: _labelForSlot(slotType),
      ));
    }

    // ── Absorber sizing: quality read, long anchored, easy absorbs ───────
    final sized = _sizeWeek(
      slots: slots,
      weekTarget: weekTarget,
      raceDistance: raceDistance,
      phase: phase,
      experienceLevel: experienceLevel,
    );
    slots
      ..clear()
      ..addAll(sized);

    _log('WEEK RESOLVED', {
      'weekNumber': weekNumber,
      'phase': phase.name,
      'dayCount': n,
      'lrDay': lrDay,
      'isCutback': isCutbackWeek,
      'slots': slots
          .where((s) => s.isTraining)
          .map((s) =>
              '${s.dayName}: ${s.intent?.name} [${s.templateId}] '
              '${s.distanceKm?.toStringAsFixed(1) ?? "?"}km')
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

  // ========================================================================
  // ABSORBER SIZING
  // ========================================================================

  /// Race-specific long run percentage bands.
  /// Returns (minFraction, maxFraction) of weekly target.
  ({double minFrac, double maxFrac}) _longRunBand(RaceDistance race) =>
      switch (race) {
        RaceDistance.fiveK        => (minFrac: 0.20, maxFrac: 0.25),
        RaceDistance.tenK         => (minFrac: 0.25, maxFrac: 0.30),
        RaceDistance.halfMarathon => (minFrac: 0.30, maxFrac: 0.35),
        RaceDistance.marathon     => (minFrac: 0.35, maxFrac: 0.40),
      };

  List<DaySlot> _sizeWeek({
    required List<DaySlot> slots,
    required WeekTarget weekTarget,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
    required String experienceLevel,
  }) {
    final targetKm = weekTarget.targetKm;

    // 1. Quality slots → read their intrinsic distance.
    final qualityKm = <int, double>{};
    var qualityTotal = 0.0;
    for (final s in slots) {
      if (!s.isTraining || s.templateId == null) continue;
      if (s.slotType != SlotType.quality1 && s.slotType != SlotType.quality2) continue;
      final t = WorkoutLibrary.byId(s.templateId!);
      if (t == null) continue;
      final variant = WorkoutLibrary.getVariant(t, phase);
      final km = _measureQualityKm(
        template: t,
        variant: variant,
        raceDistance: raceDistance,
        targetKm: targetKm,
        experienceLevel: experienceLevel,
      );
      qualityKm[s.weekday] = km;
      qualityTotal += km;
    }

    // 2. Long run → race-specific % band, clamped to template range.
    int? longWeekday;
    var longKm = 0.0;
    for (final s in slots) {
      if (s.slotType != SlotType.longRun || s.templateId == null) continue;
      final t = WorkoutLibrary.byId(s.templateId!);
      final range = t?.distanceByRace[raceDistance];
      final band = _longRunBand(raceDistance);

      final bandMid = targetKm * (band.minFrac + band.maxFrac) / 2;
      longKm = bandMid;

      if (range != null) {
        longKm = longKm.clamp(range.minKm, range.maxKm);
      }
      longWeekday = s.weekday;
      break;
    }

    // 3. Easy slots → absorb remainder.
    final easyWeekdays = slots
        .where((s) =>
            s.isTraining &&
            s.slotType == SlotType.easy &&
            s.templateId != null)
        .map((s) => s.weekday)
        .toList();

    var remaining = targetKm - qualityTotal - longKm;
    if (remaining < 0) remaining = 0;

    final easyKm = <int, double>{};
    if (easyWeekdays.isNotEmpty) {
      final easyMax = _easyMaxKm(raceDistance);
      const easyMin = 3.0;
      var perEasy = remaining / easyWeekdays.length;
      perEasy = perEasy.clamp(easyMin, easyMax);

      for (final wd in easyWeekdays) {
        easyKm[wd] = perEasy;
      }
    } else if (remaining > 0 && longWeekday != null) {
      _log('NO EASY SLOTS', {
        'remainingKm': remaining.toStringAsFixed(1),
        'note': 'week total will undershoot target — no easy days to absorb',
      });
    }

    // 4. Rebuild slots with rounded distances.
    return slots.map((s) {
      if (!s.isTraining) return s;
      double? km;
      if (qualityKm.containsKey(s.weekday)) {
        km = qualityKm[s.weekday];
      } else if (s.weekday == longWeekday) {
        km = longKm;
      } else if (easyKm.containsKey(s.weekday)) {
        km = easyKm[s.weekday];
      }
      if (km == null) return s;
      return s.withDistance((km * 2).round() / 2);
    }).toList();
  }

  double _measureQualityKm({
    required WorkoutTemplate template,
    required PhaseVariant? variant,
    required RaceDistance raceDistance,
    required double targetKm,
    required String experienceLevel,
  }) {
    final percentSum = template.blocks
        .where((b) => b.durationType == DurationType.percentage)
        .fold(0.0, (sum, b) => sum + b.value);
    final range = template.distanceByRace[raceDistance];

    if (percentSum <= 0) {
      final km = _fixedBlockDistanceKm(template, variant, experienceLevel);
      return range != null ? km.clamp(range.minKm, range.maxKm) : km;
    }

    var km = targetKm * template.recommendedPercentage;
    if (variant != null) km *= variant.volumeMultiplier;
    return range != null ? km.clamp(range.minKm, range.maxKm) : km;
  }

  double _fixedBlockDistanceKm(
    WorkoutTemplate template,
    PhaseVariant? variant,
    String experienceLevel,
  ) {
    var total = 0.0;
    for (final block in template.blocks) {
      if (block.durationType == DurationType.percentage) continue;

      double blockKm;
      if (block.type == BlockType.main && variant?.repDistanceKm != null) {
        blockKm = variant!.repDistanceKm!;
      } else if (block.type == BlockType.main &&
          variant?.repDistanceMeters != null) {
        blockKm = variant!.repDistanceMeters! / 1000.0;
      } else {
        blockKm = block.value;
      }

      var reps = (block.reps != null) ? (variant?.reps ?? block.reps!) : 1;
      if (block.reps != null) reps = _clampReps(reps, experienceLevel);

      total += blockKm * reps;

      if (block.recoveryMeters != null && reps > 1) {
        final recKm =
            (variant?.recoveryMeters ?? block.recoveryMeters!) / 1000.0;
        total += recKm * (reps - 1);
      }
    }
    return total;
  }

  int _clampReps(int reps, String level) => switch (level) {
        'beginner'     => (reps * 0.65).round().clamp(2, reps).toInt(),
        'intermediate' => (reps * 0.85).round().clamp(2, reps).toInt(),
        'advanced'     => reps,
        _              => (reps * 0.85).round().clamp(2, reps).toInt(),
      };

  double _easyMaxKm(RaceDistance race) {
    final t = WorkoutLibrary.byId('easy_steady');
    return t?.distanceByRace[race]?.maxKm ?? 10.0;
  }

  // ========================================================================
  // SLOT PATTERN + INTENT
  // ========================================================================

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
      RaceDistance.fiveK        => (q1: WorkoutIntent.vo2max,    q2: WorkoutIntent.threshold),
      RaceDistance.tenK         => (q1: WorkoutIntent.vo2max,    q2: WorkoutIntent.threshold),
      RaceDistance.halfMarathon => (q1: WorkoutIntent.threshold, q2: WorkoutIntent.vo2max),
      RaceDistance.marathon     => (q1: WorkoutIntent.threshold, q2: WorkoutIntent.vo2max),
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

  // ========================================================================
  // TEMPLATE PICKING — LADDER-AWARE
  // ========================================================================

  String? _pickTemplate({
    required WorkoutIntent intent,
    required SlotType slotType,
    required RaceDistance raceDistance,
    required TrainingPhase phase,
    required int weekNumber,
    required List<String> recentTemplateIds,
    required Map<String, int> ladderPositions,
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

    // ── Ladder-aware picking for intents that have a defined ladder ───────
    final ladder = _ladderTemplateIds[intent];
    if (ladder != null) {
      return _pickFromLadder(
        ladder: ladder,
        candidates: candidates,
        ladderPositions: ladderPositions,
        intent: intent,
        phase: phase,
        raceDistance: raceDistance,
      );
    }

    // ── Rotation-seed picking for non-ladder intents ──────────────────────
    return _pickByRotation(
      candidates: candidates,
      recentTemplateIds: recentTemplateIds,
      weekNumber: weekNumber,
      slotType: slotType,
      intent: intent,
    );
  }

  /// Pick the template at the stored ladder rung, clamped to the candidates
  /// actually available for this race/phase context.
  ///
  /// Example: stored index = 3 (tempo_continuous), but tempo_continuous is
  /// not in candidates for this phase → clamp to highest available rung.
  String _pickFromLadder({
    required List<String> ladder,
    required List<WorkoutTemplate> candidates,
    required Map<String, int> ladderPositions,
    required WorkoutIntent intent,
    required TrainingPhase phase,
    required RaceDistance raceDistance,
  }) {
    // Build an ordered list of candidate ids that appear in the ladder,
    // preserving ladder order.
    final candidateIds = candidates.map((t) => t.id).toSet();
    final orderedRungs = ladder.where((id) => candidateIds.contains(id)).toList();

    if (orderedRungs.isEmpty) {
      // No ladder templates available — fall back to first candidate.
      return candidates.first.id;
    }

    // Read stored position, clamp to available rungs.
    final storedIndex = ladderPositions[intent.name] ?? 0;
    final clampedIndex = storedIndex.clamp(0, orderedRungs.length - 1);
    final picked = orderedRungs[clampedIndex];

    assert(() {
      // ignore: avoid_print
      print('[WeekResolver] LADDER_PICK'
          '\n  intent: ${intent.name}'
          '\n  phase: ${phase.name}'
          '\n  race: ${raceDistance.name}'
          '\n  storedIndex: $storedIndex'
          '\n  clampedIndex: $clampedIndex'
          '\n  orderedRungs: $orderedRungs'
          '\n  → picked: $picked');
      return true;
    }());

    return picked;
  }

  /// Rotation-seed picking — used for non-ladder intents (aerobicBase,
  /// endurance, speed, recovery) where there's no progression ordering.
  String _pickByRotation({
    required List<WorkoutTemplate> candidates,
    required List<String> recentTemplateIds,
    required int weekNumber,
    required SlotType slotType,
    required WorkoutIntent intent,
  }) {
    final fresh = candidates.where((t) => !recentTemplateIds.contains(t.id)).toList();

    assert(() {
      if (intent != WorkoutIntent.aerobicBase && intent != WorkoutIntent.recovery) {
        // ignore: avoid_print
        print('[WeekResolver] ROTATION_POOL'
            '\n  intent: ${intent.name}'
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
          print('[WeekResolver]   → picked: $picked (seed=$seed)');
        }
        return true;
      }());
      return picked;
    }

    // All used recently — pick least recently used.
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