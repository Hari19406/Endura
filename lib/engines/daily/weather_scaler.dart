/// WeatherScaler — eases target pace when it's hot/humid.
///
/// Separate overlay from PreRunScaler (feeling/sleep/pain) and DynamicScaler
/// (RPE history). Chained after PreRunScaler in the pre-run check flow.
/// vDOT itself is never touched — this only adjusts the display-time pace
/// window, same as PreRunScaler adjusts volume/reps.
///
/// Model: the widely used "temperature + dew point" table (Runners Connect /
/// Coach Hadley). Air temp (°F) + dew point (°F) is looked up and gives a
/// percentage slowdown applied to every pace — so slower runners get a
/// larger absolute change, matching Ely et al. (2007).
library;

import '../config/workout_template_library.dart';
import '../../services/weather_service.dart';

// ============================================================================
// SCALE RESULT
// ============================================================================

class WeatherScaleResult {
  final ResolvedWorkout workout;
  final String? coachNote;
  final bool wasAdjusted;

  const WeatherScaleResult({
    required this.workout,
    this.coachNote,
    this.wasAdjusted = false,
  });
}

// ============================================================================
// WEATHER SCALER
// ============================================================================

class WeatherScaler {
  const WeatherScaler();

  /// (temp°F + dew point°F, slowdown %) anchors. Each table band
  /// ("101–110 → 0–0.5%") is interpolated linearly between its anchors.
  static const List<(double, double)> _table = [
    (100, 0.0),
    (110, 0.5),
    (120, 1.0),
    (130, 2.0),
    (140, 3.0),
    (150, 4.5),
    (160, 6.0),
    (170, 8.0),
    (180, 10.0),
  ];

  /// Above this the table says hard running isn't recommended; slowdown stays
  /// at the top band's 10%.
  static const double hardRunningLimit = 180;

  static const double _minMeaningfulPercent = 0.5;

  /// The temp + dew point sum (°F) the table is keyed on.
  double heatIndexSum(WeatherSnapshot weather) =>
      _cToF(weather.tempC) + _cToF(weather.dewPointC);

  /// Pace slowdown for [weather] as a percentage (0–10), exposed so UI (the
  /// pre-run briefing's weather card) shows the same figure the scaler applies.
  double slowdownPercent(WeatherSnapshot weather) {
    final sum = heatIndexSum(weather);
    if (sum <= _table.first.$1) return 0;
    if (sum >= _table.last.$1) return _table.last.$2;
    for (var i = 1; i < _table.length; i++) {
      final (x1, y1) = _table[i];
      if (sum <= x1) {
        final (x0, y0) = _table[i - 1];
        return y0 + (y1 - y0) * (sum - x0) / (x1 - x0);
      }
    }
    return 0;
  }

  bool isHardRunningDiscouraged(WeatherSnapshot weather) =>
      heatIndexSum(weather) > hardRunningLimit;

  /// Seconds/km [slowdownPercent] adds to a pace of [paceSecondsPerKm].
  int deltaSecondsFor(WeatherSnapshot weather, int paceSecondsPerKm) =>
      (paceSecondsPerKm * slowdownPercent(weather) / 100).round();

  WeatherScaleResult scale(ResolvedWorkout workout, WeatherSnapshot weather) {
    final percent = slowdownPercent(weather);
    if (percent < _minMeaningfulPercent) {
      return WeatherScaleResult(workout: workout);
    }

    final factor = 1 + percent / 100;
    final adjustedBlocks = workout.blocks
        .map((b) => _adjustBlock(b, factor))
        .toList();
    final note = _buildNote(weather, percent);

    return WeatherScaleResult(
      workout: ResolvedWorkout(
        templateId: workout.templateId,
        name: workout.name,
        intent: workout.intent,
        blocks: adjustedBlocks,
        phase: workout.phase,
        coachNote: note,
      ),
      coachNote: note,
      wasAdjusted: true,
    );
  }

  // ========================================================================
  // BLOCK ADJUSTMENT
  // ========================================================================

  ResolvedBlock _adjustBlock(ResolvedBlock block, double factor) {
    if (block.isRpeOnly) return block;

    return ResolvedBlock(
      type: block.type,
      distanceKm: block.distanceKm,
      durationSeconds: block.durationSeconds,
      paceMinSecondsPerKm: (block.paceMinSecondsPerKm * factor).round(),
      paceMaxSecondsPerKm: (block.paceMaxSecondsPerKm * factor).round(),
      isRpeOnly: block.isRpeOnly,
      reps: block.reps,
      recoverySeconds: block.recoverySeconds,
      recoveryMeters: block.recoveryMeters,
      label: block.label,
    );
  }

  // ========================================================================
  // COACH NOTE
  // ========================================================================

  String _buildNote(WeatherSnapshot weather, double percent) {
    final temp = weather.tempC.round();
    final dew = weather.dewPointC.round();
    final pct = percent.toStringAsFixed(1);
    final base =
        "It's $temp°C with a $dew°C dew point — paces eased ~$pct% to keep effort honest.";
    return isHardRunningDiscouraged(weather)
        ? '$base Conditions are severe — consider an easy effort or the treadmill.'
        : base;
  }

  static double _cToF(double c) => c * 9 / 5 + 32;
}
