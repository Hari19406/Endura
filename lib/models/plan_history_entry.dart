/// PlanHistoryEntry — a completed/retired plan's summary, as stored in the
/// `plan_history` Supabase table (see
/// supabase/migrations/20260913000000_create_plan_history.sql). Read-only
/// from the client: rows are written once by
/// [PlanHistoryRepository.snapshotPlan] and never edited afterward.
library;

class PlanHistoryEntry {
  final String id;
  final String planName;
  final String planType;
  final int durationWeeks;
  final double totalDistanceKm;
  final double completedDistanceKm;
  final DateTime startedAt;
  final DateTime endedAt;
  final String status; // 'completed' | 'archived'

  const PlanHistoryEntry({
    required this.id,
    required this.planName,
    required this.planType,
    required this.durationWeeks,
    required this.totalDistanceKm,
    required this.completedDistanceKm,
    required this.startedAt,
    required this.endedAt,
    required this.status,
  });

  /// 0.0–1.0, safe when [totalDistanceKm] is zero.
  double get completionRatio => totalDistanceKm > 0
      ? (completedDistanceKm / totalDistanceKm).clamp(0.0, 1.0)
      : 0.0;

  factory PlanHistoryEntry.fromJson(Map<String, dynamic> j) => PlanHistoryEntry(
    id: j['id'] as String,
    planName: j['plan_name'] as String,
    planType: j['plan_type'] as String,
    durationWeeks: (j['duration_weeks'] as num).toInt(),
    totalDistanceKm: (j['total_distance_km'] as num).toDouble(),
    completedDistanceKm: (j['completed_distance_km'] as num?)?.toDouble() ?? 0,
    startedAt: DateTime.parse(j['started_at'] as String),
    endedAt: DateTime.parse(j['ended_at'] as String),
    status: j['status'] as String? ?? 'completed',
  );
}
