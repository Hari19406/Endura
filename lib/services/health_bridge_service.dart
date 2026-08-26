// lib/services/health_bridge_service.dart

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final HealthFactory _health = HealthFactory();

  static const _types = [HealthDataType.HEART_RATE, HealthDataType.STEPS];
  static const _prefsGrantedKey = 'health_connect_permissions_granted';

  bool _authorized = false;

  /// Triggers the native OS consent screen (Health Connect/HealthKit). Only
  /// call this from an explicit user action (e.g. tapping the Settings
  /// "Health Connect" tile) — never from a background timer, since it can
  /// surface a system permission dialog unprompted.
  Future<bool> requestPermissions() async {
    try {
      _authorized = await _health.requestAuthorization(List.of(_types));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsGrantedKey, _authorized);
      return _authorized;
    } catch (e) {
      debugPrint('[HealthBridgeService] requestPermissions failed: $e');
      return false;
    }
  }

  /// Safe to call anywhere (background timers, save-time backfill) — reads
  /// the persisted result of the last explicit [requestPermissions] call
  /// rather than re-invoking the OS consent flow.
  Future<bool> hasPermissions() async {
    if (_authorized) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _authorized = prefs.getBool(_prefsGrantedKey) ?? false;
      return _authorized;
    } catch (_) {
      return false;
    }
  }

  Future<List<HealthHrSample>> fetchHeartRateSeries(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final points = await _health.getHealthDataFromTypes(start, end, [
        HealthDataType.HEART_RATE,
      ]);
      return points
          .map((p) => HealthHrSample(p.dateFrom, p.value.round()))
          .toList();
    } catch (e) {
      debugPrint('[HealthBridgeService] fetchHeartRateSeries failed: $e');
      return [];
    }
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
      final points = await _health.getHealthDataFromTypes(start, end, [
        HealthDataType.STEPS,
      ]);
      if (points.isEmpty) return null;
      final totalSteps = points.fold<double>(
        0,
        (acc, p) => acc + p.value.toDouble(),
      );
      final minutes = end.difference(start).inSeconds / 60.0;
      if (minutes <= 0) return null;
      return (totalSteps / minutes).round();
    } catch (e) {
      debugPrint('[HealthBridgeService] fetchAverageCadence failed: $e');
      return null;
    }
  }
}
