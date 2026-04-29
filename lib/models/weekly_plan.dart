import 'workout_type.dart';

class PlannedDay {
  final DateTime date;
  final WorkoutType workoutType;
  final bool isRestDay;
  final bool isCompleted;
  final bool isSkipped;

  /// Set when a workout was moved here from a skip on another day.
  /// e.g. "Wednesday" means this workout was originally scheduled Wednesday.
  final String? movedFromDay;

  const PlannedDay({
    required this.date,
    required this.workoutType,
    this.isRestDay = false,
    this.isCompleted = false,
    this.isSkipped = false,
    this.movedFromDay,
  });

  /// Whether this day still needs to be done.
  bool get isPending => !isRestDay && !isCompleted && !isSkipped;

  PlannedDay copyWith({
    bool? isCompleted,
    bool? isSkipped,
    WorkoutType? workoutType,
    bool? isRestDay,
    String? movedFromDay,
  }) =>
      PlannedDay(
        date: date,
        workoutType: workoutType ?? this.workoutType,
        isRestDay: isRestDay ?? this.isRestDay,
        isCompleted: isCompleted ?? this.isCompleted,
        isSkipped: isSkipped ?? this.isSkipped,
        movedFromDay: movedFromDay ?? this.movedFromDay,
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'workoutType': workoutType.name,
        'isRestDay': isRestDay,
        'isCompleted': isCompleted,
        'isSkipped': isSkipped,
        if (movedFromDay != null) 'movedFromDay': movedFromDay,
      };

  factory PlannedDay.fromJson(Map<String, dynamic> j) => PlannedDay(
        date: DateTime.parse(j['date'] as String),
        workoutType: WorkoutTypeX.fromString(j['workoutType'] as String),
        isRestDay: j['isRestDay'] as bool? ?? false,
        isCompleted: j['isCompleted'] as bool? ?? false,
        isSkipped: j['isSkipped'] as bool? ?? false,
        movedFromDay: j['movedFromDay'] as String?,
      );
}

class WeeklyPlan {
  final DateTime weekStartDate;
  final List<PlannedDay> days;

  const WeeklyPlan({required this.weekStartDate, required this.days});

  WeeklyPlan withDayCompleted(DateTime runDate) {
    final updated = days.map((d) {
      if (d.date.year == runDate.year &&
          d.date.month == runDate.month &&
          d.date.day == runDate.day) {
        return d.copyWith(isCompleted: true);
      }
      return d;
    }).toList();
    return WeeklyPlan(weekStartDate: weekStartDate, days: updated);
  }

  /// Mark any planned training day that is in the past, not completed,
  /// and not already skipped as skipped. Call this at the start of
  /// loadData() before generating today's workout.
  ///
  /// [completedRunDates] — dates from the DB that have actual runs.
  /// This cross-checks so we don't mark a day as skipped if the user
  /// ran but the plan wasn't updated (e.g. crash before save).
  WeeklyPlan markMissedDays({
    DateTime? now,
    List<DateTime> completedRunDates = const [],
  }) {
    final today = now ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Build a set of dates that have actual runs for fast lookup.
    final ranDates = completedRunDates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    final updated = days.map((d) {
      final dayDate = DateTime(d.date.year, d.date.month, d.date.day);

      // Only process past days that are training days (not rest).
      if (dayDate.isBefore(todayDate) &&
          !d.isRestDay &&
          !d.isCompleted &&
          !d.isSkipped) {
        // Check if there's an actual run on this date.
        if (ranDates.contains(dayDate)) {
          // User ran but plan wasn't marked — fix it.
          return d.copyWith(isCompleted: true);
        }
        // No run found → mark as skipped.
        return d.copyWith(isSkipped: true);
      }
      return d;
    }).toList();

    return WeeklyPlan(weekStartDate: weekStartDate, days: updated);
  }

  /// Count of skipped (missed) workouts this week.
  int get skippedCount => days.where((d) => d.isSkipped).length;

  /// Count of completed workouts this week.
  int get completedCount => days.where((d) => d.isCompleted).length;

  /// Planned training days that are still pending (future, not done).
  List<PlannedDay> get pendingDays => days.where((d) => d.isPending).toList();

  /// Skipped quality sessions this week (tempo/interval not completed).
  int get skippedQualityCount => days
      .where((d) => d.isSkipped && d.workoutType.isQuality)
      .length;

  Map<String, dynamic> toJson() => {
        'weekStartDate': weekStartDate.toIso8601String(),
        'days': days.map((d) => d.toJson()).toList(),
      };

  factory WeeklyPlan.fromJson(Map<String, dynamic> j) => WeeklyPlan(
        weekStartDate:
            DateTime.tryParse('${j['weekStartDate'] ?? ''}') ?? DateTime.now(),
        days: (j['days'] is List)
            ? (j['days'] as List).map((d) {
                if (d is Map) {
                  return PlannedDay.fromJson(Map<String, dynamic>.from(d));
                }
                return null;
              }).whereType<PlannedDay>().toList()
            : const [],
      );
}