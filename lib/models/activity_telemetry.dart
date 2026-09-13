// lib/models/activity_telemetry.dart
//
// Data contract for the Activity Detail View — the modern "running telemetry"
// screen (header + summary grid, route preview, training impact, km splits, and
// the scrubbable pace / elevation / heart-rate / cadence charts).
//
// The value types carry no Supabase coupling; the hydration factories at the
// bottom ([ActivityDetail.fromFeedRun], [ActivityDetail.fromRunRecord]) do the
// app-model → view-model mapping and are the only part that imports app types.
// Every per-sample / per-split field that a basic GPS-only or manual run may
// lack is nullable so the screen can omit the sections it can't populate.

import 'dart:math' as math;

import '../utils/database_service.dart' show RunRecord, decodePolylineToPoints;
import 'feed_run.dart';

/// One finished kilometre (or the final partial km) of a run.
class KmSplit {
  /// 1-based kilometre index. The last entry may cover < 1 km.
  final int km;

  /// Moving time for this split, in seconds.
  final int paceSeconds;

  /// Net elevation change across the split, in metres (may be negative).
  /// Null when the run had no altitude track.
  final double? elevationChangeM;

  /// Average heart rate held during the split, in bpm. Null when the run had
  /// no HR source.
  final int? avgHr;

  const KmSplit({
    required this.km,
    required this.paceSeconds,
    this.elevationChangeM,
    this.avgHr,
  });

  /// "m:ss" per-km label.
  String get paceLabel =>
      '${paceSeconds ~/ 60}:${(paceSeconds % 60).toString().padLeft(2, '0')}';
}

/// A single point on the high-resolution telemetry trace, keyed by cumulative
/// distance so every series shares one X axis. Any metric channel may be null
/// for a given sample (e.g. HR strap dropped, no barometer).
class TelemetrySample {
  final double distanceKm;
  final int? paceSeconds; // instantaneous pace, sec/km
  final int? hrBpm;
  final double? elevationM;
  final int? cadenceSpm; // steps per minute (both feet)

