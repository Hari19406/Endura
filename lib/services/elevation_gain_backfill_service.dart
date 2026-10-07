// lib/services/elevation_gain_backfill_service.dart
//
// One-time, version-flagged correction of `runs.elevation_gain` for runs
// already stored on the device. Older builds summed raw GPS altitude deltas,
// which overstated gain; the corrected value comes from the same helper the
// save path now uses ([ElevationGain.fromTrackSamples]).
//
// Runs without usable altitude in their track samples are left exactly as they
// are - nothing is zeroed or invented. The operation is idempotent: the value
// is a pure function of the stored samples, so a rerun changes nothing.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/database_service.dart';
import '../utils/elevation_gain.dart';
import 'cloud_sync_service.dart';

class ElevationGainBackfillResult {
  final int runsSeen;

  /// Runs whose stored gain was rewritten with a different value.
  final int runsUpdated;

  /// Runs with usable samples whose stored gain already matched.
  final int runsUnchanged;

  /// Runs left untouched because they have no usable altitude samples.
  final int runsSkipped;

  final int runsFailed;

  const ElevationGainBackfillResult({
    required this.runsSeen,
    required this.runsUpdated,
    required this.runsUnchanged,
    required this.runsSkipped,
    required this.runsFailed,
  });
}

class ElevationGainBackfillService {
  /// Bump to force one more pass on every device. Stored in SharedPreferences,
  /// no schema change.
  static const int currentVersion = 1;
  static const String prefsKey = 'elevation_gain_backfill_version';

  /// Runs handled between yields to the event loop.
  static const int batchSize = 10;

  ElevationGainBackfillService({
    Future<List<int>> Function()? loadRunIds,
    Future<RunRecord?> Function(int id)? loadRun,
    Future<bool> Function(int id, double gain)? updateLocal,
    Future<bool> Function(int id, double gain)? pushToCloud,
    this.startupDelay = Duration.zero,
    this.batchPause = Duration.zero,
  }) : _loadRunIds = loadRunIds ?? DatabaseService.instance.getAllRunIds,
       _loadRun = loadRun ?? DatabaseService.instance.getRunById,
       _updateLocal =
           updateLocal ?? DatabaseService.instance.updateRunElevationGain,
       _pushToCloud =
           pushToCloud ?? CloudSyncService.instance.updateRunElevationGain;

  static final ElevationGainBackfillService instance =
      ElevationGainBackfillService(startupDelay: const Duration(seconds: 8));

  final Future<List<int>> Function() _loadRunIds;
  final Future<RunRecord?> Function(int id) _loadRun;
  final Future<bool> Function(int id, double gain) _updateLocal;
  final Future<bool> Function(int id, double gain) _pushToCloud;
  final Duration startupDelay;
  final Duration batchPause;

  Future<ElevationGainBackfillResult?>? _inFlight;

  /// Runs [backfill] unless this device already completed [currentVersion].
  /// Returns null when skipped. Concurrent callers share one run. Never throws.
  Future<ElevationGainBackfillResult?> backfillIfNeeded() {
    return _inFlight ??= _backfillIfNeeded().whenComplete(
      () => _inFlight = null,
    );
  }

  Future<ElevationGainBackfillResult?> _backfillIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt(prefsKey) ?? 0) >= currentVersion) return null;
      if (startupDelay > Duration.zero) {
        await Future<void>.delayed(startupDelay);
      }
      final result = await backfill();
      await prefs.setInt(prefsKey, currentVersion);
      debugPrint(
        '[Elevation] backfill v$currentVersion: ${result.runsUpdated} updated, '
        '${result.runsUnchanged} unchanged, ${result.runsSkipped} skipped, '
        '${result.runsFailed} failed',
      );
      return result;
    } catch (e) {
      debugPrint('[Elevation] backfill skipped after error: $e');
      return null;
    }
  }

  /// Recomputes gain for every stored run, regardless of the version flag.
  /// Each corrected run is also re-pushed to the cloud best-effort (it does
  /// nothing when signed out; a run not yet uploaded uploads with the
  /// corrected local value).
  Future<ElevationGainBackfillResult> backfill() async {
    final ids = await _loadRunIds();
    var updated = 0, unchanged = 0, skipped = 0, failed = 0;
    for (var i = 0; i < ids.length; i++) {
      try {
        final run = await _loadRun(ids[i]);
        final gain = run == null
            ? null
            : ElevationGain.fromTrackSamples(run.trackSamples);
        if (run == null || gain == null) {
          skipped++;
        } else if ((run.elevationGain - gain).abs() < 0.05) {
          unchanged++;
        } else if (await _updateLocal(ids[i], gain)) {
          updated++;
          try {
            await _pushToCloud(ids[i], gain);
          } catch (_) {
            // Cloud copy is best-effort; the local value is already fixed.
          }
        } else {
          failed++;
        }
      } catch (e) {
        failed++;
        debugPrint('[Elevation] backfill failed for run ${ids[i]}: $e');
      }
      if ((i + 1) % batchSize == 0) {
        await Future<void>.delayed(batchPause);
      }
    }
    return ElevationGainBackfillResult(
      runsSeen: ids.length,
      runsUpdated: updated,
      runsUnchanged: unchanged,
      runsSkipped: skipped,
      runsFailed: failed,
    );
  }
}
