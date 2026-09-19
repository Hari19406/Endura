import '../engines/core/vdot_calculator.dart';

/// Placeholder race times for the current-time page, per distance key
/// (`'5k' | '10k' | 'half' | 'marathon'`, as [OPageBestTime] spells them).
///
/// Each is a modest recreational effort (~VDOT 33) so an athlete who never
/// touches the page gets a conservative, clearly-provisional starting fitness
/// instead of a time that is only plausible at one distance.
({int hours, int minutes, int seconds}) defaultRaceTimeFor(String distanceKey) =>
    switch (distanceKey) {
      '10k' => (hours: 1, minutes: 2, seconds: 0),
      'half' => (hours: 2, minutes: 18, seconds: 0),
      'marathon' => (hours: 4, minutes: 45, seconds: 0),
      _ => (hours: 0, minutes: 30, seconds: 0),
    };

double _distanceKm(String distanceKey) => switch (distanceKey) {
  '10k' => 10.0,
  'half' => 21.0975,
  'marathon' => 42.195,
  _ => 5.0,
};

/// VDOT for the untouched placeholder time. Always treated as provisional.
int fallbackVdotFor(String distanceKey) {
  final t = defaultRaceTimeFor(distanceKey);
  return vdotFromPr(
    prTimeSeconds: t.hours * 3600 + t.minutes * 60 + t.seconds,
    prDistanceKm: _distanceKm(distanceKey),
    confidence: PrConfidence.low,
  );
}
