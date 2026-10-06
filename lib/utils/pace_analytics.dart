// lib/utils/pace_analytics.dart
//
// Pure pace-zone analytics: how long a run was spent in each of five pace
// zones. No Flutter, database or UI imports — inputs are plain [PacePoint]s.
//
// PACE, NOT SPEED. Every value here is seconds per kilometre, so a LOWER number
// is FASTER and a HIGHER number is SLOWER. "Slower than the cutoff" therefore
// means `pace >= cutoff`; the zone edges are named slow/fast accordingly.
//
// The zone definition reuses Endura's existing Daniels E/M/T/I/R training
// paces (`pacesFor(vdot)` in engines/core): those five ranges have gaps
// between them, so each zone is made contiguous by cutting at the midpoint
// between the neighbouring ranges.

import '../engines/core/vdot_calculator.dart' show pacesFor;

/// One pace observation. [paceSecPerKm] is the instantaneous pace in seconds
/// per km (the track sample's `'pace'`); [timeSeconds] is seconds since the
/// start of the recorded phase; [distanceKm] is cumulative distance.
class PacePoint {
  final double? timeSeconds;
  final double? distanceKm;
  final double? paceSecPerKm;

  const PacePoint({this.timeSeconds, this.distanceKm, this.paceSecPerKm});
}

/// Time (and distance) spent in one pace zone. [percentage] is a 0.0–1.0
/// share of the time covered by valid pace samples.
class PaceZoneStat {
  /// 1 = easiest … 5 = hardest.
  final int zone;
  final String label;
  final int durationSeconds;
  final double percentage;

  /// Distance covered in this zone, in km. Null when the samples carried no
  /// distance (old runs without it).
  final double? distanceKm;

  /// The slower (higher sec/km) edge of the zone, or null when open-ended
  /// (zone 1 has no slow limit).
  final int? slowEdgeSecPerKm;

  /// The faster (lower sec/km) edge of the zone, or null when open-ended
  /// (zone 5 has no fast limit).
  final int? fastEdgeSecPerKm;

  const PaceZoneStat({
    required this.zone,
    required this.label,
    required this.durationSeconds,
    required this.percentage,
    this.distanceKm,
    this.slowEdgeSecPerKm,
    this.fastEdgeSecPerKm,
  });
}

/// Five contiguous pace zones, easiest to hardest, defined by four cutoffs.
class PaceZoneConfig {
  /// Cutoffs in sec/km, strictly descending (slowest first): the edge between
  /// zones 1/2, 2/3, 3/4 and 4/5.
  final List<double> cutoffsSecPerKm;
  final List<String> labels;

  /// The vDOT the zones were built from, when they came from one.
  final int? vdot;

  PaceZoneConfig({
    required List<double> cutoffsSecPerKm,
    List<String> labels = defaultLabels,
    this.vdot,
  }) : cutoffsSecPerKm = List.unmodifiable(cutoffsSecPerKm),
       labels = List.unmodifiable(labels) {
    if (cutoffsSecPerKm.length != 4 || labels.length != 5) {
      throw ArgumentError('PaceZoneConfig needs 4 cutoffs and 5 labels');
    }
    for (var i = 0; i < 3; i++) {
      if (cutoffsSecPerKm[i] <= cutoffsSecPerKm[i + 1]) {
        throw ArgumentError(
          'cutoffs must be strictly descending (slowest pace first)',
        );
      }
    }
  }

  static const defaultLabels = [
    'Easy',
    'Marathon',
    'Threshold',
    'Interval',
    'Repetition',
  ];

  /// Zones from the athlete's vDOT using the Daniels E/M/T/I/R table
  /// (clamped to the table's 30–85 range). Each cutoff is the midpoint of the
  /// gap between a zone's faster bound and the next-harder zone's slower
  /// bound.
  factory PaceZoneConfig.fromVdot(int vdot) {
    final p = pacesFor(vdot);
    double mid(int fasterOfEasier, int slowerOfHarder) =>
        (fasterOfEasier + slowerOfHarder) / 2;
    return PaceZoneConfig(
      vdot: vdot,
      cutoffsSecPerKm: [
        mid(p.ePaceSecPerKm.$1, p.mPaceSecPerKm.$2),
        mid(p.mPaceSecPerKm.$1, p.tPaceSecPerKm.$2),
        mid(p.tPaceSecPerKm.$1, p.iPaceSecPerKm.$2),
        mid(p.iPaceSecPerKm.$1, p.rPaceSecPerKm.$2),
      ],
    );
  }

