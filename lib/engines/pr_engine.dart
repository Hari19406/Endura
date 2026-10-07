import '../services/best_efforts_service.dart';
import '../utils/database_service.dart' show BestEffortRecord;

class Run {
  final double distanceKm;
  final int durationSeconds;
  final DateTime date;

  Run({
    required this.distanceKm,
    required this.durationSeconds,
    required this.date,
  });

  double get paceSecPerKm {
    if (distanceKm == 0 || durationSeconds == 0) return 0;
    return durationSeconds / distanceKm;
  }
}

class PREntry {
  final String label;
  final String value;
  final String? unit;
  final DateTime? setOn;

  const PREntry({
    required this.label,
    required this.value,
    this.unit,
    this.setOn,
  });
}

class PRResults {
  final PREntry? best5K;
  final PREntry? best10K;
  final PREntry? bestHalf;
  final PREntry? bestMarathon;
  final PREntry bestAvgPace;
  final PREntry longestRun;

  PRResults({
    this.best5K,
    this.best10K,
    this.bestHalf,
    this.bestMarathon,
    required this.bestAvgPace,
    required this.longestRun,
  });

  List<PREntry> get allEntries => [
    if (best5K != null) best5K!,
    if (best10K != null) best10K!,
    if (bestHalf != null) bestHalf!,
    if (bestMarathon != null) bestMarathon!,
    bestAvgPace,
    longestRun,
  ];
}

class PREngine {
  final List<Run> runs;

  /// The athlete's #1 Best Effort per standard distance (see
  /// `DatabaseService.getAllCategoryPRs`). This is the ONE source for the 5K /
  /// 10K / half / marathon records, so they always agree with the Best Efforts
  /// screens. Whole-run metrics (longest run, best average pace) still come
  /// from [runs].
  final Map<DistanceCategory, BestEffortRecord> bestEfforts;

  PREngine(this.runs, {this.bestEfforts = const {}});

  String _formatTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  String _formatPace(double secPerKm) {
    if (secPerKm <= 0) return '--:--';
    final mins = (secPerKm / 60).floor();
    final secs = (secPerKm % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  // The record for a standard distance is the athlete's #1 Best Effort — an
  // actual rolling-window time, never a projection of a whole run's average
  // pace. Null when there is no Best Effort for that distance.
  PREntry? _bestForDistance(DistanceCategory category, String label) {
    final record = bestEfforts[category];
    if (record == null) return null;
    final paceSecPerKm = record.elapsedSeconds / (category.meters / 1000);
    return PREntry(
      label: label,
      value: _formatTime(record.elapsedSeconds),
      unit: '${_formatPace(paceSecPerKm)} /km',
      setOn: record.recordedAt,
    );
  }

  PRResults calculate() {
    if (runs.isEmpty) {
      return PRResults(
        bestAvgPace: const PREntry(
          label: 'Best avg pace',
          value: '--:--',
          unit: '/km',
        ),
        longestRun: const PREntry(
          label: 'Longest run',
          value: '0.0',
          unit: 'km',
        ),
      );
    }

    final withPace = runs.where((r) => r.paceSecPerKm > 0).toList();
    final fastestRun = withPace.isEmpty
        ? null
        : withPace.reduce((a, b) => a.paceSecPerKm < b.paceSecPerKm ? a : b);
    final longestRun = runs.reduce(
      (a, b) => a.distanceKm > b.distanceKm ? a : b,
    );

    return PRResults(
      best5K: _bestForDistance(DistanceCategory.k5, 'Best 5K'),
      best10K: _bestForDistance(DistanceCategory.k10, 'Best 10K'),
      bestHalf: _bestForDistance(DistanceCategory.half, 'Best half'),
      bestMarathon: _bestForDistance(
        DistanceCategory.marathon,
        'Best marathon',
      ),
      bestAvgPace: PREntry(
        label: 'Best avg pace',
        value: fastestRun == null
            ? '--:--'
            : _formatPace(fastestRun.paceSecPerKm),
        unit: '/km',
        setOn: fastestRun?.date,
      ),
      longestRun: PREntry(
        label: 'Longest run',
        value: longestRun.distanceKm.toStringAsFixed(1),
        unit: 'km',
        setOn: longestRun.date,
      ),
    );
  }
}
