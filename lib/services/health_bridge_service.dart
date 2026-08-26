// lib/services/health_bridge_service.dart

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthHrSample {
  final DateTime time;
  final int bpm;
  const HealthHrSample(this.time, this.bpm);
}

/// Bridge to Android Health Connect / iOS HealthKit via the `health` package.
/// Used as (a) a fallback live-poll source during a run when no BLE heart
/// rate monitor is connected, and (b) an authoritative backfill at save time
/// to reconcile/fill gaps. Every call is best-effort — failures return
/// null/empty rather than throwing, so a missing/denied health source never
/// crashes or blocks a run.
class HealthBridgeService {
  HealthBridgeService._();
  static final HealthBridgeService instance = HealthBridgeService._();

  final Health _health = Health();
  bool _configured = false;

  static const _types = [HealthDataType.HEART_RATE, HealthDataType.STEPS];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Triggers the native OS consent screen (Health Connect/HealthKit). Only
  /// call this from an explicit user action (e.g. tapping the Settings
  /// "Health Connect" tile) — never from a background timer, since it can
  /// surface a system permission dialog unprompted.
  Future<bool> requestPermissions() async {
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(List.of(_types));
    } catch (e) {
      debugPrint('[HealthBridgeService] requestPermissions failed: $e');
      return false;
    }
  }

  /// Safe to call anywhere (background timers, save-time backfill) — a real
  /// permission-status check, never triggers the OS consent flow.
  Future<bool> hasPermissions() async {
    try {
      await _ensureConfigured();
      return await _health.hasPermissions(List.of(_types)) ?? false;
    } catch (e) {
      debugPrint('[HealthBridgeService] hasPermissions failed: $e');
      return false;
    }
  }

  Future<List<HealthHrSample>> fetchHeartRateSeries(
    DateTime start,
    DateTime end,
  ) async {
    try {
      await _ensureConfigured();
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: start,
        endTime: end,
      );
      final samples = <HealthHrSample>[];
      for (final p in points) {
        final bpm = _asBpm(p);
        if (bpm != null) samples.add(HealthHrSample(p.dateFrom, bpm));
      }
      return samples;
    } catch (e) {
      debugPrint('[HealthBridgeService] fetchHeartRateSeries failed: $e');
      return [];
    }
  }

  int? _asBpm(HealthDataPoint p) {
    final v = p.value;
    if (v is NumericHealthValue) return v.numericValue.round();
    return null;
  }

  Future<int?> fetchAverageHeartRate(DateTime start, DateTime end) async {
    final series = await fetchHeartRateSeries(start, end);
    if (series.isEmpty) return null;
    final sum = series.fold<int>(0, (acc, s) => acc + s.bpm);
    return (sum / series.length).round();
  }

  Future<int?> fetchPeakHeartRate(DateTime start, DateTime end) async {
    final series = await fetchHeartRateSeries(start, end);
    if (series.isEmpty) return null;
    return series.map((s) => s.bpm).reduce((a, b) => a > b ? a : b);
  }

  /// Health Connect/HealthKit don't expose a direct "instantaneous cadence"
  /// record on most devices — this derives a coarse average spm from STEPS
  /// records over the window. Used only when BLE RSC never connected for
  /// the run; never presented as a live/instant value.
  Future<int?> fetchAverageCadence(DateTime start, DateTime end) async {
    try {
      await _ensureConfigured();
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );
      if (points.isEmpty) return null;
      double totalSteps = 0;
      for (final p in points) {
        final v = p.value;
        if (v is NumericHealthValue) totalSteps += v.numericValue.toDouble();
      }
      final minutes = end.difference(start).inSeconds / 60.0;
      if (minutes <= 0 || totalSteps <= 0) return null;
      return (totalSteps / minutes).round();
    } catch (e) {
      debugPrint('[HealthBridgeService] fetchAverageCadence failed: $e');
      return null;
    }
  }
}