  /// 1-based zone for [paceSecPerKm]. A pace exactly on a cutoff belongs to
  /// the EASIER zone (slower-or-equal). Open-ended at both ends: anything
  /// slower than cutoff 1 is zone 1 and anything faster than cutoff 4 is
  /// zone 5 — callers decide separately whether a pace is valid at all.
  int zoneFor(double paceSecPerKm) {
    for (var i = 0; i < 4; i++) {
      if (paceSecPerKm >= cutoffsSecPerKm[i]) return i + 1;
    }
    return 5;
  }

  /// Slow edge of [zone] (null for zone 1).
  double? slowEdge(int zone) => zone == 1 ? null : cutoffsSecPerKm[zone - 2];

  /// Fast edge of [zone] (null for zone 5).
  double? fastEdge(int zone) => zone == 5 ? null : cutoffsSecPerKm[zone - 1];
}

class PaceAnalytics {
  PaceAnalytics._();

  /// Paces outside this range are GPS glitches, standing still or walking,
  /// not running: faster than 2:00/km or slower than 30:00/km. They are not
  /// classified and do not count toward the percentage denominator.
  static const double minValidPaceSecPerKm = 120;
  static const double maxValidPaceSecPerKm = 1800;

  /// A sample is credited with at most this long (the time to the next one).
  static const double maxDeltaSeconds = 30;

  /// A gap to the next sample longer than this is a dropout: credited nothing.
  static const double gapSeconds = 60;

  /// Credit for a sample with no usable timestamps — Endura's track-sample
  /// capture interval — so old runs without a clock still produce zones.
  static const double fallbackDeltaSeconds = 15;

  static bool isValidPace(double? pace) =>
      pace != null &&
      pace.isFinite &&
      pace >= minValidPaceSecPerKm &&
      pace <= maxValidPaceSecPerKm;

  /// Time in each zone, or an empty list when no sample has a valid pace.
  ///
  /// Each valid sample is credited with the time to the NEXT sample (of any
  /// kind, so a sample with no pace ends the previous one's interval), capped
  /// at [maxDeltaSeconds]; an interval longer than [gapSeconds] is a dropout
  /// and credited nothing. The last sample borrows the previous interval (or
  /// [fallbackDeltaSeconds]); samples without timestamps are credited
  /// [fallbackDeltaSeconds] each. Distance in a zone is the covered distance
  /// to the next sample, scaled by the credited share of the interval.
  static List<PaceZoneStat> zones(
    List<PacePoint> samples,
    PaceZoneConfig config,
  ) {
    final ordered = <PacePoint>[...samples];
    if (ordered.every((s) => s.timeSeconds != null)) {
      ordered.sort((a, b) => a.timeSeconds!.compareTo(b.timeSeconds!));
    }

    final seconds = List<double>.filled(5, 0);
    final km = List<double>.filled(5, 0);
    var anyDistance = false;
    double? lastDelta;

    for (var i = 0; i < ordered.length; i++) {
      final s = ordered[i];
      final isLast = i + 1 >= ordered.length;
      final next = isLast ? null : ordered[i + 1];
      final t = s.timeSeconds;
      final nextT = next?.timeSeconds;

      double credit;
      double? coveredKm;
      if (t != null && nextT != null) {
        final delta = nextT - t;
        if (delta > gapSeconds) {
          lastDelta = null; // dropout — don't borrow across it
          continue;
        }
        credit = delta <= 0
            ? 0
            : (delta < maxDeltaSeconds ? delta : maxDeltaSeconds);
        lastDelta = credit;
        final d0 = s.distanceKm;
        final d1 = next!.distanceKm;
        if (d0 != null && d1 != null && d1 >= d0 && delta > 0) {
          coveredKm = (d1 - d0) * (credit / delta);
        }
      } else if (t != null && isLast) {
        credit = lastDelta ?? fallbackDeltaSeconds;
      } else {
        credit = fallbackDeltaSeconds;
      }

      if (!isValidPace(s.paceSecPerKm) || credit <= 0) continue;
      final z = config.zoneFor(s.paceSecPerKm!) - 1;
      seconds[z] += credit;
      if (coveredKm != null) {
        km[z] += coveredKm;
        anyDistance = true;
      }
    }

    final total = seconds.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const [];

    return [
      for (var z = 1; z <= 5; z++)
        PaceZoneStat(
          zone: z,
          label: config.labels[z - 1],
          durationSeconds: seconds[z - 1].round(),
          percentage: seconds[z - 1] / total,
          distanceKm: anyDistance ? km[z - 1] : null,
          slowEdgeSecPerKm: config.slowEdge(z)?.round(),
          fastEdgeSecPerKm: config.fastEdge(z)?.round(),
        ),
    ];
  }
}
