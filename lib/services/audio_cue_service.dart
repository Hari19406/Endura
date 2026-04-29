// lib/services/audio_cue_service.dart

import 'package:flutter_tts/flutter_tts.dart';

class AudioCueService {
  static final AudioCueService instance = AudioCueService._();
  AudioCueService._();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isEnabled = false;

  Future<void> initialize({required bool enabled}) async {
    _isEnabled = enabled;
    if (!enabled) return;

    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45); // slightly slower than default — clear outdoors
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _isInitialized = true;
    } catch (e) {
      // Never crash the run over audio failure
      _isInitialized = false;
    }
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  Future<void> _speak(String text) async {
    if (!_isEnabled || !_isInitialized) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Silent failure — audio is non-critical
    }
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  // ── Cue triggers ──────────────────────────────────────────────

  /// Called when run starts
  Future<void> announceRunStart() async {
    await _speak('Run started. Good luck!');
  }

  /// Called every completed kilometre
  /// [kmCompleted] — how many km just completed (1, 2, 3...)
  /// [paceString] — current average pace e.g. "5:30"
  /// [elapsedSeconds] — total elapsed time
  Future<void> announceKilometre({
    required int kmCompleted,
    required String paceString,
    required int elapsedSeconds,
  }) async {
    final distanceText = kmCompleted == 1
        ? '1 kilometre'
        : '$kmCompleted kilometres';

    final paceText = _formatPaceForSpeech(paceString);
    final timeText = _formatTimeForSpeech(elapsedSeconds);

    await _speak('$distanceText. Pace $paceText. Time $timeText.');
  }

  /// Called when run is finished
  Future<void> announceRunComplete({
    required double distanceKm,
    required String averagePace,
    required int elapsedSeconds,
  }) async {
    final distanceText = distanceKm >= 10
        ? '${distanceKm.toStringAsFixed(1)} kilometres'
        : '${distanceKm.toStringAsFixed(2)} kilometres';

    final paceText = _formatPaceForSpeech(averagePace);
    final timeText = _formatTimeForSpeech(elapsedSeconds);

    await _speak(
      'Run complete. $distanceText in $timeText. '
      'Average pace $paceText per kilometre. Great work!',
    );
  }

  /// Called when pace is significantly off target
  /// [currentPace] and [targetPace] in seconds per km
  Future<void> announcePaceWarning({
    required int currentPaceSeconds,
    required int targetPaceSeconds,
  }) async {
    final diff = currentPaceSeconds - targetPaceSeconds;

    if (diff > 30) {
      await _speak('Pace dropping. Speed up a little.');
    } else if (diff < -30) {
      await _speak('Running too fast. Slow down to save energy.');
    }
  }

  // ── Formatters ─────────────────────────────────────────────────

  /// "5:30" → "5 minutes 30 seconds"
  String _formatPaceForSpeech(String pace) {
    try {
      final parts = pace.split(':');
      if (parts.length != 2) return pace;
      final minutes = int.parse(parts[0]);
      final seconds = int.parse(parts[1]);

      if (seconds == 0) return '$minutes minutes';
      if (minutes == 0) return '$seconds seconds';
      return '$minutes minutes $seconds seconds';
    } catch (_) {
      return pace;
    }
  }

  /// 3661 seconds → "1 hour 1 minute" / 330 → "5 minutes 30 seconds"
  String _formatTimeForSpeech(int totalSeconds) {
    final hours   = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      final hText = hours == 1 ? '1 hour' : '$hours hours';
      if (minutes == 0) return hText;
      final mText = minutes == 1 ? '1 minute' : '$minutes minutes';
      return '$hText $mText';
    }

    if (minutes > 0 && seconds == 0) {
      return minutes == 1 ? '1 minute' : '$minutes minutes';
    }

    if (minutes > 0) {
      final mText = minutes == 1 ? '1 minute' : '$minutes minutes';
      final sText = seconds == 1 ? '1 second' : '$seconds seconds';
      return '$mText $sText';
    }

    return seconds == 1 ? '1 second' : '$seconds seconds';
  }
}