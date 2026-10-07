// lib/models/run_weather.dart
//
// The weather a run was done in, persisted with the run as ONE nullable JSON
// payload (SQLite `runs.weather_json`, Supabase `runs.weather` jsonb) instead
// of a column per field — so adding a field later (or a historical backfill
// that fills the same shape with `source: historical`) never needs another
// schema change. Null always means "unknown": nothing here is ever defaulted.
//
// Built from the existing [WeatherSnapshot]; the fetching, caching and the
// weather-scaler pacing model are untouched.
library;

import 'dart:async';
import 'dart:convert';

import '../services/weather_service.dart'
    show WeatherCondition, WeatherSnapshot;

class RunWeather {
  /// Payload version, so a future reader can tell which fields to expect.
  static const int schemaVersion = 1;

  /// Observed by the live (current-conditions) lookup around the run.
  static const String sourceCurrent = 'current';

  /// Reserved for a future Open-Meteo historical backfill of old runs.
  static const String sourceHistorical = 'historical';

  final double tempC;
  final double apparentTempC;
  final int humidityPercent;
  final double dewPointC;
  final WeatherCondition condition;

  /// When these conditions were actually observed/fetched — not when the run
  /// was saved.
  final DateTime observedAt;
  final String source;

  const RunWeather({
    required this.tempC,
    required this.apparentTempC,
    required this.humidityPercent,
    required this.dewPointC,
    required this.condition,
    required this.observedAt,
    this.source = sourceCurrent,
  });

  factory RunWeather.fromSnapshot(WeatherSnapshot s) => RunWeather(
    tempC: s.tempC,
    apparentTempC: s.apparentTempC,
    humidityPercent: s.humidityPercent,
    dewPointC: s.dewPointC,
    condition: s.condition,
    observedAt: s.fetchedAt,
  );

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'tempC': tempC,
    'apparentTempC': apparentTempC,
    'humidityPercent': humidityPercent,
    'dewPointC': dewPointC,
    'condition': condition.name,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'source': source,
  };

  /// Parses a stored payload — a JSON string from SQLite or an already
  /// decoded map from Supabase. Returns null for anything missing, malformed
  /// or physically implausible rather than guessing, so a bad payload can
  /// never turn into a fabricated reading.
  static RunWeather? tryParse(Object? raw) {
    try {
      Object? decoded = raw;
      if (decoded is String) {
        if (decoded.isEmpty) return null;
        decoded = jsonDecode(decoded);
      }
      if (decoded is! Map) return null;

      final temp = (decoded['tempC'] as num?)?.toDouble();
      final apparent = (decoded['apparentTempC'] as num?)?.toDouble();
      final humidity = (decoded['humidityPercent'] as num?)?.round();
      final dew = (decoded['dewPointC'] as num?)?.toDouble();
      final observed = decoded['observedAt'] as String?;
      if (temp == null ||
          apparent == null ||
          humidity == null ||
          dew == null ||
          observed == null) {
        return null;
      }
      if (!temp.isFinite || temp < -60 || temp > 60) return null;
      if (humidity < 0 || humidity > 100) return null;

      WeatherCondition? condition;
      for (final c in WeatherCondition.values) {
        if (c.name == decoded['condition']) condition = c;
      }
      if (condition == null) return null;

      return RunWeather(
        tempC: temp,
        apparentTempC: apparent,
        humidityPercent: humidity,
        dewPointC: dew,
        condition: condition,
        observedAt: DateTime.parse(observed).toLocal(),
        source: decoded['source'] as String? ?? sourceCurrent,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RunWeather &&
      other.tempC == tempC &&
      other.apparentTempC == apparentTempC &&
      other.humidityPercent == humidityPercent &&
      other.dewPointC == dewPointC &&
      other.condition == condition &&
      other.observedAt == observedAt &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
    tempC,
    apparentTempC,
    humidityPercent,
    dewPointC,
    condition,
    observedAt,
    source,
  );
}

/// Decides which weather a finished run gets. Pure apart from awaiting the
/// futures it is handed, so the rules are testable without a network.
class RunWeatherCapture {
  RunWeatherCapture._();

  /// A reading is "around the run" if it was observed up to an hour before
  /// the run began (the pre-run cache lives 45 minutes) or shortly after it
  /// ended. Anything else — e.g. a stale cache returned when the network
  /// failed — is rejected rather than attached to the wrong conditions.
  static const Duration maxBeforeStart = Duration(minutes: 60);
  static const Duration maxAfterEnd = Duration(minutes: 15);

  /// Longest the run save will wait for a weather lookup that is still
  /// running. Saving never depends on it.
  static const Duration saveTimeout = Duration(seconds: 3);

  static RunWeather? forRun({
    required WeatherSnapshot? snapshot,
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    if (snapshot == null) return null;
    final at = snapshot.fetchedAt;
    if (at.isBefore(startedAt.subtract(maxBeforeStart))) return null;
    if (at.isAfter(endedAt.add(maxAfterEnd))) return null;
    return RunWeather.fromSnapshot(snapshot);
  }

  /// Resolves the weather to save with a run.
  ///
  /// [startFetch] is the lookup kicked off when the run began; it normally
  /// reuses the fresh pre-run cache, so no extra request is made. Only when no
  /// start lookup exists (e.g. a run resumed after the process was killed) is
  /// [fallbackFetch] tried — and that too is cache-first. Runs without a GPS
  /// route (treadmill / manual) get no outdoor weather. Never throws.
  static Future<RunWeather?> resolve({
    required Future<WeatherSnapshot?>? startFetch,
    required Future<WeatherSnapshot?> Function() fallbackFetch,
    required DateTime startedAt,
    required DateTime endedAt,
    required bool hasRoute,
    Duration timeout = saveTimeout,
  }) async {
    if (!hasRoute) return null;
    try {
      final snapshot = await (startFetch ?? fallbackFetch()).timeout(timeout);
      return forRun(snapshot: snapshot, startedAt: startedAt, endedAt: endedAt);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
