// Model to hold a single run's data
class Run {
  final double distanceKm;
  final int durationSeconds;

  Run({
    required this.distanceKm,
    required this.durationSeconds,
  });

  // Calculate pace in minutes per km
  double get paceMinPerKm {
    if (distanceKm == 0) return 0;
    return (durationSeconds / 60) / distanceKm;
  }

  // Calculate pace in seconds per km
  double get paceSecPerKm {
    if (distanceKm == 0) return 0;
    return durationSeconds / distanceKm;
  }
}

// Model to hold the PR (Personal Record) results
class PRResults {
  final double fastest1KmPace; // in minutes per km
  final double bestAveragePace; // in minutes per km
  final double longestDistance; // in km

  PRResults({
    required this.fastest1KmPace,
    required this.bestAveragePace,
    required this.longestDistance,
  });

  @override
  String toString() {
    return '''
PR Results:
  Fastest 1km Pace: ${fastest1KmPace.toStringAsFixed(2)} min/km
  Best Average Pace: ${bestAveragePace.toStringAsFixed(2)} min/km
  Longest Distance: ${longestDistance.toStringAsFixed(2)} km
''';
  }
}

// Main PR Engine class
class PREngine {
  final List<Run> runs;

  PREngine(this.runs);

  PRResults calculate() {
    if (runs.isEmpty) {
      return PRResults(
        fastest1KmPace: 0,
        bestAveragePace: 0,
        longestDistance: 0,
      );
    }

    // Calculate fastest 1km pace (lowest pace value = fastest)
    double fastest1KmPace = runs
        .map((run) => run.paceMinPerKm)
        .reduce((a, b) => a < b ? a : b);

    // Calculate best average pace (same as fastest pace in this context)
    double bestAveragePace = runs
        .map((run) => run.paceMinPerKm)
        .reduce((a, b) => a < b ? a : b);

    // Calculate longest distance
    double longestDistance = runs
        .map((run) => run.distanceKm)
        .reduce((a, b) => a > b ? a : b);

    return PRResults(
      fastest1KmPace: fastest1KmPace,
      bestAveragePace: bestAveragePace,
      longestDistance: longestDistance,
    );
  }
}

// Example usage
void main() {
  List<Run> pastRuns = [
    Run(distanceKm: 5.0, durationSeconds: 1500), // 5 min/km pace
    Run(distanceKm: 10.0, durationSeconds: 2700), // 4.5 min/km pace
    Run(distanceKm: 3.0, durationSeconds: 840),   // 4.67 min/km pace
    Run(distanceKm: 21.1, durationSeconds: 6300), // 4.98 min/km pace
    Run(distanceKm: 8.0, durationSeconds: 2160),  // 4.5 min/km pace
  ];

  PREngine engine = PREngine(pastRuns);
  PRResults results = engine.calculate();

  print(results);
}


