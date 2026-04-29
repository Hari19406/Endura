/// Run History Service
///
/// Provides the SavedRun model used across the app for persisted runs,
/// plus small pace-string helpers. Pace derivation goes through PaceTable
/// backed by the vDOT score stored in EngineMemory.
library;

// ============================================================================
// SAVED RUN MODEL
// ============================================================================

class SavedRun {
  final double distance;
  final String averagePace;
  final DateTime date;
  final List<Map<String, double>> gpsPoints;
  final int? rpe;
  final String? workoutType;

  SavedRun({
    required this.distance,
    required this.averagePace,
    required this.date,
    required this.gpsPoints,
    this.rpe,
    this.workoutType,
  });

  factory SavedRun.fromJson(Map<String, dynamic> json) {
    List<Map<String, double>> points = [];
    if (json['gpsPoints'] != null) {
      points = (json['gpsPoints'] as List).map((point) {
        return {
          'lat': (point['lat'] as num).toDouble(),
          'lng': (point['lng'] as num).toDouble(),
        };
      }).toList();
    }
    return SavedRun(
      distance: (json['distance'] as num).toDouble(),
      averagePace: json['averagePace'] as String,
      date: DateTime.parse(json['date'] as String),
      gpsPoints: points,
      rpe: json['rpe'] as int?,
      workoutType: json['workoutType'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'distance': distance,
        'averagePace': averagePace,
        'date': date.toIso8601String(),
        'gpsPoints': gpsPoints,
        'rpe': rpe,
        'workoutType': workoutType,
      };
}

// ============================================================================
// PACE STRING HELPERS
// ============================================================================

int paceStringToSeconds(String pace) {
  try {
    final parts = pace.split(':');
    if (parts.length != 2) return 0;
    final minutes = int.parse(parts[0]);
    final seconds = int.parse(parts[1]);
    return minutes * 60 + seconds;
  } catch (_) {
    return 0;
  }
}

String secondsToPaceString(int seconds) {
  final minutes = seconds ~/ 60;
  final secs = seconds % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}