// lib/services/cloud_sync_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../engines/memory/engine_memory_service.dart';
import '../utils/database_service.dart';

class CloudSyncService {
  static final CloudSyncService instance = CloudSyncService._();
  CloudSyncService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ── Auth helpers ──────────────────────────────────────────────────────────

  String? get _userId => _client.auth.currentUser?.id;
  bool get isSignedIn => _userId != null;

  // ── Upload a single run ───────────────────────────────────────────────────

  Future<bool> uploadRun(RunRecord run) async {
    if (!isSignedIn) return false;

    try {
      final plan = await _planTagFor(run);
      await _client.from('runs').upsert({
        'user_id': _userId,
        'distance_km': run.distanceKm,
        'average_pace': run.averagePace,
        'duration_seconds': run.durationSeconds,
        'date': run.date.toUtc().toIso8601String(),
        'route_polyline': run.routePolyline,
        'workout_type': run.workoutType,
        'cs_value_at_time': run.csValueAtTime,
        'elevation_gain': run.elevationGain,
        // Only include rpe/elapsed when they have a value — avoids overwriting a
        // server-side value with NULL if it's set after the first sync.
        if (run.rpe != null) 'rpe': run.rpe,
        if (run.elapsedSeconds != null) 'elapsed_seconds': run.elapsedSeconds,
        if (plan.$1 != null) 'plan_name': plan.$1,
        if (plan.$2 != null) 'plan_progress': plan.$2,
      });

      await DatabaseService.instance.markRunSynced(run.id!);
      return true;
    } catch (e, stack) {
      debugPrint('CloudSync uploadRun error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  // ── Sync all unsynced local runs ──────────────────────────────────────────

  Future<SyncResult> syncPendingRuns() async {
    if (!isSignedIn) {
      return SyncResult(uploaded: 0, failed: 0, skipped: true);
    }

    try {
      final unsynced = await DatabaseService.instance.getUnsyncedRuns();

      if (unsynced.isEmpty) {
        return SyncResult(uploaded: 0, failed: 0, skipped: false);
      }

      int uploaded = 0;
      int failed = 0;

      for (final run in unsynced) {
        if (await uploadRun(run)) {
          uploaded++;
        } else {
          failed++;
        }
      }

      debugPrint('CloudSync: $uploaded uploaded, $failed failed');
      return SyncResult(uploaded: uploaded, failed: failed, skipped: false);
    } catch (e, stack) {
      debugPrint('CloudSync syncPendingRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return SyncResult(uploaded: 0, failed: 0, skipped: false);
    }
  }

  /// Pushes an RPE update for a run that was already synced.
  ///
  /// Call this immediately after [DatabaseService.updateRunRpe] succeeds so
  /// the cloud row stays in sync without waiting for the next full sync cycle.
  Future<bool> updateRunRpe(int runId, int rpe) async {
    if (!isSignedIn) return false;

    try {
      // Supabase rows are matched by user_id + local SQLite id stored in
      // a `local_id` column. If you don't store local_id in Supabase,
      // match by date + distance instead — see the alternate query below.
      //
      // Option A — if your Supabase `runs` table has a `local_id` column:
      //   await _client
      //       .from('runs')
      //       .update({'rpe': rpe})
      //       .eq('user_id', _userId!)
      //       .eq('local_id', runId);
      //
      // Option B (current) — match by date + distance (no schema change needed):
      final localRun = await _getLocalRun(runId);
      if (localRun == null) {
        debugPrint('[CloudSync] updateRunRpe: run $runId not found locally');
        return false;
      }

      // Use a 60-second window around the run date to tolerate UTC/local drift
      final utcDate = localRun.date.toUtc();
      final windowStart = utcDate
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      final windowEnd = utcDate
          .add(const Duration(minutes: 1))
          .toIso8601String();

      await _client
          .from('runs')
          .update({'rpe': rpe})
          .eq('user_id', _userId!)
          .gte('date', windowStart)
          .lte('date', windowEnd);

      return true;
    } catch (e, stack) {
      debugPrint('[CloudSync] updateRunRpe error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  /// Best-effort resolve of the Supabase `runs.id` for a locally-recorded run,
  /// matched by a ±1-minute date window + a close distance (mirrors
  /// [updateRunRpe]'s approach) — there is no persisted local↔cloud id mapping.
  /// Used to point comments (`activity_comments.run_id`) at the right cloud
  /// row when an [ActivityDetail] only carries a local SQLite id. Returns null
  /// when signed out, unsynced, or no match is found.
  Future<int?> resolveCloudRunId({
    required DateTime date,
    required double distanceKm,
  }) async {
    try {
      // Reads _client/_userId inside the try too: both throw if Supabase was
      // never initialised (tests, preview harnesses), not just on a failed
      // query.
      final uid = _userId;
      if (uid == null) return null;
      final utc = date.toUtc();
      final windowStart = utc
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      final windowEnd = utc.add(const Duration(minutes: 1)).toIso8601String();
      final rows = await _client
          .from('runs')
          .select('id, distance_km')
          .eq('user_id', uid)
          .gte('date', windowStart)
          .lte('date', windowEnd);
      for (final row in (rows as List)) {
        final d = (row['distance_km'] as num?)?.toDouble();
        if (d != null && (d - distanceKm).abs() < 0.05) {
          return (row['id'] as num).toInt();
        }
      }
      return null;
    } catch (e) {
      debugPrint('[CloudSync] resolveCloudRunId error: $e');
      return null;
    }
  }

  // ── Download runs from cloud (new device restore) ─────────────────────────

  Future<bool> downloadAndRestoreRuns() async {
    if (!isSignedIn) return false;

    try {
      final response = await _client
          .from('runs')
          .select()
          .eq('user_id', _userId!)
          .order('date', ascending: false);

      final cloudRuns = response as List<dynamic>;
      debugPrint('CloudSync: found ${cloudRuns.length} runs in cloud');
      if (cloudRuns.isEmpty) return true;

      // Get existing local run dates for dedup
      final localDates = await DatabaseService.instance.getAllRunDates();

      int restored = 0;
      int skipped = 0;
      for (final row in cloudRuns) {
        try {
          final cloudDate = DateTime.parse(row['date'] as String).toLocal();

          // Skip if we already have a run within 60s of this timestamp
          final isDuplicate = localDates.any(
            (d) => d.difference(cloudDate).inSeconds.abs() < 60,
          );
          if (isDuplicate) {
            skipped++;
            continue;
          }

          final run = RunRecord(
            distanceKm: (row['distance_km'] as num).toDouble(),
            averagePace: row['average_pace'] as String,
            durationSeconds: row['duration_seconds'] as int? ?? 0,
            date: cloudDate,
            routePolyline: row['route_polyline'] as String? ?? '',
            workoutType: row['workout_type'] as String? ?? 'easy',
            syncedToCloud: true,
            csValueAtTime: row['cs_value_at_time'] != null
                ? (row['cs_value_at_time'] as num).toDouble()
                : null,
            rpe: row['rpe'] as int?,
            elevationGain: (row['elevation_gain'] as num?)?.toDouble() ?? 0,
            elapsedSeconds: row['elapsed_seconds'] as int?,
          );

          await DatabaseService.instance.insertRun(run);
          restored++;
        } catch (e) {
          debugPrint('CloudSync: failed to restore run: $e');
        }
      }

      debugPrint('CloudSync: restored $restored, skipped $skipped duplicates');
      return true;
    } catch (e, stack) {
      debugPrint('CloudSync downloadAndRestoreRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  /// Pulls the most recent [limit] cloud runs into local SQLite, de-duped by
  /// timestamp. Used by first-login hydration on a fresh device — lighter than
  /// [downloadAndRestoreRuns], which pulls the entire history.
  Future<int> downloadRecentRuns({int limit = 30}) async {
    if (!isSignedIn) return 0;
    try {
      final response = await _client
          .from('runs')
          .select()
          .eq('user_id', _userId!)
          .order('date', ascending: false)
          .limit(limit);

      final localDates = await DatabaseService.instance.getAllRunDates();
      int restored = 0;
      for (final row in (response as List)) {
        try {
          final cloudDate = DateTime.parse(row['date'] as String).toLocal();
          final dup = localDates.any(
            (d) => d.difference(cloudDate).inSeconds.abs() < 60,
          );
          if (dup) continue;
          await DatabaseService.instance.insertRun(
            RunRecord(
              distanceKm: (row['distance_km'] as num).toDouble(),
              averagePace: row['average_pace'] as String,
              durationSeconds: row['duration_seconds'] as int? ?? 0,
              date: cloudDate,
              routePolyline: row['route_polyline'] as String? ?? '',
              workoutType: row['workout_type'] as String? ?? 'easy',
              syncedToCloud: true,
              csValueAtTime: row['cs_value_at_time'] != null
                  ? (row['cs_value_at_time'] as num).toDouble()
                  : null,
              rpe: row['rpe'] as int?,
              elevationGain: (row['elevation_gain'] as num?)?.toDouble() ?? 0,
              elapsedSeconds: row['elapsed_seconds'] as int?,
            ),
          );
          restored++;
        } catch (e) {
          debugPrint('CloudSync downloadRecentRuns: skipped a row: $e');
        }
      }
      debugPrint('CloudSync: hydrated $restored recent runs');
      return restored;
    } catch (e, stack) {
      debugPrint('CloudSync downloadRecentRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return 0;
    }
  }

  // ── Delete all cloud runs for this user (GDPR) ────────────────────────────

  Future<bool> deleteAllCloudRuns() async {
    if (!isSignedIn) return false;

    try {
      await _client.from('runs').delete().eq('user_id', _userId!);
      return true;
    } catch (e, stack) {
      debugPrint('CloudSync deleteAllCloudRuns error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// The `(plan_name, plan_progress)` tag to stamp on a run in the cloud, for
  /// the activity feed. Only guided (non-free) runs made against an active race
  /// plan get one — everything else is `(null, null)` and the columns stay NULL.
  Future<(String?, String?)> _planTagFor(RunRecord run) async {
    if (run.workoutType == 'free') return (null, null);
    try {
      final plan = (await EngineMemoryService().load()).racePlan;
      if (plan == null) return (null, null);
      final name = switch (plan.goalRace) {
        '10k' => '10K Plan',
        'half_marathon' => 'Half Marathon Plan',
        'marathon' => 'Marathon Plan',
        '5k' => '5K Plan',
        _ => 'Training Plan',
      };
      final progress = plan.totalWeeks > 0
          ? 'Week ${plan.currentWeekNumber(run.date)} / ${plan.totalWeeks}'
          : null;
      return (name, progress);
    } catch (e) {
      debugPrint('[CloudSync] _planTagFor error: $e');
      return (null, null);
    }
  }

  Future<RunRecord?> _getLocalRun(int runId) async {
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query(
        'runs',
        where: 'id = ?',
        whereArgs: [runId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return RunRecord.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }
}

// ── Sync result model ─────────────────────────────────────────────────────────

class SyncResult {
  final int uploaded;
  final int failed;
  final bool skipped;

  SyncResult({
    required this.uploaded,
    required this.failed,
    required this.skipped,
  });

  bool get hasFailures => failed > 0;
  bool get allSucceeded => !skipped && failed == 0;

  @override
  String toString() =>
      'SyncResult(uploaded: $uploaded, failed: $failed, skipped: $skipped)';
}
