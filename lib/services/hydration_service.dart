// lib/services/hydration_service.dart
//
// First-login hydration for multi-device support. When a user signs in on a
// device whose local SQLite has no runs yet, pull down their remote profile
// state, shoe locker, and last 30 runs so the app is usable offline
// immediately. Also flushes any locally-queued shoe changes.

import 'package:flutter/foundation.dart';

import '../utils/database_service.dart';
import 'cloud_sync_service.dart';
import 'profile_service.dart';
import 'shoe_service.dart';

class HydrationService {
  static final HydrationService instance = HydrationService._();
  HydrationService._();

  bool _running = false;

  /// Safe to call on every `signedIn` / `initialSession` event. Cheap when the
  /// local DB is already populated.
  Future<void> hydrateOnLogin() async {
    if (_running) return;
    _running = true;
    try {
      // Push first so offline-made shoe edits aren't clobbered by a pull.
      await ShoeService.instance.pushPending();

      final existing = await DatabaseService.instance.getRecentRuns(limit: 1);
      final isFreshDevice = existing.isEmpty;

      if (isFreshDevice) {
        debugPrint('[Hydration] fresh device — pulling remote state');
        await Future.wait([
          ProfileService.instance.syncPlanState(),
          ShoeService.instance.hydrateFromRemote(),
          CloudSyncService.instance.downloadRecentRuns(limit: 30),
        ]);
      }
      // Established devices keep their local locker as the source of truth;
      // cross-device shoe reconciliation is left for a later real sync pass.
    } catch (e) {
      debugPrint('[Hydration] error: $e');
    } finally {
      _running = false;
    }
  }
}
