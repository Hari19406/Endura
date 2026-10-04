import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// WEATHER CONDITION
// ============================================================================

/// Bucketed from Open-Meteo's WMO weather_code.
enum WeatherCondition { clear, cloudy, rain, snow, fog }

WeatherCondition _conditionFromWmoCode(int code) {
  if (code == 0 || code == 1) return WeatherCondition.clear;
  if (code == 2 || code == 3) return WeatherCondition.cloudy;
  if (code == 45 || code == 48) return WeatherCondition.fog;
  if (code >= 71 && code <= 77) return WeatherCondition.snow;
  if (code == 85 || code == 86) return WeatherCondition.snow;
  // 51-67 drizzle/rain, 80-82 rain showers, 95-99 thunderstorm.
  return WeatherCondition.rain;
}

// ============================================================================
// WEATHER SNAPSHOT
// ============================================================================

class WeatherSnapshot {
  final double tempC;
  final double apparentTempC;
  final int humidityPercent;
  final double dewPointC;
  final WeatherCondition condition;
  final DateTime fetchedAt;

  const WeatherSnapshot({
    required this.tempC,
    required this.apparentTempC,
    required this.humidityPercent,
    required this.dewPointC,
    required this.condition,
    required this.fetchedAt,
  });

  /// Magnus-formula dew point — only used to read caches written before
  /// [dewPointC] was stored.
  static double dewPointFrom(double tempC, int humidityPercent) {
    const a = 17.62, b = 243.12;
    final rh = humidityPercent.clamp(1, 100) / 100;
    final g = math.log(rh) + a * tempC / (b + tempC);
    return b * g / (a - g);
  }

  bool get isStale =>
      DateTime.now().difference(fetchedAt) > const Duration(minutes: 45);

  Map<String, dynamic> toJson() => {
    'tempC': tempC,
    'apparentTempC': apparentTempC,
    'humidityPercent': humidityPercent,
    'dewPointC': dewPointC,
    'condition': condition.name,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    final tempC = (json['tempC'] as num).toDouble();
    final humidity = json['humidityPercent'] as int;
    return WeatherSnapshot(
      tempC: tempC,
      apparentTempC: (json['apparentTempC'] as num).toDouble(),
      humidityPercent: humidity,
      dewPointC:
          (json['dewPointC'] as num?)?.toDouble() ??
          dewPointFrom(tempC, humidity),
      condition: WeatherCondition.values.firstWhere(
        (c) => c.name == json['condition'],
        orElse: () => WeatherCondition.clear,
      ),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    );
  }
}

// ============================================================================
// WEATHER SERVICE
// ============================================================================

/// Fetches current weather for the device's location, cached for 45 minutes.
///
/// Provider is isolated to [_fetchFromOpenMeteo] — swapping providers later
/// only means changing that one method's body, not any call site.
class WeatherService {
  static const String _cacheKey = 'weather_snapshot';

  static Future<WeatherSnapshot?> getCurrentWeather({
    bool forceRefresh = false,
  }) async {
    final cached = await _readCache();
    if (!forceRefresh && cached != null && !cached.isStale) return cached;

    final position = await getLocation();
    if (position == null) return cached; // stale cache is better than nothing

    final snapshot = await _fetchFromOpenMeteo(
      position.latitude,
      position.longitude,
    );
    if (snapshot == null) return cached;

    await _writeCache(snapshot);
    return snapshot;
  }

  // ── Location ──────────────────────────────────────────────────────────

  /// Public so [LocationService] can reuse the same permission/timeout
  /// handling to reverse-geocode a human-readable place name, without
  /// duplicating this logic.
  static Future<Position?> getLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.reduced,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  // ── Provider (Open-Meteo) ────────────────────────────────────────────

  static Future<WeatherSnapshot?> _fetchFromOpenMeteo(
    double lat,
    double lng,
  ) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lng'
        '&current=temperature_2m,relative_humidity_2m,apparent_temperature,dew_point_2m,weather_code'
        '&timezone=auto',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;
      if (current == null) return null;

      return WeatherSnapshot(
        tempC: (current['temperature_2m'] as num).toDouble(),
        apparentTempC: (current['apparent_temperature'] as num).toDouble(),
        humidityPercent: (current['relative_humidity_2m'] as num).round(),
        dewPointC: (current['dew_point_2m'] as num).toDouble(),
        condition: _conditionFromWmoCode(
          (current['weather_code'] as num).round(),
        ),
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Cache ─────────────────────────────────────────────────────────────

  static Future<WeatherSnapshot?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      return WeatherSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(WeatherSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(snapshot.toJson()));
    } catch (_) {
      // Non-fatal — just means we re-fetch next time.
    }
  }
}
