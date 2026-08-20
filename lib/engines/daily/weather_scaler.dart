/// WeatherScaler — eases target pace when it's hot/humid.
///
/// Separate overlay from PreRunScaler (feeling/sleep/pain) and DynamicScaler
/// (RPE history). Chained after PreRunScaler in the pre-run check flow.
/// vDOT itself is never touched — this only adjusts the display-time pace
/// window, same as PreRunScaler adjusts volume/reps.
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

  static const double _baselineC = 15.0;
  static const double _secondsPerDegree = 3.5;
  static const double _humidityThreshold = 60.0;
  static const double _humidityMultiplier = 1.3;
  static const int _maxDeltaSecondsPerKm = 45;
  static const int _minMeaningfulDelta = 3;

  WeatherScaleResult scale(ResolvedWorkout workout, WeatherSnapshot weather) {
    final delta = _computeDeltaSecondsPerKm(weather);
    if (delta < _minMeaningfulDelta) {
      return WeatherScaleResult(workout: workout);
    }

    final adjustedBlocks = workout.blocks.map((b) => _adjustBlock(b, delta)).toList();
    final note = _buildNote(weather, delta);

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
  // DELTA CALCULATION
  // ========================================================================

  int _computeDeltaSecondsPerKm(WeatherSnapshot weather) {
    final degreesOver = weather.apparentTempC - _baselineC;
    if (degreesOver <= 0) return 0;

    var delta = degreesOver * _secondsPerDegree;
    if (weather.humidityPercent > _humidityThreshold) {
      delta *= _humidityMultiplier;
    }
    return delta.round().clamp(0, _maxDeltaSecondsPerKm);
  }

  // ========================================================================
  // BLOCK ADJUSTMENT
  // ========================================================================

  ResolvedBlock _adjustBlock(ResolvedBlock block, int deltaSecondsPerKm) {
    if (block.isRpeOnly) return block;

    return ResolvedBlock(
      type: block.type,
      distanceKm: block.distanceKm,
      durationSeconds: block.durationSeconds,
      paceMinSecondsPerKm: block.paceMinSecondsPerKm + deltaSecondsPerKm,
      paceMaxSecondsPerKm: block.paceMaxSecondsPerKm + deltaSecondsPerKm,
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

  String _buildNote(WeatherSnapshot weather, int delta) {
    final temp = weather.apparentTempC.round();
    final humid = weather.humidityPercent > _humidityThreshold;
    final conditionStr = humid ? '$temp°C and humid' : '$temp°C';
    return "It's $conditionStr — paces eased ~${delta}s/km to keep effort honest.";
  }
}
