// lib/services/hr_session.dart
//
// Collects heart-rate readings for ONE run: validates them, tracks whether the
// latest reading is still fresh, and accumulates the average/peak that get
// saved. Pure Dart — the run screen feeds it readings and decides when they
// count, so none of this needs BLE, Health Connect or a widget to test.
//
// Two source kinds are kept apart because they sample very differently:
//   • BLE strap/watch: ~1 Hz instantaneous bpm → "fresh" for a few seconds.
//   • Health Connect/HealthKit poll: a ~35 s-window average every ~30 s →
//     "fresh" for most of a poll interval, and never mixed into BLE stats.

import '../utils/hr_analytics.dart';

enum HrSourceKind { ble, healthPoll }

class HrSession {
  /// How long a BLE reading may be used as "the current HR".
  static const Duration bleFreshness = Duration(seconds: 5);

  /// How long a Health Connect/HealthKit poll value may be used.
  static const Duration pollFreshness = Duration(seconds: 45);

  final _Stats _ble = _Stats();
  final _Stats _poll = _Stats();

  int? _latestBpm;
  DateTime? _latestAt;
  HrSourceKind? _latestSource;

  /// Readings rejected by the 30–230 bpm sanity filter.
  int rejectedCount = 0;

  /// Records one reading.
  ///
  /// Readings outside [HrAnalytics.minValidBpm]–[HrAnalytics.maxValidBpm] are
  /// discarded entirely. A valid reading is only kept when [counting] is true
  /// — i.e. the run is running and in the main set, the same window as
  /// distance, pace and the track samples. A warmup, cooldown or paused
  /// reading therefore affects neither the average/peak nor the "current" HR
  /// a main-set sample can pick up.
  void onReading(
    int bpm,
    DateTime now, {
    required HrSourceKind source,
    required bool counting,
  }) {
    if (!HrAnalytics.isValidBpm(bpm)) {
      rejectedCount++;
      return;
    }
    if (!counting) return;
    _latestBpm = bpm;
    _latestAt = now;
    _latestSource = source;
    (source == HrSourceKind.ble ? _ble : _poll).add(bpm);
  }

  /// The latest counted reading if it is still fresh at [now], else null.
  /// [maxAge] defaults to the source's own window ([bleFreshness] for BLE,
  /// [pollFreshness] for Health Connect/HealthKit). A stale reading (strap
  /// dropped, poll missed) must not be written into a track sample.
  int? currentOrNull(DateTime now, {Duration? maxAge}) {
    final bpm = _latestBpm;
    final at = _latestAt;
    final source = _latestSource;
    if (bpm == null || at == null || source == null) return null;
    final limit =
        maxAge ?? (source == HrSourceKind.ble ? bleFreshness : pollFreshness);
    return now.difference(at) > limit ? null : bpm;
  }

  /// Forgets the current reading from [source] (e.g. the strap disconnected)
  /// so it can't be reused. The average/peak already accumulated stay.
  void invalidateCurrent(HrSourceKind source) {
    if (_latestSource != source) return;
    _latestBpm = null;
    _latestAt = null;
    _latestSource = null;
  }

  /// BLE readings take precedence over poll values: if the strap delivered
  /// anything during the counted window, the poll's window averages are left
  /// out of the run's average and peak.
  _Stats? get _active => _ble.count > 0
      ? _ble
      : _poll.count > 0
      ? _poll
      : null;

  /// Which source the average/peak came from, or null with no counted data.
  HrSourceKind? get activeSource => _ble.count > 0
      ? HrSourceKind.ble
      : _poll.count > 0
      ? HrSourceKind.healthPoll
      : null;

  /// Mean of the counted, valid readings, or null if there are none.
  int? get avg => _active?.avg;

  /// Highest counted, valid reading, or null if there are none.
  int? get peak => _active?.peak;

  /// How many readings make up [avg]/[peak].
  int get countedReadings => _active?.count ?? 0;

  void reset() {
    _ble.clear();
    _poll.clear();
    _latestBpm = null;
    _latestAt = null;
    _latestSource = null;
    rejectedCount = 0;
  }
}

class _Stats {
  int count = 0;
  int _sum = 0;
  int peak = 0;

  void add(int bpm) {
    count++;
    _sum += bpm;
    if (bpm > peak) peak = bpm;
  }

  int get avg => (_sum / count).round();

  void clear() {
    count = 0;
    _sum = 0;
    peak = 0;
  }
}
