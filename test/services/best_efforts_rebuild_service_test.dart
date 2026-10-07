/// BestEffortsRebuildService — the one-time, version-flagged recompute of the
/// best_efforts table from stored runs. The calculation itself is
/// BestEffortsService.analyzeRun; these tests cover the rebuild around it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_rebuild_service.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 5:00/km samples every 50 m up to [totalM].
List<Map<String, dynamic>> _samples(double totalM) => [
  for (var d = 50.0; d <= totalM + 1e-9; d += 50) {'t': d / 50 * 15, 'd': d},
];

RunRecord _run(
  int id, {
  List<Map<String, dynamic>>? samples,
  double distanceKm = 6.0,
  int? durationSeconds,
  DateTime? date,
}) => RunRecord(
  id: id,
  date: date ?? DateTime(2026, 9, id.clamp(1, 28), 7),
  distanceKm: distanceKm,
  averagePace: '5:00',
  durationSeconds: durationSeconds ?? (distanceKm * 300).round(),
  routePolyline: '',
  trackSamples: samples ?? _samples(distanceKm * 1000),
);

/// In-memory stand-ins for the database, recording every call.
class _Fakes {
  final Map<int, RunRecord> runs = {};
  final Map<String, List<BestEffortResult>> rows = {};
  final Map<String, DateTime> recordedAt = {};
  int loadRunIdsCalls = 0;
  int replaceCalls = 0;
  int orphansToReport = 0;
  Set<int> failOnRun = {};
  Object? failOrphans;

  BestEffortsRebuildService service({Duration startupDelay = Duration.zero}) =>
      BestEffortsRebuildService(
        loadRunIds: () async {
          loadRunIdsCalls++;
          return runs.keys.toList()..sort();
        },
        loadRun: (id) async {
          if (failOnRun.contains(id)) throw StateError('boom $id');
          return runs[id];
        },
        replaceRunEfforts: (runId, results, at) async {
          replaceCalls++;
          rows[runId] =
              results; // replace semantics: the run's rows are swapped
          recordedAt[runId] = at;
        },
        deleteOrphans: () async {
          if (failOrphans != null) throw failOrphans!;
          return orphansToReport;
        },
        startupDelay: startupDelay,
      );

