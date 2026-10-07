// lib/utils/trend_analytics.dart
//
// Pure long-term trend maths for the You → Stats Trends card. No Flutter, no
// database: callers hand in lightweight [TrendRun]s and get back calendar
// buckets, range totals and deltas against the previous equivalent period.
//
// Calendar arithmetic is done with the `DateTime(y, m, d)` constructor and
// whole-day counting on UTC dates — never `Duration(days: 7)` on a local
// midnight — so a DST change or a year boundary can't shift a run into the
// wrong week or month.
library;

enum TrendRange {
  weeks8('8W', 'previous 8 weeks'),
  months6('6M', 'previous 6 months'),
  year1('1Y', 'previous 12 months'),
  all('All', null);

  const TrendRange(this.label, this.previousLabel);
  final String label;

  /// "vs …" caption for the delta; null when there is no previous period.
  final String? previousLabel;
}

enum TrendGranularity { week, month }

enum TrendMetric {
  distance('Distance'),
  time('Time'),
  runs('Runs'),
  elevation('Elevation'),
  pace('Pace'),
  heartRate('Avg HR'),
  bestEffort('Best Effort');

  const TrendMetric(this.label);
  final String label;
}

/// The only per-run data trends need — deliberately no samples, route or splits.
class TrendRun {
  final DateTime date;
  final double distanceKm;
  final int movingTimeSeconds;
  final double elevationGain;
  final int? avgHr;

  const TrendRun({
    required this.date,
    required this.distanceKm,
    required this.movingTimeSeconds,
    this.elevationGain = 0,
    this.avgHr,
  });
}

/// One stored Best Effort, reduced to what the progression chart needs.
class BestEffortPoint {
  final String id;
  final String runId;
  final DateTime date;
  final int seconds;

  /// True when this effort was faster than every earlier effort at the same
  /// distance (a PR at the time it was set). Set by
  /// [TrendAnalytics.withProgressivePrs]; false on raw rows.
  final bool isPr;

  const BestEffortPoint({
    required this.id,
    required this.runId,
    required this.date,
    required this.seconds,
    this.isPr = false,
  });

  BestEffortPoint markPr(bool value) => BestEffortPoint(
    id: id,
    runId: runId,
    date: date,
    seconds: seconds,
    isPr: value,
  );
}

class TrendSummary {
  final int runCount;
  final double distanceKm;
  final int movingSeconds;
  final double elevationMeters;

  /// Total moving time / total distance over runs that have both, in s/km.
  final double? paceSecondsPerKm;

  /// Average of the runs that actually recorded HR (moving-time weighted);
  /// null when none did. Missing HR is never interpolated or counted as zero.
  final double? avgHr;
  final int hrRuns;

  const TrendSummary({
    required this.runCount,
    required this.distanceKm,
    required this.movingSeconds,
    required this.elevationMeters,
    this.paceSecondsPerKm,
    this.avgHr,
    this.hrRuns = 0,
  });

  static const empty = TrendSummary(
    runCount: 0,
    distanceKm: 0,
    movingSeconds: 0,
    elevationMeters: 0,
  );

  /// The value the chart/headline shows for [metric] (null = no data).
  double? valueFor(TrendMetric metric) => switch (metric) {
    TrendMetric.distance => distanceKm,
    TrendMetric.time => movingSeconds.toDouble(),
    TrendMetric.runs => runCount.toDouble(),
    TrendMetric.elevation => elevationMeters,
    TrendMetric.pace => paceSecondsPerKm,
    TrendMetric.heartRate => avgHr,
    TrendMetric.bestEffort => null,
  };
}

class TrendBucket {
  /// First calendar day of the bucket (local midnight).
  final DateTime start;

  /// First day AFTER the bucket.
  final DateTime end;
  final TrendSummary summary;

  const TrendBucket({
    required this.start,
    required this.end,
    required this.summary,
  });
}

class TrendDelta {
  final double current;
  final double previous;

  const TrendDelta({required this.current, required this.previous});

  double get absolute => current - previous;

  /// Percent change vs previous; null when previous is zero.
  double? get percent =>
      previous == 0 ? null : (current - previous) / previous * 100;
}

