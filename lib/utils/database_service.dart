// lib/utils/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'stats.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../services/best_efforts_service.dart';
import 'trend_analytics.dart' show BestEffortPoint, TrendRun;

class RunRecord {
  final int? id;
  final double distanceKm;
  final String averagePace;
  final int durationSeconds;
  final DateTime date;
  final String routePolyline;
  final String workoutType;
  final bool syncedToCloud;
  final double? csValueAtTime;
  // ── RPE (1–10). Null until the user rates the run. ──────────────────────
  final int? rpe;
  // ── Elevation gain in meters, accumulated from GPS altitude during the
  // main-set phase only (matches distanceKm/durationSeconds scope). 0 for
  // runs recorded before this field existed. ─────────────────────────────
  final double elevationGain;
  // ── Per-km splits as [{'km': 1, 'seconds': 320}, ...], main-set only.
  // Empty for runs recorded before this field existed or under 1km. ──────
  final List<Map<String, dynamic>> splits;
  // ── Wall-clock elapsed seconds including paused time (vs durationSeconds,
  // which is moving time). Null for runs recorded before this field existed
  // or for runs with no pauses (nothing new to show over durationSeconds).
  final int? elapsedSeconds;
  // ── Heart rate / cadence summaries. Null when no BLE HR/cadence monitor or
  // Health Connect/HealthKit source was available for that run — never a
  // fabricated/estimated value. ───────────────────────────────────────────
  final int? avgHeartRate;
  final int? peakHeartRate;
  final int? avgCadence;
  final int? peakCadence;
  // ── Grade-adjusted average pace, same "mm:ss" shape as averagePace. Null
  // if fewer than 2 track samples have both altitude and pace. ───────────
  final String? gapAveragePace;
  // ── Fine-grained time series captured during the main-set phase (every
  // ~15s or ~150m), backing the pace-trend/elevation-profile/HR/cadence
  // charts. Each entry: {t, d, alt?, pace?, hr?, cad?}. Empty for runs
  // recorded before this field existed. ───────────────────────────────────
  final List<Map<String, dynamic>> trackSamples;

  // ── Link to the plan slot this run fulfilled. Format
  // "<planId>::w<week>::d<weekday>" (see ScheduledWorkoutContext.dayId). Null
  // for free runs and for runs recorded before this field existed. ─────────
  final String? scheduledDayId;

  // ── User-facing run name ("Morning Run", "Week 3 · Cruise Intervals", or
  // whatever the athlete typed on the summary screen). Null for runs recorded
  // before this field existed — readers fall back to a workout-type label. ───
  final String? title;

