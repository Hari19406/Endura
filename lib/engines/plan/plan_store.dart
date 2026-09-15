/// PlanStore — persistence for the materialised full plan.
///
///   * local cache (SharedPreferences) is the fast path, always written
///   * Supabase `materialized_plans` is the durable copy (survives reinstall,
///     syncs devices); best-effort, failures never block the app
///   * load() reconciles the two by `updatedAt`, newest wins
///
/// Mirrors EngineStateSyncService's "sync is best-effort, local is truth for
/// this session" approach.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'materialized_plan.dart';

/// Outcome of [PlanStore.saveAndSync] — lets a caller (onboarding's "building
/// your plan" screen) tell "safely in the cloud" from "only on this device,
/// retry later".
enum PlanSyncOutcome {
  /// Local cache written AND the Supabase row confirmed.
  syncedRemote,

  /// Local cache written, but the remote push failed (offline / server error).
  /// The plan is safe on-device and will ride the next natural sync; the UI
  /// should offer a retry.
  savedLocalOnly,

  /// Local cache written; there is no remote to sync to (signed out, or
  /// Supabase not initialised). Not an error.
  savedNoRemote,
}

class PlanStore {
  static final PlanStore instance = PlanStore._();
  PlanStore._();

  @visibleForTesting
  PlanStore.forTest();

