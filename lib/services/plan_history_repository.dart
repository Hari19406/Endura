/// PlanHistoryRepository — read/write for the `plan_history` table: a summary
/// row snapshotted whenever the athlete's active plan is retired (explicit
/// teardown via [EngineMemoryService.resetCurrentPlan], or replaced by a new
/// plan via [EngineMemoryService.saveRacePlan]).
///
/// Unlike [PlanStore] (one upserted row per user), this is an append-only
/// log — reads go straight to Supabase and fall back to an empty list when
/// signed out, offline, or on any error; there is no local cache to
/// reconcile. Writes are best-effort and must never throw, since they're
/// always called from inside another mutation's flow (plan reset / replace)
/// that must not be blocked by a history-write failure.
library;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../engines/plan/materialized_plan.dart';
import '../models/plan_history_entry.dart';
import '../models/race_plan.dart';

class PlanHistoryRepository {
  static final PlanHistoryRepository instance = PlanHistoryRepository._();
  PlanHistoryRepository._();

  static const _table = 'plan_history';

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Supabase not initialised (tests, preview harnesses)
    }
  }

  User? get _user => _client?.auth.currentUser;

  /// All past plans for the signed-in athlete, newest first. Empty when
  /// signed out, offline, or there is no history yet.
  Future<List<PlanHistoryEntry>> fetchAll() async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return const [];
    try {
      final rows = await client
          .from(_table)
          .select()
          .eq('user_id', user.id)
          .order('ended_at', ascending: false);
      return (rows as List)
          .map((r) => PlanHistoryEntry.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugPrint('[PlanHistoryRepository] fetchAll failed: $e');
      return const [];
    }
  }

  /// Snapshot [racePlan] — with [materialized] supplying completion stats,
  /// when it's still the plan being retired — into `plan_history`. Silent
  /// no-op when signed out; a write failure is logged, never thrown.
  Future<void> snapshotPlan({
    required RacePlan racePlan,
    MaterializedPlan? materialized,
    String? planNameOverride,
  }) async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return;

    final totalDistanceKm = racePlan.weeks.fold<double>(
      0,
      (s, w) => s + w.targetKm,
    );
    final completedDistanceKm = materialized == null
        ? 0.0
        : materialized.weeks.fold<double>(
            0,
            (s, w) => s +
                w.days.fold<double>(
                  0,
                  (s2, d) => s2 + (d.completion?.actualKm ?? 0),
                ),
          );

    final planType = _planTypeLabel(racePlan.goalRace);
    final planName =
        planNameOverride ??
        '$planType · ${DateFormat('MMM yyyy').format(racePlan.createdAt)}';

    try {
      await client.from(_table).insert({
        'user_id': user.id,
        'plan_name': planName,
        'plan_type': planType,
        'duration_weeks': racePlan.weeks.length,
        'total_distance_km': totalDistanceKm,
        'completed_distance_km': completedDistanceKm,
        'started_at': racePlan.createdAt.toUtc().toIso8601String(),
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'status': 'completed',
        'snapshot_data': racePlan.toJson(),
      });
    } catch (e) {
      debugPrint('[PlanHistoryRepository] snapshot failed: $e');
    }
  }

  static String _planTypeLabel(String goalRace) => switch (goalRace) {
    '10k' => '10K Plan',
    'half_marathon' => 'Half Marathon Plan',
    'marathon' => 'Marathon Plan',
    _ => '5K Plan',
  };
}
