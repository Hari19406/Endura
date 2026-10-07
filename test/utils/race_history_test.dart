import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/best_efforts_service.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:run_app/utils/race_history.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

RaceRun _race(int id, DateTime date, double km, int seconds) => RaceRun(
  id: id,
  date: date,
  distanceKm: km,
  durationSeconds: seconds,
);

void main() {
  group('RaceHistory grouping', () {
    test('categoryFor accepts GPS-realistic distances', () {
      expect(RaceHistory.categoryFor(5.02), DistanceCategory.k5);
      expect(RaceHistory.categoryFor(5.3), DistanceCategory.k5);
      expect(RaceHistory.categoryFor(4.9), DistanceCategory.k5);
      expect(RaceHistory.categoryFor(10.2), DistanceCategory.k10);
      expect(RaceHistory.categoryFor(21.2), DistanceCategory.half);
      expect(RaceHistory.categoryFor(42.5), DistanceCategory.marathon);
      expect(RaceHistory.categoryFor(7.0), isNull);
      expect(RaceHistory.categoryFor(4.5), isNull);
    });

    test('groups by distance, newest first, with delta to the previous', () {
      final groups = RaceHistory.group([
        _race(1, DateTime(2026, 3, 1), 5.0, 1260),
        _race(2, DateTime(2026, 6, 1), 5.1, 1218),
        _race(3, DateTime(2026, 9, 1), 5.0, 1230),
        _race(4, DateTime(2026, 5, 1), 10.1, 2700),
      ]);
      expect(groups.map((g) => g.category), [
        DistanceCategory.k5,
        DistanceCategory.k10,
      ]);
      final fiveK = groups.first.entries;
      expect(fiveK.map((e) => e.race.id), [3, 2, 1]);
      expect(fiveK.map((e) => e.deltaSeconds), [12, -42, null]);
      expect(groups[1].entries.single.deltaSeconds, isNull);
    });

    test('empty input and non-standard distances', () {
      expect(RaceHistory.group(const []), isEmpty);
      final races = [_race(1, DateTime(2026, 1, 1), 7.0, 2000)];
      expect(RaceHistory.group(races), isEmpty);
      expect(RaceHistory.otherCount(races), 1);
    });

    test('pace is time over recorded distance', () {
      expect(_race(1, DateTime(2026, 1, 1), 5.0, 1250).paceSecPerKm, 250);
    });
  });

  group('race marking (real database)', () {
    sqfliteFfiInit();
    late Database db;
    final dbs = DatabaseService.instance;

    setUp(() async {
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

    Future<int> insert({
      String type = 'easy',
      double km = 5.0,
      int seconds = 1250,
      DateTime? date,
      String? scheduledDayId,
    }) => dbs.insertRun(
      RunRecord(
        date: date ?? DateTime(2026, 9, 1, 8),
        distanceKm: km,
        averagePace: '4:10',
        durationSeconds: seconds,
        routePolyline: '12.97,77.59;12.98,77.60',
        workoutType: type,
        rpe: 7,
        scheduledDayId: scheduledDayId,
        title: 'Parkrun',
      ),
    );

    test('marking changes only workout_type', () async {
      final id = await insert(scheduledDayId: 'p::w2::d3');
      final before = (await dbs.getRunById(id))!;
      expect(await dbs.setRunRace(id, true), 'race');
      final after = (await dbs.getRunById(id))!;
      expect(after.workoutType, 'race');
      expect(after.distanceKm, before.distanceKm);
      expect(after.durationSeconds, before.durationSeconds);
      expect(after.averagePace, before.averagePace);
      expect(after.rpe, before.rpe);
      expect(after.title, before.title);
      expect(after.routePolyline, before.routePolyline);
      expect(after.scheduledDayId, 'p::w2::d3'); // plan link intact
    });

    test('unmarking restores free and is a no-op for non-races', () async {
      final id = await insert();
      await dbs.setRunRace(id, true);
      expect(await dbs.setRunRace(id, false), 'free');
      expect((await dbs.getRunById(id))!.workoutType, 'free');

      final tempo = await insert(type: 'tempo');
      expect(await dbs.setRunRace(tempo, false), 'tempo');
      expect((await dbs.getRunById(tempo))!.workoutType, 'tempo');
    });

    test('marking twice is idempotent; unknown run gives null', () async {
      final id = await insert();
      await dbs.setRunRace(id, true);
      expect(await dbs.setRunRace(id, true), 'race');
      expect(await dbs.setRunRace(9999, true), isNull);
    });

    test('getRaceRuns returns only marked races, oldest first', () async {
      final a = await insert(date: DateTime(2026, 8, 1));
      await insert(date: DateTime(2026, 8, 5)); // ordinary run
      final c = await insert(date: DateTime(2026, 7, 1), km: 10.0);
      await dbs.setRunRace(a, true);
      await dbs.setRunRace(c, true);
      final races = await dbs.getRaceRuns();
      expect(races.map((r) => r.id), [c, a]);
      expect(races.last.distanceKm, 5.0);
      expect(races.last.durationSeconds, 1250);
    });

    test('a marked race flows into the race history', () async {
      final r1 = await insert(date: DateTime(2026, 3, 1), seconds: 1300);
      final r2 = await insert(date: DateTime(2026, 9, 1), seconds: 1250);
      await dbs.setRunRace(r1, true);
      await dbs.setRunRace(r2, true);
      final groups = RaceHistory.group(await dbs.getRaceRuns());
      expect(groups.single.category, DistanceCategory.k5);
      expect(groups.single.entries.first.deltaSeconds, -50);
    });

    test('a race stays an ordinary run in history and Best Efforts storage',
        () async {
      final id = await insert();
      await dbs.setRunRace(id, true);
      expect(await dbs.getAllRuns(), hasLength(1));
      expect((await dbs.getAllRuns()).single.id, id);
      // Best Efforts are keyed by run, not by type.
      await dbs.insertBestEffort(
        BestEffortRecord(
          id: 'be1',
          runId: '$id',
          category: DistanceCategory.k5,
          elapsedSeconds: 1240,
          recordedAt: DateTime(2026, 9, 1),
        ),
      );
      expect(
        (await dbs.getAllCategoryPRs())[DistanceCategory.k5]!.elapsedSeconds,
        1240,
      );
    });

    test('getObservedEfforts: 3K+ efforts since the cutoff only', () async {
      final id = await insert();
      Future<void> put(String idKey, DistanceCategory c, int s, DateTime d) =>
          dbs.insertBestEffort(
            BestEffortRecord(
              id: idKey,
              runId: '$id',
              category: c,
              elapsedSeconds: s,
              recordedAt: d,
            ),
          );
      await put('a', DistanceCategory.k5, 1200, DateTime(2026, 9, 1));
      await put('b', DistanceCategory.k1, 220, DateTime(2026, 9, 1));
      await put('c', DistanceCategory.k10, 2600, DateTime(2024, 1, 1));
      final efforts = await dbs.getObservedEfforts(since: DateTime(2025, 10, 7));
      expect(efforts.map((e) => e.category), [DistanceCategory.k5]);
      expect(efforts.single.seconds, 1200);
    });
  });
}
