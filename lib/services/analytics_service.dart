// lib/services/analytics_service.dart
//
// Thin wrapper around PostHog. Every analytics event in the app should go
// through here so that:
//   1. Event names live in one place (no typos / drift across screens).
//   2. Every call is wrapped in try/catch — analytics can NEVER crash the app
//      or block a user flow.
//   3. If PostHog wasn't initialised (missing credentials), calls are safe
//      no-ops, matching how the SDK behaves before setup().

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

class Analytics {
  Analytics._();

  /// Tie all subsequent events to a specific user. Call after sign-in.
  static Future<void> identify(
    String userId, {
    Map<String, Object>? properties,
  }) async {
    try {
      await Posthog().identify(userId: userId, userProperties: properties);
    } catch (e) {
      debugPrint('[Analytics] identify failed: $e');
    }
  }

  /// Clear the identified user. Call on sign-out so the next user isn't
  /// merged into the previous person's profile.
  static Future<void> reset() async {
    try {
      await Posthog().reset();
    } catch (e) {
      debugPrint('[Analytics] reset failed: $e');
    }
  }

  /// Generic event capture. Prefer the named helpers below where they exist.
  static Future<void> capture(
    String event, {
    Map<String, Object>? properties,
  }) async {
    try {
      await Posthog().capture(eventName: event, properties: properties);
    } catch (e) {
      debugPrint('[Analytics] capture "$event" failed: $e');
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────
  static Future<void> appOpened() => capture('app_opened');

  // ── Auth ───────────────────────────────────────────────────────────────
  static Future<void> signup(String method) =>
      capture('signup', properties: {'method': method});

  static Future<void> login(String method) =>
      capture('login', properties: {'method': method});

  // ── Onboarding funnel ────────────────────────────────────────────────────
  static Future<void> onboardingStepViewed(String step, int index) => capture(
    'onboarding_step_viewed',
    properties: {'step': step, 'step_index': index},
  );

  static Future<void> onboardingCompleted({
    required String goal,
    required String level,
    required int runsPerWeek,
    required int planWeeks,
  }) => capture(
    'onboarding_completed',
    properties: {
      'goal': goal,
      'level': level,
      'runs_per_week': runsPerWeek,
      'plan_weeks': planWeeks,
    },
  );

  // ── Plan ─────────────────────────────────────────────────────────────────
  static Future<void> planCreated({
    required String goal,
    required String level,
  }) => capture('plan_created', properties: {'goal': goal, 'level': level});

  static Future<void> planDaySkipped() => capture('plan_day_skipped');

  // ── Workout engagement ────────────────────────────────────────────────────
  static Future<void> workoutStarted(String workoutType) =>
      capture('workout_started', properties: {'workout_type': workoutType});

  static Future<void> workoutPaused() => capture('workout_paused');
  static Future<void> workoutResumed() => capture('workout_resumed');
  static Future<void> workoutDiscarded() => capture('workout_discarded');

  static Future<void> workoutCompleted({
    required int durationSeconds,
    required double distanceKm,
    required String workoutType,
    required bool isFreeRun,
    String? averagePace,
  }) => capture(
    'workout_completed',
    properties: {
      'duration': durationSeconds,
      'distance': distanceKm,
      'workout_type': workoutType,
      'is_free_run': isFreeRun,
      if (averagePace != null) 'average_pace': averagePace,
    },
  );

  static Future<void> runShared({
    required String workoutType,
    required String source,
    String style = 'classic',
    String template = 'full',
    String action = 'share',
  }) => capture(
    'run_shared',
    properties: {
      'workout_type': workoutType,
      'source': source,
      'style': style,
      'template': template,
      'action': action,
    },
  );

  // ── Revenue ────────────────────────────────────────────────────────────────
  static Future<void> paywallViewed() => capture('paywall_viewed');

  static Future<void> subscriptionStarted() => capture('subscription_started');

  static Future<void> paywallDismissed() => capture('paywall_dismissed');

  // ── Errors ─────────────────────────────────────────────────────────────────
  static Future<void> runSaveFailed(String reason) =>
      capture('run_save_failed', properties: {'reason': reason});
}
