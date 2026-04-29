import 'database_service.dart';

class RunHistory {
  final double distance;
  final String averagePace;
  final DateTime date;
  final List<Map<String, double>> gpsPoints;
  final int durationSeconds;
  final int? rpe;
  final String? workoutType;

  RunHistory({
    required this.distance,
    required this.averagePace,
    required this.date,
    required this.gpsPoints,
    this.durationSeconds = 0,
    this.rpe,
    this.workoutType,
  });

  Map<String, dynamic> toJson() => {
        'distance': distance,
        'averagePace': averagePace,
        'date': date.toIso8601String(),
        'gpsPoints': gpsPoints,
        'durationSeconds': durationSeconds,
        'rpe': rpe,
        'workoutType': workoutType,
      };

  factory RunHistory.fromJson(Map<String, dynamic> json) {
    List<Map<String, double>> points = [];
    if (json['gpsPoints'] != null) {
      points = (json['gpsPoints'] as List).map((point) {
        return {
          'lat': (point['lat'] as num).toDouble(),
          'lng': (point['lng'] as num).toDouble(),
        };
      }).toList();
    }

    return RunHistory(
      distance: (json['distance'] as num).toDouble(),
      averagePace: json['averagePace'] as String,
      date: DateTime.parse(json['date'] as String),
      gpsPoints: points,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      rpe: json['rpe'] as int?,
      workoutType: json['workoutType'] as String?,
    );
  }
}

class WeeklyStats {
  final double totalDistance;
  final String averagePace;
  final List<String> dailyAveragePaces;
  final int totalRuns;
  final DateTime startDate;
  final DateTime endDate;

  WeeklyStats({
    required this.totalDistance,
    required this.averagePace,
    required this.dailyAveragePaces,
    required this.totalRuns,
    required this.startDate,
    required this.endDate,
  });

  @override
  String toString() {
    return 'WeeklyStats(\n'
        '  totalDistance: ${totalDistance.toStringAsFixed(2)} km\n'
        '  averagePace: $averagePace /km\n'
        '  totalRuns: $totalRuns\n'
        '  dailyPaces: ${dailyAveragePaces.join(', ')}\n'
        '  period: ${startDate.toString().split(' ')[0]} to '
        '${endDate.toString().split(' ')[0]}\n'
        ')';
  }
}

// Filter runs from the last 7 days
List<RunHistory> filterLast7Days(List<RunHistory> allRuns) {
  final now = DateTime.now();
  final sevenDaysAgo = now.subtract(const Duration(days: 7));
  return allRuns.where((run) => run.date.isAfter(sevenDaysAgo)).toList();
}

// Convert pace string (mm:ss) to seconds
double paceToSeconds(String pace) {
  if (pace == '--:--' || pace.isEmpty) return double.infinity;
  try {
    final parts = pace.split(':');
    if (parts.length != 2) return double.infinity;
    final minutes = int.parse(parts[0]);
    final seconds = int.parse(parts[1]);
    return (minutes * 60 + seconds).toDouble();
  } catch (_) {
    return double.infinity;
  }
}

// Convert seconds to pace string (mm:ss)
String secondsToPace(double seconds) {
  if (seconds <= 0 || seconds.isInfinite || seconds.isNaN) return '--:--';
  if (seconds > 5999) return '99:59';
  final minutes = seconds ~/ 60;
  final secs = (seconds % 60).round();
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

// Calculate total distance
double calculateTotalDistance(List<RunHistory> runs) {
  if (runs.isEmpty) return 0.0;
  return runs.fold(0.0, (sum, run) => sum + run.distance);
}

// Calculate average pace from multiple runs
String calculateAveragePace(List<RunHistory> runs) {
  if (runs.isEmpty) return '--:--';
  double totalPaceSeconds = 0;
  int validRuns = 0;
  for (final run in runs) {
    final paceSeconds = paceToSeconds(run.averagePace);
    if (paceSeconds != double.infinity) {
      totalPaceSeconds += paceSeconds;
      validRuns++;
    }
  }
  if (validRuns == 0) return '--:--';
  return secondsToPace(totalPaceSeconds / validRuns);
}

// Get start of day (midnight) for a given date
DateTime getStartOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

// Calculate daily average paces for the last 7 days
List<String> calculateDailyAveragePaces(List<RunHistory> runs) {
  if (runs.isEmpty) return [];
  final Map<DateTime, List<RunHistory>> runsByDay = {};
  for (final run in runs) {
    final dayKey = getStartOfDay(run.date);
    runsByDay.putIfAbsent(dayKey, () => []).add(run);
  }
  final dailyPaces = runsByDay.entries
      .map((e) => MapEntry(e.key, calculateAveragePace(e.value)))
      .toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return dailyPaces.map((e) => e.value).toList();
}

// Main function: Get weekly statistics
Future<WeeklyStats> getWeeklyStats() async {
  final allRuns = await loadSavedRuns();
  final last7DaysRuns = filterLast7Days(allRuns);
  final now = DateTime.now();
  return WeeklyStats(
    totalDistance: calculateTotalDistance(last7DaysRuns),
    averagePace: calculateAveragePace(last7DaysRuns),
    dailyAveragePaces: calculateDailyAveragePaces(last7DaysRuns),
    totalRuns: last7DaysRuns.length,
    startDate: now.subtract(const Duration(days: 7)),
    endDate: now,
  );
}

// Alternative: Get weekly stats from already loaded runs
WeeklyStats getWeeklyStatsFromRuns(List<RunHistory> allRuns) {
  final last7DaysRuns = filterLast7Days(allRuns);
  final now = DateTime.now();
  return WeeklyStats(
    totalDistance: calculateTotalDistance(last7DaysRuns),
    averagePace: calculateAveragePace(last7DaysRuns),
    dailyAveragePaces: calculateDailyAveragePaces(last7DaysRuns),
    totalRuns: last7DaysRuns.length,
    startDate: now.subtract(const Duration(days: 7)),
    endDate: now,
  );
}