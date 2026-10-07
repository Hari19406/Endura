/// Weather survives every hop to storage: RunRecord toMap/fromMap, real SQLite
/// (`runs.weather_json`), the Supabase upload payload and restore shape — and
/// runs without weather stay completely valid.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/run_weather.dart';
import 'package:run_app/services/cloud_sync_service.dart';
import 'package:run_app/services/weather_service.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

final _weather = RunWeather(
  tempC: 27.4,
  apparentTempC: 30.2,
  humidityPercent: 71,
  dewPointC: 21.3,
  condition: WeatherCondition.cloudy,
  observedAt: DateTime(2026, 10, 7, 6, 40),
);

RunRecord _run({
  RunWeather? weather,
  String route = '12.9,77.6;12.91,77.61',
  int? hr,
  DateTime? date,
}) => RunRecord(
  distanceKm: 8.2,
  averagePace: '5:10',
  durationSeconds: 2540,
  date: date ?? DateTime(2026, 10, 7, 7),
  routePolyline: route,
  avgHeartRate: hr,
  weather: weather,
);

/// Records the `columns` of every `query`, forwarding to the real database.
class _SpyDb implements Database {
  _SpyDb(this._inner);
  final Database _inner;
  final List<List<String>?> columns = [];

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    this.columns.add(columns);
    return _inner.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not expected');
}

