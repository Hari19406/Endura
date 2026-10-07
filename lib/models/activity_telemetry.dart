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

import '../services/athlete_physiology.dart';
import '../services/best_efforts_service.dart';
import '../utils/database_service.dart' show RunRecord, decodePolylineToPoints;
import '../utils/gap_calculator.dart';
import '../utils/hr_analytics.dart';
import '../utils/pace_analytics.dart';
import '../utils/run_effort_analytics.dart';
import '../utils/run_title.dart';
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

  /// Physical length this split covers, in km. 1.0 for every full kilometre;
  /// less for a trailing partial (e.g. 0.7 for a 0.7 km run). For a partial
  /// split [paceSeconds] is already normalised to a per-km pace, so its bar
  /// and label stay comparable with the full splits.
  final double distanceKm;

  /// Grade-adjusted pace for this split, in the same unit and normalisation
  /// as [paceSeconds] (a per-unit pace). Null when the run had no usable
  /// altitude/segment coverage for the split — never fabricated.
  final int? gapPaceSeconds;

  const KmSplit({
    required this.km,
    required this.paceSeconds,
    this.elevationChangeM,
    this.avgHr,
    this.distanceKm = 1.0,
    this.gapPaceSeconds,
    bool? partial,
  }) : isPartial = partial ?? distanceKm < 0.995;

  /// True for a trailing split shorter than one display unit (km or mile).
  final bool isPartial;

  KmSplit copyWith({int? paceSeconds}) => KmSplit(
    km: km,
    paceSeconds: paceSeconds ?? this.paceSeconds,
    elevationChangeM: elevationChangeM,
    avgHr: avgHr,
    distanceKm: distanceKm,
    gapPaceSeconds: gapPaceSeconds,
    partial: isPartial,
  );

  /// "m:ss" per-km label.
  String get paceLabel =>
      '${paceSeconds ~/ 60}:${(paceSeconds % 60).toString().padLeft(2, '0')}';

  /// "m:ss" GAP label, or null when there is no GAP for this split.
  String? get gapPaceLabel => gapPaceSeconds == null
      ? null
      : '${gapPaceSeconds! ~/ 60}:${(gapPaceSeconds! % 60).toString().padLeft(2, '0')}';
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

  /// Seconds since the start of the recorded phase (the sample's `'t'`).
  /// Null for synthesised samples (e.g. Feed runs) that carry no clock.
  final double? timeSeconds;

  const TelemetrySample({
    required this.distanceKm,
    this.paceSeconds,
    this.hrBpm,
    this.elevationM,
    this.cadenceSpm,
    this.timeSeconds,
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

  /// The max HR the [hrZones] were computed against, and where it came from.
  /// Null when the zones carry no such provenance (Feed runs, fixtures).
  final MaxHrResolution? maxHr;

  /// Time in each of the five pace zones (easiest → hardest), empty when the
  /// run has no usable pace samples or no zone config was supplied.
  final List<PaceZoneStat> paceZones;

  /// The vDOT the [paceZones] boundaries came from, for the card caption.
  final int? paceZonesVdot;

  // ── Aggregates (null when the run carries no such data) ──────────────────
  final int? calories;
  final int? avgCadence;
  final int? peakCadence;
  final int? avgHr;
  final int? peakHr;

  /// Grade-adjusted average pace, "m:ss" per km. Null when there's no elevation
  /// track to adjust against — the GAP block is omitted in that case.
  final String? avgGapPace;

  /// The GAP analysis behind [avgGapPace] and the per-split GAP (null when
  /// there is no usable telemetry, and for Feed runs).
  final GapAnalysis? gap;

  /// Pace, HR and elevation aligned on one axis, validated and cleaned with
  /// the same rules as the HR / pace-zone / GAP analytics. Built by the
  /// factories; for an [ActivityDetail] constructed directly (tests, fixtures)
  /// [effort] derives it from [telemetrySeries] on demand.
  final RunEffortSeries? effortSeries;

  /// The Best Efforts achieved in this run, each with its rank among all of the
  /// athlete's efforts at that distance and the current all-time best. Read
  /// from the stored `best_efforts` rows (see `getRunBestEfforts`), never
  /// recalculated here. Empty when the run has none and for Feed runs.
  final List<RunBestEffort> bestEfforts;

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
    this.maxHr,
    this.paceZones = const [],
    this.paceZonesVdot,
    this.avgCadence,
    this.peakCadence,
    this.avgHr,
    this.peakHr,
    this.avgGapPace,
    this.gap,
    this.effortSeries,
    this.bestEfforts = const [],
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
    // Compare like with like: GAP and the raw pace over the SAME valid
    // segments, so a flat run reads exactly 0 (the official average pace
    // also covers stretches the GAP analysis had to skip).
    final analysis = gap;
    if (analysis != null) return analysis.deltaSecPerKm.round();
    final raw = avgPaceSeconds;
    final gapSeconds = avgGapSeconds;
    if (raw == null || gapSeconds == null) return null;
    return gapSeconds - raw;
  }

  int _channelCount(bool Function(TelemetrySample) has) =>
      telemetrySeries.where(has).length;

  /// The aligned, validated pace / HR / elevation series.
  RunEffortSeries get effort =>
      effortSeries ?? buildEffortSeries(telemetrySeries, gap: gap);

  /// Builds the aligned effort series from telemetry samples.
  static RunEffortSeries buildEffortSeries(
    List<TelemetrySample> samples, {
    GapAnalysis? gap,
    bool cleanElevation = true,
  }) => RunEffortSeries.build(
    [
      for (final s in samples)
        EffortInput(
          timeSeconds: s.timeSeconds,
          distanceKm: s.distanceKm,
          paceSecPerKm: s.paceSeconds?.toDouble(),
          hrBpm: s.hrBpm,
          elevationM: s.elevationM,
        ),
    ],
    gap: gap,
    cleanElevation: cleanElevation,
  );

  /// ≥ 2 samples carry a VALID instantaneous pace (120–1800 s/km) → the Pace
  /// chart can render.
  bool get hasPaceSeries => effort.hasPace;

  /// ≥ 2 samples carry a cadence reading → the Cadence chart can render.
  bool get hasCadenceSeries => _channelCount((s) => s.cadenceSpm != null) >= 2;

  /// Zones + ≥ 2 VALID HR samples (30–230 bpm) → the Heart Rate & Zones card
  /// can render.
  bool get hasHrData => hrZones.isNotEmpty && effort.hasHr;

  /// ≥ 2 altitude samples → the Elevation Profile can render, even when the
  /// net gain is 0 m (a flat baseline). Hidden only when no altitude was
  /// recorded at all (indoor / no GPS altitude).
  bool get hasElevationData => effort.hasElevation;

  /// The combined pace · HR · elevation chart: needs a clock and at least two
  /// channels. Feed runs (synthesised from per-km splits, no clock) never
  /// qualify.
  bool get hasEffortChart => effort.supportsCombinedChart;

  HrSummary? get _seriesHrSummary => HrAnalytics.summary([
    for (final s in telemetrySeries) HrPoint(bpm: s.hrBpm),
  ]);

  /// Mean HR over the trace (valid 30–230 bpm readings only) — display
  /// fallback when [avgHr] wasn't supplied.
  int? get seriesAvgHr => _seriesHrSummary?.avg;

  int? get seriesPeakHr => _seriesHrSummary?.peak;

  int? get effectiveAvgHr => avgHr ?? seriesAvgHr;
  int? get effectivePeakHr => peakHr ?? seriesPeakHr;

  bool get anySplitHasElevation =>
      splits.any((s) => s.elevationChangeM != null);
  bool get anySplitHasHr => splits.any((s) => s.avgHr != null);

  /// Fastest split's pace in seconds — the reference the splits-bar lengths are
  /// measured against. Excludes zero/garbage paces (<= 60s/km is not a real
  /// running pace) so one corrupt split can't collapse the whole bar scale.
  /// Falls back to 0 when there is no split left to measure against.
  int get fastestSplitSeconds {
    final valid = splits.map((s) => s.paceSeconds).where((p) => p > 60);
    return valid.isEmpty ? 0 : valid.reduce(math.min);
  }

  int get slowestSplitSeconds {
    final valid = splits.map((s) => s.paceSeconds).where((p) => p > 60);
    return valid.isEmpty ? 0 : valid.reduce(math.max);
  }

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
    final healed = _healedSplits(splits);
    if (!useMiles || healed.isEmpty) return healed;

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
          final avgPaceSecPerKm = paces.reduce((a, b) => a + b) / paces.length;
          final alts = inBucket
              .map((s) => s.elevationM)
              .whereType<double>()
              .toList();
          final hrs = inBucket.map((s) => s.hrBpm).whereType<int>().toList();
          final milePace = (avgPaceSecPerKm * mileKm).round();
          final gapRatio = gap?.ratioBetween(lo, hi);
          rebucketed.add(
            KmSplit(
              km: u,
              // avg pace (sec/km) × one mile = seconds per mile. Always the
              // per-unit pace — a trailing partial bucket is normalised too
              // (its real length is carried in distanceKm) so its bar/label
              // stay comparable with the full miles.
              paceSeconds: milePace,
              gapPaceSeconds: gapRatio == null
                  ? null
                  : (milePace * gapRatio).round(),
              distanceKm: hi - lo,
              partial: (hi - lo) < mileKm - 0.005,
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
      for (final s in healed)
        KmSplit(
          km: s.km,
          paceSeconds: (s.paceSeconds * mileKm).round(),
          elevationChangeM: s.elevationChangeM,
          avgHr: s.avgHr,
          distanceKm: s.distanceKm,
          gapPaceSeconds: s.gapPaceSeconds == null
              ? null
              : (s.gapPaceSeconds! * mileKm).round(),
          partial: s.isPartial,
        ),
    ];
  }

  /// Heals any split whose recorded duration is invalid (`paceSeconds <= 0`
  /// — never a real "moving time for this split") by distributing the run's
  /// remaining moving time across just the invalid ones:
  /// `(totalMovingTime - validSplitsTime) / invalidCount`. A duplicate GPS
  /// timestamp or an out-of-order km crossing during live recording is
  /// guarded against at the source now (see RunScreen's split capture), but
  /// a run recorded before that fix can still carry one in storage — this is
  /// the universal fallback that keeps every historical and future run safe
  /// to render. Falls back to the run's overall average pace when every
  /// split is invalid, and only ever leaves a 0 in place when total moving
  /// time genuinely was 0 (nothing sane to distribute).
  List<KmSplit> _healedSplits(List<KmSplit> raw) {
    if (raw.isEmpty) return raw;
    final invalidCount = raw.where((s) => s.paceSeconds <= 0).length;
    if (invalidCount == 0) return raw;

    final totalMovingSeconds = movingTime.inSeconds;
    final fallbackPace = avgPaceSeconds;

    if (invalidCount == raw.length) {
      if (totalMovingSeconds <= 0 ||
          fallbackPace == null ||
          fallbackPace <= 0) {
        return raw; // Total moving time really was 0 — 0:00 is correct here.
      }
      return [for (final s in raw) s.copyWith(paceSeconds: fallbackPace)];
    }

    final validSplitsTime = raw
        .where((s) => s.paceSeconds > 0)
        .fold<int>(0, (sum, s) => sum + s.paceSeconds);
    final remaining = totalMovingSeconds - validSplitsTime;
    final healedDuration = remaining > 0
        ? (remaining / invalidCount).round()
        : (fallbackPace ?? 1);

    return [
      for (final s in raw)
        s.paceSeconds > 0
            ? s
            : s.copyWith(paceSeconds: math.max(1, healedDuration)),
    ];
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  Hydration factories
  // ───────────────────────────────────────────────────────────────────────────

  /// Builds a view-model from an activity-feed row. Feed payloads never carry
  /// the full GPS/HR/cadence trace (that never leaves the recording device —
  /// see [CloudSyncService.uploadRun]), so the HR & Zones and Cadence cards
  /// are always skipped here. [FeedRun.splits] — a compact per-km breakdown
  /// that *is* uploaded — drives the KILOMETRE SPLITS card directly, and also
  /// seeds a coarse, km-resolution synthetic trace (see
  /// [_telemetryFromSplits]) so the Pace and Elevation scrub charts render
  /// too, just at lower resolution than a locally-recorded run's.
  factory ActivityDetail.fromFeedRun(
    FeedRun run, {
    int? commentCountOverride,
    int? reactionCountOverride,
  }) {
    final elapsed = run.elapsedSeconds;
    final splits = _splitsFromRaw(run.splits);
    final feedSeries = _telemetryFromSplits(splits);
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
      splits: splits,
      telemetrySeries: feedSeries,
      effortSeries: buildEffortSeries(feedSeries, cleanElevation: false),
      hrZones: const [],
      routePoints: run.points,
    );
  }

  /// Parses [FeedRun.splits]' raw `{'km', 'seconds', 'elev'?, 'hr'?}` maps
  /// into [KmSplit]s. Tolerant of a missing/malformed entry — skips it rather
  /// than throwing, so one bad row doesn't blank the whole splits card.
  static List<KmSplit> _splitsFromRaw(List<Map<String, dynamic>> raw) {
    final splits = <KmSplit>[];
    for (final m in raw) {
      final km = (m['km'] as num?)?.toInt();
      final seconds = (m['seconds'] as num?)?.toInt();
      if (km == null || seconds == null) continue;
      splits.add(
        KmSplit(
          km: km,
          paceSeconds: seconds,
          elevationChangeM: (m['elev'] as num?)?.toDouble(),
          avgHr: (m['hr'] as num?)?.toInt(),
        ),
      );
    }
    return splits;
  }

  /// Synthesises one [TelemetrySample] per km boundary from [splits] — a
  /// cumulative elevation profile (running sum of each split's elevation
  /// delta) and each split's own pace, so [hasElevationData]/[hasPaceSeries]
  /// (and the scrub charts that gate on them) work from data no finer than
  /// what a Feed row actually carries. Leaves `elevationM` null throughout
  /// when not a single split has an elevation delta (nothing to accumulate).
  static List<TelemetrySample> _telemetryFromSplits(List<KmSplit> splits) {
    if (splits.isEmpty) return const [];
    final hasElevation = splits.any((s) => s.elevationChangeM != null);
    var cumulativeElevation = 0.0;
    final samples = [
      TelemetrySample(distanceKm: 0, elevationM: hasElevation ? 0 : null),
    ];
    for (final s in splits) {
      if (hasElevation) cumulativeElevation += s.elevationChangeM ?? 0;
      samples.add(
        TelemetrySample(
          distanceKm: s.km.toDouble(),
          paceSeconds: s.paceSeconds,
          elevationM: hasElevation ? cumulativeElevation : null,
        ),
      );
    }
    return samples;
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
    MaxHrResolution maxHr = MaxHrResolution.fallback,
    PaceZoneConfig? paceZoneConfig,
    List<RunBestEffort> bestEfforts = const [],
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
          timeSeconds: (m['t'] as num?)?.toDouble(),
        ),
      );
    }

    // GAP is always recomputed from the telemetry (never read back from the
    // stored `gap_average_pace`, which older builds wrote with an inverted
    // formula). The finish line closes the gap after the last sample.
    final gap = GapCalculator.analyze(
      [
        for (final s in samples)
          GapSample(
            distanceM: s.distanceKm * 1000,
            timeSeconds: s.timeSeconds,
            altitudeM: s.elevationM,
            paceSecPerKm: s.paceSeconds?.toDouble(),
          ),
      ],
      finalDistanceM: record.distanceKm * 1000,
      finalSeconds: record.durationSeconds.toDouble(),
    );

    int? splitGap(int paceSeconds, double loKm, double hiKm) {
      if (gap == null || paceSeconds <= 0) return null;
      final ratio = gap.ratioBetween(loKm, hiKm);
      return ratio == null ? null : (paceSeconds * ratio).round();
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
          gapPaceSeconds: splitGap(sec, km - 1.0, km.toDouble()),
        ),
      );
    }

    // Trailing partial kilometre (or the whole of a run shorter than 1 km):
    // stored splits only exist for completed km, so without this a short run
    // has no splits card at all. Stored `seconds` are per-km durations (the
    // run screen converts its cumulative markers to deltas on save), so the
    // partial's time is whatever moving time the full splits don't account for.
    final coveredKm = splits.isEmpty ? 0 : splits.last.km;
    final remainingKm = record.distanceKm - coveredKm;
    if (remainingKm >= 0.1 && remainingKm < 1.0) {
      final usedSec = splits.fold<int>(0, (sum, s) => sum + s.paceSeconds);
      final remainingSec = record.durationSeconds - usedSec;
      if (remainingSec > 0) {
        final lo = coveredKm * 1000.0;
        final seg = ts.where((s) {
          final d = (s['d'] as num?)?.toDouble();
          return d != null && d >= lo;
        });
        final alts = seg
            .map((s) => (s['alt'] as num?)?.toDouble())
            .whereType<double>()
            .toList(growable: false);
        final hrs = seg
            .map((s) => (s['hr'] as num?)?.toDouble())
            .whereType<double>()
            .toList(growable: false);
        final partialPace = (remainingSec / remainingKm).round();
        splits.add(
          KmSplit(
            km: coveredKm + 1,
            paceSeconds: partialPace,
            gapPaceSeconds: splitGap(
              partialPace,
              coveredKm.toDouble(),
              record.distanceKm,
            ),
            elevationChangeM: alts.length >= 2 ? alts.last - alts.first : null,
            avgHr: hrs.isEmpty
                ? null
                : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
            distanceKm: remainingKm,
          ),
        );
      }
    }

    final avgHr =
        record.avgHeartRate ??
        HrAnalytics.summary([
          for (final s in samples) HrPoint(bpm: s.hrBpm),
        ])?.avg;
    final hrZones = [
      for (final z in HrAnalytics.zones([
        for (final s in samples)
          HrPoint(timeSeconds: s.timeSeconds, bpm: s.hrBpm),
      ], maxHr.bpm))
        HrZone(
          zone: z.zone,
          label: z.label,
          durationSeconds: z.durationSeconds,
          percentage: z.percentage,
          bpmLow: z.bpmLow,
          bpmHigh: z.bpmHigh,
        ),
    ];

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
      title:
          RunTitle.normalize(record.title) ??
          _titleForWorkout(record.workoutType),
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
      maxHr: hrZones.isEmpty ? null : maxHr,
      paceZones: paceZoneConfig == null
          ? const []
          : PaceAnalytics.zones([
              for (final s in samples)
                PacePoint(
                  timeSeconds: s.timeSeconds,
                  distanceKm: s.distanceKm,
                  paceSecPerKm: s.paceSeconds?.toDouble(),
                ),
            ], paceZoneConfig),
      paceZonesVdot: paceZoneConfig?.vdot,
      avgCadence: record.avgCadence,
      peakCadence: record.peakCadence,
      avgHr: avgHr,
      peakHr: record.peakHeartRate,
      avgGapPace: gap == null ? null : _paceLabel(gap.avgGapSecPerKm),
      gap: gap,
      effortSeries: buildEffortSeries(samples, gap: gap),
      bestEfforts: bestEfforts,
      routePoints: decodePolylineToPoints(record.routePolyline),
    );
  }

  static String _paceLabel(double secPerKm) {
    final s = secPerKm.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
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
    double clock = 0; // seconds, advanced by each step's pace
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
          timeSeconds: clock,
        ),
      );
      clock += pace * step;
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