  const RunRecord({
    this.id,
    required this.distanceKm,
    required this.averagePace,
    required this.durationSeconds,
    required this.date,
    required this.routePolyline,
    this.workoutType = 'easy',
    this.syncedToCloud = false,
    this.csValueAtTime,
    this.rpe,
    this.elevationGain = 0,
    this.splits = const [],
    this.elapsedSeconds,
    this.avgHeartRate,
    this.peakHeartRate,
    this.avgCadence,
    this.peakCadence,
    this.gapAveragePace,
    this.trackSamples = const [],
    this.scheduledDayId,
    this.title,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'distance_km': distanceKm,
    'average_pace': averagePace,
    'duration_seconds': durationSeconds,
    'date': date.toIso8601String(),
    'route_polyline': routePolyline,
    'workout_type': workoutType,
    'synced_to_cloud': syncedToCloud ? 1 : 0,
    'cs_value_at_time': csValueAtTime,
    // rpe (and the new nullable fields below) are intentionally omitted when
    // null so SQLite keeps DEFAULT NULL and existing rows are never
    // accidentally zeroed out.
    if (rpe != null) 'rpe': rpe,
    'elevation_gain': elevationGain,
    'splits_json': jsonEncode(splits),
    if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
    if (avgHeartRate != null) 'avg_heart_rate': avgHeartRate,
    if (peakHeartRate != null) 'peak_heart_rate': peakHeartRate,
    if (avgCadence != null) 'avg_cadence': avgCadence,
    if (peakCadence != null) 'peak_cadence': peakCadence,
    if (gapAveragePace != null) 'gap_average_pace': gapAveragePace,
    'track_samples_json': jsonEncode(trackSamples),
    if (scheduledDayId != null) 'scheduled_day_id': scheduledDayId,
    if (title != null) 'title': title,
  };

  factory RunRecord.fromMap(Map<String, dynamic> map) => RunRecord(
    id: map['id'] as int?,
    distanceKm: (map['distance_km'] as num).toDouble(),
    averagePace: map['average_pace'] as String,
    durationSeconds: map['duration_seconds'] as int,
    date: DateTime.parse(map['date'] as String),
    routePolyline: map['route_polyline'] as String? ?? '',
    workoutType: map['workout_type'] as String? ?? 'easy',
    syncedToCloud: (map['synced_to_cloud'] as int? ?? 0) == 1,
    csValueAtTime: map['cs_value_at_time'] != null
        ? (map['cs_value_at_time'] as num).toDouble()
        : null,
    // Safe cast: column may not exist on very old DB rows returned as null
    rpe: map['rpe'] as int?,
    elevationGain: (map['elevation_gain'] as num?)?.toDouble() ?? 0,
    splits: _decodeSplits(map['splits_json'] as String?),
    elapsedSeconds: map['elapsed_seconds'] as int?,
    avgHeartRate: map['avg_heart_rate'] as int?,
    peakHeartRate: map['peak_heart_rate'] as int?,
    avgCadence: map['avg_cadence'] as int?,
    peakCadence: map['peak_cadence'] as int?,
    gapAveragePace: map['gap_average_pace'] as String?,
    trackSamples: _decodeTrackSamples(map['track_samples_json'] as String?),
    scheduledDayId: map['scheduled_day_id'] as String?,
    title: map['title'] as String?,
  );

  static List<Map<String, dynamic>> _decodeSplits(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> _decodeTrackSamples(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Converts to RunHistory for consumption by home / you screens.
  /// rpe and durationSeconds are now forwarded correctly.
  RunHistory toRunHistory() => RunHistory(
    distance: distanceKm,
    averagePace: averagePace,
    date: date,
    gpsPoints: _decodePolyline(routePolyline),
    durationSeconds: durationSeconds,
    rpe: rpe,
    workoutType: workoutType,
  );

  static List<Map<String, double>> _decodePolyline(String polyline) =>
      decodePolylineToPoints(polyline);
}

class TrainingStateRecord {
  final int? id;
  final DateTime date;
  final double acuteLoad;
  final double chronicLoad;

  /// Legacy DB column `critical_speed` preserved for backward compatibility.
  final double fitnessAnchorValue;
  final DateTime? lastQualityDate;
  final DateTime? lastLongRunDate;

  const TrainingStateRecord({
    this.id,
    required this.date,
    required this.acuteLoad,
    required this.chronicLoad,
    required this.fitnessAnchorValue,
    this.lastQualityDate,
    this.lastLongRunDate,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'date': date.toIso8601String(),
    'acute_load': acuteLoad,
    'chronic_load': chronicLoad,
    'acwr': 1.0,
    'critical_speed': fitnessAnchorValue,
    'last_quality_date': lastQualityDate?.toIso8601String(),
    'last_long_run_date': lastLongRunDate?.toIso8601String(),
  };

  factory TrainingStateRecord.fromMap(Map<String, dynamic> map) =>
      TrainingStateRecord(
        id: map['id'] as int?,
        date: DateTime.parse(map['date'] as String),
        acuteLoad: (map['acute_load'] as num).toDouble(),
        chronicLoad: (map['chronic_load'] as num).toDouble(),
        fitnessAnchorValue: (map['critical_speed'] as num?)?.toDouble() ?? 0.0,
        lastQualityDate: map['last_quality_date'] != null
            ? DateTime.parse(map['last_quality_date'] as String)
            : null,
        lastLongRunDate: map['last_long_run_date'] != null
            ? DateTime.parse(map['last_long_run_date'] as String)
            : null,
      );
}

/// A single "top N" row in the `best_efforts` table: the fastest recorded
/// continuous segment of [category]'s distance, extracted from one run's
/// telemetry by [BestEffortsService]. Id is deterministic
/// (`'<runId>_<category.name>'`) so recomputing for the same run overwrites
/// rather than duplicates.
class BestEffortRecord {
  final String id;
  final String runId;
  final DistanceCategory category;
  final int elapsedSeconds;
  final DateTime recordedAt;

  const BestEffortRecord({
    required this.id,
    required this.runId,
    required this.category,
    required this.elapsedSeconds,
    required this.recordedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'run_id': runId,
    'distance_category': category.name,
    'elapsed_seconds': elapsedSeconds,
    'recorded_at': recordedAt.toIso8601String(),
  };

  factory BestEffortRecord.fromMap(Map<String, dynamic> map) =>
      BestEffortRecord(
        id: map['id'] as String,
        runId: map['run_id'] as String,
        category:
            DistanceCategory.fromKey(map['distance_category'] as String) ??
            DistanceCategory.k5,
        elapsedSeconds: map['elapsed_seconds'] as int,
        recordedAt: DateTime.parse(map['recorded_at'] as String),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// DatabaseService
// ─────────────────────────────────────────────────────────────────────────────

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();
  static Database? _db;

  /// Test seam: point the service at an already-open (e.g. in-memory ffi)
  /// database. Pass null to reset.
  @visibleForTesting
  static void useDatabaseForTesting(Database? db) => _db = db;

  /// Test seam: create the real, current schema on [db].
  @visibleForTesting
  static Future<void> createSchemaForTesting(Database db) => _createSchema(db);

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'runapp.db');

    return openDatabase(
      path,
      // ── Version history ─────────────────────────────────────────────────
      // v1 → original schema (no rpe, no cs_value_at_time)
      // v2 → added cs_value_at_time
      // v3 → added rpe
      // v4 → added skip_counts
      // v5 → added achievements
      // v6 → added elevation_gain, splits_json
      // v7 → backfilled free-run rpe=0 rows to NULL (free runs never rate RPE)
      // v8 → added elapsed_seconds, avg/peak heart_rate, avg/peak cadence,
      //      gap_average_pace, track_samples_json
      // v9 → added `shoes` table (offline-first shoe locker; mirrors the
      //      Supabase `shoes` table, syncs best-effort)
      // ────────────────────────────────────────────────────────────────────
      // v10 → added `runs.scheduled_day_id` (direct link from a completed run
      //       to the plan slot it fulfilled; see ScheduledWorkoutContext)
      // v11 → added `best_efforts` table (rolling-window efforts per
      //       benchmark distance, ranked at query time; see BestEffortsService)
      // v12 → added `runs.title` (user-editable run name, set on the summary
      //       screen; NULL for older runs)
      version: 12,
      onCreate: (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        // Each migration block is additive and guarded by the old version so
        // it runs exactly once per device regardless of which version the user
        // had installed.

        if (oldVersion < 2) {
          // v1 → v2: cs_value_at_time
          // Wrapped in try/catch so the app never crashes if somehow the
          // column already exists (e.g. manual testing, emulator reuse).
          try {
            await db.execute(
              'ALTER TABLE runs ADD COLUMN cs_value_at_time REAL',
            );
          } catch (e) {
            debugPrint('[DB] cs_value_at_time already exists, skipping: $e');
          }
        }

        if (oldVersion < 3) {
          // v2 → v3: rpe
          try {
            await db.execute('ALTER TABLE runs ADD COLUMN rpe INTEGER');
          } catch (e) {
            debugPrint('[DB] rpe already exists, skipping: $e');
          }
        }

        if (oldVersion < 4) {
          // v3 → v4: skip_counts
          try {
            await db.execute('''
              CREATE TABLE skip_counts (
                workout_type  TEXT    PRIMARY KEY,
                count         INTEGER NOT NULL DEFAULT 0
              )
            ''');
          } catch (e) {
            debugPrint('[DB] skip_counts already exists, skipping: $e');
          }
        }

        if (oldVersion < 5) {
          // v4 → v5: achievements
          try {
            await db.execute('''
              CREATE TABLE achievements (
                type        TEXT    PRIMARY KEY,
                unlocked_at TEXT    NOT NULL,
                tier        INTEGER NOT NULL
              )
            ''');
          } catch (e) {
            debugPrint('[DB] achievements already exists, skipping: $e');
          }
        }

        if (oldVersion < 6) {
          // v5 → v6: elevation_gain, splits_json
          try {
            await db.execute(
              'ALTER TABLE runs ADD COLUMN elevation_gain REAL NOT NULL DEFAULT 0',
            );
          } catch (e) {
            debugPrint('[DB] elevation_gain already exists, skipping: $e');
          }
          try {
            await db.execute(
              "ALTER TABLE runs ADD COLUMN splits_json TEXT NOT NULL DEFAULT '[]'",
            );
          } catch (e) {
            debugPrint('[DB] splits_json already exists, skipping: $e');
          }
        }

        if (oldVersion < 7) {
          // v6 → v7: free runs used to be saved with rpe=0 (no real rating —
          // the RPE picker is never shown for them). Null those out so they
          // stop showing "RPE 0/10" in history and stop skewing the Training
          // Status average, matching how new free runs behave going forward.
          try {
            await db.execute(
              "UPDATE runs SET rpe = NULL WHERE workout_type = 'free' AND rpe = 0",
            );
          } catch (e) {
            debugPrint('[DB] free-run rpe backfill failed: $e');
          }
        }

        if (oldVersion < 8) {
          // v7 → v8: elapsed_seconds (moving vs elapsed), HR/cadence
          // summaries, GAP, and track_samples_json for pace-trend/elevation/
          // HR/cadence charts. All nullable — old rows read back as "not
          // available", never zero.
          for (final col in [
            'elapsed_seconds INTEGER',
            'avg_heart_rate INTEGER',
            'peak_heart_rate INTEGER',
            'avg_cadence INTEGER',
            'peak_cadence INTEGER',
            'gap_average_pace TEXT',
          ]) {
            try {
              await db.execute('ALTER TABLE runs ADD COLUMN $col');
            } catch (e) {
              debugPrint('[DB] $col already exists, skipping: $e');
            }
          }
          try {
            await db.execute(
              "ALTER TABLE runs ADD COLUMN track_samples_json TEXT NOT NULL DEFAULT '[]'",
            );
          } catch (e) {
            debugPrint('[DB] track_samples_json already exists, skipping: $e');
          }
        }

        if (oldVersion < 9) {
          // v8 → v9: offline-first shoe locker.
          try {
            await db.execute(_createShoesTableSql);
          } catch (e) {
            debugPrint('[DB] shoes table already exists, skipping: $e');
          }
        }

        if (oldVersion < 10) {
          // v9 → v10: scheduled_day_id — direct plan-slot link for guided runs.
          try {
            await db.execute(
              'ALTER TABLE runs ADD COLUMN scheduled_day_id TEXT',
            );
          } catch (e) {
            debugPrint('[DB] scheduled_day_id already exists, skipping: $e');
          }
        }

        if (oldVersion < 11) {
          // v10 → v11: best_efforts — top-10 rolling-window PR leaderboard
          // per benchmark distance, computed once at run-save time.
          try {
            await db.execute(_createBestEffortsTableSql);
          } catch (e) {
            debugPrint('[DB] best_efforts table already exists, skipping: $e');
          }
          try {
            await db.execute(_createBestEffortsIndexSql);
          } catch (e) {
            debugPrint('[DB] idx_best_efforts already exists, skipping: $e');
          }
        }

        if (oldVersion < 12) {
          // v11 → v12: title — user-editable run name. Nullable: old rows read
          // back as "no title" and fall back to a workout-type label.
          try {
            await db.execute('ALTER TABLE runs ADD COLUMN title TEXT');
          } catch (e) {
            debugPrint('[DB] title already exists, skipping: $e');
          }
        }
      },
    );
  }

  /// Creates the complete, current schema on a fresh install. Also the seam
  /// database tests use to build an in-memory database with the real tables.
  static Future<void> _createSchema(Database db) async {
    // Fresh install: create the complete, up-to-date schema in one shot.
    await db.execute('''
      CREATE TABLE runs (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        distance_km       REAL    NOT NULL,
        average_pace      TEXT    NOT NULL,
        duration_seconds  INTEGER NOT NULL,
        date              TEXT    NOT NULL,
        route_polyline    TEXT    NOT NULL DEFAULT '',
        workout_type      TEXT    NOT NULL DEFAULT 'easy',
        synced_to_cloud   INTEGER NOT NULL DEFAULT 0,
        cs_value_at_time  REAL,
        rpe               INTEGER,
        elevation_gain    REAL    NOT NULL DEFAULT 0,
        splits_json       TEXT    NOT NULL DEFAULT '[]',
        elapsed_seconds   INTEGER,
        avg_heart_rate    INTEGER,
        peak_heart_rate   INTEGER,
        avg_cadence       INTEGER,
        peak_cadence      INTEGER,
        gap_average_pace  TEXT,
        track_samples_json TEXT  NOT NULL DEFAULT '[]',
        scheduled_day_id  TEXT,
        title             TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE training_snapshots (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        date               TEXT NOT NULL,
        acute_load         REAL NOT NULL,
        chronic_load       REAL NOT NULL,
        acwr               REAL NOT NULL,
        critical_speed     REAL NOT NULL DEFAULT 0.0,
        last_quality_date  TEXT,
        last_long_run_date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE skip_counts (
        workout_type  TEXT    PRIMARY KEY,
        count         INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE achievements (
        type        TEXT    PRIMARY KEY,
        unlocked_at TEXT    NOT NULL,
        tier        INTEGER NOT NULL
      )
    ''');
    await db.execute(_createShoesTableSql);
    await db.execute(_createBestEffortsTableSql);
    await db.execute('CREATE INDEX idx_runs_date ON runs(date DESC)');
    await db.execute(
      'CREATE INDEX idx_snap_date ON training_snapshots(date DESC)',
    );
    await db.execute(_createBestEffortsIndexSql);
  }

  static const String _createShoesTableSql = '''
    CREATE TABLE shoes (
      id                  TEXT    PRIMARY KEY,
      brand               TEXT    NOT NULL,
      model               TEXT    NOT NULL,
      nickname            TEXT,
      distance_meters     REAL    NOT NULL DEFAULT 0,
      max_distance_meters REAL    NOT NULL DEFAULT 800000,
      is_default          INTEGER NOT NULL DEFAULT 0,
      is_retired          INTEGER NOT NULL DEFAULT 0,
      updated_at          TEXT    NOT NULL,
      synced_to_cloud     INTEGER NOT NULL DEFAULT 0,
      pending_delete      INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const String _createBestEffortsTableSql = '''
    CREATE TABLE best_efforts (
      id                TEXT    PRIMARY KEY,
      run_id            TEXT    NOT NULL,
      distance_category TEXT    NOT NULL,
      elapsed_seconds   INTEGER NOT NULL,
      recorded_at       TEXT    NOT NULL,
      FOREIGN KEY (run_id) REFERENCES runs (id) ON DELETE CASCADE
    )
  ''';

  static const String _createBestEffortsIndexSql =
      'CREATE INDEX idx_best_efforts_category_time '
      'ON best_efforts(distance_category, elapsed_seconds ASC)';

  // ── CRUD: shoes (local mirror of the Supabase `shoes` table) ──────────────

  Future<List<Map<String, dynamic>>> getShoeRows({
    bool includeDeleted = false,
  }) async {
    try {
      final db = await database;
      return db.query(
        'shoes',
        where: includeDeleted ? null : 'pending_delete = 0',
        orderBy: 'is_retired ASC, distance_meters DESC',
      );
    } catch (e, stack) {
      debugPrint('getShoeRows error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  Future<void> upsertShoeRow(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('shoes', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteShoeRow(String id) async {
    final db = await database;
    await db.delete('shoes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markShoeSynced(String id) async {
    final db = await database;
    await db.update(
      'shoes',
      {'synced_to_cloud': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedShoeRows() async {
    final db = await database;
    return db.query('shoes', where: 'synced_to_cloud = 0');
  }

  Future<void> replaceAllShoeRows(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('shoes');
      for (final r in rows) {
        await txn.insert(
          'shoes',
          r,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ── CRUD: runs ────────────────────────────────────────────────────────────

  Future<int> insertRun(RunRecord run) async {
    try {
      final db = await database;
      return db.insert(
        'runs',
        run.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, stack) {
      debugPrint('insertRun error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return -1;
    }
  }

  Future<void> deleteRun(int id) async {
    final db = await database;
    await db.delete('runs', where: 'id = ?', whereArgs: [id]);
    // No enforced FK cascade (foreign_keys pragma isn't enabled), so clean
    // up this run's best-effort rows explicitly.
    await db.delete(
      'best_efforts',
      where: 'run_id = ?',
      whereArgs: [id.toString()],
    );
  }

  Future<RunRecord?> getRunById(int id) async {
    try {
      final db = await database;
      final rows = await db.query(
        'runs',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return RunRecord.fromMap(rows.first);
    } catch (e, stack) {
      debugPrint('[DB] getRunById error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return null;
    }
  }

  Future<List<RunRecord>> getAllRuns() async {
    try {
      final db = await database;
      final rows = await db.query('runs', orderBy: 'date DESC');
      return rows.map(RunRecord.fromMap).toList();
    } catch (e, stack) {
      debugPrint('getAllRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  Future<List<RunRecord>> getRecentRuns({int limit = 28}) async {
    try {
      final db = await database;
      final rows = await db.query('runs', orderBy: 'date DESC', limit: limit);
      return rows.map(RunRecord.fromMap).toList();
    } catch (e, stack) {
      debugPrint('getRecentRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  /// Runs that could share a route with another, newest first, for Matched
  /// Runs. Only runs with a recorded polyline qualify (manual / treadmill runs
  /// are skipped) and [excludeId] — the run being viewed — is left out. Reads
  /// just the columns matching and comparison need: never `track_samples_json`,
  /// so the returned records have empty `trackSamples`.
  Future<List<RunRecord>> getRouteCandidates(int? excludeId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'runs',
        columns: [
          'id',
          'date',
          'distance_km',
          'average_pace',
          'duration_seconds',
          'route_polyline',
          'splits_json',
          'avg_heart_rate',
          'elevation_gain',
        ],
        where: excludeId == null
            ? "route_polyline <> ''"
            : "route_polyline <> '' AND id <> ?",
        whereArgs: excludeId == null ? null : [excludeId],
        orderBy: 'date DESC',
      );
      return rows.map(RunRecord.fromMap).toList();
    } catch (e, stack) {
      debugPrint('[DB] getRouteCandidates error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  /// Every run reduced to the five columns Trends needs, oldest first. Unlike
  /// [getAllRuns] this never reads the route polyline, splits or track
  /// samples, which dominate a run row's size. `avg_heart_rate` stays null
  /// for runs without an HR source — it is never defaulted.
  Future<List<TrendRun>> getTrendRuns() async {
    try {
      final db = await database;
      final rows = await db.query(
        'runs',
        columns: [
          'date',
          'distance_km',
          'duration_seconds',
          'elevation_gain',
          'avg_heart_rate',
        ],
        orderBy: 'date ASC',
      );
      return [
        for (final r in rows)
          TrendRun(
            date: DateTime.parse(r['date'] as String),
            distanceKm: (r['distance_km'] as num?)?.toDouble() ?? 0,
            movingTimeSeconds: (r['duration_seconds'] as num?)?.toInt() ?? 0,
            elevationGain: (r['elevation_gain'] as num?)?.toDouble() ?? 0,
            avgHr: (r['avg_heart_rate'] as num?)?.toInt(),
          ),
      ];
    } catch (e, stack) {
      debugPrint('[DB] getTrendRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  /// Every stored effort for [category] as (date, time) points, oldest first,
  /// read straight from `best_efforts` — nothing is recalculated. Only runs
  /// that actually have an effort at that distance have a row. `isPr` is left
  /// false; Trends flags progressive PRs with
  /// `TrendAnalytics.withProgressivePrs`.
  Future<List<BestEffortPoint>> getBestEffortSeries(
    DistanceCategory category,
  ) async {
    try {
      final db = await database;
      final rows = await db.query(
        'best_efforts',
        columns: ['id', 'run_id', 'elapsed_seconds', 'recorded_at'],
        where: 'distance_category = ?',
        whereArgs: [category.name],
        orderBy: 'recorded_at ASC, id ASC',
      );
      return [
        for (final r in rows)
          BestEffortPoint(
            id: r['id'] as String,
            runId: r['run_id'] as String,
            date: DateTime.parse(r['recorded_at'] as String),
            seconds: (r['elapsed_seconds'] as num).toInt(),
          ),
      ];
    } catch (e, stack) {
      debugPrint('[DB] getBestEffortSeries error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  /// Highest stored `peak_heart_rate` across all runs, or null when no run
  /// recorded one. Feeds the observed-max fallback in AthletePhysiology.
  Future<int?> getMaxPeakHeartRate() async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT MAX(peak_heart_rate) AS m FROM runs',
      );
      if (rows.isEmpty) return null;
      return (rows.first['m'] as num?)?.toInt();
    } catch (e, stack) {
      debugPrint('[DB] getMaxPeakHeartRate error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return null;
    }
  }

  Future<List<RunRecord>> getRunsSince(DateTime since) async {
    final db = await database;
    final rows = await db.query(
      'runs',
      where: 'date >= ?',
      whereArgs: [since.toIso8601String()],
      orderBy: 'date DESC',
    );
    return rows.map(RunRecord.fromMap).toList();
  }

  Future<List<RunRecord>> getUnsyncedRuns() async {
    final db = await database;
    final rows = await db.query(
      'runs',
      where: 'synced_to_cloud = 0',
      orderBy: 'date ASC',
    );
    return rows.map(RunRecord.fromMap).toList();
  }

  /// Recent runs not yet linked to a plan day — what "Link Activity" on the
  /// pre-run briefing screen offers to attach to the day being previewed.
  Future<List<RunRecord>> getUnlinkedRuns({int limit = 20}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'runs',
        where: 'scheduled_day_id IS NULL',
        orderBy: 'date DESC',
        limit: limit,
      );
      return rows.map(RunRecord.fromMap).toList();
    } catch (e, stack) {
      debugPrint('getUnlinkedRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  /// Stamps [dayId] (`"<planId>::w<week>::d<weekday>"`) onto an already-logged
  /// run — the retroactive counterpart to the auto-link `RunScreen` does when
  /// saving a run against a live scheduled session.
  Future<void> updateRunScheduledDayId(int runId, String dayId) async {
    try {
      final db = await database;
      await db.update(
        'runs',
        {'scheduled_day_id': dayId},
        where: 'id = ?',
        whereArgs: [runId],
      );
    } catch (e, stack) {
      debugPrint('updateRunScheduledDayId error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
    }
  }

  Future<void> markRunSynced(int runId) async {
    final db = await database;
    await db.update(
      'runs',
      {'synced_to_cloud': 1},
      where: 'id = ?',
      whereArgs: [runId],
    );
  }

  /// Writes the RPE value for a completed run.
  ///
  /// Returns true if a row was actually updated (runId exists).
  /// Returns false and logs on any error — never throws.
  Future<bool> updateRunRpe(int runId, int rpe) async {
    assert(rpe >= 1 && rpe <= 10, 'RPE must be 1–10');
    try {
      final db = await database;
      final affected = await db.update(
        'runs',
        {'rpe': rpe},
        where: 'id = ?',
        whereArgs: [runId],
      );
      if (affected == 0) {
        debugPrint('[DB] updateRunRpe: no row found for id=$runId');
      }
      return affected > 0;
    } catch (e, stack) {
      debugPrint('[DB] updateRunRpe error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  /// Writes the user-facing title for a run (see [RunRecord.title]).
  ///
  /// Returns true if a row was actually updated. Returns false and logs on any
  /// error — never throws.
  Future<bool> updateRunTitle(int runId, String title) async {
    try {
      final db = await database;
      final affected = await db.update(
        'runs',
        {'title': title},
        where: 'id = ?',
        whereArgs: [runId],
      );
      if (affected == 0) {
        debugPrint('[DB] updateRunTitle: no row found for id=$runId');
      }
      return affected > 0;
    } catch (e, stack) {
      debugPrint('[DB] updateRunTitle error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  Future<void> deleteAllRuns() async {
    final db = await database;
    await db.delete('runs');
    await db.delete('best_efforts');
  }

  // ── CRUD: best_efforts ──────────────────────────────────────────────────────

  /// Stores the best-effort segments for one run, REPLACING whatever that run
  /// had before: the run's old rows are deleted and the new ones inserted in
  /// one transaction, so a recompute that now rejects an effort (e.g. it fails
  /// the plausibility rules) removes the stale row instead of leaving it.
  /// Idempotent — rows are keyed `'<runId>_<category>'`. An empty [results]
  /// clears the run's rows. Every row is kept: the leaderboard is ranked at
  /// query time, never trimmed, so deleting a run can promote the next-fastest.
  /// Never blocks or throws — callers should treat this as best-effort, same as
  /// shoe/aggregate updates.
  Future<void> insertBestEffortsForRun(
    String runId,
    List<BestEffortResult> results, {
    DateTime? recordedAt,
  }) async {
    final when = recordedAt ?? DateTime.now();
    try {
      final db = await database;
      await db.transaction((txn) async {
        await txn.delete(
          'best_efforts',
          where: 'run_id = ?',
          whereArgs: [runId],
        );
        for (final r in results) {
          final record = BestEffortRecord(
            id: '${runId}_${r.category.name}',
            runId: runId,
            category: r.category,
            elapsedSeconds: r.elapsedSeconds,
            recordedAt: when,
          );
          await txn.insert(
            'best_efforts',
            record.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e, stack) {
      debugPrint('[DB] insertBestEffortsForRun error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
    }
  }

  Future<void> insertBestEffort(BestEffortRecord record) async {
    try {
      final db = await database;
      await db.insert(
        'best_efforts',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, stack) {
      debugPrint('[DB] insertBestEffort error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
    }
  }

  /// Removes best-effort rows whose run no longer exists (a run deleted by an
  /// older build, or by a path that didn't clean up). Returns rows removed.
  Future<int> deleteOrphanBestEfforts() async {
    try {
      final db = await database;
      return await db.rawDelete(
        'DELETE FROM best_efforts '
        'WHERE run_id NOT IN (SELECT CAST(id AS TEXT) FROM runs)',
      );
    } catch (e, stack) {
      debugPrint('[DB] deleteOrphanBestEfforts error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return 0;
    }
  }

  /// Ids of every stored run, oldest first. Lets the best-efforts rebuild load
  /// runs one at a time instead of holding every run's track samples at once.
  Future<List<int>> getAllRunIds() async {
    try {
      final db = await database;
      final rows = await db.query('runs', columns: ['id'], orderBy: 'id ASC');
      return [for (final r in rows) r['id'] as int];
    } catch (e, stack) {
      debugPrint('[DB] getAllRunIds error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  /// The [limit] fastest efforts for [category], fastest first (null = all).
  /// Ranked here at query time; ties go to the earlier effort, then id, so the
  /// order is stable.
  Future<List<BestEffortRecord>> getBestEffortsForCategory(
    DistanceCategory category, {
    int? limit = 10,
  }) async {
    try {
      final db = await database;
      final rows = await db.query(
        'best_efforts',
        where: 'distance_category = ?',
        whereArgs: [category.name],
        orderBy: 'elapsed_seconds ASC, recorded_at ASC, id ASC',
        limit: limit,
      );
      return rows.map(BestEffortRecord.fromMap).toList();
    } catch (e, stack) {
      debugPrint('[DB] getBestEffortsForCategory error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  /// The best efforts achieved in one run, each with its rank among ALL
  /// retained efforts at that distance and the current all-time best, in
  /// distance order. Read straight from `best_efforts` (no recalculation), and
  /// ranked with the same ordering as [getBestEffortsForCategory] —
  /// `elapsed_seconds, recorded_at, id` — so the rank always equals the
  /// effort's position on the leaderboard. Empty when the run has none.
  Future<List<RunBestEffort>> getRunBestEfforts(String runId) async {
    try {
      final db = await database;
      final mine = await db.query(
        'best_efforts',
        where: 'run_id = ?',
        whereArgs: [runId],
      );
      final out = <RunBestEffort>[];
      for (final row in mine) {
        final record = BestEffortRecord.fromMap(row);
        final category = record.category.name;

        final ahead = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM best_efforts WHERE distance_category = ? AND ('
            'elapsed_seconds < ? OR (elapsed_seconds = ? AND ('
            'recorded_at < ? OR (recorded_at = ? AND id < ?))))',
            [
              category,
              record.elapsedSeconds,
              record.elapsedSeconds,
              row['recorded_at'],
              row['recorded_at'],
              record.id,
            ],
          ),
        );
        final total = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM best_efforts WHERE distance_category = ?',
            [category],
          ),
        );
        final best = await getBestEffortsForCategory(record.category, limit: 1);

        out.add(
          RunBestEffort(
            category: record.category,
            elapsedSeconds: record.elapsedSeconds,
            rank: (ahead ?? 0) + 1,
            totalEfforts: total ?? 1,
            bestSeconds: best.isEmpty
                ? record.elapsedSeconds
                : best.first.elapsedSeconds,
          ),
        );
      }
      out.sort((a, b) => a.category.index.compareTo(b.category.index));
      return out;
    } catch (e, stack) {
      debugPrint('[DB] getRunBestEfforts error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  /// The #1 (fastest) effort for every category that has at least one
  /// recorded effort. Categories never reached by any run are omitted.
  Future<Map<DistanceCategory, BestEffortRecord>> getAllCategoryPRs() async {
    final result = <DistanceCategory, BestEffortRecord>{};
    for (final category in DistanceCategory.values) {
      final top = await getBestEffortsForCategory(category, limit: 1);
      if (top.isNotEmpty) result[category] = top.first;
    }
    return result;
  }

  // ── CRUD: training_snapshots ──────────────────────────────────────────────

  Future<void> insertTrainingSnapshot(TrainingStateRecord snap) async {
    final db = await database;
    await db.insert(
      'training_snapshots',
      snap.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TrainingStateRecord?> getLatestTrainingState() async {
    final db = await database;
    final rows = await db.query(
      'training_snapshots',
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TrainingStateRecord.fromMap(rows.first);
  }

  Future<List<TrainingStateRecord>> getRecentSnapshots({int limit = 28}) async {
    final db = await database;
    final rows = await db.query(
      'training_snapshots',
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map(TrainingStateRecord.fromMap).toList();
  }

  Future<void> deleteAllSnapshots() async {
    final db = await database;
    await db.delete('training_snapshots');
  }

  // ── CRUD: skip_counts ─────────────────────────────────────────────────────

  /// Increments the skip count for [workoutType] by 1.
  Future<void> incrementSkipCount(String workoutType) async {
    try {
      final db = await database;
      await db.rawInsert(
        'INSERT INTO skip_counts (workout_type, count) VALUES (?, 1) '
        'ON CONFLICT(workout_type) DO UPDATE SET count = count + 1',
        [workoutType],
      );
    } catch (e, stack) {
      debugPrint('[DB] incrementSkipCount error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
    }
  }

  /// Returns all skip counts keyed by workout type name.
  Future<Map<String, int>> getSkipCounts() async {
    try {
      final db = await database;
      final rows = await db.query('skip_counts');
      return {
        for (final r in rows) r['workout_type'] as String: r['count'] as int,
      };
    } catch (e, stack) {
      debugPrint('[DB] getSkipCounts error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return {};
    }
  }

  // ── CRUD: achievements ────────────────────────────────────────────────────

  /// Persists an achievement the first time it is earned.
  /// Uses INSERT OR IGNORE so the unlock date is frozen — calling this again
  /// for an already-earned achievement is a no-op.
  /// Returns true if the row was newly inserted (i.e. first time earning it).
  Future<bool> saveAchievementIfNew(
    String type,
    DateTime unlockedAt,
    int tier,
  ) async {
    try {
      final db = await database;
      final affected = await db.rawInsert(
        'INSERT OR IGNORE INTO achievements (type, unlocked_at, tier) '
        'VALUES (?, ?, ?)',
        [type, unlockedAt.toIso8601String(), tier],
      );
      return affected > 0;
    } catch (e, stack) {
      debugPrint('[DB] saveAchievementIfNew error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  /// Returns a map of achievement type name → frozen unlock date.
  Future<Map<String, DateTime>> getAchievementDates() async {
    try {
      final db = await database;
      final rows = await db.query('achievements');
      return {
        for (final r in rows)
          r['type'] as String: DateTime.parse(r['unlocked_at'] as String),
      };
    } catch (e, stack) {
      debugPrint('[DB] getAchievementDates error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return {};
    }
  }

  /// Returns all run dates for duplicate detection during cloud restore.
  Future<List<DateTime>> getAllRunDates() async {
    try {
      final db = await database;
      final rows = await db.query('runs', columns: ['date']);
      return rows.map((r) => DateTime.parse(r['date'] as String)).toList();
    } catch (e) {
      debugPrint('[DB] getAllRunDates error: $e');
      return [];
    }
  }

  // ── SharedPreferences → SQLite one-time migration ─────────────────────────

  Future<void> migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('sqlite_migration_done') ?? false;
      if (done) return;

      final historyJson = prefs.getString('run_history');
      if (historyJson == null || historyJson.isEmpty) {
        await prefs.setBool('sqlite_migration_done', true);
        return;
      }

      final List<dynamic> decoded = json.decode(historyJson);
      final db = await database;
      final batch = db.batch();

      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final gpsPoints = (item['gpsPoints'] as List? ?? []).cast<Map>();
          final polyline = _encodePolyline(gpsPoints);
          final pace = item['averagePace'] as String? ?? '0:00';
          final distKm = (item['distance'] as num?)?.toDouble() ?? 0.0;

          batch.insert('runs', {
            'distance_km': distKm,
            'average_pace': pace,
            'duration_seconds': _estimateDuration(pace, distKm),
            'date': item['date'] as String? ?? DateTime.now().toIso8601String(),
            'route_polyline': polyline,
            'workout_type': 'easy',
            'synced_to_cloud': 0,
            // rpe not available in legacy data — leave NULL
          });
        } catch (_) {
          continue;
        }
      }

      await batch.commit(noResult: true);
      await prefs.setBool('sqlite_migration_done', true);
    } catch (e, stack) {
      debugPrint('[DB] Migration error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
    }
  }

  Future<void> insertRunIfNotExists(RunRecord run) async {
    try {
      final db = await database;
      final runDateUtc = run.date.toUtc();
      final windowStart = runDateUtc
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      final windowEnd = runDateUtc
          .add(const Duration(minutes: 1))
          .toIso8601String();

      final existing = await db.query(
        'runs',
        where: 'date BETWEEN ? AND ? AND ROUND(distance_km, 1) = ROUND(?, 1)',
        whereArgs: [windowStart, windowEnd, run.distanceKm],
      );
      if (existing.isEmpty) {
        await db.insert('runs', run.toMap());
        debugPrint('[DB] Restored run: ${run.distanceKm}km on ${run.date}');
      } else {
        debugPrint(
          '[DB] Skipped duplicate run: ${run.distanceKm}km on ${run.date}',
        );
      }
    } catch (e, stack) {
      debugPrint('insertRunIfNotExists error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static String _encodePolyline(List<Map> points) =>
      points.map((p) => '${p['lat']},${p['lng']}').join(';');

  static int _estimateDuration(String pace, double distKm) {
    try {
      final parts = pace.split(':');
      if (parts.length != 2) return 0;
      final secs = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      return (secs * distKm).round();
    } catch (_) {
      return 0;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top-level helpers (called from home_screen.dart / you_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────

/// Drop-in replacement for the old SharedPreferences-based loadSavedRuns().
/// Returns RunHistory objects that now carry durationSeconds and rpe.
Future<List<RunHistory>> loadSavedRuns() async {
  final records = await DatabaseService.instance.getAllRuns();
  return records.map((r) => r.toRunHistory()).toList();
}

/// Helper for run_screen.dart when encoding GPS route on save.
String encodeRouteToPolyline(List<Map<String, double>> points) =>
    points.map((p) => '${p['lat']},${p['lng']}').join(';');

/// Decodes the app's `"lat,lng;lat,lng"` polyline format into the
/// `[{lat, lng}, ...]` shape used by [RouteTracePainter] and the activity feed.
/// Returns an empty list for an empty or malformed string.
List<Map<String, double>> decodePolylineToPoints(String polyline) {
  if (polyline.isEmpty) return [];
  try {
    return polyline.split(';').where((s) => s.isNotEmpty).map((pair) {
      final parts = pair.split(',');
      return {'lat': double.parse(parts[0]), 'lng': double.parse(parts[1])};
    }).toList();
  } catch (_) {
    return [];
  }
}
