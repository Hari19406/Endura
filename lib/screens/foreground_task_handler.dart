import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This callback runs in a separate isolate to track time even when app is backgrounded
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RunTrackingTaskHandler());
}

class RunTrackingTaskHandler extends TaskHandler {
  int _backgroundSeconds = 0;
  DateTime? _lastTickTime;
  
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('[ForegroundTask] Started at $timestamp');
    _lastTickTime = timestamp;
    _backgroundSeconds = 0;
    
    // Load the start time from preferences
    final prefs = await SharedPreferences.getInstance();
    final startTimeMillis = prefs.getInt('run_start_time');
    if (startTimeMillis != null) {
      final startTime = DateTime.fromMillisecondsSinceEpoch(startTimeMillis);
      final elapsed = timestamp.difference(startTime).inSeconds;
      _backgroundSeconds = elapsed > 0 ? elapsed : 0;
      print('[ForegroundTask] Resumed with $_backgroundSeconds seconds elapsed');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (_lastTickTime != null) {
      final elapsed = timestamp.difference(_lastTickTime!).inSeconds;
      _backgroundSeconds += elapsed;
      
      // Save current elapsed time to shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('background_elapsed_seconds', _backgroundSeconds);
      
      print('[ForegroundTask] Elapsed: $_backgroundSeconds seconds');
      
      // Update notification
      FlutterForegroundTask.updateService(
        notificationTitle: 'Run in progress',
        notificationText: '${_formatTime(_backgroundSeconds)} elapsed',
      );
    }
    _lastTickTime = timestamp;
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('[ForegroundTask] Stopped at $timestamp');
    
    // Clean up preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('run_start_time');
    await prefs.remove('background_elapsed_seconds');
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
}