  Map<String, Map<DistanceCategory, int>> snapshot() => {
    for (final e in rows.entries)
      e.key: {for (final r in e.value) r.category: r.elapsedSeconds},
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('rebuild()', () {
    test('computes efforts for every run that has samples', () async {
      final f = _Fakes()
        ..runs[1] = _run(1)
        ..runs[2] = _run(2, distanceKm: 3.0);
      final result = await f.service().rebuild();

      expect(result.runsSeen, 2);
      expect(result.runsProcessed, 2);
      expect(result.runsSkipped, 0);
      expect(f.snapshot()['1']![DistanceCategory.k5], 1500);
      expect(f.snapshot()['2']!.containsKey(DistanceCategory.k5), isFalse);
      expect(f.snapshot()['2']![DistanceCategory.k3], 900);
      expect(result.effortsWritten, f.rows.values.expand((r) => r).length);
    });

    test(
      'uses the same analyzeRun as the save path (identical results)',
      () async {
        final run = _run(1);
        final f = _Fakes()..runs[1] = run;
        await f.service().rebuild();

        final direct = BestEffortsService.analyzeRun(
          run.trackSamples,
          finalDistanceMeters: run.distanceKm * 1000,
          finalSeconds: run.durationSeconds.toDouble(),
        );
        expect(f.snapshot()['1'], {
          for (final r in direct) r.category: r.elapsedSeconds,
        });
      },
    );

    test('is idempotent: running it twice gives the same table', () async {
      final f = _Fakes()
        ..runs[1] = _run(1)
        ..runs[2] = _run(2, distanceKm: 4.0)
        ..runs[3] = _run(3, distanceKm: 11.0);
      final svc = f.service();

      await svc.rebuild();
      final first = f.snapshot();
      await svc.rebuild();
      final second = f.snapshot();

      expect(second, first);
      expect(f.rows.length, 3); // no duplicates, one entry per run
    });

    test(
      'replaces stale rows, including a category that no longer qualifies',
      () async {
        final f = _Fakes()..runs[1] = _run(1, distanceKm: 3.0);
        // An old, flawed row set: a bogus 5K and a bogus fast 1K for run 1.
        f.rows['1'] = const [
          BestEffortResult(category: DistanceCategory.k5, elapsedSeconds: 600),
          BestEffortResult(category: DistanceCategory.k1, elapsedSeconds: 60),
        ];
        await f.service().rebuild();

        final run1 = f.snapshot()['1']!;
        expect(
          run1.containsKey(DistanceCategory.k5),
          isFalse,
        ); // 3 km run: no 5K
        expect(run1[DistanceCategory.k1], 300); // corrected, not 60
      },
    );

    test('records each effort against the run\'s own date', () async {
      final date = DateTime(2026, 8, 3, 6, 30);
      final f = _Fakes()..runs[7] = _run(7, date: date);
      await f.service().rebuild();
      expect(f.recordedAt['7'], date);
    });

    test('runs without usable samples are skipped, not computed', () async {
      final f = _Fakes()
        ..runs[1] = _run(1)
        ..runs[2] =
            _run(2, samples: const []) // pre-v8 / cloud-restored
        ..runs[3] = _run(
          3,
          samples: [
            {'t': 15.0, 'd': 50.0},
          ],
        ); // a single sample
      final result = await f.service().rebuild();

      expect(result.runsProcessed, 1);
      expect(result.runsSkipped, 2);
      expect(f.rows.keys, ['1']);
    });

    test(
      'no efforts are estimated from splits for runs without samples',
      () async {
        final noSamples = RunRecord(
          id: 4,
          date: DateTime(2026, 9, 4),
          distanceKm: 5.0,
          averagePace: '5:00',
          durationSeconds: 1500,
          routePolyline: '',
          splits: [
            for (var k = 1; k <= 5; k++) {'km': k, 'seconds': 300},
          ],
        );
        final f = _Fakes()..runs[4] = noSamples;
        final result = await f.service().rebuild();
        expect(result.runsSkipped, 1);
        expect(f.rows, isEmpty);
      },
    );

    test(
      'the closing point comes from the stored distance and duration',
      () async {
        // Samples stop at 4950 m; the stored totals say 5.02 km in 1506 s.
        final withTotals = _run(
          1,
          samples: _samples(4950),
          distanceKm: 5.02,
          durationSeconds: 1506,
        );
        // Same samples, but the run record says it only reached 4.95 km.
        final withoutReach = _run(
          2,
          samples: _samples(4950),
          distanceKm: 4.95,
          durationSeconds: 1485,
        );
        final f = _Fakes()
          ..runs[1] = withTotals
          ..runs[2] = withoutReach;
        await f.service().rebuild();

        expect(f.snapshot()['1']![DistanceCategory.k5], 1500);
        expect(f.snapshot()['2']!.containsKey(DistanceCategory.k5), isFalse);
      },
    );

    test(
      'older runs pass the plausibility checks (clock stall is rejected)',
      () async {
        final stalled = _run(
          1,
          samples: [
            for (var d = 50.0; d <= 1000; d += 50) {'t': d / 50 * 15, 'd': d},
            for (var k = 1; k <= 8; k++) {'t': 300.0, 'd': 1000.0 + k * 150},
            {'t': 800.0, 'd': 2250.0},
            for (var k = 1; k <= 30; k++)
              {'t': 800 + k * 15.0, 'd': 2250.0 + k * 50},
          ],
          distanceKm: 3.75,
          durationSeconds: 1250,
        );
        final f = _Fakes()..runs[1] = stalled;
        await f.service().rebuild();
        expect(f.snapshot()['1']![DistanceCategory.k1], 300);
      },
    );

    test('reports orphan rows removed', () async {
      final f = _Fakes()
        ..runs[1] = _run(1)
        ..orphansToReport = 4;
      final result = await f.service().rebuild();
      expect(result.orphansRemoved, 4);
    });

    test('one failing run is counted and the rest still process', () async {
      final f = _Fakes()
        ..runs[1] = _run(1)
        ..runs[2] = _run(2)
        ..runs[3] = _run(3)
        ..failOnRun = {2};
      final result = await f.service().rebuild();
      expect(result.runsFailed, 1);
      expect(result.runsProcessed, 2);
      expect(f.rows.keys.toSet(), {'1', '3'});
    });

    test('a long history is processed in full, in batches', () async {
      final f = _Fakes();
      for (var i = 1; i <= 35; i++) {
        f.runs[i] = _run(i, distanceKm: 1.2);
      }
      final result = await f.service().rebuild();
      expect(result.runsProcessed, 35);
      expect(BestEffortsRebuildService.batchSize, lessThan(35));
      expect(f.rows.length, 35);
    });

    test(
      'a missing run (deleted between listing and loading) is skipped',
      () async {
        final f = _Fakes()..runs[1] = _run(1);
        final svc = BestEffortsRebuildService(
          loadRunIds: () async => [1, 99],
          loadRun: (id) async => f.runs[id],
          replaceRunEfforts: (id, r, at) async => f.rows[id] = r,
          deleteOrphans: () async => 0,
        );
        final result = await svc.rebuild();
        expect(result.runsSkipped, 1);
        expect(result.runsProcessed, 1);
      },
    );
  });

  group('rebuildIfNeeded() — version flag', () {
    test('runs once on a fresh device and records the version', () async {
      final f = _Fakes()..runs[1] = _run(1);
      final result = await f.service().rebuildIfNeeded();

      expect(result, isNotNull);
      expect(result!.runsProcessed, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(BestEffortsRebuildService.prefsKey),
        BestEffortsRebuildService.currentVersion,
      );
    });

    test('does not rebuild again once the version is recorded', () async {
      final f = _Fakes()..runs[1] = _run(1);
      final svc = f.service();
      await svc.rebuildIfNeeded();
      final callsAfterFirst = f.replaceCalls;

      final second = await svc.rebuildIfNeeded();
      final third = await f.service().rebuildIfNeeded(); // a fresh instance too

      expect(second, isNull);
      expect(third, isNull);
      expect(f.replaceCalls, callsAfterFirst);
      expect(f.loadRunIdsCalls, 1);
    });

    test('a device already at the current version is left alone', () async {
      SharedPreferences.setMockInitialValues({
        BestEffortsRebuildService.prefsKey:
            BestEffortsRebuildService.currentVersion,
      });
      final f = _Fakes()..runs[1] = _run(1);
      expect(await f.service().rebuildIfNeeded(), isNull);
      expect(f.loadRunIdsCalls, 0);
      expect(f.rows, isEmpty);
    });

    test('an older recorded version triggers a fresh rebuild', () async {
      SharedPreferences.setMockInitialValues({
        BestEffortsRebuildService.prefsKey:
            BestEffortsRebuildService.currentVersion - 1,
      });
      final f = _Fakes()..runs[1] = _run(1);
      expect(await f.service().rebuildIfNeeded(), isNotNull);
      expect(f.rows.keys, ['1']);
    });

    test('concurrent callers share a single rebuild', () async {
      final f = _Fakes()..runs[1] = _run(1);
      final svc = f.service();
      final results = await Future.wait([
        svc.rebuildIfNeeded(),
        svc.rebuildIfNeeded(),
        svc.rebuildIfNeeded(),
      ]);
      expect(f.loadRunIdsCalls, 1);
      expect(results.whereType<BestEffortsRebuildResult>(), hasLength(3));
    });

    test(
      'an infrastructure failure does not set the flag, so it retries',
      () async {
        final f = _Fakes()
          ..runs[1] = _run(1)
          ..failOrphans = StateError('db unavailable');
        final svc = f.service();

        expect(await svc.rebuildIfNeeded(), isNull); // swallowed, never throws
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(BestEffortsRebuildService.prefsKey), isNull);

        f.failOrphans = null;
        expect(await svc.rebuildIfNeeded(), isNotNull); // next launch succeeds
      },
    );

    test(
      'a run that fails deterministically does not cause endless rebuilds',
      () async {
        final f = _Fakes()
          ..runs[1] = _run(1)
          ..runs[2] = _run(2)
          ..failOnRun = {2};
        final svc = f.service();
        final first = await svc.rebuildIfNeeded();
        expect(first!.runsFailed, 1);
        expect(await svc.rebuildIfNeeded(), isNull); // flag was set
      },
    );

    test('an empty history completes and sets the flag', () async {
      final f = _Fakes();
      final result = await f.service().rebuildIfNeeded();
      expect(result!.runsSeen, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(BestEffortsRebuildService.prefsKey), 1);
    });
  });
}