class TrendWindow {
  final TrendGranularity granularity;
  final DateTime start;
  final DateTime end;
  final int bucketCount;

  /// The equivalent window immediately before this one; null for All.
  final DateTime? previousStart;

  const TrendWindow({
    required this.granularity,
    required this.start,
    required this.end,
    required this.bucketCount,
    this.previousStart,
  });
}

class TrendResult {
  final TrendRange range;
  final TrendWindow window;
  final List<TrendBucket> buckets;
  final TrendSummary summary;

  /// Totals for the previous equivalent window; null for [TrendRange.all].
  final TrendSummary? previousSummary;

  /// Total runs inside the window (the "M" of "N of M runs").
  int get runCount => summary.runCount;

  const TrendResult({
    required this.range,
    required this.window,
    required this.buckets,
    required this.summary,
    required this.previousSummary,
  });

  /// Change vs the previous equivalent period, or null when it can't be
  /// compared honestly (no previous period, or either side lacks data).
  TrendDelta? deltaFor(TrendMetric metric) {
    final prev = previousSummary;
    if (prev == null) return null;
    final cur = summary.valueFor(metric);
    final old = prev.valueFor(metric);
    if (cur == null || old == null) return null;
    return TrendDelta(current: cur, previous: old);
  }
}

class TrendAnalytics {
  TrendAnalytics._();

  static const int _minHr = 30;
  static const int _maxHr = 230;

  // ── Calendar helpers ──────────────────────────────────────────────────────

  static DateTime dateOnly(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    return DateTime(local.year, local.month, local.day);
  }

  /// Monday 00:00 of the week containing [d].
  static DateTime weekStart(DateTime d) {
    final day = dateOnly(d);
    return DateTime(day.year, day.month, day.day - (day.weekday - 1));
  }

