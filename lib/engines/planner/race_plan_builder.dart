import 'dart:math';
import '../../models/race_plan.dart';
import '../../models/training_phase.dart';

class RacePlanBuilder {
  static RacePlan build({
    required double currentWeeklyKm,
    required String goalRace,
    required DateTime raceDate,
    required String experienceLevel,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final weeksOut = max(1, raceDate.difference(today).inDays ~/ 7);

    if (weeksOut < 4) {
      return _buildMinimalPlan(
        currentWeeklyKm: currentWeeklyKm, 
        goalRace: goalRace,
        raceDate: raceDate,
        experienceLevel: experienceLevel,
        weeksOut: weeksOut,
        today: today,
      );
    }

    final taperWeeks = _taperWeeksFor(goalRace);
    final peakVolume = _peakVolume(goalRace, experienceLevel, currentWeeklyKm);
    final buildWeeks = weeksOut - taperWeeks;

    final rawIncrement = (peakVolume - currentWeeklyKm) / max(1, buildWeeks);
    final maxIncrement = currentWeeklyKm * 0.10;
    final safeIncrement = rawIncrement.clamp(-5.0, max(1.5, maxIncrement));

    final peakLongRunKm = _peakLongRunKm(goalRace, experienceLevel);
    final currentLongRunKm = max(5.0, currentWeeklyKm * 0.30);
    final longRunIncrement =
        (peakLongRunKm - currentLongRunKm) / max(1, buildWeeks);
    final safeLongRunIncrement =
        longRunIncrement.clamp(-2.0, currentLongRunKm * 0.10);

    final weeks = <WeekTarget>[];
    var volume = currentWeeklyKm;
    var longRunKm = currentLongRunKm;

    for (var w = 1; w <= weeksOut; w++) {
      final phase = _phaseFor(w, weeksOut, taperWeeks);

      if ((phase == TrainingPhase.base || phase == TrainingPhase.build) &&
          w % 4 == 0) {
        weeks.add(_buildWeek(
          week: w,
          targetKm: volume * 0.70,
          phase: phase,
          goalRace: goalRace,
          experienceLevel: experienceLevel,
          longRunKm: longRunKm * 0.75,
          isDeload: true,
        ));
        continue;
      }

      if (phase == TrainingPhase.taper) {
        final taperWeek = w - (weeksOut - taperWeeks);
        final taperFactor = 1.0 - (taperWeek * (0.5 / max(1, taperWeeks)));
        final taperVolume = peakVolume * taperFactor.clamp(0.4, 1.0);
        final taperLongRun =
            (peakLongRunKm * (taperFactor + 0.1).clamp(0.5, 0.8));
        weeks.add(_buildWeek(
          week: w,
          targetKm: taperVolume,
          phase: phase,
          goalRace: goalRace,
          experienceLevel: experienceLevel,
          longRunKm: taperLongRun,
          isDeload: false,
        ));
        continue;
      }

      volume = (volume + safeIncrement).clamp(
        currentWeeklyKm * 0.5,
        peakVolume,
      );
      longRunKm = (longRunKm + safeLongRunIncrement).clamp(
        5.0,
        peakLongRunKm,
      );

      weeks.add(_buildWeek(
        week: w,
        targetKm: volume,
        phase: phase,
        goalRace: goalRace,
        experienceLevel: experienceLevel,
        longRunKm: longRunKm,
        isDeload: false,
      ));
    }

    return RacePlan(
      goalRace: goalRace,
      raceDate: raceDate,
      createdAt: today,
      startingWeeklyKm: currentWeeklyKm,
      experienceLevel: experienceLevel,
      weeks: weeks,
    );
  }

  static WeekTarget exploreTarget({
    required double fourWeekAvgKm,
    required String experienceLevel,
  }) {
    final target = fourWeekAvgKm <= 0 ? 15.0 : fourWeekAvgKm;
    final longRunKm = max(5.0, target * 0.30);
    return WeekTarget(
      week: 1,
      targetKm: target,
      phase: TrainingPhase.base,
      qualityCount: experienceLevel == 'beginner' ? 0 : 1,
      hasLongRun: fourWeekAvgKm >= 10.0,
      longRunKm: longRunKm,
      keySession: experienceLevel == 'beginner' ? 'easy' : 'tempo',
    );
  }

  static WeekTarget _buildWeek({
    required int week,
    required double targetKm,
    required TrainingPhase phase,
    required String goalRace,
    required String experienceLevel,
    required double longRunKm,
    required bool isDeload,
  }) {
    final qualityCount = _qualityCount(phase, experienceLevel, isDeload);
    final hasLongRun = _shouldHaveLongRun(phase, goalRace, isDeload);
    final keySession = _keySession(phase, goalRace);
    final adjustedLongRun = hasLongRun ? _roundHalf(longRunKm) : 0.0;

    return WeekTarget(
      week: week,
      targetKm: _roundHalf(targetKm),
      phase: phase,
      qualityCount: qualityCount,
      hasLongRun: hasLongRun,
      longRunKm: adjustedLongRun,
      keySession: keySession,
    );
  }

  static int _qualityCount(
      TrainingPhase phase, String level, bool isDeload) {
    if (isDeload) return phase == TrainingPhase.build ? 1 : 0;
    return switch (phase) {
      TrainingPhase.base => level == 'advanced' ? 1 : 0,
      TrainingPhase.build => level == 'beginner' ? 1 : 2,
      TrainingPhase.peak => 2,
      TrainingPhase.taper => 1,
    };
  }

  static bool _shouldHaveLongRun(
      TrainingPhase phase, String goalRace, bool isDeload) {
    if (isDeload) return false;
    if (phase == TrainingPhase.taper) {
      return goalRace == 'half_marathon' || goalRace == 'marathon';
    }
    return true;
  }

  static String _keySession(TrainingPhase phase, String goalRace) {
    return switch (phase) {
      TrainingPhase.base => 'easy',
      TrainingPhase.build => switch (goalRace) {
          '5k' || '10k' => 'intervals',
          _ => 'tempo',
        },
      TrainingPhase.peak => switch (goalRace) {
          '5k' => 'intervals',
          '10k' => 'tempo',
          _ => 'race_pace',
        },
      TrainingPhase.taper => 'easy',
    };
  }

  static double _peakVolume(String race, String level, double current) {
    final minimums = {
      '5k': {'beginner': 25.0, 'intermediate': 40.0, 'advanced': 55.0},
      '10k': {'beginner': 30.0, 'intermediate': 50.0, 'advanced': 70.0},
      'half_marathon': {
        'beginner': 40.0,
        'intermediate': 55.0,
        'advanced': 80.0,
      },
      'marathon': {
        'beginner': 50.0,
        'intermediate': 70.0,
        'advanced': 110.0,
      },
    };
    final floor = minimums[race]?[level] ?? 30.0;
    return max(floor, current * 1.20);
  }

  static double _peakLongRunKm(String race, String level) {
    return switch (race) {
      '5k' => switch (level) {
          'advanced' => 12.0,
          'intermediate' => 10.0,
          _ => 8.0,
        },
      '10k' => switch (level) {
          'advanced' => 16.0,
          'intermediate' => 14.0,
          _ => 10.0,
        },
      'half_marathon' => switch (level) {
          'advanced' => 24.0,
          'intermediate' => 20.0,
          _ => 16.0,
        },
      'marathon' => switch (level) {
          'advanced' => 35.0,
          'intermediate' => 32.0,
          _ => 28.0,
        },
      _ => 12.0,
    };
  }

  static int _taperWeeksFor(String race) => switch (race) {
        '5k' => 1,
        '10k' => 1,
        'half_marathon' => 2,
        'marathon' => 3,
        _ => 1,
      };

  static TrainingPhase _phaseFor(int week, int total, int taperWeeks) {
    if (week > total - taperWeeks) return TrainingPhase.taper;
    final buildStart = ((total - taperWeeks) * 0.4).ceil();
    if (week <= buildStart) return TrainingPhase.base;
    final peakStart = total - taperWeeks - 1;
    if (week >= peakStart) return TrainingPhase.peak;
    return TrainingPhase.build;
  }

  static RacePlan _buildMinimalPlan({
    required double currentWeeklyKm,
    required String goalRace,
    required DateTime raceDate,
    required String experienceLevel,
    required int weeksOut,
    required DateTime today,
  }) {
    final weeks = List.generate(weeksOut, (i) {
      final isTaper = i == weeksOut - 1 && weeksOut > 1;
      return WeekTarget(
        week: i + 1,
        targetKm: isTaper ? currentWeeklyKm * 0.70 : currentWeeklyKm,
        phase: isTaper ? TrainingPhase.taper : TrainingPhase.build,
        qualityCount: isTaper ? 1 : 2,
        hasLongRun: !isTaper,
        longRunKm: isTaper ? 0.0 : max(5.0, currentWeeklyKm * 0.30),
        keySession: isTaper ? 'easy' : 'tempo',
      );
    });
    return RacePlan(
      goalRace: goalRace,
      raceDate: raceDate,
      createdAt: today,
      startingWeeklyKm: currentWeeklyKm,
      experienceLevel: experienceLevel,
      weeks: weeks,
    );
  }

  static double _roundHalf(double v) => (v * 2).round() / 2;
}