  const TelemetrySample({
    required this.distanceKm,
    this.paceSeconds,
    this.hrBpm,
    this.elevationM,
    this.cadenceSpm,
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

/// Everything the Activity Detail View needs to render one run.
class ActivityDetail {
  // ── Identity ──────────────────────────────────────────────────────────────
  /// Backing `runs.id`. Null for fixtures with no persisted row — the social
  /// actions (comments) degrade gracefully in that case.
  final int? runId;

  /// True when [runId] is a **Supabase** `runs.id` — safe to use directly for
  /// social features (comments). False when it's only a local SQLite id (the
  /// You/History tab, before there's a known cloud row) — there is no
  /// persisted local↔cloud id mapping, so the screen resolves the cloud id by
  /// date + distance the moment a social action needs it. See
  /// [CloudSyncService.resolveCloudRunId].
  final bool runIdIsCloud;

  /// Owning athlete's id (`runs.user_id`). Used for share-link building.
  final String? athleteId;

  /// Comments already on this activity, for the pill badge. The comment sheet
  /// fetches the live list itself.
  final int commentCount;

  /// Cheers/reactions already on this activity.
  final int reactionCount;

  /// Raw workout-type code ('easy', 'tempo', 'interval', 'long', 'free', …) —
  /// kept alongside the human [title] because the share-card export needs the
  /// code, not the label.
  final String workoutType;

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

  /// Wall-clock time including pauses. Null when the source didn't report it
  /// (or it equals [movingTime] — no stops).
  final Duration? elapsedTime;

  /// Total ascent in metres. Null when the recording had no barometric/GPS
  /// altitude — the Elevation Profile card is omitted in that case.
  final double? elevationGainM;

  // ── Series ────────────────────────────────────────────────────────────────
  final List<KmSplit> splits;
  final List<TelemetrySample> telemetrySeries;
  final List<HrZone> hrZones;

  // ── Aggregates (null when the run carries no such data) ──────────────────
  final int? calories;
  final int? avgCadence;
  final int? peakCadence;
  final int? avgHr;
  final int? peakHr;

  /// Grade-adjusted average pace, "m:ss" per km. Null when there's no elevation
  /// track to adjust against — the GAP block is omitted in that case.
  final String? avgGapPace;

  /// Decoded `{lat, lng}` points for the route preview. May be empty.
  final List<Map<String, double>> routePoints;

  const ActivityDetail({
    this.runId,
    this.runIdIsCloud = false,
    this.athleteId,
    this.commentCount = 0,
    this.reactionCount = 0,
    this.workoutType = 'easy',
    required this.runnerName,
    required this.timestamp,
    required this.source,
    required this.location,
    required this.title,
    this.avatarUrl,
    required this.distanceKm,
    required this.avgPace,
    required this.movingTime,
    this.elapsedTime,
    this.elevationGainM,
    this.calories,
    required this.splits,
    required this.telemetrySeries,
    required this.hrZones,
    this.avgCadence,
    this.peakCadence,
    this.avgHr,
    this.peakHr,
    this.avgGapPace,
    this.routePoints = const [],
  });

  /// Parses a "m:ss" pace label into seconds. Null on empty/malformed input.
  static int? paceLabelToSeconds(String? label) {
    if (label == null) return null;
    final parts = label.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0].trim());
    final s = int.tryParse(parts[1].trim());
    if (m == null || s == null) return null;
    return m * 60 + s;
  }

  int? get avgPaceSeconds => paceLabelToSeconds(avgPace);
  int? get avgGapSeconds => paceLabelToSeconds(avgGapPace);

  /// GAP minus raw pace, in seconds/km. Negative → GAP is faster than raw.
  int? get gapDeltaSeconds {
    final raw = avgPaceSeconds;
    final gap = avgGapSeconds;
    if (raw == null || gap == null) return null;
    return gap - raw;
  }

  int _channelCount(bool Function(TelemetrySample) has) =>
      telemetrySeries.where(has).length;

  /// ≥ 2 samples carry an instantaneous pace → the Pace chart can render.
  bool get hasPaceSeries => _channelCount((s) => s.paceSeconds != null) >= 2;

  /// ≥ 2 samples carry a cadence reading → the Cadence chart can render.
  bool get hasCadenceSeries => _channelCount((s) => s.cadenceSpm != null) >= 2;

  /// Zones + ≥ 2 HR samples → the Heart Rate & Zones card can render.
  bool get hasHrData =>
      hrZones.isNotEmpty && _channelCount((s) => s.hrBpm != null) >= 2;

  /// A gain figure plus ≥ 2 altitude samples → the Elevation Profile can render.
  bool get hasElevationData =>
      elevationGainM != null && _channelCount((s) => s.elevationM != null) >= 2;

  /// Mean HR over the trace — display fallback when [avgHr] wasn't supplied.
  int? get seriesAvgHr {
    final v = telemetrySeries
        .map((s) => s.hrBpm)
        .whereType<int>()
        .toList(growable: false);
    if (v.isEmpty) return null;
    return (v.reduce((a, b) => a + b) / v.length).round();
  }

  int? get seriesPeakHr {
    final v = telemetrySeries.map((s) => s.hrBpm).whereType<int>();
    return v.isEmpty ? null : v.reduce(math.max);
  }

  int? get effectiveAvgHr => avgHr ?? seriesAvgHr;
  int? get effectivePeakHr => peakHr ?? seriesPeakHr;

  bool get anySplitHasElevation =>
      splits.any((s) => s.elevationChangeM != null);
  bool get anySplitHasHr => splits.any((s) => s.avgHr != null);

  /// Fastest split's pace in seconds — the reference the splits-bar lengths are
  /// measured against. Falls back to the slowest value when there are no splits.
  int get fastestSplitSeconds =>
      splits.isEmpty ? 0 : splits.map((s) => s.paceSeconds).reduce(math.min);

  int get slowestSplitSeconds =>
      splits.isEmpty ? 0 : splits.map((s) => s.paceSeconds).reduce(math.max);

  /// Splits sized to the display unit — the *contract* is that
  /// `.paceSeconds`/`.paceLabel` on the returned rows are always already
  /// expressed in the requested unit (never needs a further [UnitUtils]
  /// conversion), and `.km` is the 1-based index in that unit.
  ///
  /// [splits] itself always stays kilometre-bucketed (the stored/canonical
  /// shape — see the class doc on [KmSplit]); this re-buckets the raw
  /// [telemetrySeries] into 1-mile segments when [useMiles] is true, so a
  /// "split" always means one physical distance unit, not a relabelled
  /// kilometre. Falls back to the stored km buckets (their pace values
  /// converted in place) when there's no trace fine-grained enough to
  /// re-bucket from — a `FeedRun`-hydrated activity never has splits in the
  /// first place, and a locally-recorded one carries a trace whenever it
  /// carries splits at all, so this fallback is a rare, low-precision edge
  /// case rather than the common path.
  List<KmSplit> splitsForDisplay({required bool useMiles}) {
    if (!useMiles || splits.isEmpty) return splits;

    const mileKm = 1.609344;
    if (telemetrySeries.length >= 2) {
      final totalKm = telemetrySeries.last.distanceKm;
      if (totalKm > 0) {
        final unitCount = (totalKm / mileKm).ceil();
        final rebucketed = <KmSplit>[];
        for (var u = 1; u <= unitCount; u++) {
          final lo = (u - 1) * mileKm;
          final hi = math.min(u * mileKm, totalKm);
          final inBucket = telemetrySeries
              .where((s) => s.distanceKm >= lo && s.distanceKm <= hi)
              .toList();
          if (inBucket.isEmpty) continue;
          final paces = inBucket
              .map((s) => s.paceSeconds)
              .whereType<int>()
              .toList();
          if (paces.isEmpty) continue;
          final avgPaceSecPerKm =
              paces.reduce((a, b) => a + b) / paces.length;
          final alts = inBucket
              .map((s) => s.elevationM)
              .whereType<double>()
              .toList();
          final hrs = inBucket
              .map((s) => s.hrBpm)
              .whereType<int>()
              .toList();
          rebucketed.add(
            KmSplit(
              km: u,
              // avg pace (sec/km) × this bucket's real km-length: for a full
              // ~1-mile bucket that's already "seconds per mile" — the same
              // convention the km bucketer uses (sec/km × ~1km ≈ itself).
              paceSeconds: (avgPaceSecPerKm * (hi - lo)).round(),
              elevationChangeM: alts.length >= 2
                  ? alts.last - alts.first
                  : null,
              avgHr: hrs.isEmpty
                  ? null
                  : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
            ),
          );
        }
        if (rebucketed.isNotEmpty) return rebucketed;
      }
    }

    // Fallback: keep the km bucket boundaries but convert each pace value so
    // the "always in the requested unit" contract still holds.
    return [
      for (final s in splits)
        KmSplit(
          km: s.km,
          paceSeconds: (s.paceSeconds * mileKm).round(),
          elevationChangeM: s.elevationChangeM,
          avgHr: s.avgHr,
        ),
    ];
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  Hydration factories
  // ───────────────────────────────────────────────────────────────────────────

  /// Builds a view-model from an activity-feed row. Feed payloads are
  /// summary-only (no splits, no telemetry, no calories), so the detail screen
  /// renders just the header, summary grid, GAP block (if the row has GAP),
  /// route preview and the social row — every chart section is skipped.
  factory ActivityDetail.fromFeedRun(
    FeedRun run, {
    int? commentCountOverride,
    int? reactionCountOverride,
  }) {
    final elapsed = run.elapsedSeconds;
    return ActivityDetail(
      runId: run.runId,
      runIdIsCloud: true, // FeedRun.runId is the Supabase runs.id
      athleteId: run.athleteId,
      commentCount: commentCountOverride ?? run.commentCount,
      reactionCount: reactionCountOverride ?? run.reactionCount,
      workoutType: run.workoutType,
      runnerName: run.displayName,
      timestamp: run.date.toLocal(),
      source: run.source,
      location: run.location ?? '',
      title: run.title,
      avatarUrl: run.avatarUrl,
      distanceKm: run.distanceKm,
      avgPace: run.averagePace,
      movingTime: Duration(seconds: run.durationSeconds),
      elapsedTime: (elapsed != null && elapsed > run.durationSeconds)
          ? Duration(seconds: elapsed)
          : null,
      elevationGainM: run.elevationGain > 0 ? run.elevationGain : null,
      calories: null,
      splits: const [],
      telemetrySeries: const [],
      hrZones: const [],
      routePoints: run.points,
    );
  }

  /// Builds a view-model from a locally-recorded [RunRecord] (You / History
  /// tab). Splits and the fine-grained telemetry trace are mapped when the run
  /// carries them; per-split elevation/HR and the HR zone breakdown are derived
  /// from the trace. Basic GPS-only or manual runs (no `trackSamples`) still
  /// hydrate cleanly — they just yield empty series and the screen omits those
  /// sections.
  factory ActivityDetail.fromRunRecord(
    RunRecord record, {
    required String runnerName,
    String? avatarUrl,
    String? location,
    int? estimatedCalories,
  }) {
    final ts = record.trackSamples;

    final samples = <TelemetrySample>[];
    for (final m in ts) {
      final d = (m['d'] as num?)?.toDouble();
      if (d == null) continue;
      samples.add(
        TelemetrySample(
          distanceKm: d / 1000.0,
          paceSeconds: (m['pace'] as num?)?.round(),
          hrBpm: (m['hr'] as num?)?.round(),
          elevationM: (m['alt'] as num?)?.toDouble(),
          cadenceSpm: (m['cad'] as num?)?.round(),
        ),
      );
    }

    final splits = <KmSplit>[];
    for (final m in record.splits) {
      final km = (m['km'] as num?)?.toInt();
      final sec = (m['seconds'] as num?)?.toInt();
      if (km == null || sec == null) continue;
      final lo = (km - 1) * 1000.0;
      final hi = km * 1000.0;
      final seg = ts.where((s) {
        final d = (s['d'] as num?)?.toDouble();
        return d != null && d >= lo && d <= hi;
      });
      final alts = seg
          .map((s) => (s['alt'] as num?)?.toDouble())
          .whereType<double>()
          .toList(growable: false);
      final hrs = seg
          .map((s) => (s['hr'] as num?)?.toDouble())
          .whereType<double>()
          .toList(growable: false);
      splits.add(
        KmSplit(
          km: km,
          paceSeconds: sec,
          elevationChangeM: alts.length >= 2 ? alts.last - alts.first : null,
          avgHr: hrs.isEmpty
              ? null
              : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
        ),
      );
    }

    final hrSamples = samples
        .map((s) => s.hrBpm)
        .whereType<int>()
        .toList(growable: false);
    final avgHr =
        record.avgHeartRate ??
        (hrSamples.isEmpty
            ? null
            : (hrSamples.reduce((a, b) => a + b) / hrSamples.length).round());
    final hrZones = hrSamples.isNotEmpty
        ? _zonesFromSamples(hrSamples, record.durationSeconds)
        : const <HrZone>[];

    final elapsed = record.elapsedSeconds;

    return ActivityDetail(
      runId: record.id,
      runIdIsCloud: false, // local SQLite id — resolve the cloud id lazily
      commentCount: 0,
      reactionCount: 0,
      workoutType: record.workoutType,
      runnerName: runnerName,
      timestamp: record.date.toLocal(),
      source: 'Endura Tracker',
      location: location ?? '',
      title: _titleForWorkout(record.workoutType),
      avatarUrl: avatarUrl,
      distanceKm: record.distanceKm,
      avgPace: record.averagePace,
      movingTime: Duration(seconds: record.durationSeconds),
      elapsedTime: (elapsed != null && elapsed > record.durationSeconds)
          ? Duration(seconds: elapsed)
          : null,
      elevationGainM: record.elevationGain > 0 ? record.elevationGain : null,
      calories: estimatedCalories,
      splits: splits,
      telemetrySeries: samples,
      hrZones: hrZones,
      avgCadence: record.avgCadence,
      peakCadence: record.peakCadence,
      avgHr: avgHr,
      peakHr: record.peakHeartRate,
      avgGapPace: record.gapAveragePace,
      routePoints: decodePolylineToPoints(record.routePolyline),
    );
  }

  static String _titleForWorkout(String type) => switch (type) {
    'easy' => 'Easy Run',
    'tempo' => 'Tempo Run',
    'interval' => 'Interval Workout',
    'long' => 'Long Run',
    'race' || 'race_pace' || 'raceSpecific' => 'Race Pace Run',
    'recovery' => 'Recovery Run',
    'free' || 'free_run' || 'freeRun' => 'Free Run',
    _ => 'Run',
  };

  /// Derives a Z1–Z5 breakdown from raw HR samples using %-of-max bands
  /// (max HR estimated from the observed peak, floored at 190).
  static List<HrZone> _zonesFromSamples(List<int> hr, int movingSeconds) {
    final maxHr = math.max(hr.reduce(math.max) + 4, 190);
    const defs = <({int z, String label, double lo, double hi})>[
      (z: 1, label: 'Recovery', lo: 0.50, hi: 0.60),
      (z: 2, label: 'Easy', lo: 0.60, hi: 0.70),
      (z: 3, label: 'Aerobic', lo: 0.70, hi: 0.80),
      (z: 4, label: 'Threshold', lo: 0.80, hi: 0.90),
      (z: 5, label: 'VO₂ Max', lo: 0.90, hi: 1.0),
    ];
    final counts = <int, int>{for (var z = 1; z <= 5; z++) z: 0};
    for (final v in hr) {
      final frac = v / maxHr;
      var z = 1;
      for (final d in defs) {
        if (frac >= d.lo) z = d.z;
      }
      counts[z] = counts[z]! + 1;
    }
    final total = hr.length;
    return [
      for (final d in defs)
        HrZone(
          zone: d.z,
          label: d.label,
          durationSeconds: total == 0
              ? 0
              : (counts[d.z]! / total * movingSeconds).round(),
          percentage: total == 0
              ? 0
              : double.parse((counts[d.z]! / total).toStringAsFixed(3)),
          bpmLow: (d.lo * maxHr).round(),
          bpmHigh: (d.hi * maxHr).round(),
        ),
    ];
  }

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
      final grade =
          math.sin(t * math.pi * 2.2) * 3.4 +
          6 * math.exp(-math.pow((t - 0.45) * 5, 2).toDouble());
      elev += grade * step * 4 + (rng.nextDouble() - 0.5) * 1.2;

      // HR drifts up with effort + cardiac drift, spikes on the hill.
      final hr =
          (150 +
                  22 * t +
                  10 * math.exp(-math.pow((t - 0.47) * 6, 2).toDouble()) +
                  (kick != 0 ? 6 : 0) +
                  (rng.nextDouble() - 0.5) * 4)
              .round()
              .clamp(132, 184);

      final cad =
          (176 +
                  4 * t +
                  (kick != 0 ? 5 : 0) -
                  (hill > 6 ? 3 : 0) +
                  (rng.nextDouble() - 0.5) * 4)
              .round()
              .clamp(164, 190);

      samples.add(
        TelemetrySample(
          distanceKm: double.parse(d.clamp(0, totalKm).toStringAsFixed(3)),
          paceSeconds: pace,
          hrBpm: hr,
          elevationM: double.parse(elev.toStringAsFixed(1)),
          cadenceSpm: cad,
        ),
      );
    }

    // ── Km splits: average the trace over each 1 km bucket ──────────────────
    final splits = <KmSplit>[];
    final kmCount = totalKm.ceil();
    for (var k = 1; k <= kmCount; k++) {
      final lo = (k - 1).toDouble();
      final hi = math.min(k.toDouble(), totalKm);
      final inBucket = samples
          .where((s) => s.distanceKm >= lo && s.distanceKm <= hi)
          .toList();
      if (inBucket.isEmpty) continue;
      final avgPaceSec =
          (inBucket.map((s) => s.paceSeconds!).reduce((a, b) => a + b) /
                  inBucket.length)
              .round();
      final spanKm = hi - lo;
      final elevChange = inBucket.last.elevationM! - inBucket.first.elevationM!;
      final avgHr =
          (inBucket.map((s) => s.hrBpm!).reduce((a, b) => a + b) /
                  inBucket.length)
              .round();
      splits.add(
        KmSplit(
          km: k,
          paceSeconds: (avgPaceSec * spanKm).round(),
          elevationChangeM: double.parse(elevChange.toStringAsFixed(1)),
          avgHr: avgHr,
        ),
      );
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
        if (s.hrBpm! >= e.value.lo) z = e.key;
      }
      counts[z] = counts[z]! + 1;
    }
    final movingSeconds = 3491; // 58:11
    final totalSamples = samples.length;
    final hrZones = <HrZone>[];
    for (var z = 1; z <= 5; z++) {
      final frac = totalSamples == 0 ? 0.0 : counts[z]! / totalSamples;
      final def = zoneDefs[z]!;
      hrZones.add(
        HrZone(
          zone: z,
          label: def.label,
          durationSeconds: (frac * movingSeconds).round(),
          percentage: double.parse(frac.toStringAsFixed(3)),
          bpmLow: def.lo,
          bpmHigh: def.hi,
        ),
      );
    }

