/// Pure formatting helpers for the live-run foreground notification.
///
/// Split out from [RunTrackingTaskHandler] (which extends the plugin's
/// isolate-bound `TaskHandler` and can't be unit-tested directly) so the
/// title/content string-building logic can be verified without a platform
/// channel.
library;

/// Builds the notification title.
///
/// Structured workouts show which step is active; open/free runs fall back
/// to a plain "Run in progress" title.
String buildRunNotificationTitle({
  required bool hasStructuredSteps,
  required int stepIndex,
  required int stepTotal,
  String? stepLabel,
}) {
  if (hasStructuredSteps) {
    final label = stepLabel ?? 'Step';
    return 'Endura · Step ${stepIndex + 1} of $stepTotal ($label)';
  }
  return 'Endura · Run in progress';
}

/// Builds the notification content text: distance, rolling pace, target-pace
/// status (structured workouts only), and remaining step distance.
String buildRunNotificationContent({
  required double distanceMeters,
  required bool useMiles,
  required int paceSecPerKm,
  required bool isPaused,
  required bool hasStructuredSteps,
  required bool stepIsRpe,
  int? targetMinSecPerKm,
  int? targetMaxSecPerKm,
  double? remainingStepMeters,
}) {
  final distance = formatRunDistance(distanceMeters, useMiles);
  final pace = paceSecPerKm > 0
      ? '${formatRunPace(paceSecPerKm, useMiles)} ${useMiles ? '/mi' : '/km'}'
      : '--:-- ${useMiles ? '/mi' : '/km'}';
  final status = runTargetPaceStatus(
    paceSecPerKm,
    stepIsRpe,
    targetMinSecPerKm,
    targetMaxSecPerKm,
  );

  final parts = <String>[distance, pace];
  if (status != null) parts.add(status);
  if (hasStructuredSteps && remainingStepMeters != null && remainingStepMeters > 0) {
    parts.add('${formatRunDistance(remainingStepMeters, useMiles)} left');
  }

  final text = parts.join(' · ');
  return isPaused ? 'Paused · $text' : text;
}

/// Classifies [paceSecPerKm] against the step's target window.
/// Returns null when there's no target to compare against (RPE-only step,
/// missing window, or no pace reading yet).
String? runTargetPaceStatus(
  int paceSecPerKm,
  bool isRpe,
  int? minSecPerKm,
  int? maxSecPerKm,
) {
  if (isRpe || minSecPerKm == null || maxSecPerKm == null || paceSecPerKm <= 0) {
    return null;
  }
  if (paceSecPerKm >= minSecPerKm && paceSecPerKm <= maxSecPerKm) {
    return 'On Target';
  }
  const slack = 15;
  if (paceSecPerKm < minSecPerKm) {
    return (minSecPerKm - paceSecPerKm) <= slack ? 'Surging' : 'Off Target';
  }
  return (paceSecPerKm - maxSecPerKm) <= slack ? 'Easing' : 'Off Target';
}

/// Formats seconds-per-km as a per-unit pace string, e.g. "4:20".
String formatRunPace(int secPerKm, bool useMiles) {
  final secPerUnit = useMiles ? (secPerKm * 1.60934).round() : secPerKm;
  final m = secPerUnit ~/ 60;
  final s = secPerUnit % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Formats a metre distance in the display unit, e.g. "3.42 km" / "2.13 mi".
String formatRunDistance(double meters, bool useMiles) {
  final km = meters / 1000;
  final value = useMiles ? km * 0.621371 : km;
  return '${value.toStringAsFixed(2)} ${useMiles ? 'mi' : 'km'}';
}
