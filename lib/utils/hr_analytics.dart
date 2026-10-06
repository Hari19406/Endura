// lib/utils/hr_analytics.dart
//
// Pure heart-rate analytics: summary (avg / peak) and a time-weighted 5-zone
// breakdown. No Flutter, database, BLE, Health Connect or Supabase imports —
// every input is a plain [HrPoint], so everything here is deterministic and
// unit-testable. The Activity Detail model maps [HrZoneStat] onto its own
// `HrZone` view type.

import 'dart:math' as math;

/// One heart-rate observation. [timeSeconds] is seconds since the start of the
/// recorded phase (the `'t'` field of a track sample); null when unknown.
class HrPoint {
  final double? timeSeconds;
  final int? bpm;

  const HrPoint({this.timeSeconds, this.bpm});
}

/// Average and peak over the valid readings of a run.
class HrSummary {
  final int avg;
  final int peak;

  /// How many readings passed validation.
  final int count;

  const HrSummary({required this.avg, required this.peak, required this.count});
}

/// Time spent in one zone. [percentage] is a 0.0–1.0 share of the time
/// covered by valid HR readings (gaps are excluded from the denominator).
class HrZoneStat {
  final int zone;
  final String label;
  final int durationSeconds;
  final double percentage;

  /// Inclusive bpm bounds, derived from the max HR.
  final int bpmLow;
  final int bpmHigh;

  const HrZoneStat({
    required this.zone,
    required this.label,
    required this.durationSeconds,
    required this.percentage,
    required this.bpmLow,
    required this.bpmHigh,
  });
}

/// The zone model: fractions of max HR at which each zone starts.
class HrZoneConfig {
  /// Lower bound of each zone as a fraction of max HR, ascending.
  final List<double> lowerFractions;

  /// Upper bound of the last zone as a fraction of max HR. Readings above it
  /// still count as the last zone.
  final double topFraction;

  final List<String> labels;

  const HrZoneConfig({
    required this.lowerFractions,
    required this.labels,
    this.topFraction = 1.0,
  });

  /// Z1 50–60 %, Z2 60–70 %, Z3 70–80 %, Z4 80–90 %, Z5 90–100 %+ of max HR.
  static const standard = HrZoneConfig(
    lowerFractions: [0.50, 0.60, 0.70, 0.80, 0.90],
    labels: ['Recovery', 'Easy', 'Aerobic', 'Threshold', 'VO₂ Max'],
  );

  int get zoneCount => lowerFractions.length;

  /// 1-based zone for [bpm]. Readings below the first bound count as zone 1
  /// and readings above the top bound as the last zone.
  int zoneFor(int bpm, int maxHr) {
    final frac = bpm / maxHr;
    var zone = 1;
    for (var i = 0; i < lowerFractions.length; i++) {
      if (frac >= lowerFractions[i]) zone = i + 1;
    }
    return zone;
  }

  /// Inclusive bpm bounds of the 1-based [zone] for [maxHr].
  (int low, int high) boundsFor(int zone, int maxHr) {
    final i = zone - 1;
    final hiFraction = i + 1 < lowerFractions.length
        ? lowerFractions[i + 1]
        : topFraction;
    return ((lowerFractions[i] * maxHr).round(), (hiFraction * maxHr).round());
  }
}

class HrAnalytics {
  HrAnalytics._();

  /// Readings outside this range are sensor errors, not heart rates.
  static const int minValidBpm = 30;
  static const int maxValidBpm = 230;

  /// A reading is credited with at most this many seconds (the time to the
  /// next sample, capped).
  static const double maxDeltaSeconds = 30;

  /// A gap to the next sample longer than this is a dropout and credits no
  /// time at all; gaps between [maxDeltaSeconds] and this are capped.
  static const double gapSeconds = 60;

  /// Credit for a reading with no usable timestamps (no next sample and no
  /// previous interval to borrow) — the track-sample capture interval.
  static const double fallbackDeltaSeconds = 15;

  static bool isValidBpm(int? bpm) =>
      bpm != null && bpm >= minValidBpm && bpm <= maxValidBpm;

  /// Mean and peak of the valid readings, or null when there are none. Null
  /// and physiologically invalid readings are ignored.
  static HrSummary? summary(Iterable<HrPoint> samples) {
    var sum = 0;
    var count = 0;
    var peak = 0;
    for (final s in samples) {
      final bpm = s.bpm;
      if (!isValidBpm(bpm)) continue;
      sum += bpm!;
      count++;
      peak = math.max(peak, bpm);
    }
    if (count == 0) return null;
    return HrSummary(avg: (sum / count).round(), peak: peak, count: count);
  }

  /// Time in each zone for [maxHr], or an empty list when there is no valid
  /// reading to credit time to.
  ///
  /// Each valid reading is credited with the time to the *next* sample (of
  /// any kind, so a null-HR sample ends the previous reading's interval),
  /// capped at [maxDeltaSeconds]; an interval longer than [gapSeconds] is a
  /// dropout and credited nothing. The last reading borrows the previous
  /// interval (or [fallbackDeltaSeconds]); samples without timestamps are
  /// credited [fallbackDeltaSeconds] each.
  static List<HrZoneStat> zones(
    List<HrPoint> samples,
    int maxHr, {
    HrZoneConfig config = HrZoneConfig.standard,
  }) {
    if (maxHr <= 0) return const [];

    // Chronological order when timestamps exist; stable for equal/missing.
    final ordered = <HrPoint>[...samples];
    if (ordered.every((s) => s.timeSeconds != null)) {
      ordered.sort((a, b) => a.timeSeconds!.compareTo(b.timeSeconds!));
    }

    final seconds = List<double>.filled(config.zoneCount, 0);
    double? lastDelta;
    for (var i = 0; i < ordered.length; i++) {
      final bpm = ordered[i].bpm;
      final t = ordered[i].timeSeconds;
      final next = i + 1 < ordered.length ? ordered[i + 1].timeSeconds : null;

      double credit;
      if (t != null && next != null) {
        final delta = next - t;
        if (delta > gapSeconds) {
          lastDelta = null; // dropout — don't borrow across it
          continue;
        }
        credit = delta <= 0 ? 0 : math.min(delta, maxDeltaSeconds);
        lastDelta = credit;
      } else if (t != null && next == null && i + 1 >= ordered.length) {
        credit = lastDelta ?? fallbackDeltaSeconds;
      } else {
        credit = fallbackDeltaSeconds;
      }

      if (!isValidBpm(bpm) || credit <= 0) continue;
      seconds[config.zoneFor(bpm!, maxHr) - 1] += credit;
    }

    final total = seconds.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const [];

    return [
      for (var z = 1; z <= config.zoneCount; z++)
        () {
          final (low, high) = config.boundsFor(z, maxHr);
          return HrZoneStat(
            zone: z,
            label: config.labels[z - 1],
            durationSeconds: seconds[z - 1].round(),
            percentage: seconds[z - 1] / total,
            bpmLow: low,
            bpmHigh: high,
          );
        }(),
    ];
  }
}
