// lib/utils/weather_analytics.dart
//
// Weather vs performance, kept deliberately simple and honest. Pure maths over
// lightweight [WeatherRun]s — no Flutter, no database.
//
// Methodology:
//  • Only runs that carry stored weather (and positive distance and moving
//    time) are analysed. Nothing is interpolated or defaulted; the caller
//    supplies outdoor GPS runs only.
//  • Pace is distance-weighted: total moving time ÷ total distance, the same
//    definition the Trends card uses.
//  • HR is time-weighted over runs with a valid average HR (30–230 bpm) only —
//    a missing HR is never treated as zero, and a run without HR simply drops
//    out of the HR analysis.
//  • A band is only comparable once it has [minBandRuns] runs; the heat-impact
//    insight needs [minHeatRuns] on each side.
//  • These are observed differences between the athlete's own runs. They are
//    not a causal estimate: effort, route, fitness and time of day all differ
//    between runs.
library;

import '../services/weather_service.dart' show WeatherCondition;
import 'trend_analytics.dart' show TrendAnalytics;

/// One outdoor run with stored weather, reduced to what the analysis needs.
class WeatherRun {
  final double tempC;
  final int humidityPercent;
  final WeatherCondition condition;
  final double distanceKm;
  final int movingTimeSeconds;
  final int? avgHr;

  const WeatherRun({
    required this.tempC,
    required this.humidityPercent,
    required this.condition,
    required this.distanceKm,
    required this.movingTimeSeconds,
    this.avgHr,
  });
}

enum TempBand {
  under15('<15°'),
  from15('15–20°'),
  from20('20–25°'),
  from25('25–30°'),
  from30('30°+');

  const TempBand(this.label);
  final String label;

  /// Lower bound inclusive, upper bound exclusive: 20.0 is in 20–25°.
  static TempBand of(double tempC) {
    if (tempC < 15) return under15;
    if (tempC < 20) return from15;
    if (tempC < 25) return from20;
    if (tempC < 30) return from25;
    return from30;
  }
}

enum HumidityBand {
  dry('<40%'),
  moderate('40–60%'),
  humid('60–80%'),
  veryHumid('80%+');

  const HumidityBand(this.label);
  final String label;

  static HumidityBand of(int percent) {
    if (percent < 40) return dry;
    if (percent < 60) return moderate;
    if (percent < 80) return humid;
    return veryHumid;
  }
}

/// Aggregate for one band (a temperature band, humidity band or condition).
class WeatherBandStat {
  final String key;
  final String label;
  final int runCount;
  final double distanceKm;
  final int movingSeconds;

  /// Total moving time ÷ total distance, s/km. Null when there are no runs.
  final double? paceSecondsPerKm;

  /// Time-weighted average HR over runs with valid HR; null when none.
  final double? avgHr;
  final int hrRuns;

  const WeatherBandStat({
    required this.key,
    required this.label,
    required this.runCount,
    required this.distanceKm,
    required this.movingSeconds,
    this.paceSecondsPerKm,
    this.avgHr,
    this.hrRuns = 0,
  });

  bool get hasEnoughRuns => runCount >= WeatherAnalytics.minBandRuns;
  bool get hasEnoughHr => hrRuns >= WeatherAnalytics.minBandRuns;
}

class HeatImpact {
  final String hotLabel;
  final String baselineLabel;
  final int hotRuns;
  final int baselineRuns;

  /// Hot band pace − baseline pace, s/km. Positive = slower in the heat.
  final double deltaSecondsPerKm;

  const HeatImpact({
    required this.hotLabel,
    required this.baselineLabel,
    required this.hotRuns,
    required this.baselineRuns,
    required this.deltaSecondsPerKm,
  });

  /// Within a few seconds either way is not worth calling a difference.
  bool get isNegligible =>
      deltaSecondsPerKm.abs() < WeatherAnalytics.negligibleSeconds;
}

class WeatherReport {
  /// Runs that went into the analysis (weather present, valid distance/time).
  final int runCount;
  final List<WeatherBandStat> temperature;
  final List<WeatherBandStat> humidity;

  /// Only conditions that actually have runs, in enum order.
  final List<WeatherBandStat> conditions;
  final HeatImpact? heatImpact;

  const WeatherReport({
    required this.runCount,
    required this.temperature,
    required this.humidity,
    required this.conditions,
    required this.heatImpact,
  });

