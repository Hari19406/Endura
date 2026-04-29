double paceStringToSpeed(String pace) {
  try {
    final parts = pace.split(':');
    if (parts.length != 2) return 0;

    final minutes = int.parse(parts[0]);
    final seconds = int.parse(parts[1]);

    final totalSeconds = (minutes * 60) + seconds;
    if (totalSeconds <= 0) return 0;

    return 1000 / totalSeconds;
  } catch (_) {
    return 0;
  }
}