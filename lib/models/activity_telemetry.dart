// lib/models/activity_telemetry.dart
//
// Data contract for the Activity Detail View — the modern "running telemetry"
// screen (header + summary grid, route preview, training impact, km splits, and
// the scrubbable pace / elevation / heart-rate / cadence charts).
//
// These are plain value types with no Supabase coupling. Today the screen is
// fed by [ActivityDetail.mock] (see the Dev Launcher entry); a real
// `fromRows` factory can be added when the `runs` table grows the matching
// per-sample columns.

import 'dart:math' as math;

/// One finished kilometre (or the final partial km) of a run.
class KmSplit {
  /// 1-based kilometre index. The last entry may cover < 1 km.
  final int km;

  /// Moving time for this split, in seconds.
  final int paceSeconds;

  /// Net elevation change across the split, in metres (may be negative).
  final double elevationChangeM;

  /// Average heart rate held during the split, in bpm.
  final int avgHr;

  const KmSplit({
    required this.km,
    required this.paceSeconds,
    required this.elevationChangeM,
    required this.avgHr,
  });

  /// "m:ss" per-km label.
  String get paceLabel =>
      '${paceSeconds ~/ 60}:${(paceSeconds % 60).toString().padLeft(2, '0')}';
}

/// A single point on the high-resolution telemetry trace, keyed by cumulative
/// distance so every series shares one X axis.
class TelemetrySample {
  final double distanceKm;
  final int paceSeconds; // instantaneous pace, sec/km
  final int hrBpm;
  final double elevationM;
  final int cadenceSpm; // steps per minute (both feet)

  const TelemetrySample({
    required this.distanceKm,
    required this.paceSeconds,
    required this.hrBpm,
    required this.elevationM,
    required this.cadenceSpm,
  });
}

/// Time spent in one heart-rate zone (Z1–Z5).
class HrZone {
  /// 1-based zone number.
  final int zone;

  /// Short label, e.g. "Easy", "Threshold".
  final String label;

  final int durationSeconds;

  /// Fraction of moving time in this zone, 0.0–1.0.
  final double percentage;

  /// Inclusive bpm bounds for the zone.
  final int bpmLow;
  final int bpmHigh;

  const HrZone({
    required this.zone,
    required this.label,
    required this.durationSeconds,
    required this.percentage,
    required this.bpmLow,
    required this.bpmHigh,
  });

  String get bpmRange => '$bpmLow–$bpmHigh bpm';

  String get durationLabel {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  String get percentLabel => '${(percentage * 100).round()}%';
}

/// Coaching-engine read on what the run did to the athlete's model.
class TrainingImpact {
  /// Bump to the long-term fitness (CTL-like) track, e.g. +0.6.
  final double fitnessImpact;

  /// Bump to short-term fatigue (ATL-like) track, e.g. +3.6.
  final double fatigueImpact;

  /// Headline training-load score for the session, e.g. +27.
  final int impactScore;

  const TrainingImpact({
    required this.fitnessImpact,
    required this.fatigueImpact,
    required this.impactScore,
  });

  /// Share of the fitness+fatigue split that is "fitness", 0.0–1.0. Used to
  /// size the horizontal split-ratio bar.
  double get fitnessRatio {
    final total = fitnessImpact.abs() + fatigueImpact.abs();
    if (total <= 0) return 0.5;
    return (fitnessImpact.abs() / total).clamp(0.0, 1.0);
  }
}

/// Everything the Activity Detail View needs to render one run.
class ActivityDetail {
  // ── Header ────────────────────────────────────────────────────────────────
  final String runnerName;
  final DateTime timestamp;
  final String source; // "Garmin", "Endura Tracker", …
  final String location; // "Cubbon Park, Bengaluru"
  final String title; // freeform run title
  final String? avatarUrl;

  // ── Summary metrics ───────────────────────────────────────────────────────
  final double distanceKm;
  final String avgPace; // "m:ss" per km
  final Duration movingTime;
  final double elevationGainM;
  final int calories;

  // ── Training impact ───────────────────────────────────────────────────────
  final TrainingImpact trainingImpact;

  // ── Series ────────────────────────────────────────────────────────────────
  final List<KmSplit> splits;
  final List<TelemetrySample> telemetrySeries;
  final List<HrZone> hrZones;

