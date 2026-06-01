/// WeekResolver — assigns a WorkoutIntent and template to every day of the week,
/// then sizes each training slot (absorber model: quality read, long anchored,
/// easy absorbs the remainder).
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

  /// Sizes every training slot:
  ///   • quality  → intrinsic (interval block sum) or distance-driven (tempo)
  ///   • long run → race-specific % of weekly target, clamped to template range
  ///   • easy     → absorbs remainder, clamped to easy max; if capped, accept
  ///                the week total as-is (no overflow → long run)
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

      // Target the midpoint of the race-specific band.
      final bandMid = targetKm * (band.minFrac + band.maxFrac) / 2;
      longKm = bandMid;

      if (range != null) {
        longKm = longKm.clamp(range.minKm, range.maxKm);
      }
      longWeekday = s.weekday;
      break;
    }

    // 3. Easy slots → absorb remainder.
    //    If per-easy exceeds the cap, cap each easy run and accept the week
    //    total as a natural undershoot (no overflow into the long run).
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

      // Clamp to [min, max] and let the week total land wherever it lands.
      // Spec §6: ±2 km tolerance is fine — don't force 50.0 when 49 or 51
      // is what the arithmetic produces.
      // Spec §7: no overflow into the long run.
      perEasy = perEasy.clamp(easyMin, easyMax);

      for (final wd in easyWeekdays) {
        easyKm[wd] = perEasy;
      }
    } else if (remaining > 0 && longWeekday != null) {
      // No easy slots at all (very tight cutback with only quality + long).
      // Still don't push into long run — log and move on.
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

  /// Quality session distance.
  ///   • All-fixed interval template (no percentage blocks) → intrinsic block
  ///     sum, using experience-clamped reps (matches what WorkoutResolver runs).
  ///   • Has percentage blocks (continuous tempo, race simulation) →
  ///     distance-driven: recommendedPercentage × target, clamped to range.
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

  /// Sum of all fixed-distance blocks (warmup + reps×repDist + jog recoveries
  /// + cooldown), applying variant overrides and experience rep-clamping.
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

  /// Mirrors WorkoutResolver._clampRepsForExperience so sized distance matches
  /// the distance actually run. Keep the two in sync if the ratios change.
  int _clampReps(int reps, String level) => switch (level) {
        'beginner'     => (reps * 0.65).round().clamp(2, reps).toInt(),
        'intermediate' => (reps * 0.85).round().clamp(2, reps).toInt(),
        'advanced'     => reps,
        _              => (reps * 0.85).round().clamp(2, reps).toInt(),
      };

  /// Easy-run ceiling for the race, read from the easy_steady template range.
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