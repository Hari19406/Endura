/// PlanConfigState — the typed, immutable snapshot of everything the
/// periodized generator needs from intake.
///
/// Pure data: no engine calls, no persistence, no Flutter widget deps beyond
/// [RangeValues] (a plain value type). Onboarding and Settings each assemble
/// one of these and hand it to `RacePlanBuilder` / `PlanMaterializer`.
///
/// Volume bounds are sourced from [VolumeModel] — the single source of truth —
/// via [PlanConfigState.fromInputs]; callers should not invent their own.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show RangeValues;

import '../engines/config/archetype_table.dart' show ExperienceLevel;
import '../engines/config/volume_model.dart';
import '../engines/config/workout_template_library.dart' show RaceDistance;

/// The goal a plan is built around. Race distances taper to a date; [fitness]
/// and [consistency] periodize volume without a race target.
enum PlanGoalType {
  fiveK,
  tenK,
  half,
  marathon,
  fitness,
  consistency;

  /// The race distance this goal targets, or `null` for non-race goals.
  RaceDistance? get raceDistance => switch (this) {
    PlanGoalType.fiveK => RaceDistance.fiveK,
    PlanGoalType.tenK => RaceDistance.tenK,
    PlanGoalType.half => RaceDistance.halfMarathon,
    PlanGoalType.marathon => RaceDistance.marathon,
    PlanGoalType.fitness => null,
    PlanGoalType.consistency => null,
  };

  bool get isRace => raceDistance != null;

  /// Distance used for volume math even for non-race goals (fitness/consistency
  /// train like a 10 K block).
  RaceDistance get volumeReferenceDistance =>
      raceDistance ?? RaceDistance.tenK;

  /// The legacy `goal_race` string key used across the engine + prefs.
  String get goalRaceKey => switch (this) {
    PlanGoalType.fiveK => '5k',
    PlanGoalType.tenK => '10k',
    PlanGoalType.half => 'half_marathon',
    PlanGoalType.marathon => 'marathon',
    PlanGoalType.fitness => 'fitness',
    PlanGoalType.consistency => 'consistency',
  };

  static PlanGoalType fromGoalRaceKey(String key) => switch (key) {
    '5k' => PlanGoalType.fiveK,
    '10k' => PlanGoalType.tenK,
    'half_marathon' || 'half' => PlanGoalType.half,
    'marathon' => PlanGoalType.marathon,
    'consistency' || 'getting_started' => PlanGoalType.consistency,
    _ => PlanGoalType.fitness,
  };
}

@immutable
class PlanConfigState {
  /// Goal archetype (race distance, general fitness, or consistency).
  final PlanGoalType goalType;

  /// Self-reported training history, needed for volume + long-run bounds.
  final ExperienceLevel experience;

  /// Derived fitness from a benchmark race time (Daniels VDOT). Provisional
  /// 40 when the athlete supplies no time trial.
  final double vDOT;

  /// Sessions per week the athlete commits to. 2–7.
  final int runsPerWeek;

  /// Weekly volume band in km: `start` = floor (week-1 / gradual-start base),
  /// `end` = peak the macrocycle ramps toward. Backed by
  /// [VolumeModel.onboardingRange] + [VolumeModel.safeCapKm].
  final RangeValues weeklyVolumeRange;

  /// Long-run band in km: `start` = week-1 long run, `end` = peak long run.
  /// Backed by [VolumeModel.longRunRangeKm].
  final RangeValues longRunRange;

  /// Preferred long-run weekday. 1 = Monday … 7 = Sunday.
  final int longRunDay;

  /// Weekdays the athlete can run (1 = Mon … 7 = Sun). Its cardinality should
  /// match [runsPerWeek]; the generator honours the set, not the count, when
  /// they disagree.
  final Set<int> availableDays;

  /// Macrocycle length in weeks. 3–20. For race goals this is derived from the
  /// race date; for fitness/consistency it is chosen directly.
  final int durationWeeks;

  /// When true, weeks 1–4 start at ~75% of the volume floor and ramp smoothly
  /// back to it, easing an athlete in off a break.
  final bool gradualStart;

  PlanConfigState({
    required this.goalType,
    required this.experience,
    required this.vDOT,
    required this.runsPerWeek,
    required this.weeklyVolumeRange,
    required this.longRunRange,
    required this.longRunDay,
    required Set<int> availableDays,
    required this.durationWeeks,
    this.gradualStart = false,
  }) : availableDays = Set.unmodifiable(availableDays),
       assert(runsPerWeek >= 2 && runsPerWeek <= 7, 'runsPerWeek must be 2–7'),
       assert(
         durationWeeks >= 3 && durationWeeks <= 20,
         'durationWeeks must be 3–20',
       ),
       assert(longRunDay >= 1 && longRunDay <= 7, 'longRunDay must be 1–7'),
       assert(
         availableDays.isNotEmpty &&
             availableDays.every((d) => d >= 1 && d <= 7),
         'availableDays must be a non-empty subset of 1–7',
       );

  /// The gradual-start factor applied to a given plan week (1-based).
  /// Weeks 1–4 ramp 0.75 → 1.0; every later week is 1.0. Always 1.0 when
  /// [gradualStart] is off.
  double gradualStartFactorForWeek(int week) {
    if (!gradualStart || week >= 5) return 1.0;
    const base = 0.75;
    // week 1 → 0.75, week 2 → ~0.83, week 3 → ~0.92, week 4 → 1.0
    return base + (1.0 - base) * ((week - 1) / 4.0);
  }

