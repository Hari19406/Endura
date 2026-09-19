/// Run titles — the default name a run gets, and cleanup of a user-edited one.
///
///   • planned run → "Week 3 · Cruise Intervals"
///   • free run    → by time of day: "Morning Run", "Afternoon Run",
///                   "Evening Run", "Night Run"
library;

class RunTitle {
  const RunTitle._();

  /// Longest title we store. Keeps feed cards and share sheets from wrapping.
  static const int maxLength = 60;

  /// "Morning Run" (05–12), "Afternoon Run" (12–17), "Evening Run" (17–21),
  /// otherwise "Night Run". Uses the wall-clock hour of [when].
  static String forTimeOfDay(DateTime when) {
    final h = when.hour;
    if (h >= 5 && h < 12) return 'Morning Run';
    if (h >= 12 && h < 17) return 'Afternoon Run';
    if (h >= 17 && h < 21) return 'Evening Run';
    return 'Night Run';
  }

  /// "Week 3 · Cruise Intervals", or just the workout name when the plan week
  /// isn't known.
  static String forPlanned({required String workoutName, int? weekNumber}) {
    final name = workoutName.trim();
    return (weekNumber != null && weekNumber > 0)
        ? 'Week $weekNumber · $name'
        : name;
  }

  /// The default title for a run started at [startedAt]. A planned run with a
  /// workout name gets that name; everything else falls back to time of day.
  static String resolve({
    required DateTime startedAt,
    required bool isFreeRun,
    String? workoutName,
    int? weekNumber,
  }) {
    final name = workoutName?.trim();
    if (!isFreeRun && name != null && name.isNotEmpty) {
      return forPlanned(workoutName: name, weekNumber: weekNumber);
    }
    return forTimeOfDay(startedAt);
  }

  /// Clean a user-typed title for storage: trims, collapses runs of
  /// whitespace, and caps at [maxLength]. Null when nothing is left — callers
  /// fall back to the default title rather than saving a blank name.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return null;
    return cleaned.length > maxLength
        ? cleaned.substring(0, maxLength).trimRight()
        : cleaned;
  }
}
