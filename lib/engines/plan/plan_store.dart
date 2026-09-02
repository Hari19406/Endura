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
    final json = jsonEncode(plan.toJson());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey, json);
    await prefs.setString(_localUpdatedAtKey, now.toIso8601String());

    unawaited(_pushRemote(plan, now));
  }

  Future<void> _pushRemote(MaterializedPlan plan, DateTime updatedAt) async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return;
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
    }
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
      final row = await client
          .from(_table)
          .select('payload, updated_at')
          .eq('user_id', user.id)
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

  bool get isRemoteAvailable => _isSignedIn;
}