  static const empty = WeatherReport(
    runCount: 0,
    temperature: [],
    humidity: [],
    conditions: [],
    heatImpact: null,
  );
}

class WeatherAnalytics {
  WeatherAnalytics._();

  /// Runs a band needs before its pace/HR is shown or compared.
  static const int minBandRuns = 3;

  /// Runs needed on EACH side before a heat-impact sentence is generated.
  static const int minHeatRuns = 5;

  /// Differences smaller than this (s/km) are reported as "similar".
  static const double negligibleSeconds = 3;

  /// Bands to chart: at least two comparable ones, otherwise there is nothing
  /// to compare. [forHr] checks HR coverage instead of run count.
  static List<WeatherBandStat> comparable(
    List<WeatherBandStat> stats, {
    bool forHr = false,
  }) {
    final usable = [
      for (final s in stats)
        if (forHr ? s.hasEnoughHr : s.hasEnoughRuns) s,
    ];
    return usable.length >= 2 ? usable : const [];
  }

  static bool _usable(WeatherRun r) =>
      r.distanceKm > 0 &&
      r.movingTimeSeconds > 0 &&
      r.tempC.isFinite &&
      r.tempC >= -60 &&
      r.tempC <= 60 &&
      r.humidityPercent >= 0 &&
      r.humidityPercent <= 100;

  static WeatherBandStat _stat(
    String key,
    String label,
    List<WeatherRun> runs,
  ) {
    var distance = 0.0;
    var seconds = 0;
    var hrRuns = 0;
    var hrWeighted = 0.0, hrWeight = 0.0;
    for (final r in runs) {
      distance += r.distanceKm;
      seconds += r.movingTimeSeconds;
      if (TrendAnalytics.isValidHr(r.avgHr)) {
        hrRuns++;
        hrWeighted += r.avgHr! * r.movingTimeSeconds;
        hrWeight += r.movingTimeSeconds;
      }
    }
    return WeatherBandStat(
      key: key,
      label: label,
      runCount: runs.length,
      distanceKm: distance,
      movingSeconds: seconds,
      paceSecondsPerKm: runs.isEmpty ? null : seconds / distance,
      avgHr: hrRuns == 0 ? null : hrWeighted / hrWeight,
      hrRuns: hrRuns,
    );
  }

  static WeatherReport analyze(Iterable<WeatherRun> runs) {
    final usable = [
      for (final r in runs)
        if (_usable(r)) r,
    ];
    if (usable.isEmpty) return WeatherReport.empty;

    final temperature = [
      for (final b in TempBand.values)
        _stat(b.name, b.label, [
          for (final r in usable)
            if (TempBand.of(r.tempC) == b) r,
        ]),
    ];
    final humidity = [
      for (final b in HumidityBand.values)
        _stat(b.name, b.label, [
          for (final r in usable)
            if (HumidityBand.of(r.humidityPercent) == b) r,
        ]),
    ];
    final conditions = [
      for (final c in WeatherCondition.values)
        if (usable.any((r) => r.condition == c))
          _stat(c.name, c.name, [
            for (final r in usable)
              if (r.condition == c) r,
          ]),
    ];

    return WeatherReport(
      runCount: usable.length,
      temperature: temperature,
      humidity: humidity,
      conditions: conditions,
      heatImpact: _heatImpact(temperature),
    );
  }

  /// "Hot" vs the 20–25° baseline, using the hottest band with enough runs
  /// (30°+, else 25–30°). Null unless both sides have [minHeatRuns].
  static HeatImpact? _heatImpact(List<WeatherBandStat> temperature) {
    WeatherBandStat band(TempBand b) =>
        temperature.firstWhere((s) => s.key == b.name);

    final baseline = band(TempBand.from20);
    if (baseline.runCount < minHeatRuns || baseline.paceSecondsPerKm == null) {
      return null;
    }
    for (final b in [TempBand.from30, TempBand.from25]) {
      final hot = band(b);
      if (hot.runCount >= minHeatRuns && hot.paceSecondsPerKm != null) {
        return HeatImpact(
          hotLabel: hot.label,
          baselineLabel: baseline.label,
          hotRuns: hot.runCount,
          baselineRuns: baseline.runCount,
          deltaSecondsPerKm: hot.paceSecondsPerKm! - baseline.paceSecondsPerKm!,
        );
      }
    }
    return null;
  }
}