  /// Effective volume floor once the gradual-start ease-in is applied.
  double volumeFloorForWeek(int week) =>
      weeklyVolumeRange.start * gradualStartFactorForWeek(week);

  /// Build a config from raw intake, sourcing every volume bound from
  /// [VolumeModel]. `peakWeeklyKmOverride` / `peakLongRunKmOverride` let an
  /// editable "how we built your plan" receipt feed user tweaks back in while
  /// still clamping to the safe cap.
  factory PlanConfigState.fromInputs({
    required PlanGoalType goalType,
    required ExperienceLevel experience,
    required double vDOT,
    required int runsPerWeek,
    required int longRunDay,
    required Set<int> availableDays,
    required int durationWeeks,
    bool gradualStart = false,
    double? currentWeeklyKm,
    double? peakWeeklyKmOverride,
    double? peakLongRunKmOverride,
  }) {
    final race = goalType.volumeReferenceDistance;
    final band = VolumeModel.onboardingRange(
      race: race,
      experience: experience,
      days: runsPerWeek,
    );
    final safeCap = VolumeModel.safeCapKm(race);
    final floor = (currentWeeklyKm ?? band.defaultKm).clamp(band.min, safeCap);
    final peak = (peakWeeklyKmOverride ?? band.max).clamp(floor, safeCap);

    final lr = VolumeModel.longRunRangeKm(race: race, experience: experience);
    final lrPeak = (peakLongRunKmOverride ?? lr.peak).clamp(lr.start, peak);

    return PlanConfigState(
      goalType: goalType,
      experience: experience,
      vDOT: vDOT,
      runsPerWeek: runsPerWeek,
      weeklyVolumeRange: RangeValues(
        floor.toDouble(),
        peak.toDouble(),
      ),
      longRunRange: RangeValues(lr.start, lrPeak.toDouble()),
      longRunDay: longRunDay,
      availableDays: availableDays,
      durationWeeks: durationWeeks,
      gradualStart: gradualStart,
    );
  }

  PlanConfigState copyWith({
    PlanGoalType? goalType,
    ExperienceLevel? experience,
    double? vDOT,
    int? runsPerWeek,
    RangeValues? weeklyVolumeRange,
    RangeValues? longRunRange,
    int? longRunDay,
    Set<int>? availableDays,
    int? durationWeeks,
    bool? gradualStart,
  }) => PlanConfigState(
    goalType: goalType ?? this.goalType,
    experience: experience ?? this.experience,
    vDOT: vDOT ?? this.vDOT,
    runsPerWeek: runsPerWeek ?? this.runsPerWeek,
    weeklyVolumeRange: weeklyVolumeRange ?? this.weeklyVolumeRange,
    longRunRange: longRunRange ?? this.longRunRange,
    longRunDay: longRunDay ?? this.longRunDay,
    availableDays: availableDays ?? this.availableDays,
    durationWeeks: durationWeeks ?? this.durationWeeks,
    gradualStart: gradualStart ?? this.gradualStart,
  );

  /// Stable hash of the plan-defining inputs. A change here means any
  /// materialised plan built from the old value is stale.
  String get fingerprint => [
    goalType.name,
    experience.name,
    vDOT.toStringAsFixed(1),
    runsPerWeek,
    weeklyVolumeRange.start.toStringAsFixed(1),
    weeklyVolumeRange.end.toStringAsFixed(1),
    longRunRange.start.toStringAsFixed(1),
    longRunRange.end.toStringAsFixed(1),
    longRunDay,
    (availableDays.toList()..sort()).join(','),
    durationWeeks,
    gradualStart,
  ].join('|');

  Map<String, dynamic> toJson() => {
    'goalType': goalType.name,
    'experience': experience.name,
    'vDOT': vDOT,
    'runsPerWeek': runsPerWeek,
    'weeklyVolumeRange': [weeklyVolumeRange.start, weeklyVolumeRange.end],
    'longRunRange': [longRunRange.start, longRunRange.end],
    'longRunDay': longRunDay,
    'availableDays': availableDays.toList()..sort(),
    'durationWeeks': durationWeeks,
    'gradualStart': gradualStart,
  };

  factory PlanConfigState.fromJson(Map<String, dynamic> j) {
    RangeValues range(dynamic raw) {
      final list = (raw as List).map((e) => (e as num).toDouble()).toList();
      return RangeValues(list[0], list[1]);
    }

    return PlanConfigState(
      goalType: PlanGoalType.values.firstWhere(
        (e) => e.name == j['goalType'],
        orElse: () => PlanGoalType.fitness,
      ),
      experience: ExperienceLevel.values.firstWhere(
        (e) => e.name == j['experience'],
        orElse: () => ExperienceLevel.beginner,
      ),
      vDOT: (j['vDOT'] as num).toDouble(),
      runsPerWeek: (j['runsPerWeek'] as num).toInt(),
      weeklyVolumeRange: range(j['weeklyVolumeRange']),
      longRunRange: range(j['longRunRange']),
      longRunDay: (j['longRunDay'] as num).toInt(),
      availableDays: (j['availableDays'] as List)
          .map((e) => (e as num).toInt())
          .toSet(),
      durationWeeks: (j['durationWeeks'] as num).toInt(),
      gradualStart: j['gradualStart'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlanConfigState && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;

  @override
  String toString() => 'PlanConfigState(${fingerprint.replaceAll('|', ', ')})';
}
