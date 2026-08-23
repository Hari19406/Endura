import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This callback runs in a separate isolate to track time even when app is backgrounded
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RunTrackingTaskHandler());
}

class RunTrackingTaskHandler extends TaskHandler {
  DateTime? _startTime;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('[ForegroundTask] Started at $timestamp');

    // Load the start time from preferences
    final prefs = await SharedPreferences.getInstance();
    final startTimeMillis = prefs.getInt('run_start_time');
    _startTime = startTimeMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(startTimeMillis)
        : timestamp;
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (_startTime == null) return;

    // Always derive elapsed time from the absolute start time rather than
    // accumulating per-tick deltas, so a delayed/missed tick (Android can
    // throttle repeating background events) can't cause the displayed time
    // to drift behind the real elapsed time.
    final elapsed = timestamp.difference(_startTime!).inSeconds;
    final backgroundSeconds = elapsed > 0 ? elapsed : 0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('background_elapsed_seconds', backgroundSeconds);
    final distanceMeters = prefs.getDouble('run_distance_meters') ?? 0.0;
    final useMiles = prefs.getString('distance_unit') == 'miles';

    print(
      '[ForegroundTask] Elapsed: $backgroundSeconds seconds, distance: $distanceMeters m',
    );

    // Update notification
    FlutterForegroundTask.updateService(
      notificationTitle: 'Run in progress',
      notificationText:
          '${_formatTime(backgroundSeconds)} · ${_formatDistance(distanceMeters, useMiles)}',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('[ForegroundTask] Stopped at $timestamp');

    // Clean up preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('run_start_time');
    await prefs.remove('background_elapsed_seconds');
    await prefs.remove('run_distance_meters');
  }

  String _formatTime(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    int secs = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else {
      return '${minutes}m ${secs}s';
    }
  }

  String _formatDistance(double meters, bool useMiles) {
    final km = meters / 1000;
    final value = useMiles ? km * 0.621371 : km;
    return '${value.toStringAsFixed(2)} ${useMiles ? 'mi' : 'km'}';
  }
}
