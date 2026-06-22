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
  PREngine(this.runs);

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

  // Among runs of at least [minKm], find the fastest-paced one and project
  // its pace onto [targetKm] to get the PR time.
  PREntry? _bestForDistance(double minKm, double targetKm, String label) {
    final eligible =
        runs.where((r) => r.distanceKm >= minKm && r.paceSecPerKm > 0).toList();
    if (eligible.isEmpty) return null;
    final best =
        eligible.reduce((a, b) => a.paceSecPerKm < b.paceSecPerKm ? a : b);
    final timeSeconds = (best.paceSecPerKm * targetKm).round();
    return PREntry(
      label: label,
      value: _formatTime(timeSeconds),
      unit: '${_formatPace(best.paceSecPerKm)} /km',
      setOn: best.date,
    );
  }

  PRResults calculate() {
    if (runs.isEmpty) {
      return PRResults(
        bestAvgPace:
            const PREntry(label: 'Best avg pace', value: '--:--', unit: '/km'),
        longestRun:
            const PREntry(label: 'Longest run', value: '0.0', unit: 'km'),
      );
    }

    final withPace = runs.where((r) => r.paceSecPerKm > 0).toList();
    final fastestRun = withPace.isEmpty
        ? null
        : withPace.reduce((a, b) => a.paceSecPerKm < b.paceSecPerKm ? a : b);
    final longestRun =
        runs.reduce((a, b) => a.distanceKm > b.distanceKm ? a : b);

    return PRResults(
      best5K: _bestForDistance(4.5, 5.0, 'Best 5K'),
      best10K: _bestForDistance(9.0, 10.0, 'Best 10K'),
      bestHalf: _bestForDistance(19.0, 21.0975, 'Best half'),
      bestMarathon: _bestForDistance(40.0, 42.195, 'Best marathon'),
      bestAvgPace: PREntry(
        label: 'Best avg pace',
        value: fastestRun == null ? '--:--' : _formatPace(fastestRun.paceSecPerKm),
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