  static const _localKey = 'materialized_plan_v1';
  static const _localUpdatedAtKey = 'materialized_plan_v1_updated_at';
  static const _table = 'materialized_plans';

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Supabase not initialised (tests, preview harnesses)
    }
  }

  User? get _user => _client?.auth.currentUser;
  bool get _isSignedIn => _user != null;

  // ── Save ─────────────────────────────────────────────────────────────────

  /// Write the plan to the local cache immediately, then push to Supabase in
  /// the background. Returns once the local write completes.
  Future<void> save(MaterializedPlan plan) async {
    final now = DateTime.now().toUtc();
    await _writeLocal(plan, now);
    unawaited(_upsertRemote(plan, now));
  }

  /// Like [save], but awaits the Supabase write and reports whether it landed.
  /// Onboarding's plan-build screen uses the result to offer a retry when only
  /// the on-device copy could be written.
  Future<PlanSyncOutcome> saveAndSync(MaterializedPlan plan) async {
    final now = DateTime.now().toUtc();
    await _writeLocal(plan, now);

    final client = _client;
    final user = _user;
    if (client == null || user == null) return PlanSyncOutcome.savedNoRemote;

    final ok = await _upsertRemote(plan, now);
    return ok ? PlanSyncOutcome.syncedRemote : PlanSyncOutcome.savedLocalOnly;
  }

  /// Upsert this plan's row, then supersede every *other* plan for the user by
  /// deleting it — the app keeps exactly one live materialised plan per user,
  /// which is what lets [_loadRemote] use `maybeSingle()`. Returns whether the
  /// upsert itself succeeded; the supersede sweep is best-effort.
  Future<bool> _upsertRemote(MaterializedPlan plan, DateTime updatedAt) async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return false;
    try {
      await client.from(_table).upsert({
        'user_id': user.id,
        'plan_id': plan.planId,
        'inputs_fingerprint': plan.inputsFingerprint,
        'built_from_vdot': plan.builtFromVdot,
        'schema_version': MaterializedPlan.schemaVersion,
        'payload': plan.toJson(),
        'updated_at': updatedAt.toIso8601String(),
      }, onConflict: 'user_id,plan_id');
    } catch (e) {
      debugPrint('[PlanStore] remote push failed: $e');
      return false;
    }
    try {
      await client
          .from(_table)
          .delete()
          .eq('user_id', user.id)
          .neq('plan_id', plan.planId);
    } catch (e) {
      debugPrint('[PlanStore] superseded-plan sweep failed: $e');
    }
    return true;
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  /// Newest of (local cache, Supabase row). Null when neither has a plan.
  Future<MaterializedPlan?> load() async {
    final (local, localAt) = await _loadLocal();
    final (remote, remoteAt) = await _loadRemote();

    if (local == null) {
      if (remote != null) await _writeLocal(remote, remoteAt ?? DateTime.now());
      return remote;
    }
    if (remote == null) return local;

    // Both present — newest wins; refresh the loser.
    final localTime = localAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final remoteTime = remoteAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (remoteTime.isAfter(localTime)) {
      await _writeLocal(remote, remoteTime);
      return remote;
    }
    return local;
  }

  Future<(MaterializedPlan?, DateTime?)> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localKey);
      if (raw == null) return (null, null);
      final plan = MaterializedPlan.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final at = DateTime.tryParse(prefs.getString(_localUpdatedAtKey) ?? '');
      return (plan, at);
    } catch (e) {
      debugPrint('[PlanStore] local load failed: $e');
      return (null, null);
    }
  }

  Future<(MaterializedPlan?, DateTime?)> _loadRemote() async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return (null, null);
    try {
      // Order + limit defensively: a fresh plan's row and the one it supersedes
      // co-exist for the moment between the upsert and the sweep in
      // [_upsertRemote], and a bare maybeSingle() throws on two rows.
      final row = await client
          .from(_table)
          .select('payload, updated_at')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return (null, null);
      final plan = MaterializedPlan.fromJson(
        Map<String, dynamic>.from(row['payload'] as Map),
      );
      final at = DateTime.tryParse(row['updated_at'] as String? ?? '');
      return (plan, at);
    } catch (e) {
      debugPrint('[PlanStore] remote load failed: $e');
      return (null, null);
    }
  }

  Future<void> _writeLocal(MaterializedPlan plan, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey, jsonEncode(plan.toJson()));
    await prefs.setString(_localUpdatedAtKey, at.toUtc().toIso8601String());
  }

  // ── Read: today's session ────────────────────────────────────────────────

  /// Load the plan and pull out today's day + its week, bundled. The caller
  /// supplies [weekNumber] (usually `RacePlan.currentWeekNumber(now)`) so this
  /// stays decoupled from RacePlan / EngineMemory. Returns null when no plan is
  /// persisted yet or the plan does not cover today — the caller then shows an
  /// explicit placeholder rather than recomputing a session.
  Future<MaterializedDayContext?> getTodayDayContext({
    required int weekNumber,
    DateTime? now,
  }) async {
    final plan = await load();
    if (plan == null) return null;
    final weekdayIndex = (now ?? DateTime.now()).weekday - 1; // 0 = Monday
    return plan.contextForWeekday(
      weekNumber: weekNumber,
      weekdayIndex: weekdayIndex,
    );
  }

  // ── Write: mark a day completed ──────────────────────────────────────────

  /// Stamp [DayCompletion] onto the plan day at [weekNumber] / [weekday]
  /// (0 = Monday) and persist (local + Supabase via [saveAndSync]). Called the
  /// moment a guided run is saved, so the plan reflects the completed session
  /// immediately — no post-hoc fuzzy distance scan.
  ///
  /// Returns true when a matching, not-yet-completed day was updated; false
  /// when there is no plan, the slot is missing, or it was already linked.
  Future<bool> markDayCompleted({
    required int weekNumber,
    required int weekday,
    required double actualKm,
    int? actualPaceSecPerKm,
    double? rpe,
    String? runId,
    DateTime? completedAt,
  }) async {
    final plan = await load();
    if (plan == null) return false;

    final wi = plan.weeks.indexWhere((w) => w.weekNumber == weekNumber);
    if (wi < 0) return false;
    final week = plan.weeks[wi];

    final di = week.days.indexWhere((d) => d.weekday == weekday);
    if (di < 0) return false;
    if (week.days[di].isCompleted) return false;

    final updatedDay = week.days[di].copyWith(
      completion: DayCompletion(
        completedAt: completedAt ?? DateTime.now(),
        actualKm: actualKm,
        actualPaceSecPerKm: actualPaceSecPerKm,
        rpe: rpe,
        runId: runId,
      ),
    );
    final days = List<MaterializedDay>.of(week.days)..[di] = updatedDay;
    final weeks = List<MaterializedWeek>.of(plan.weeks)
      ..[wi] = week.copyWith(days: days);

    await saveAndSync(plan.copyWith(weeks: weeks));
    return true;
  }

  // ── Write: mark a day skipped ────────────────────────────────────────────

  /// Stamp a skip timestamp onto the plan day at [weekNumber] / [weekday]
  /// (0 = Monday) — the deliberate "Skip Workout" action from the pre-run
  /// briefing screen, distinct from a day that simply hasn't happened yet.
  ///
  /// Returns true when a matching day (not already completed or skipped) was
  /// updated; false when there is no plan, the slot is missing, or the day
  /// was already completed/skipped.
  Future<bool> markDaySkipped({
    required int weekNumber,
    required int weekday,
    DateTime? skippedAt,
  }) async {
    final plan = await load();
    if (plan == null) return false;

    final wi = plan.weeks.indexWhere((w) => w.weekNumber == weekNumber);
    if (wi < 0) return false;
    final week = plan.weeks[wi];

    final di = week.days.indexWhere((d) => d.weekday == weekday);
    if (di < 0) return false;
    if (week.days[di].isCompleted || week.days[di].isSkipped) return false;

    final updatedDay = week.days[di].copyWith(
      skippedAt: skippedAt ?? DateTime.now(),
    );
    final days = List<MaterializedDay>.of(week.days)..[di] = updatedDay;
    final weeks = List<MaterializedWeek>.of(plan.weeks)
      ..[wi] = week.copyWith(days: days);

    await saveAndSync(plan.copyWith(weeks: weeks));
    return true;
  }

  // ── Clear ────────────────────────────────────────────────────────────────

  /// Drop the cached plan (e.g. plan ended, or user signed out). Remote rows
  /// are left for `on delete cascade` / explicit deletion elsewhere.
  Future<void> clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localKey);
    await prefs.remove(_localUpdatedAtKey);
  }

  Future<void> deleteRemote(String planId) async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return;
    try {
      await client
          .from(_table)
          .delete()
          .eq('user_id', user.id)
          .eq('plan_id', planId);
    } catch (e) {
      debugPrint('[PlanStore] remote delete failed: $e');
    }
  }

  /// Full teardown of the athlete's active plan: drops the local cache AND
  /// every remote row for this user (the class invariant is "exactly one live
  /// materialised plan per user", so there is never more than one to remove).
  /// Historical `runs` rows are untouched — this table has no relationship to
  /// them. Call this whenever the athlete changes race goal or resets
  /// training (e.g. from ManagePlanScreen's "Remove Plan"), never partially —
  /// clearing only the local cache (or only EngineMemory's racePlan) leaves a
  /// stale plan that Home/PlanOverview will read straight back via [load].
  Future<void> resetActivePlan() async {
    await clearLocal();
    final client = _client;
    final user = _user;
    if (client == null || user == null) return;
    try {
      await client.from(_table).delete().eq('user_id', user.id);
    } catch (e) {
      debugPrint('[PlanStore] resetActivePlan remote delete failed: $e');
    }
  }

  bool get isRemoteAvailable => _isSignedIn;
}
