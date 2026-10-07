// lib/services/best_efforts_rebuild_service.dart
//
// One-time, version-flagged rebuild of the `best_efforts` table from the runs
// already stored on the device. It exists because the table was previously
// filled only at save time (so older runs had no efforts), was trimmed to the
// top 10 per distance, and was computed before the plausibility rules.
//
// It does NOT contain a calculation of its own: every run goes through
// BestEffortsService.analyzeRun — the same function the save path uses — with
// the run's stored distance and duration supplying the closing point. Runs
// without usable track samples (before DB v8, or cloud-restored) are skipped;
// no efforts are estimated from splits.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/database_service.dart';
import 'best_efforts_service.dart';

/// What a rebuild did.
class BestEffortsRebuildResult {
  /// Runs looked at.
  final int runsSeen;

  /// Runs recomputed (they had usable samples).
  final int runsProcessed;

  /// Runs skipped because they carry no usable track samples.
  final int runsSkipped;

  /// Runs that threw while being read or computed.
  final int runsFailed;

  /// Effort rows written across all processed runs.
  final int effortsWritten;

  /// Rows removed because their run no longer exists.
  final int orphansRemoved;

  const BestEffortsRebuildResult({
    required this.runsSeen,
    required this.runsProcessed,
    required this.runsSkipped,
    required this.runsFailed,
    required this.effortsWritten,
    required this.orphansRemoved,
  });
}

class BestEffortsRebuildService {
  /// Bump to force one more rebuild on every device (a rule change, a bug fix
  /// in the calculation). Stored in SharedPreferences, no schema change.
  static const int currentVersion = 1;
  static const String prefsKey = 'best_efforts_rebuild_version';

  /// Runs handled between yields to the event loop, so a long history never
  /// blocks the UI thread for more than a few runs at a time.
  static const int batchSize = 10;

  /// Defaults read the real database; every dependency is injectable so the
  /// rebuild can be tested without sqflite.
  BestEffortsRebuildService({
    Future<List<int>> Function()? loadRunIds,
    Future<RunRecord?> Function(int id)? loadRun,
    Future<void> Function(
      String runId,
      List<BestEffortResult> results,
      DateTime recordedAt,
    )?
    replaceRunEfforts,
    Future<int> Function()? deleteOrphans,
    this.startupDelay = Duration.zero,
    this.batchPause = Duration.zero,
  }) : _loadRunIds = loadRunIds ?? DatabaseService.instance.getAllRunIds,
       _loadRun = loadRun ?? DatabaseService.instance.getRunById,
       _replaceRunEfforts =
           replaceRunEfforts ??
           ((runId, results, recordedAt) =>
               DatabaseService.instance.insertBestEffortsForRun(
                 runId,
                 results,
                 recordedAt: recordedAt,
               )),
       _deleteOrphans =
           deleteOrphans ?? DatabaseService.instance.deleteOrphanBestEfforts;

  static final BestEffortsRebuildService instance = BestEffortsRebuildService(
    startupDelay: const Duration(seconds: 5),
  );

  final Future<List<int>> Function() _loadRunIds;
  final Future<RunRecord?> Function(int id) _loadRun;
  final Future<void> Function(
    String runId,
    List<BestEffortResult> results,
    DateTime recordedAt,
  )
  _replaceRunEfforts;
  final Future<int> Function() _deleteOrphans;

  /// Wait this long before starting, so the rebuild doesn't compete with app
  /// start-up.
  final Duration startupDelay;

  /// Pause between batches (zero still yields to the event loop).
  final Duration batchPause;

  Future<BestEffortsRebuildResult?>? _inFlight;

  /// Runs [rebuild] unless this device already completed the current
  /// [currentVersion]. Returns null when skipped. Concurrent callers share one
  /// run. Never throws.
  Future<BestEffortsRebuildResult?> rebuildIfNeeded() {
    return _inFlight ??= _rebuildIfNeeded().whenComplete(
      () => _inFlight = null,
    );
  }

  Future<BestEffortsRebuildResult?> _rebuildIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt(prefsKey) ?? 0) >= currentVersion) return null;

      if (startupDelay > Duration.zero) {
        await Future<void>.delayed(startupDelay);
      }
      final result = await rebuild();

      // Flag only after the whole history has been attempted. A run that fails
      // deterministically is counted in the result rather than retried on every
      // launch; the writes are idempotent, so a crash mid-way just reruns.
      await prefs.setInt(prefsKey, currentVersion);
      debugPrint(
        '[BestEfforts] rebuild v$currentVersion: '
        '${result.runsProcessed} processed, ${result.runsSkipped} skipped, '
        '${result.runsFailed} failed, ${result.effortsWritten} efforts, '
        '${result.orphansRemoved} orphans removed',
      );
      return result;
    } catch (e) {
      debugPrint('[BestEfforts] rebuild skipped after error: $e');
      return null;
    }
  }

  /// Recomputes Best Efforts for every stored run, regardless of the version
  /// flag. Idempotent: each run's rows are replaced, so running it twice yields
  /// the same table.
  Future<BestEffortsRebuildResult> rebuild() async {
    final orphans = await _deleteOrphans();
    final ids = await _loadRunIds();

    var processed = 0, skipped = 0, failed = 0, written = 0;
    for (var i = 0; i < ids.length; i++) {
      try {
        final run = await _loadRun(ids[i]);
        if (run == null || run.trackSamples.length < 2) {
          skipped++;
        } else {
          final results = BestEffortsService.analyzeRun(
            run.trackSamples,
            finalDistanceMeters: run.distanceKm * 1000,
            finalSeconds: run.durationSeconds.toDouble(),
          );
          await _replaceRunEfforts(ids[i].toString(), results, run.date);
          processed++;
          written += results.length;
        }
      } catch (e) {
        failed++;
        debugPrint('[BestEfforts] rebuild failed for run ${ids[i]}: $e');
      }
      // Hand the thread back every batch so the UI stays responsive.
      if ((i + 1) % batchSize == 0) {
        await Future<void>.delayed(batchPause);
      }
    }

    return BestEffortsRebuildResult(
      runsSeen: ids.length,
      runsProcessed: processed,
      runsSkipped: skipped,
      runsFailed: failed,
      effortsWritten: written,
      orphansRemoved: orphans,
    );
  }
}
