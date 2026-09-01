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

  // ── Short-notice interception ─────────────────────────────────────────────
  static Future<void> shortNoticeShown({
    required String goal,
    required int weeksAvailable,
  }) => capture(
    'short_notice_shown',
    properties: {'goal': goal, 'weeks_available': weeksAvailable},
  );

  /// 'continue_anyway' | 'pick_another'. The split tells us whether the
  /// interception is genuinely helping or just costing us signups.
  static Future<void> shortNoticeChoice(String choice) =>
      capture('short_notice_choice', properties: {'choice': choice});

  // ── Plan reveal ───────────────────────────────────────────────────────────
  // Fired once per onboarding run, on the first successful projection — not on
  // every arrival at the reveal, or returning from an edit would inflate it and
  // destroy the funnel denominator.
  static Future<void> planRevealViewed({
    required String goal,
    required int planWeeks,
    required double peakWeeklyKm,
    required int runsPerWeek,
  }) => capture(
    'plan_reveal_viewed',
    properties: {
      'goal': goal,
      'plan_weeks': planWeeks,
      'peak_weekly_km': peakWeeklyKm.round(),
      'runs_per_week': runsPerWeek,
    },
  );

  static Future<void> planRevealEditTapped(String row) =>
      capture('plan_reveal_edit_tapped', properties: {'row': row});

  /// [changed] is false when the user opened a row and left it as it was —
  /// which tells us the row was confusing rather than wrong.
  static Future<void> planRevealEditReturned({
    required String row,
    required bool changed,
  }) => capture(
    'plan_reveal_edit_returned',
    properties: {'row': row, 'changed': changed},
  );

  /// Latched once per screen visit; firing per touch move would flood PostHog.
  static Future<void> planRevealCurveScrubbed() =>
      capture('plan_reveal_curve_scrubbed');

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
