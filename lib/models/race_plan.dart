import 'training_phase.dart';

class WeekTarget {
  final int week;
  final double targetKm;
  final TrainingPhase phase;
  final int qualityCount;
  final bool hasLongRun;
  final double longRunKm;
  final String keySession;

  const WeekTarget({
    required this.week,
    required this.targetKm,
    required this.phase,
    required this.qualityCount,
    required this.hasLongRun,
    required this.longRunKm,
    required this.keySession,
  });

  WeekTarget copyWith({
    double? targetKm,
    TrainingPhase? phase,
    int? qualityCount,
    bool? hasLongRun,
    double? longRunKm,
    String? keySession,
  }) =>
      WeekTarget(
        week: week,
        targetKm: targetKm ?? this.targetKm,
        phase: phase ?? this.phase,
        qualityCount: qualityCount ?? this.qualityCount,
        hasLongRun: hasLongRun ?? this.hasLongRun,
        longRunKm: longRunKm ?? this.longRunKm,
        keySession: keySession ?? this.keySession,
      );

  WeekTarget copyWithTarget(double newTargetKm) => copyWith(targetKm: newTargetKm);

  Map<String, dynamic> toJson() => {
        'week': week,
        'targetKm': targetKm,
        'phase': phase.name,
        'qualityCount': qualityCount,
        'hasLongRun': hasLongRun,
        'longRunKm': longRunKm,
        'keySession': keySession,
      };

  factory WeekTarget.fromJson(Map<String, dynamic> j) => WeekTarget(
        week: (j['week'] as num).toInt(),
        targetKm: (j['targetKm'] as num).toDouble(),
        phase: TrainingPhase.values.firstWhere(
          (p) => p.name == j['phase'],
          orElse: () => TrainingPhase.base,
        ),
        qualityCount: (j['qualityCount'] as num).toInt(),
        hasLongRun: j['hasLongRun'] as bool,
        longRunKm: (j['longRunKm'] as num).toDouble(),
        keySession: j['keySession'] as String,
      );
}

class RacePlan {
  final String goalRace;
  final DateTime raceDate;
  final DateTime createdAt;
  final double startingWeeklyKm;
  final String experienceLevel;
  final List<WeekTarget> weeks;

  const RacePlan({
    required this.goalRace,
    required this.raceDate,
    required this.createdAt,
    required this.startingWeeklyKm,
    required this.experienceLevel,
    required this.weeks,
  });

  int get totalWeeks => weeks.length;

  WeekTarget? currentWeek(DateTime now) {
    final weekIndex = now.difference(createdAt).inDays ~/ 7;
    if (weekIndex < 0 || weekIndex >= weeks.length) return null;
    return weeks[weekIndex];
  }

  int currentWeekNumber(DateTime now) {
    final idx = now.difference(createdAt).inDays ~/ 7;
    return (idx + 1).clamp(1, weeks.length);
  }

  bool isComplete(DateTime now) => now.isAfter(raceDate);

  Map<String, dynamic> toJson() => {
        'goalRace': goalRace,
        'raceDate': raceDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'startingWeeklyKm': startingWeeklyKm,
        'experienceLevel': experienceLevel,
        'weeks': weeks.map((w) => w.toJson()).toList(),
      };

  factory RacePlan.fromJson(Map<String, dynamic> j) => RacePlan(
        goalRace: j['goalRace'] as String? ?? 'fitness',
        raceDate: DateTime.tryParse('${j['raceDate'] ?? ''}') ?? DateTime.now(),
        createdAt:
            DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now(),
        startingWeeklyKm: (j['startingWeeklyKm'] as num?)?.toDouble() ?? 0.0,
        experienceLevel: j['experienceLevel'] as String? ?? 'beginner',
        weeks: (j['weeks'] is List)
            ? (j['weeks'] as List).map((w) {
                if (w is Map) {
                  return WeekTarget.fromJson(Map<String, dynamic>.from(w));
                }
                return null;
              }).whereType<WeekTarget>().toList()
            : const [],
      );
}
