/// Notification title/content formatting for the live-run foreground
/// service — covers both open/free runs and structured workouts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/run_notification_formatter.dart';

void main() {
  group('buildRunNotificationTitle', () {
    test('free run falls back to a plain title', () {
      expect(
        buildRunNotificationTitle(
          hasStructuredSteps: false,
          stepIndex: 0,
          stepTotal: 0,
        ),
        'Endura · Run in progress',
      );
    });

    test('structured workout shows 1-based step and label', () {
      expect(
        buildRunNotificationTitle(
          hasStructuredSteps: true,
          stepIndex: 2,
          stepTotal: 6,
          stepLabel: 'Interval',
        ),
        'Endura · Step 3 of 6 (Interval)',
      );
    });

    test('missing label falls back to "Step"', () {
      expect(
        buildRunNotificationTitle(
          hasStructuredSteps: true,
          stepIndex: 0,
          stepTotal: 3,
        ),
        'Endura · Step 1 of 3 (Step)',
      );
    });
  });

  group('buildRunNotificationContent', () {
    test('open run: distance + pace, no target status', () {
      final text = buildRunNotificationContent(
        distanceMeters: 3420,
        useMiles: false,
        paceSecPerKm: 260,
        isPaused: false,
        hasStructuredSteps: false,
        stepIsRpe: false,
      );
      expect(text, '3.42 km · 4:20 /km');
    });

    test('structured step inside target window shows "On Target"', () {
      final text = buildRunNotificationContent(
        distanceMeters: 3420,
        useMiles: false,
        paceSecPerKm: 260,
        isPaused: false,
        hasStructuredSteps: true,
        stepIsRpe: false,
        targetMinSecPerKm: 255,
        targetMaxSecPerKm: 270,
      );
      expect(text, '3.42 km · 4:20 /km · On Target');
    });

    test('appends remaining step distance for structured workouts', () {
      final text = buildRunNotificationContent(
        distanceMeters: 3420,
        useMiles: false,
        paceSecPerKm: 260,
        isPaused: false,
        hasStructuredSteps: true,
        stepIsRpe: false,
        targetMinSecPerKm: 255,
        targetMaxSecPerKm: 270,
        remainingStepMeters: 380,
      );
      expect(text, '3.42 km · 4:20 /km · On Target · 0.38 km left');
    });

    test('RPE-only step shows no target status', () {
      final text = buildRunNotificationContent(
        distanceMeters: 1000,
        useMiles: false,
        paceSecPerKm: 300,
        isPaused: false,
        hasStructuredSteps: true,
        stepIsRpe: true,
        targetMinSecPerKm: 255,
        targetMaxSecPerKm: 270,
      );
      expect(text, '1.00 km · 5:00 /km');
    });

    test('no pace reading yet shows placeholder', () {
      final text = buildRunNotificationContent(
        distanceMeters: 0,
        useMiles: false,
        paceSecPerKm: 0,
        isPaused: false,
        hasStructuredSteps: false,
        stepIsRpe: false,
      );
      expect(text, '0.00 km · --:-- /km');
    });

    test('paused run is prefixed', () {
      final text = buildRunNotificationContent(
        distanceMeters: 500,
        useMiles: false,
        paceSecPerKm: 300,
        isPaused: true,
        hasStructuredSteps: false,
        stepIsRpe: false,
      );
      expect(text, 'Paused · 0.50 km · 5:00 /km');
    });

    test('miles unit converts distance and pace', () {
      final text = buildRunNotificationContent(
        distanceMeters: 1609.34,
        useMiles: true,
        paceSecPerKm: 300,
        isPaused: false,
        hasStructuredSteps: false,
        stepIsRpe: false,
      );
      // 1609.34 m -> 1.00 mi; 300 s/km -> ~482.8 s/mi -> 8:03/mi
      expect(text, '1.00 mi · 8:03 /mi');
    });
  });

  group('runTargetPaceStatus', () {
    test('faster than target within slack is "Surging"', () {
      expect(runTargetPaceStatus(245, false, 255, 270), 'Surging');
    });

    test('faster than target beyond slack is "Off Target"', () {
      expect(runTargetPaceStatus(200, false, 255, 270), 'Off Target');
    });

    test('slower than target within slack is "Easing"', () {
      expect(runTargetPaceStatus(280, false, 255, 270), 'Easing');
    });

    test('slower than target beyond slack is "Off Target"', () {
      expect(runTargetPaceStatus(320, false, 255, 270), 'Off Target');
    });

    test('RPE-only or missing window returns null', () {
      expect(runTargetPaceStatus(260, true, 255, 270), isNull);
      expect(runTargetPaceStatus(260, false, null, 270), isNull);
      expect(runTargetPaceStatus(0, false, 255, 270), isNull);
    });
  });
}
