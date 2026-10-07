import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  final dbs = DatabaseService.instance;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, _) => DatabaseService.createSchemaForTesting(db),
      ),
    );
    DatabaseService.useDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseService.useDatabaseForTesting(null);
    await db.close();
  });

  Future<int> insert({
    String polyline = '12.97,77.59;12.98,77.60',
    DateTime? date,
    int? hr,
    double elev = 25,
  }) => dbs.insertRun(
    RunRecord(
      date: date ?? DateTime(2026, 9, 1, 7),
      distanceKm: 5.2,
      averagePace: '5:00',
      durationSeconds: 1560,
      routePolyline: polyline,
      splits: const [
        {'km': 1, 'seconds': 300},
        {'km': 2, 'seconds': 310},
      ],
      avgHeartRate: hr,
      elevationGain: elev,
      trackSamples: const [
        {'t': 15, 'd': 50, 'alt': 900.0, 'hr': 140},
      ],
    ),
  );

  test('excludes the run being viewed', () async {
    final a = await insert(date: DateTime(2026, 9, 1));
    final b = await insert(date: DateTime(2026, 9, 2));
    final rows = await dbs.getRouteCandidates(a);
    expect(rows.map((r) => r.id), [b]);
  });

  test('null excludeId returns every run with a route, newest first', () async {
    final a = await insert(date: DateTime(2026, 9, 1));
    final b = await insert(date: DateTime(2026, 9, 3));
    final rows = await dbs.getRouteCandidates(null);
    expect(rows.map((r) => r.id), [b, a]);
  });

  test('skips runs without a recorded route (manual / treadmill)', () async {
    final withRoute = await insert();
    await insert(polyline: '');
    final rows = await dbs.getRouteCandidates(null);
    expect(rows.map((r) => r.id), [withRoute]);
  });

  test('returns the columns needed for matching and comparison', () async {
    await insert(hr: 151);
    final r = (await dbs.getRouteCandidates(null)).single;
    expect(r.distanceKm, 5.2);
    expect(r.averagePace, '5:00');
    expect(r.durationSeconds, 1560);
    expect(r.date, DateTime(2026, 9, 1, 7));
    expect(r.routePolyline, '12.97,77.59;12.98,77.60');
    expect(r.splits.map((s) => s['seconds']), [300, 310]);
    expect(r.avgHeartRate, 151);
    expect(r.elevationGain, 25);
  });

  test('does not load track samples', () async {
    await insert();
    // The row really does hold samples...
    final full = (await dbs.getAllRuns()).single;
    expect(full.trackSamples, isNotEmpty);
    // ...but the candidate query never reads them.
    final candidate = (await dbs.getRouteCandidates(null)).single;
    expect(candidate.trackSamples, isEmpty);
  });
}
