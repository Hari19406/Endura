library;

// ============================================================================
// READINESS
// ============================================================================

enum Readiness { green, yellow, red }

// ============================================================================
// RPE TREND
// ============================================================================

enum RecentRpeTrend { increasing, decreasing, stable, unknown }

// ============================================================================
// RUN ANALYSIS — RPE signals passed into the engine
// ============================================================================

class RunAnalysis {
  final double? avgRpe;
  final RecentRpeTrend recentRpeTrend;
  final bool lastEasyRunTooHard;

  const RunAnalysis({
    this.avgRpe,
    this.recentRpeTrend = RecentRpeTrend.unknown,
    this.lastEasyRunTooHard = false,
  });
}