    final elevGain = _cumulativeGain(samples);
    final hrValues = samples.map((s) => s.hrBpm!).toList();
    final cadValues = samples.map((s) => s.cadenceSpm!).toList();

    return ActivityDetail(
      runId: 1173,
      runIdIsCloud: true,
      athleteId: 'mock-athlete-aditya',
      commentCount: 3,
      reactionCount: 12,
      workoutType: 'long',
      runnerName: 'Aditya Rao',
      timestamp: DateTime(2026, 9, 7, 6, 42),
      source: 'Garmin',
      location: 'Cubbon Park, Bengaluru',
      title: 'Sunday progression — negative split',
      avatarUrl: null,
      distanceKm: totalKm,
      avgPace: '4:58',
      movingTime: const Duration(seconds: 3491),
      elapsedTime: const Duration(seconds: 3611), // ~2 min stopped
      elevationGainM: elevGain,
      calories: 812,
      splits: splits,
      telemetrySeries: samples,
      hrZones: hrZones,
      avgCadence: (cadValues.reduce((a, b) => a + b) / cadValues.length)
          .round(),
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
      final a = s[i].elevationM;
      final b = s[i - 1].elevationM;
      if (a == null || b == null) continue;
      final d = a - b;
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
      final r =
          0.010 +
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
