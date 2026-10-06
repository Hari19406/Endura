// lib/services/athlete_pace_zones.dart
//
// Builds the athlete's pace zones from their current vDOT (the engine
// memory's `vdotScore`), using Endura's existing Daniels E/M/T/I/R table.

import '../engines/memory/engine_memory_service.dart';
import '../utils/pace_analytics.dart';

class AthletePaceZones {
  /// [vdotLoader] defaults to the stored engine memory; injectable so tests
  /// don't need SharedPreferences.
  AthletePaceZones({Future<int?> Function()? vdotLoader})
    : _vdotLoader =
          vdotLoader ??
          (() async => (await EngineMemoryService().load()).vdotScore);

  static final AthletePaceZones instance = AthletePaceZones();

  final Future<int?> Function() _vdotLoader;

  /// Zones for the athlete's current vDOT, or null if it can't be read.
  /// Never throws. Zones use the CURRENT vDOT, not the vDOT at the time of the
  /// run (that isn't stored per run).
  Future<PaceZoneConfig?> resolve() async {
    try {
      final vdot = await _vdotLoader();
      return vdot == null ? null : PaceZoneConfig.fromVdot(vdot);
    } catch (_) {
      return null;
    }
  }
}
