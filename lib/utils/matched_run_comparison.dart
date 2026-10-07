// lib/utils/matched_run_comparison.dart
//
// Compares today's run against earlier runs on the same route (Matched Runs
// V1). Pure maths over plain summaries — HR, elevation and GAP deltas exist
// only when BOTH runs carry usable values; nothing is ever fabricated.
library;

import '../models/activity_telemetry.dart';
import 'database_service.dart' show RunRecord;

/// The few numbers needed to compare one run with another.
class MatchedRunSummary {
  final int? id;
  final DateTime date;
  final double distanceKm;
  final int durationSeconds;

  /// Average pace in seconds per km; null when unknown.
  final int? paceSecPerKm;

  /// Full-kilometre split durations, keyed by 1-based km. Partial trailing
  /// splits are never included.
  final Map<int, int> splitSeconds;
  final int? avgHr;
  final double? elevationGainM;

  /// Grade-adjusted pace, seconds per km. Null unless recomputed from samples.
  final int? gapSecPerKm;

  const MatchedRunSummary({
    this.id,
    required this.date,
    required this.distanceKm,
    required this.durationSeconds,
    this.paceSecPerKm,
    this.splitSeconds = const {},
    this.avgHr,
    this.elevationGainM,
    this.gapSecPerKm,
  });

  /// Today's run, from the Activity Detail view-model.
  factory MatchedRunSummary.fromActivity(ActivityDetail a) =>
      MatchedRunSummary(
        id: a.runId,
        date: a.timestamp,
        distanceKm: a.distanceKm,
        durationSeconds: a.movingTime.inSeconds,
        paceSecPerKm: a.avgPaceSeconds,
        splitSeconds: {
          for (final s in a.splits)
            if (!s.isPartial && s.paceSeconds > 0) s.km: s.paceSeconds,
        },
        avgHr: _positive(a.avgHr),
        elevationGainM: _positiveD(a.elevationGainM),
        gapSecPerKm: _positive(a.avgGapSeconds),
      );

  /// An earlier run from a (sample-free) candidate row. Pass [gapSecPerKm]
  /// only when it was recomputed from samples — the stored column is not
  /// trusted.
  factory MatchedRunSummary.fromRunRecord(
    RunRecord r, {
    int? gapSecPerKm,
  }) {
    final fullKm = r.distanceKm.floor();
    final splits = <int, int>{};
    for (final m in r.splits) {
      final km = (m['km'] as num?)?.toInt();
      final sec = (m['seconds'] as num?)?.toInt();
      if (km == null || sec == null || sec <= 0 || km > fullKm) continue;
      splits[km] = sec;
    }
    return MatchedRunSummary(
      id: r.id,
      date: r.date,
      distanceKm: r.distanceKm,
      durationSeconds: r.durationSeconds,
      paceSecPerKm: ActivityDetail.paceLabelToSeconds(r.averagePace),
      splitSeconds: splits,
      avgHr: _positive(r.avgHeartRate),
      elevationGainM: _positiveD(r.elevationGain),
      gapSecPerKm: _positive(gapSecPerKm),
    );
  }

  static int? _positive(int? v) => v != null && v > 0 ? v : null;
  static double? _positiveD(double? v) => v != null && v > 0 ? v : null;
}

class SplitDelta {
  final int km;

  /// Today minus the other run, seconds. Negative = faster today.
  final int deltaSeconds;
  const SplitDelta(this.km, this.deltaSeconds);
}

/// Today's run measured against one earlier run. Every delta is
/// "today − other": negative means today was faster / lower.
class MatchedRunComparison {
  final MatchedRunSummary other;
  final int timeDeltaSeconds;
  final int? paceDeltaSecPerKm;

  /// Today − other distance in km; null unless they differ by more than 2%.
  final double? distanceDiffKm;
  final List<SplitDelta> splitDeltas;
  final int? hrDelta;
  final double? elevationDeltaM;
  final int? gapDeltaSecPerKm;

  const MatchedRunComparison({
    required this.other,
    required this.timeDeltaSeconds,
    this.paceDeltaSecPerKm,
    this.distanceDiffKm,
    this.splitDeltas = const [],
    this.hrDelta,
    this.elevationDeltaM,
    this.gapDeltaSecPerKm,
  });

  /// Total time is only a fair comparison when the distances agree to 2%.
  bool get timeIsLikeForLike => distanceDiffKm == null;

  factory MatchedRunComparison.between(
    MatchedRunSummary today,
    MatchedRunSummary other,
  ) {
    final distDiff = today.distanceKm - other.distanceKm;
    final distRelative = other.distanceKm > 0
        ? distDiff.abs() / other.distanceKm
        : 0.0;
    final todayPace = today.paceSecPerKm;
    final otherPace = other.paceSecPerKm;
    final todayGap = today.gapSecPerKm;
    final otherGap = other.gapSecPerKm;
    final todayElev = today.elevationGainM;
    final otherElev = other.elevationGainM;
    return MatchedRunComparison(
      other: other,
      timeDeltaSeconds: today.durationSeconds - other.durationSeconds,
      paceDeltaSecPerKm: todayPace != null && otherPace != null
          ? todayPace - otherPace
          : null,
      distanceDiffKm: distRelative > 0.02 ? distDiff : null,
      splitDeltas: [
        for (final km in (today.splitSeconds.keys.toList()..sort()))
          if (other.splitSeconds.containsKey(km))
            SplitDelta(km, today.splitSeconds[km]! - other.splitSeconds[km]!),
      ],
      hrDelta: today.avgHr != null && other.avgHr != null
          ? today.avgHr! - other.avgHr!
          : null,
      elevationDeltaM: todayElev != null && otherElev != null
          ? todayElev - otherElev
          : null,
      gapDeltaSecPerKm: todayGap != null && otherGap != null
          ? todayGap - otherGap
          : null,
    );
  }
}

/// Today's run versus the previous and best matched runs.
class MatchedRunsResult {
  /// Number of other runs matched to this route (all dates).
  final int matchCount;

  /// How many of them happened before today's run.
  final int previousCount;
  final MatchedRunComparison? previous;
  final MatchedRunComparison? best;

  const MatchedRunsResult({
    required this.matchCount,
    required this.previousCount,
    this.previous,
    this.best,
  });

  /// True when the previous run is also the fastest on this route.
  bool get previousIsBest =>
      previous != null && best != null && previous!.other.id == best!.other.id;

  /// Picks the previous run (latest before [today]) and the best run (lowest
  /// average pace, falling back to shortest time) out of [matches].
  /// Null when there are no matches.
  static MatchedRunsResult? build(
    MatchedRunSummary today,
    List<MatchedRunSummary> matches,
  ) {
    if (matches.isEmpty) return null;
    final earlier =
        matches.where((m) => m.date.isBefore(today.date)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final best = matches.reduce((a, b) => _isFaster(b, a) ? b : a);
    return MatchedRunsResult(
      matchCount: matches.length,
      previousCount: earlier.length,
      previous: earlier.isEmpty
          ? null
          : MatchedRunComparison.between(today, earlier.first),
      best: MatchedRunComparison.between(today, best),
    );
  }

  static bool _isFaster(MatchedRunSummary a, MatchedRunSummary b) {
    final pa = a.paceSecPerKm;
    final pb = b.paceSecPerKm;
    if (pa != null && pb != null && pa != pb) return pa < pb;
    return a.durationSeconds < b.durationSeconds;
  }
}

/// "0:48" / "1:02:09" for a non-negative number of seconds.
String formatMatchedDuration(int seconds) {
  final s = seconds.abs();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