  // ── Aggregates ────────────────────────────────────────────────────────────
  final int avgCadence;
  final int peakCadence;
  final int avgHr;
  final int peakHr;
  final String avgGapPace; // grade-adjusted, "m:ss" per km

  /// Decoded `{lat, lng}` points for the route preview. May be empty.
  final List<Map<String, double>> routePoints;

  const ActivityDetail({
    required this.runnerName,
    required this.timestamp,
    required this.source,
    required this.location,
    required this.title,
    this.avatarUrl,
    required this.distanceKm,
    required this.avgPace,
    required this.movingTime,
    required this.elevationGainM,
    required this.calories,
    required this.trainingImpact,
    required this.splits,
    required this.telemetrySeries,
    required this.hrZones,
    required this.avgCadence,
    required this.peakCadence,
    required this.avgHr,
    required this.peakHr,
    required this.avgGapPace,
    this.routePoints = const [],
  });

  /// Fastest split's pace in seconds — the reference the splits-bar lengths are
  /// measured against. Falls back to the slowest value when there are no splits.
  int get fastestSplitSeconds => splits.isEmpty
      ? 0
      : splits.map((s) => s.paceSeconds).reduce(math.min);

  int get slowestSplitSeconds => splits.isEmpty
      ? 0
      : splits.map((s) => s.paceSeconds).reduce(math.max);

  // ───────────────────────────────────────────────────────────────────────────
  //  Mock fixture
  // ───────────────────────────────────────────────────────────────────────────

