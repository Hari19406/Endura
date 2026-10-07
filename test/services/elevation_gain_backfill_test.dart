import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/elevation_gain_backfill_service.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 40 m of steady climb over 2 km, sampled every 50 m.
List<Map<String, dynamic>> _climb() => [
  for (var i = 0; i <= 40; i++) {'t': i * 15, 'd': i * 50.0, 'alt': 900.0 + i},
];

List<Map<String, dynamic>> _noAltitude() => [
  for (var i = 0; i <= 40; i++) {'t': i * 15, 'd': i * 50.0, 'alt': null},
];

void main() {
  sqfliteFfiInit();

  late Database db;
  final dbs = DatabaseService.instance;
  late List<(int, double)> pushed;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pushed = [];
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (db, _) => DatabaseService.createSchemaForTesting(db),
      ),
    );
    DatabaseService.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseService.useDatabaseForTesting(null);
    await db.close();
  });

  ElevationGainBackfillService service() => ElevationGainBackfillService(
    pushToCloud: (id, gain) async {
      pushed.add((id, gain));
      return true;
    },
  );

  Future<int> insert({
    required double stored,
    List<Map<String, dynamic>> samples = const [],
    DateTime? date,
  }) => dbs.insertRun(
    RunRecord(
      date: date ?? DateTime(2026, 9, 1, 7),
      distanceKm: 2.0,
      averagePace: '5:00',
      durationSeconds: 600,
      routePolyline: '',
      elevationGain: stored,
      trackSamples: samples,
    ),
  );

  Future<double> gainOf(int id) async =>
      (await dbs.getRunById(id))!.elevationGain;

  test('updates runs that have usable altitude samples', () async {
    final id = await insert(stored: 78, samples: _climb());
    final result = await service().backfill();
    expect(result.runsUpdated, 1);
    expect(await gainOf(id), closeTo(40, 6));
    expect(await gainOf(id), lessThan(78));
  });

  test('leaves runs without usable samples exactly as they were', () async {
    final noSamples = await insert(stored: 55);
    final noAlt = await insert(stored: 20, samples: _noAltitude());
    final result = await service().backfill();
    expect(result.runsSkipped, 2);
    expect(result.runsUpdated, 0);
    expect(await gainOf(noSamples), 55);
    expect(await gainOf(noAlt), 20);
  });

  test('re-pushes only corrected runs to the cloud', () async {
    final fixed = await insert(stored: 78, samples: _climb());
    await insert(stored: 55);
    await service().backfill();
    expect(pushed.map((p) => p.$1), [fixed]);
    expect(pushed.single.$2, closeTo(40, 6));
  });

  test('a failing cloud push does not undo the local correction', () async {
    final id = await insert(stored: 78, samples: _climb());
    final svc = ElevationGainBackfillService(
      pushToCloud: (_, _) async => throw Exception('offline'),
    );
    final result = await svc.backfill();
    expect(result.runsUpdated, 1);
    expect(result.runsFailed, 0);
    expect(await gainOf(id), closeTo(40, 6));
  });

  test('is idempotent', () async {
    final id = await insert(stored: 78, samples: _climb());
    await insert(stored: 55);
    await service().backfill();
    final once = await gainOf(id);

    pushed.clear();
    final second = await service().backfill();
    expect(second.runsUpdated, 0);
    expect(second.runsUnchanged, 1);
    expect(await gainOf(id), once);
    expect(pushed, isEmpty);
  });

  test('handles a long history in batches', () async {
    final ids = <int>[];
    for (var i = 0; i < 27; i++) {
      ids.add(
        await insert(
          stored: 78,
          samples: i.isEven ? _climb() : const [],
          date: DateTime(2026, 1, 1).add(Duration(days: i)),
        ),
      );
    }
    final result = await service().backfill();
    expect(result.runsSeen, 27);
    expect(result.runsUpdated, 14);
    expect(result.runsSkipped, 13);
    expect(await gainOf(ids[1]), 78);
  });

  group('version flag', () {
    test('runs once per version, then is skipped', () async {
      await insert(stored: 78, samples: _climb());
      final svc = service();
      final first = await svc.backfillIfNeeded();
      expect(first, isNotNull);
      expect(first!.runsUpdated, 1);
      expect((await SharedPreferences.getInstance()).getInt(
        ElevationGainBackfillService.prefsKey,
      ), ElevationGainBackfillService.currentVersion);
      expect(await svc.backfillIfNeeded(), isNull);
    });

    test('concurrent callers share one run', () async {
      await insert(stored: 78, samples: _climb());
      final svc = service();
      final results = await Future.wait([
        svc.backfillIfNeeded(),
        svc.backfillIfNeeded(),
      ]);
      expect(identical(results[0], results[1]), isTrue);
      expect(pushed, hasLength(1));
    });
  });
}
