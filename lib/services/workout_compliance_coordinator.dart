/// WorkoutComplianceCoordinator — the integration point for post-run workout
/// matching.
///
/// Loads the persisted [MaterializedPlan] + the athlete's run history, hands
/// them to the pure [WorkoutComplianceMatcher.match], and persists the result
/// when a scheduled day gained a completion.
///
/// This is purely additive — it only links runs the athlete already logged back
/// to the days they were scheduled for. It never moves, drops or rewrites a
/// workout (that is [PlanAdaptation]'s job, which stays unwired).
library;

import 'package:flutter/foundation.dart';

import '../engines/plan/materialized_plan.dart';
import '../engines/plan/plan_store.dart';
import '../utils/database_service.dart' show loadSavedRuns;
import '../utils/stats.dart' show RunHistory;
import 'workout_compliance_matcher.dart';

class WorkoutComplianceCoordinator {
  WorkoutComplianceCoordinator._();
  static final WorkoutComplianceCoordinator instance =
      WorkoutComplianceCoordinator._();

  bool _running = false;

  /// Match the persisted plan against logged runs and persist any new links.
  /// Returns the matches made (empty when nothing changed). Never throws —
  /// failures are logged and swallowed so the dashboard still paints.
  Future<List<ComplianceMatch>> sync({int windowDays = 1}) async {
    if (_running) return const [];
    _running = true;
    try {
      final plan = await PlanStore.instance.load();
      if (plan == null || plan.weeks.isEmpty) return const [];

      final activities = await _activities();
      if (activities.isEmpty) return const [];

      final result = WorkoutComplianceMatcher.match(
        plan: plan,
        recentActivities: activities,
        windowDays: windowDays,
      );

      if (result.changed) {
        await PlanStore.instance.save(result.plan);
        for (final m in result.matches) {
          debugPrint('[Compliance] W${m.weekNumber} ${_wd(m.weekday)} '
              '${m.slot.name} ← run ${m.activityId} '
              '(${m.actualKm.toStringAsFixed(1)}/${m.targetKm.toStringAsFixed(1)} km, '
              'offset ${m.dayOffset}d)');
        }
      }
      return result.matches;
    } catch (e, s) {
      debugPrint('[WorkoutComplianceCoordinator] sync failed: $e\n$s');
      return const [];
    } finally {
      _running = false;
    }
  }

  Future<List<CompletedActivity>> _activities() async {
    final List<RunHistory> runs = await loadSavedRuns();
    return [
      for (final r in runs)
        CompletedActivity(
          // RunHistory has no stable id — a run is uniquely a (date, distance)
          // for matching purposes.
          id: '${r.date.toIso8601String()}#${r.distance.toStringAsFixed(2)}',
          date: r.date,
          distanceKm: r.distance,
          durationSeconds: r.durationSeconds,
          paceSecPerKm: _paceToSec(r.averagePace),
          rpe: r.rpe?.toDouble(),
        ),
    ];
  }

  static int? _paceToSec(String pace) {
    final parts = pace.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0].trim());
    final s = int.tryParse(parts[1].trim());
    if (m == null || s == null) return null;
    return m * 60 + s;
  }

  static String _wd(int i) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i.clamp(0, 6)];
}
