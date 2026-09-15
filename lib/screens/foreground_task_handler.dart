import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/run_notification_formatter.dart';

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

    // Reload so this isolate sees writes the UI isolate made to the same
    // on-disk SharedPreferences store since our last tick.
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await prefs.setInt('background_elapsed_seconds', backgroundSeconds);

    final distanceMeters = prefs.getDouble('run_distance_meters') ?? 0.0;
    final useMiles = prefs.getString('distance_unit') == 'miles';
    final isPaused = prefs.getString('run_state') == 'paused';
    final paceSecPerKm = prefs.getInt('rolling_pace_sec_per_km') ?? 0;

    final stepTotal = prefs.getInt('step_total') ?? 0;
    final hasStructuredSteps = stepTotal > 1;
    final stepIndex = (prefs.getInt('step_index') ?? 0).clamp(
      0,
      stepTotal > 0 ? stepTotal - 1 : 0,
    );
    final stepLabel = prefs.getString('step_label');
    final stepIsRpe = prefs.getBool('step_is_rpe') ?? false;
    final targetMin = prefs.getInt('step_target_min');
    final targetMax = prefs.getInt('step_target_max');
    final remainingM = prefs.getDouble('step_remaining_m');

    print(
      '[ForegroundTask] Elapsed: $backgroundSeconds seconds, distance: $distanceMeters m',
    );

    FlutterForegroundTask.updateService(
      notificationTitle: buildRunNotificationTitle(
        hasStructuredSteps: hasStructuredSteps,
        stepIndex: stepIndex,
        stepTotal: stepTotal,
        stepLabel: stepLabel,
      ),
      notificationText: buildRunNotificationContent(
        distanceMeters: distanceMeters,
        useMiles: useMiles,
        paceSecPerKm: paceSecPerKm,
        isPaused: isPaused,
        hasStructuredSteps: hasStructuredSteps,
        stepIsRpe: stepIsRpe,
        targetMinSecPerKm: targetMin,
        targetMaxSecPerKm: targetMax,
        remainingStepMeters: remainingM,
      ),
      notificationButtons: [
        NotificationButton(
          id: 'pause_resume',
          text: isPaused ? 'Resume' : 'Pause',
        ),
        if (hasStructuredSteps && stepIndex < stepTotal - 1)
          const NotificationButton(id: 'next_step', text: 'Next Step'),
      ],
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
    await prefs.remove('run_state');
    await prefs.remove('rolling_pace_sec_per_km');
    await prefs.remove('step_index');
    await prefs.remove('step_total');
    await prefs.remove('step_label');
    await prefs.remove('step_is_rpe');
    await prefs.remove('step_target_min');
    await prefs.remove('step_target_max');
    await prefs.remove('step_remaining_m');
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Relay the tap to the UI isolate, which owns the real run/GPS state.
    FlutterForegroundTask.sendDataToMain({'action': id});
  }
}
