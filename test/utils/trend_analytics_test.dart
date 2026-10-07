/// Pure trend maths: Monday-aligned weekly buckets, monthly buckets, empty
/// period filling, DST / year boundaries, weighted pace, HR exclusion and
/// coverage, previous-period deltas and Best Effort PR flagging.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/trend_analytics.dart';

// A Wednesday. Its week starts Monday 2026-10-05.
final _now = DateTime(2026, 10, 7, 12);

TrendRun _run(
  DateTime date, {
  double km = 5,
  int secs = 1500,
  double elev = 0,
  int? hr,
}) => TrendRun(
  date: date,
  distanceKm: km,
  movingTimeSeconds: secs,
  elevationGain: elev,
  avgHr: hr,
);

BestEffortPoint _point(String id, DateTime date, int seconds) =>
    BestEffortPoint(id: id, runId: id, date: date, seconds: seconds);

void main() {
  group('Monday-aligned weekly buckets', () {
    test('weekStart is the Monday 00:00 of the week', () {
      expect(
        TrendAnalytics.weekStart(DateTime(2026, 10, 5)),
        DateTime(2026, 10, 5),
      );
      expect(
        TrendAnalytics.weekStart(DateTime(2026, 10, 11, 23, 59)),
        DateTime(2026, 10, 5),
      );
      expect(TrendAnalytics.weekStart(_now), DateTime(2026, 10, 5));
    });

    test('8W is eight contiguous Monday buckets ending this week', () {
      final r = TrendAnalytics.build(const [], TrendRange.weeks8, now: _now);
      expect(r.buckets, hasLength(8));
      expect(r.window.granularity, TrendGranularity.week);
      expect(r.buckets.last.start, DateTime(2026, 10, 5));
      expect(r.buckets.first.start, DateTime(2026, 8, 17));
      for (var i = 0; i < r.buckets.length; i++) {
        expect(r.buckets[i].start.weekday, DateTime.monday);
        expect(r.buckets[i].start.hour, 0);
        if (i > 0) expect(r.buckets[i].start, r.buckets[i - 1].end);
      }
    });

    test('6M is 26 weekly buckets', () {
      final r = TrendAnalytics.build(const [], TrendRange.months6, now: _now);
      expect(r.buckets, hasLength(26));
      expect(r.window.granularity, TrendGranularity.week);
    });

    test('Sunday night belongs to the week that started the Monday before', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 10, 5, 0, 0)), // Monday 00:00
          _run(DateTime(2026, 10, 11, 23, 59)), // Sunday 23:59, same week
        ],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.buckets.last.summary.runCount, 2);
      expect(r.buckets[6].summary.runCount, 0);
    });

    test('runs after this week, or before the window, are not counted', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 10, 12)), // next Monday: future
          _run(DateTime(2026, 8, 16, 23, 59)), // Sunday before the window
          _run(DateTime(2026, 8, 17)), // first day of the window
        ],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.summary.runCount, 1);
      expect(r.buckets.first.summary.runCount, 1);
    });
  });

  group('monthly buckets', () {
    test('1Y is twelve calendar months ending this month', () {
      final r = TrendAnalytics.build(const [], TrendRange.year1, now: _now);
      expect(r.buckets, hasLength(12));
      expect(r.window.granularity, TrendGranularity.month);
      expect(r.buckets.first.start, DateTime(2025, 11, 1));
      expect(r.buckets.last.start, DateTime(2026, 10, 1));
      for (var i = 1; i < r.buckets.length; i++) {
        expect(r.buckets[i].start, r.buckets[i - 1].end);
        expect(r.buckets[i].start.day, 1);
      }
    });

    test('month edges: the 31st and the 1st land in different months', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 1, 31, 23, 30)),
          _run(DateTime(2026, 2, 1, 0, 30)),
        ],
        TrendRange.year1,
        now: _now,
      );
      final jan = r.buckets.firstWhere((b) => b.start == DateTime(2026, 1, 1));
      final feb = r.buckets.firstWhere((b) => b.start == DateTime(2026, 2, 1));
      expect(jan.summary.runCount, 1);
      expect(feb.summary.runCount, 1);
    });

    test('All starts at the first run\'s month and ends this month', () {
      final r = TrendAnalytics.build(
        [_run(DateTime(2025, 12, 20)), _run(DateTime(2026, 3, 2))],
        TrendRange.all,
        now: _now,
      );
      expect(r.buckets.first.start, DateTime(2025, 12, 1));
      expect(r.buckets.last.start, DateTime(2026, 10, 1));
      expect(r.buckets, hasLength(11));
      expect(r.summary.runCount, 2);
    });

    test('All with no runs is a single current-month bucket', () {
      final r = TrendAnalytics.build(const [], TrendRange.all, now: _now);
      expect(r.buckets, hasLength(1));
      expect(r.buckets.single.start, DateTime(2026, 10, 1));
    });
  });

  group('empty-period filling', () {
    test('periods with no runs still exist, empty and honest', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 8, 18), hr: 150),
          _run(DateTime(2026, 9, 24), hr: 150),
        ],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.buckets, hasLength(8));
      final empty = r.buckets.where((b) => b.summary.runCount == 0).toList();
      expect(empty, hasLength(6));
      for (final b in empty) {
        expect(b.summary.distanceKm, 0);
        expect(b.summary.movingSeconds, 0);
        expect(b.summary.paceSecondsPerKm, isNull);
        expect(b.summary.avgHr, isNull);
      }
    });

    test('monthly gaps are filled too', () {
      final r = TrendAnalytics.build(
        [_run(DateTime(2025, 11, 5)), _run(DateTime(2026, 10, 5))],
        TrendRange.year1,
        now: _now,
      );
      expect(r.buckets.where((b) => b.summary.runCount == 0), hasLength(10));
    });
  });

  group('DST and year boundaries', () {
    test(
      'weekly buckets stay on Mondays at midnight across both DST changes',
      () {
        // 8 weeks ending 2026-03-31 span the US (Mar 8) and EU (Mar 29) changes.
        final now = DateTime(2026, 3, 31, 12);
        final r = TrendAnalytics.build(const [], TrendRange.weeks8, now: now);
        for (var i = 0; i < r.buckets.length; i++) {
          final b = r.buckets[i];
          expect(b.start.weekday, DateTime.monday, reason: '${b.start}');
          expect(b.start.hour, 0, reason: '${b.start}');
          expect(TrendAnalytics.daysBetween(b.start, b.end), 7);
          if (i > 0) expect(b.start, r.buckets[i - 1].end);
        }
      },
    );

    test('runs on and around DST change days land in the right week', () {
      final now = DateTime(2026, 3, 31, 12);
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 3, 8, 0, 30)), // US spring-forward Sunday
          _run(DateTime(2026, 3, 8, 23, 30)),
          _run(DateTime(2026, 3, 9, 0, 30)), // Monday after
          _run(DateTime(2026, 3, 29, 0, 30)), // EU spring-forward Sunday
          _run(DateTime(2026, 3, 29, 23, 30)),
          _run(DateTime(2026, 3, 30, 0, 30)), // Monday after
        ],
        TrendRange.weeks8,
        now: now,
      );
      int inWeek(DateTime monday) =>
          r.buckets.firstWhere((b) => b.start == monday).summary.runCount;
      expect(inWeek(DateTime(2026, 3, 2)), 2); // Mar 8 runs
      expect(inWeek(DateTime(2026, 3, 9)), 1);
      expect(inWeek(DateTime(2026, 3, 23)), 2); // Mar 29 runs
      expect(inWeek(DateTime(2026, 3, 30)), 1);
    });

    test('a week that straddles New Year is one bucket', () {
      final now = DateTime(2026, 1, 14, 12);
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2025, 12, 29)),
          _run(DateTime(2025, 12, 31, 23, 59)),
          _run(DateTime(2026, 1, 1, 0, 1)),
          _run(DateTime(2026, 1, 4, 20)),
        ],
        TrendRange.weeks8,
        now: now,
      );
      final nye = r.buckets.firstWhere(
        (b) => b.start == DateTime(2025, 12, 29),
      );
      expect(nye.end, DateTime(2026, 1, 5));
      expect(nye.summary.runCount, 4);
    });

    test('monthly buckets roll Dec → Jan correctly', () {
      final now = DateTime(2026, 2, 10);
      final r = TrendAnalytics.build(
        [_run(DateTime(2025, 12, 31, 23, 59)), _run(DateTime(2026, 1, 1))],
        TrendRange.year1,
        now: now,
      );
      final dec = r.buckets.firstWhere((b) => b.start == DateTime(2025, 12, 1));
      final jan = r.buckets.firstWhere((b) => b.start == DateTime(2026, 1, 1));
      expect(dec.end, jan.start);
      expect(dec.summary.runCount, 1);
      expect(jan.summary.runCount, 1);
    });

    test('daysBetween ignores DST', () {
      expect(
        TrendAnalytics.daysBetween(DateTime(2026, 3, 1), DateTime(2026, 4, 1)),
        31,
      );
      expect(
        TrendAnalytics.daysBetween(
          DateTime(2026, 10, 20),
          DateTime(2026, 11, 3),
        ),
        14,
      );
    });

    test('UTC timestamps are bucketed by their local calendar day', () {
      final utc = DateTime.utc(2026, 10, 6, 12);
      final r = TrendAnalytics.build([_run(utc)], TrendRange.weeks8, now: _now);
      final local = utc.toLocal();
      final expected = TrendAnalytics.weekStart(local);
      final bucket = r.buckets.firstWhere((b) => b.summary.runCount == 1);
      expect(bucket.start, expected);
    });
  });

  group('totals and frequency', () {
    test('distance, time, elevation and run count are summed', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 10, 5), km: 5, secs: 1500, elev: 40),
          _run(DateTime(2026, 10, 6), km: 10.5, secs: 3300, elev: 120.6),
        ],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.summary.runCount, 2);
      expect(r.summary.distanceKm, closeTo(15.5, 1e-9));
      expect(r.summary.movingSeconds, 4800);
      expect(r.summary.elevationMeters, closeTo(160.6, 1e-9));
    });

    test('run frequency is the per-bucket run count', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 10, 5)),
          _run(DateTime(2026, 10, 7)),
          _run(DateTime(2026, 10, 9)),
          _run(DateTime(2026, 9, 29)),
        ],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.buckets.last.summary.runCount, 3);
      expect(r.buckets[6].summary.runCount, 1);
      expect(r.summary.valueFor(TrendMetric.runs), 4);
    });

    test('negative elevation is ignored, not subtracted', () {
      final s = TrendAnalytics.summarize([
        _run(DateTime(2026, 10, 5), elev: -30),
        _run(DateTime(2026, 10, 6), elev: 50),
      ]);
      expect(s.elevationMeters, 50);
    });
  });

  group('weighted average pace', () {
    test('is total moving time / total distance, not the mean of paces', () {
      final s = TrendAnalytics.summarize([
        _run(DateTime(2026, 10, 5), km: 5, secs: 1500), // 300 s/km
        _run(DateTime(2026, 10, 6), km: 10, secs: 3300), // 330 s/km
      ]);
      expect(s.paceSecondsPerKm, closeTo(4800 / 15, 1e-9)); // 320, not 315
    });

    test('runs without distance or time do not distort pace', () {
      final s = TrendAnalytics.summarize([
        _run(DateTime(2026, 10, 5), km: 5, secs: 1500),
        _run(DateTime(2026, 10, 6), km: 0, secs: 600),
        _run(DateTime(2026, 10, 7), km: 3, secs: 0),
      ]);
      expect(s.paceSecondsPerKm, 300);
      // …but their moving time still counts toward the time total.
      expect(s.movingSeconds, 2100);
      expect(s.distanceKm, 8);
    });

    test('no valid run → no pace', () {
      expect(TrendAnalytics.summarize(const []).paceSecondsPerKm, isNull);
      expect(
        TrendAnalytics.summarize([
          _run(DateTime(2026, 10, 5), km: 0),
        ]).paceSecondsPerKm,
        isNull,
      );
    });
  });

  group('average HR uses only runs with HR', () {
    test('runs without HR are excluded, not counted as zero', () {
      final s = TrendAnalytics.summarize([
        _run(DateTime(2026, 10, 5), secs: 3600, hr: 150),
        _run(DateTime(2026, 10, 6), secs: 1800, hr: 170),
        _run(DateTime(2026, 10, 7), secs: 5000), // no HR
        _run(DateTime(2026, 10, 8), secs: 5000, hr: 0), // implausible
      ]);
      expect(s.hrRuns, 2);
      expect(s.runCount, 4);
      // Moving-time weighted over the two runs that have HR only.
      expect(s.avgHr, closeTo((150 * 3600 + 170 * 1800) / 5400, 1e-9));
    });

    test('out-of-range HR is treated as missing', () {
      expect(
        TrendAnalytics.hasHr(_run(DateTime(2026, 10, 5), hr: 29)),
        isFalse,
      );
      expect(
        TrendAnalytics.hasHr(_run(DateTime(2026, 10, 5), hr: 231)),
        isFalse,
      );
      expect(TrendAnalytics.hasHr(_run(DateTime(2026, 10, 5), hr: 30)), isTrue);
      expect(
        TrendAnalytics.hasHr(_run(DateTime(2026, 10, 5), hr: 230)),
        isTrue,
      );
    });

    test('no HR anywhere → null average and zero coverage (never 0 bpm)', () {
      final r = TrendAnalytics.build(
        [_run(DateTime(2026, 10, 5)), _run(DateTime(2026, 10, 6))],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.summary.avgHr, isNull);
      expect(r.summary.hrRuns, 0);
      expect(r.summary.runCount, 2);
      expect(r.buckets.every((b) => b.summary.avgHr == null), isTrue);
    });

    test('coverage is per window: N runs with HR of M runs', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 10, 5), hr: 150),
          _run(DateTime(2026, 10, 6)),
          _run(DateTime(2026, 9, 28), hr: 140),
          _run(DateTime(2026, 9, 29)),
          _run(DateTime(2026, 9, 30)),
        ],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.summary.hrRuns, 2);
      expect(r.summary.runCount, 5);
      expect(r.buckets.last.summary.hrRuns, 1);
      expect(r.buckets.last.summary.runCount, 2);
    });

    test('zero-duration HR runs fall back to a plain mean', () {
      final s = TrendAnalytics.summarize([
        _run(DateTime(2026, 10, 5), secs: 0, hr: 140),
        _run(DateTime(2026, 10, 6), secs: 0, hr: 160),
      ]);
      expect(s.avgHr, 150);
    });

    test('a bucket with HR and one without keep their own values', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 10, 5), hr: 150),
          _run(DateTime(2026, 9, 28)), // no HR in that week
        ],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.buckets.last.summary.avgHr, 150);
      expect(r.buckets[6].summary.avgHr, isNull);
    });
  });

  group('delta vs the previous equivalent period', () {
    // 8W window: 2026-08-17 … 2026-10-11. Previous: 2026-06-22 … 2026-08-16.
    final current = [
      _run(DateTime(2026, 9, 1), km: 10, secs: 3000, elev: 100, hr: 150),
      _run(DateTime(2026, 10, 5), km: 20, secs: 6000, elev: 200, hr: 150),
    ];
    final previous = [
      _run(DateTime(2026, 7, 1), km: 10, secs: 3300, elev: 50, hr: 140),
      _run(DateTime(2026, 8, 16, 23, 59), km: 10, secs: 3300, elev: 50),
    ];

    test('compares the same-length period immediately before', () {
      final r = TrendAnalytics.build(
        [...current, ...previous],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.summary.distanceKm, 30);
      expect(r.previousSummary!.distanceKm, 20);
      final d = r.deltaFor(TrendMetric.distance)!;
      expect(d.absolute, 10);
      expect(d.percent, closeTo(50, 1e-9));
      expect(r.deltaFor(TrendMetric.runs)!.absolute, 0);
      expect(r.deltaFor(TrendMetric.time)!.percent, closeTo(36.36, 0.01));
      expect(r.deltaFor(TrendMetric.elevation)!.absolute, 200);
    });

    test('pace and HR deltas use their own periods\' weighted values', () {
      final r = TrendAnalytics.build(
        [...current, ...previous],
        TrendRange.weeks8,
        now: _now,
      );
      final pace = r.deltaFor(TrendMetric.pace)!;
      expect(pace.current, closeTo(9000 / 30, 1e-9)); // 300
      expect(pace.previous, closeTo(6600 / 20, 1e-9)); // 330
      expect(pace.absolute, lessThan(0)); // faster
      final hr = r.deltaFor(TrendMetric.heartRate)!;
      expect(hr.current, 150);
      expect(hr.previous, 140); // only the run that has HR
    });

    test('nothing in the previous period → no percent, no pace/HR delta', () {
      final r = TrendAnalytics.build(current, TrendRange.weeks8, now: _now);
      final d = r.deltaFor(TrendMetric.distance)!;
      expect(d.previous, 0);
      expect(d.percent, isNull);
      expect(r.deltaFor(TrendMetric.pace), isNull);
      expect(r.deltaFor(TrendMetric.heartRate), isNull);
    });

    test('previous period without HR gives no HR delta', () {
      final r = TrendAnalytics.build(
        [
          ...current,
          _run(DateTime(2026, 7, 1), km: 10, secs: 3300), // no HR
        ],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.deltaFor(TrendMetric.heartRate), isNull);
      expect(r.deltaFor(TrendMetric.pace), isNotNull);
    });

    test('runs older than the previous period are ignored', () {
      final r = TrendAnalytics.build(
        [...current, _run(DateTime(2026, 6, 21), km: 99)],
        TrendRange.weeks8,
        now: _now,
      );
      expect(r.previousSummary!.runCount, 0);
    });

    test('1Y compares against the 12 months before', () {
      final r = TrendAnalytics.build(
        [
          _run(DateTime(2026, 5, 1), km: 30),
          _run(DateTime(2025, 5, 1), km: 20), // previous 12 months
          _run(DateTime(2024, 5, 1), km: 99), // older: ignored
        ],
        TrendRange.year1,
        now: _now,
      );
      expect(r.deltaFor(TrendMetric.distance)!.percent, closeTo(50, 1e-9));
    });

    test('All has no previous period, so no delta', () {
      final r = TrendAnalytics.build(current, TrendRange.all, now: _now);
      expect(r.previousSummary, isNull);
      expect(r.deltaFor(TrendMetric.distance), isNull);
      expect(TrendRange.all.previousLabel, isNull);
    });
  });

  group('Best Effort progression', () {
    test('flags each effort faster than every earlier one', () {
      final points = TrendAnalytics.withProgressivePrs([
        _point('a', DateTime(2026, 1, 1), 1500),
        _point('b', DateTime(2026, 2, 1), 1600),
        _point('c', DateTime(2026, 3, 1), 1450),
        _point('d', DateTime(2026, 4, 1), 1450), // equal: not a new PR
        _point('e', DateTime(2026, 5, 1), 1400),
      ]);
      expect(points.map((p) => p.isPr), [true, false, true, false, true]);
    });

    test('orders oldest first regardless of input order, ties by id', () {
      final day = DateTime(2026, 1, 1);
      final points = TrendAnalytics.withProgressivePrs([
        _point('z', DateTime(2026, 3, 1), 1400),
        _point('b', day, 1500),
        _point('a', day, 1500),
      ]);
      expect(points.map((p) => p.id), ['a', 'b', 'z']);
      // 'a' sorts before 'b', so only 'a' set the 1500 PR.
      expect(points.map((p) => p.isPr), [true, false, true]);
    });

    test('an empty series stays empty', () {
      expect(TrendAnalytics.withProgressivePrs(const []), isEmpty);
    });

    test('window filtering keeps PR flags computed over full history', () {
      final all = TrendAnalytics.withProgressivePrs([
        _point('old', DateTime(2025, 1, 1), 1300), // fast, long ago
        _point('in', DateTime(2026, 9, 20), 1500), // slower: not a PR
      ]);
      final window = TrendAnalytics.windowFor(TrendRange.weeks8, now: _now);
      final inWindow = TrendAnalytics.pointsInWindow(all, window);
      expect(inWindow.map((p) => p.id), ['in']);
      expect(inWindow.single.isPr, isFalse);
    });

    test('window is end-exclusive on calendar days', () {
      final window = TrendAnalytics.windowFor(TrendRange.weeks8, now: _now);
      final pts = TrendAnalytics.pointsInWindow([
        _point('first', DateTime(2026, 8, 17), 1500),
        _point('before', DateTime(2026, 8, 16, 23, 59), 1500),
        _point('last', DateTime(2026, 10, 11, 23, 59), 1500),
        _point('after', DateTime(2026, 10, 12), 1500),
      ], window);
      expect(pts.map((p) => p.id), ['first', 'last']);
    });
  });
}