void main() {
  sqfliteFfiInit();

  group('RunRecord serialisation', () {
    test('weather is stored as one JSON payload and read back equal', () {
      final map = _run(weather: _weather).toMap();
      expect(map['weather_json'], isA<String>());
      expect(jsonDecode(map['weather_json'] as String)['tempC'], 27.4);
      expect(RunRecord.fromMap(map).weather, _weather);
    });

    test('a run without weather omits the column and reads back null', () {
      final map = _run().toMap();
      expect(map.containsKey('weather_json'), isFalse);
      expect(RunRecord.fromMap(map).weather, isNull);
    });

    test('a row from before weather existed is a valid run', () {
      final old = {
        'id': 1,
        'distance_km': 5.0,
        'average_pace': '5:00',
        'duration_seconds': 1500,
        'date': DateTime(2026, 1, 1).toIso8601String(),
      };
      final run = RunRecord.fromMap(old);
      expect(run.weather, isNull);
      expect(run.distanceKm, 5.0);
    });

    test('a corrupt payload degrades to no weather, not a crash', () {
      final map = _run(weather: _weather).toMap()..['weather_json'] = '{oops';
      expect(RunRecord.fromMap(map).weather, isNull);
      expect(RunRecord.fromMap(map).distanceKm, 8.2);
    });
  });

  group('local SQLite', () {
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

    test('the schema has a nullable weather_json column', () async {
      final cols = await db.rawQuery('PRAGMA table_info(runs)');
      final weather = cols.firstWhere((c) => c['name'] == 'weather_json');
      expect(weather['notnull'], 0);
      expect(weather['type'], 'TEXT');
    });

    test('a run with weather saves and reloads with every field', () async {
      final id = await dbs.insertRun(_run(weather: _weather));
      final loaded = (await dbs.getAllRuns()).single;
      expect(loaded.id, id);
      expect(loaded.weather, _weather);
      expect(loaded.weather!.observedAt, DateTime(2026, 10, 7, 6, 40));
      expect(loaded.weather!.condition, WeatherCondition.cloudy);
    });

    test('a run without weather saves and reloads normally', () async {
      await dbs.insertRun(_run());
      final loaded = (await dbs.getAllRuns()).single;
      expect(loaded.weather, isNull);
      expect(loaded.distanceKm, 8.2);
    });

    test('a pre-weather row inserted without the column still loads', () async {
      await db.insert('runs', {
        'distance_km': 5.0,
        'average_pace': '5:00',
        'duration_seconds': 1500,
        'date': DateTime(2026, 1, 1).toIso8601String(),
      });
      final loaded = (await dbs.getAllRuns()).single;
      expect(loaded.weather, isNull);
    });

    test('weather does not disturb the other run fields', () async {
      await dbs.insertRun(_run(weather: _weather, hr: 151));
      final loaded = (await dbs.getAllRuns()).single;
      expect(loaded.avgHeartRate, 151);
      expect(loaded.routePolyline, '12.9,77.6;12.91,77.61');
      expect(loaded.averagePace, '5:10');
    });

    group('getWeatherRuns', () {
      test('returns only outdoor runs that have weather', () async {
        await dbs.insertRun(_run(weather: _weather, hr: 150));
        await dbs.insertRun(
          _run(weather: _weather, route: '', date: DateTime(2026, 10, 8)),
        ); // treadmill / manual: no route
        await dbs.insertRun(_run(date: DateTime(2026, 10, 9))); // no weather

        final runs = await dbs.getWeatherRuns();
        expect(runs, hasLength(1));
        expect(runs.single.tempC, 27.4);
        expect(runs.single.humidityPercent, 71);
        expect(runs.single.condition, WeatherCondition.cloudy);
        expect(runs.single.distanceKm, 8.2);
        expect(runs.single.movingTimeSeconds, 2540);
        expect(runs.single.avgHr, 150);
      });

      test('a run without HR keeps a null HR (never zero)', () async {
        await dbs.insertRun(_run(weather: _weather));
        expect((await dbs.getWeatherRuns()).single.avgHr, isNull);
      });

      test('a corrupt payload is skipped, not turned into weather', () async {
        final id = await dbs.insertRun(_run(weather: _weather));
        await db.update(
          'runs',
          {'weather_json': 'garbage'},
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(await dbs.getWeatherRuns(), isEmpty);
      });

      test('reads only the columns it needs, never route or samples', () async {
        await dbs.insertRun(_run(weather: _weather));
        final spy = _SpyDb(db);
        DatabaseService.useDatabaseForTesting(spy);

        await dbs.getWeatherRuns();

        final cols = spy.columns.single;
        expect(cols, isNotNull);
        expect(cols!.toSet(), {
          'distance_km',
          'duration_seconds',
          'avg_heart_rate',
          'weather_json',
        });
        expect(cols, isNot(contains('route_polyline')));
        expect(cols, isNot(contains('track_samples_json')));
      });
    });
  });

  group('cloud upload payload', () {
    test('includes the weather as a JSON object', () {
      final payload = CloudSyncService.buildRunPayload(
        userId: 'u1',
        run: _run(weather: _weather),
      );
      expect(payload['weather'], isA<Map<String, dynamic>>());
      expect(RunWeather.tryParse(payload['weather']), _weather);
      // The whole payload must be encodable for the upsert.
      expect(() => jsonEncode(payload), returnsNormally);
    });

    test('leaves weather out entirely when the run has none', () {
      final payload = CloudSyncService.buildRunPayload(
        userId: 'u1',
        run: _run(),
      );
      expect(payload.containsKey('weather'), isFalse);
    });

    test('detects a project without the weather column', () {
      expect(
        CloudSyncService.isMissingWeatherColumn(
          PostgrestException(
            message:
                "Could not find the 'weather' column of 'runs' "
                'in the schema cache',
            code: 'PGRST204',
          ),
        ),
        isTrue,
      );
      expect(
        CloudSyncService.isMissingWeatherColumn(
          PostgrestException(message: 'permission denied', code: '42501'),
        ),
        isFalse,
      );
    });

    test('an upload retries without weather when the column is missing', () {
      final payload = CloudSyncService.buildRunPayload(
        userId: 'u1',
        run: _run(weather: _weather),
      );
      final reduced = CloudSyncService.withoutMissingOptionalColumn(
        payload,
        PostgrestException(
          message: "Could not find the 'weather' column of 'runs'",
          code: 'PGRST204',
        ),
      );
      expect(reduced, isNotNull);
      expect(reduced!.containsKey('weather'), isFalse);
      expect(reduced['distance_km'], 8.2);
      expect(payload.containsKey('weather'), isTrue, reason: 'input untouched');
    });

    test('title and weather can both be dropped, one retry at a time', () {
      final run = RunRecord(
        distanceKm: 5,
        averagePace: '5:00',
        durationSeconds: 1500,
        date: DateTime(2026, 10, 7),
        routePolyline: 'x',
        title: 'Morning Run',
        weather: _weather,
      );
      var payload = CloudSyncService.buildRunPayload(userId: 'u', run: run);
      payload = CloudSyncService.withoutMissingOptionalColumn(
        payload,
        PostgrestException(message: "no 'title' column", code: 'PGRST204'),
      )!;
      expect(payload.containsKey('title'), isFalse);
      expect(payload.containsKey('weather'), isTrue);
      payload = CloudSyncService.withoutMissingOptionalColumn(
        payload,
        PostgrestException(message: "no 'weather' column", code: 'PGRST204'),
      )!;
      expect(payload.containsKey('weather'), isFalse);
    });

    test(
      'an unrelated error, or a missing column we did not send, is not retried',
      () {
        final withWeather = CloudSyncService.buildRunPayload(
          userId: 'u',
          run: _run(weather: _weather),
        );
        expect(
          CloudSyncService.withoutMissingOptionalColumn(
            withWeather,
            PostgrestException(message: 'permission denied', code: '42501'),
          ),
          isNull,
        );
        final without = CloudSyncService.buildRunPayload(
          userId: 'u',
          run: _run(),
        );
        expect(
          CloudSyncService.withoutMissingOptionalColumn(
            without,
            PostgrestException(
              message: "no 'weather' column",
              code: 'PGRST204',
            ),
          ),
          isNull,
        );
      },
    );
  });

  group('cloud restore shape', () {
    test('a cloud row\'s weather jsonb becomes the same RunWeather', () {
      final uploaded = CloudSyncService.buildRunPayload(
        userId: 'u1',
        run: _run(weather: _weather),
      );
      // Supabase returns jsonb as an already-decoded map.
      final row = jsonDecode(jsonEncode(uploaded)) as Map<String, dynamic>;
      expect(RunWeather.tryParse(row['weather']), _weather);
    });

    test('rows from before the column existed restore with no weather', () {
      expect(RunWeather.tryParse(null), isNull);
      expect(RunWeather.tryParse(<String, dynamic>{}), isNull);
    });

    test('restored weather persists locally and reloads', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 13,
          onCreate: (db, _) => DatabaseService.createSchemaForTesting(db),
        ),
      );
      DatabaseService.useDatabaseForTesting(db);
      addTearDown(() async {
        DatabaseService.useDatabaseForTesting(null);
        await db.close();
      });

      final row =
          jsonDecode(
                jsonEncode(
                  CloudSyncService.buildRunPayload(
                    userId: 'u1',
                    run: _run(weather: _weather),
                  ),
                ),
              )
              as Map<String, dynamic>;
      await DatabaseService.instance.insertRun(
        RunRecord(
          distanceKm: (row['distance_km'] as num).toDouble(),
          averagePace: row['average_pace'] as String,
          durationSeconds: row['duration_seconds'] as int,
          date: DateTime.parse(row['date'] as String).toLocal(),
          routePolyline: row['route_polyline'] as String,
          syncedToCloud: true,
          weather: RunWeather.tryParse(row['weather']),
        ),
      );
      final loaded = (await DatabaseService.instance.getAllRuns()).single;
      expect(loaded.weather, _weather);
      expect(loaded.syncedToCloud, isTrue);
    });
  });
}
