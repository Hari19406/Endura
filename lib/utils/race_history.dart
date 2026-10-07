// lib/utils/race_history.dart
//
// Race history: runs the athlete marked as races (`workout_type == 'race'`),
// grouped by standard race distance. A race is an ordinary run with an extra
// classification — this file only groups and compares; it computes no PRs
// (Best Efforts stay the canonical source) and touches no training state.
//
// Race time is the run's moving time and pace is moving time ÷ recorded
// distance — GPS distance can differ slightly from the official course.
library;

import '../services/best_efforts_service.dart' show DistanceCategory;

/// A marked race, reduced to what the history needs.
class RaceRun {
  final int id;
  final DateTime date;
  final double distanceKm;
  final int durationSeconds;

  const RaceRun({
    required this.id,
    required this.date,
    required this.distanceKm,
    required this.durationSeconds,
  });

  double get paceSecPerKm =>
      distanceKm > 0 ? durationSeconds / distanceKm : 0;
}

class RaceHistoryEntry {
  final RaceRun race;

  /// This race's time minus the previous race at the same distance, seconds.
  /// Negative = faster. Null for the first race at a distance.
  final int? deltaSeconds;

  const RaceHistoryEntry(this.race, this.deltaSeconds);
}

class RaceHistoryGroup {
  final DistanceCategory category;

  /// Newest first.
  final List<RaceHistoryEntry> entries;
  const RaceHistoryGroup(this.category, this.entries);
}

class RaceHistory {
  RaceHistory._();

  /// Standard race distances shown, in display order.
  static const List<DistanceCategory> categories = [
    DistanceCategory.k5,
    DistanceCategory.k10,
    DistanceCategory.half,
    DistanceCategory.marathon,
  ];

  /// Recorded distance accepted for a standard distance: a little short
  /// (3%) to a little long (6%) of the nominal distance.
  static const double lowTolerance = 0.97;
  static const double highTolerance = 1.06;

  /// The standard race distance [distanceKm] counts as, or null.
  static DistanceCategory? categoryFor(double distanceKm) {
    for (final c in categories) {
      final km = c.meters / 1000;
      if (distanceKm >= km * lowTolerance && distanceKm <= km * highTolerance) {
        return c;
      }
    }
    return null;
  }

  /// Groups [races] by standard distance. Groups with no race are omitted;
  /// races at non-standard distances are left out (see [otherCount]).
  static List<RaceHistoryGroup> group(List<RaceRun> races) {
    final out = <RaceHistoryGroup>[];
    for (final c in categories) {
      final mine =
          races.where((r) => categoryFor(r.distanceKm) == c).toList()
            ..sort((a, b) => a.date.compareTo(b.date)); // oldest first
      if (mine.isEmpty) continue;
      final entries = <RaceHistoryEntry>[
        for (var i = 0; i < mine.length; i++)
          RaceHistoryEntry(
            mine[i],
            i == 0 ? null : mine[i].durationSeconds - mine[i - 1].durationSeconds,
          ),
      ];
      out.add(RaceHistoryGroup(c, entries.reversed.toList()));
    }
    return out;
  }

  /// Marked races that are not at a standard distance.
  static int otherCount(List<RaceRun> races) =>
      races.where((r) => categoryFor(r.distanceKm) == null).length;
}