  static DateTime addWeeks(DateTime weekStart, int weeks) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + 7 * weeks);

  static DateTime monthStart(DateTime d) {
    final day = dateOnly(d);
    return DateTime(day.year, day.month, 1);
  }

  static DateTime addMonths(DateTime monthStart, int months) =>
      DateTime(monthStart.year, monthStart.month + months, 1);

  /// Whole calendar days from [a] to [b], immune to DST (counted on UTC).
  static int daysBetween(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static int _monthsBetween(DateTime a, DateTime b) =>
      (b.year - a.year) * 12 + (b.month - a.month);

  // ── Windows ───────────────────────────────────────────────────────────────

  static TrendWindow windowFor(
    TrendRange range, {
    required DateTime now,
    DateTime? firstRunDate,
  }) {
    switch (range) {
      case TrendRange.weeks8:
        return _weekWindow(now, 8);
      case TrendRange.months6:
        return _weekWindow(now, 26);
      case TrendRange.year1:
        final current = monthStart(now);
        final start = addMonths(current, -11);
        return TrendWindow(
          granularity: TrendGranularity.month,
          start: start,
          end: addMonths(current, 1),
          bucketCount: 12,
          previousStart: addMonths(start, -12),
        );
      case TrendRange.all:
        final current = monthStart(now);
        var start = firstRunDate == null ? current : monthStart(firstRunDate);
        if (start.isAfter(current)) start = current;
        return TrendWindow(
          granularity: TrendGranularity.month,
          start: start,
          end: addMonths(current, 1),
          bucketCount: _monthsBetween(start, current) + 1,
        );
    }
  }

  static TrendWindow _weekWindow(DateTime now, int weeks) {
    final current = weekStart(now);
    final start = addWeeks(current, -(weeks - 1));
    return TrendWindow(
      granularity: TrendGranularity.week,
      start: start,
      end: addWeeks(current, 1),
      bucketCount: weeks,
      previousStart: addWeeks(start, -weeks),
    );
  }

  /// Index of the bucket [date] falls in, relative to [start]; may be
  /// negative or beyond the window.
  static int _bucketIndex(
    DateTime date,
    DateTime start,
    TrendGranularity granularity,
  ) {
    final day = dateOnly(date);
    return granularity == TrendGranularity.week
        ? (daysBetween(start, day) / 7).floor()
        : _monthsBetween(start, day);
  }

  static DateTime _bucketStart(
    DateTime windowStart,
    TrendGranularity g,
    int index,
  ) => g == TrendGranularity.week
      ? addWeeks(windowStart, index)
      : addMonths(windowStart, index);

  // ── Aggregation ───────────────────────────────────────────────────────────

  static bool hasHr(TrendRun r) {
    final hr = r.avgHr;
    return hr != null && hr >= _minHr && hr <= _maxHr;
  }

  static TrendSummary summarize(Iterable<TrendRun> runs) {
    var count = 0;
    var distance = 0.0, elevation = 0.0;
    var moving = 0;
    var paceDistance = 0.0;
    var paceSeconds = 0;
    var hrRuns = 0;
    var hrPlainSum = 0.0, hrWeightedSum = 0.0, hrWeight = 0.0;

    for (final r in runs) {
      count++;
      final km = r.distanceKm > 0 ? r.distanceKm : 0.0;
      final secs = r.movingTimeSeconds > 0 ? r.movingTimeSeconds : 0;
      distance += km;
      moving += secs;
      if (r.elevationGain > 0) elevation += r.elevationGain;
      if (km > 0 && secs > 0) {
        paceDistance += km;
        paceSeconds += secs;
      }
      if (hasHr(r)) {
        hrRuns++;
        hrPlainSum += r.avgHr!;
        hrWeightedSum += r.avgHr! * secs;
        hrWeight += secs;
      }
    }

    return TrendSummary(
      runCount: count,
      distanceKm: distance,
      movingSeconds: moving,
      elevationMeters: elevation,
      paceSecondsPerKm: paceDistance > 0 ? paceSeconds / paceDistance : null,
      avgHr: hrRuns == 0
          ? null
          : (hrWeight > 0 ? hrWeightedSum / hrWeight : hrPlainSum / hrRuns),
      hrRuns: hrRuns,
    );
  }

  /// Buckets [runs] for [range] as of [now], filling every empty period, and
  /// totals the window plus the previous equivalent window for deltas.
  static TrendResult build(
    List<TrendRun> runs,
    TrendRange range, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    DateTime? first;
    for (final r in runs) {
      if (first == null || r.date.isBefore(first)) first = r.date;
    }
    final window = windowFor(range, now: today, firstRunDate: first);

    final perBucket = List.generate(window.bucketCount, (_) => <TrendRun>[]);
    final previous = <TrendRun>[];
    for (final r in runs) {
      final i = _bucketIndex(r.date, window.start, window.granularity);
      if (i >= 0 && i < window.bucketCount) {
        perBucket[i].add(r);
      } else if (window.previousStart != null &&
          i < 0 &&
          i >= -window.bucketCount) {
        previous.add(r);
      }
    }

    final buckets = [
      for (var i = 0; i < window.bucketCount; i++)
        TrendBucket(
          start: _bucketStart(window.start, window.granularity, i),
          end: _bucketStart(window.start, window.granularity, i + 1),
          summary: summarize(perBucket[i]),
        ),
    ];

    return TrendResult(
      range: range,
      window: window,
      buckets: buckets,
      summary: summarize(perBucket.expand((b) => b)),
      previousSummary: window.previousStart == null
          ? null
          : summarize(previous),
    );
  }

  // ── Best Effort progression ───────────────────────────────────────────────

  /// Orders [points] oldest-first (date, then id) and flags each effort that
  /// was strictly faster than every earlier one — the PRs of the progression.
  /// An equal time never replaces the earlier holder, matching the Best
  /// Efforts leaderboard tie-break.
  static List<BestEffortPoint> withProgressivePrs(
    Iterable<BestEffortPoint> points,
  ) {
    final sorted = [...points]
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    int? best;
    return [
      for (final p in sorted)
        () {
          final isPr = best == null || p.seconds < best!;
          if (isPr) best = p.seconds;
          return p.markPr(isPr);
        }(),
    ];
  }

  /// Points that fall inside [window] (calendar days, end exclusive). PR flags
  /// are kept as computed over the full history.
  static List<BestEffortPoint> pointsInWindow(
    List<BestEffortPoint> points,
    TrendWindow window,
  ) => [
    for (final p in points)
      if (!dateOnly(p.date).isBefore(window.start) &&
          dateOnly(p.date).isBefore(window.end))
        p,
  ];
}