  /// A realistic ~11.73 km progression run used by the Dev Launcher and tests.
  /// Deterministic — everything is derived from a seeded [math.Random].
  factory ActivityDetail.mock() {
    const totalKm = 11.73;
    final rng = math.Random(1173);

    // ── Telemetry trace: one sample every ~150 m ────────────────────────────
    final samples = <TelemetrySample>[];
    const step = 0.15;
    double elev = 42;
    for (double d = 0; d <= totalKm + 0.0001; d += step) {
      final t = d / totalKm; // 0..1 progress

      // Negative-split effort: starts ~5:25/km, finishes ~4:48/km, with a
      // mid-run hill that bleeds ~20 s/km and a fast last 400 m.
      final base = 325 - 37 * t;
      final hill = 20 * math.exp(-math.pow((t - 0.45) * 6, 2).toDouble());
      final kick = t > 0.94 ? -18.0 : 0.0;
      final noise = (rng.nextDouble() - 0.5) * 10;
      final pace = (base + hill + kick + noise).round().clamp(255, 360);

      // Rolling terrain: a climb into the mid-run hill, then net downhill.
      final grade = math.sin(t * math.pi * 2.2) * 3.4 +
          6 * math.exp(-math.pow((t - 0.45) * 5, 2).toDouble());
      elev += grade * step * 4 + (rng.nextDouble() - 0.5) * 1.2;

      // HR drifts up with effort + cardiac drift, spikes on the hill.
      final hr = (150 +
              22 * t +
              10 * math.exp(-math.pow((t - 0.47) * 6, 2).toDouble()) +
              (kick != 0 ? 6 : 0) +
              (rng.nextDouble() - 0.5) * 4)
          .round()
          .clamp(132, 184);

      final cad = (176 +
              4 * t +
              (kick != 0 ? 5 : 0) -
              (hill > 6 ? 3 : 0) +
              (rng.nextDouble() - 0.5) * 4)
          .round()
          .clamp(164, 190);

      samples.add(TelemetrySample(
        distanceKm: double.parse(d.clamp(0, totalKm).toStringAsFixed(3)),
        paceSeconds: pace,
        hrBpm: hr,
        elevationM: double.parse(elev.toStringAsFixed(1)),
        cadenceSpm: cad,
      ));
    }

    // ── Km splits: average the trace over each 1 km bucket ──────────────────
    final splits = <KmSplit>[];
    final kmCount = totalKm.ceil();
    for (var k = 1; k <= kmCount; k++) {
      final lo = (k - 1).toDouble();
      final hi = math.min(k.toDouble(), totalKm);
      final inBucket =
          samples.where((s) => s.distanceKm >= lo && s.distanceKm <= hi).toList();
      if (inBucket.isEmpty) continue;
      final avgPaceSec = (inBucket.map((s) => s.paceSeconds).reduce((a, b) => a + b) /
              inBucket.length)
          .round();
      final spanKm = hi - lo;
      final elevChange =
          inBucket.last.elevationM - inBucket.first.elevationM;
      final avgHr = (inBucket.map((s) => s.hrBpm).reduce((a, b) => a + b) /
              inBucket.length)
          .round();
      splits.add(KmSplit(
        km: k,
        paceSeconds: (avgPaceSec * spanKm).round(),
        elevationChangeM: double.parse(elevChange.toStringAsFixed(1)),
        avgHr: avgHr,
      ));
    }

    // ── HR zones (est. max 188) ────────────────────────────────────────────
    const maxHr = 188;
    final zoneDefs = <int, ({String label, int lo, int hi})>{
      1: (label: 'Recovery', lo: 94, hi: 122),
      2: (label: 'Easy', lo: 123, hi: 141),
      3: (label: 'Aerobic', lo: 142, hi: 160),
      4: (label: 'Threshold', lo: 161, hi: 175),
      5: (label: 'VO₂ Max', lo: 176, hi: maxHr),
    };
    // Bucket every sample (≈ equal dt between samples) into its zone.
    final counts = {for (var z = 1; z <= 5; z++) z: 0};
    for (final s in samples) {
      var z = 1;
      for (final e in zoneDefs.entries) {
        if (s.hrBpm >= e.value.lo) z = e.key;
      }
      counts[z] = counts[z]! + 1;
    }
    final movingSeconds = 3491; // 58:11
    final totalSamples = samples.length;
    final hrZones = <HrZone>[];
    for (var z = 1; z <= 5; z++) {
      final frac = totalSamples == 0 ? 0.0 : counts[z]! / totalSamples;
      final def = zoneDefs[z]!;
      hrZones.add(HrZone(
        zone: z,
        label: def.label,
        durationSeconds: (frac * movingSeconds).round(),
        percentage: double.parse(frac.toStringAsFixed(3)),
        bpmLow: def.lo,
        bpmHigh: def.hi,
      ));
    }

    final elevGain = _cumulativeGain(samples);
    final hrValues = samples.map((s) => s.hrBpm).toList();
    final cadValues = samples.map((s) => s.cadenceSpm).toList();

    return ActivityDetail(
      runnerName: 'Aditya Rao',
      timestamp: DateTime(2026, 9, 7, 6, 42),
      source: 'Garmin',
      location: 'Cubbon Park, Bengaluru',
      title: 'Sunday progression — negative split',
      avatarUrl: null,
      distanceKm: totalKm,
      avgPace: '4:58',
      movingTime: const Duration(seconds: 3491),
      elevationGainM: elevGain,
      calories: 812,
      trainingImpact: const TrainingImpact(
        fitnessImpact: 0.6,
        fatigueImpact: 3.6,
        impactScore: 27,
      ),
      splits: splits,
      telemetrySeries: samples,
      hrZones: hrZones,
      avgCadence:
          (cadValues.reduce((a, b) => a + b) / cadValues.length).round(),
      peakCadence: cadValues.reduce(math.max),
      avgHr: (hrValues.reduce((a, b) => a + b) / hrValues.length).round(),
      peakHr: hrValues.reduce(math.max),
      avgGapPace: '4:53',
      routePoints: _mockRoute(),
    );
  }

  static double _cumulativeGain(List<TelemetrySample> s) {
    double gain = 0;
    for (var i = 1; i < s.length; i++) {
      final d = s[i].elevationM - s[i - 1].elevationM;
      if (d > 0) gain += d;
    }
    return double.parse(gain.toStringAsFixed(0));
  }

  /// A rough closed loop around Cubbon Park (~11.7 km of switchbacks).
  static List<Map<String, double>> _mockRoute() {
    final rng = math.Random(77);
    const centerLat = 12.9763;
    const centerLng = 77.5929;
    final pts = <Map<String, double>>[];
    const n = 90;
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2;
      // Wobbly radius so it reads like streets, not a circle.
      final r = 0.010 +
          0.004 * math.sin(a * 3) +
          0.0018 * math.sin(a * 7) +
          (rng.nextDouble() - 0.5) * 0.0009;
      pts.add({
        'lat': centerLat + r * math.sin(a) * 0.72,
        'lng': centerLng + r * math.cos(a),
      });
    }
    pts.add(Map<String, double>.from(pts.first)); // close the loop
    return pts;
  }
}
