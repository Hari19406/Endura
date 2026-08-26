// lib/services/ble_scanner_service.dart

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Thin shared wrapper around FlutterBluePlus scanning, filtered by a single
/// GATT service UUID (used by both the heart-rate and cadence pairing flows
/// so they don't each duplicate scan/stop logic).
class BleScannerService {
  BleScannerService._();
  static final BleScannerService instance = BleScannerService._();

  /// Scans for nearby devices advertising [serviceUuid] and returns whatever
  /// was found once scanning stops (either at [timeout] or via [stopScan]).
  Future<List<ScanResult>> scanForService(
    Guid serviceUuid, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final results = <String, ScanResult>{};
    final sub = FlutterBluePlus.onScanResults.listen((batch) {
      for (final r in batch) {
        results[r.device.remoteId.str] = r;
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [serviceUuid],
        timeout: timeout,
      );
      await Future.delayed(timeout);
    } finally {
      await sub.cancel();
      await stopScan();
    }
    return results.values.toList();
  }

  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }
}
