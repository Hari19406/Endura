// lib/utils/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'stats.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

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
        // rpe is intentionally omitted when null so SQLite keeps DEFAULT NULL
        // and existing rows are never accidentally zeroed out.
        if (rpe != null) 'rpe': rpe,
        'elevation_gain': elevationGain,
        'splits_json': jsonEncode(splits),
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
      );

  static List<Map<String, dynamic>> _decodeSplits(String? json) {
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

  static List<Map<String, double>> _decodePolyline(String polyline) {
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

// ─────────────────────────────────────────────────────────────────────────────
// DatabaseService
// ─────────────────────────────────────────────────────────────────────────────

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();
  static Database? _db;

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
      // ────────────────────────────────────────────────────────────────────
      version: 7,
      onCreate: (db, _) async {
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
            splits_json       TEXT    NOT NULL DEFAULT '[]'
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
        await db.execute('CREATE INDEX idx_runs_date ON runs(date DESC)');
        await db.execute(
            'CREATE INDEX idx_snap_date ON training_snapshots(date DESC)');
      },
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
                'ALTER TABLE runs ADD COLUMN cs_value_at_time REAL');
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
                'ALTER TABLE runs ADD COLUMN elevation_gain REAL NOT NULL DEFAULT 0');
          } catch (e) {
            debugPrint('[DB] elevation_gain already exists, skipping: $e');
          }
          try {
            await db.execute(
                "ALTER TABLE runs ADD COLUMN splits_json TEXT NOT NULL DEFAULT '[]'");
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
                "UPDATE runs SET rpe = NULL WHERE workout_type = 'free' AND rpe = 0");
          } catch (e) {
            debugPrint('[DB] free-run rpe backfill failed: $e');
          }
        }
      },
    );
  }

  // ── CRUD: runs ────────────────────────────────────────────────────────────

  Future<int> insertRun(RunRecord run) async {
    try {
      final db = await database;
      return db.insert('runs', run.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, stack) {
      debugPrint('insertRun error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return -1;
    }
  }

  Future<void> deleteRun(int id) async {
    final db = await database;
    await db.delete('runs', where: 'id = ?', whereArgs: [id]);
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
      final rows =
          await db.query('runs', orderBy: 'date DESC', limit: limit);
      return rows.map(RunRecord.fromMap).toList();
    } catch (e, stack) {
      debugPrint('getRecentRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
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
    final rows = await db.query('runs',
        where: 'synced_to_cloud = 0', orderBy: 'date ASC');
    return rows.map(RunRecord.fromMap).toList();
  }

  Future<void> markRunSynced(int runId) async {
    final db = await database;
    await db.update('runs', {'synced_to_cloud': 1},
        where: 'id = ?', whereArgs: [runId]);
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

  Future<void> deleteAllRuns() async {
    final db = await database;
    await db.delete('runs');
  }

  // ── CRUD: training_snapshots ──────────────────────────────────────────────

  Future<void> insertTrainingSnapshot(TrainingStateRecord snap) async {
    final db = await database;
    await db.insert('training_snapshots', snap.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<TrainingStateRecord?> getLatestTrainingState() async {
    final db = await database;
    final rows = await db.query('training_snapshots',
        orderBy: 'date DESC', limit: 1);
    if (rows.isEmpty) return null;
    return TrainingStateRecord.fromMap(rows.first);
  }

  Future<List<TrainingStateRecord>> getRecentSnapshots(
      {int limit = 28}) async {
    final db = await database;
    final rows = await db.query('training_snapshots',
        orderBy: 'date DESC', limit: limit);
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
        for (final r in rows)
          r['workout_type'] as String: r['count'] as int,
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
      String type, DateTime unlockedAt, int tier) async {
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
          r['type'] as String:
              DateTime.parse(r['unlocked_at'] as String),
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
      return rows
          .map((r) => DateTime.parse(r['date'] as String))
          .toList();
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
            'date': item['date'] as String? ??
                DateTime.now().toIso8601String(),
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
      final windowStart =
          runDateUtc.subtract(const Duration(minutes: 1)).toIso8601String();
      final windowEnd =
          runDateUtc.add(const Duration(minutes: 1)).toIso8601String();

      final existing = await db.query(
        'runs',
        where:
            'date BETWEEN ? AND ? AND ROUND(distance_km, 1) = ROUND(?, 1)',
        whereArgs: [windowStart, windowEnd, run.distanceKm],
      );
      if (existing.isEmpty) {
        await db.insert('runs', run.toMap());
        debugPrint('[DB] Restored run: ${run.distanceKm}km on ${run.date}');
      } else {
        debugPrint(
            '[DB] Skipped duplicate run: ${run.distanceKm}km on ${run.date}');
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