// lib/models/feed_run.dart
//
// One row in the friends activity feed — a run by an athlete the signed-in user
// follows, joined with that athlete's public profile fields. Built by
// SocialService.fetchFriendsFeed from the `runs` + `profiles` tables.

import '../utils/database_service.dart' show decodePolylineToPoints;

class FeedRun {
  final int runId; // runs.id (bigint)
  final String athleteId; // == runs.user_id == profiles.id
  final String displayName;
  final String? avatarUrl;
  final String? location; // "City, Country" or null
  final DateTime date; // run start (runs.date), UTC-parsed
  final double distanceKm;
  final String averagePace; // "mm:ss" per km
  final int durationSeconds; // moving time
  final int? elapsedSeconds; // wall-clock, null when unknown / == moving time
  final double elevationGain; // metres, 0 when unknown
  final String workoutType;
  final String routePolyline; // app "lat,lng;lat,lng" format, may be empty

  /// Athlete has an active Endura Pro entitlement → verified badge.
  final bool isSubscribed;

  /// Recording source label for the card subtitle (there's one first-party
  /// tracker, so this is effectively a constant today).
  final String source;

  /// Training-plan tag stamped at upload time for guided runs. Both null for
  /// free runs / runs made with no active plan — the card collapses the pill.
  final String? planName;
  final String? planProgress; // e.g. "Week 3 / 8"

  /// Per-km splits as `[{'km': 1, 'seconds': 320, 'elev': -4.0, 'hr': 152}, ...]`
  /// — `elev`/`hr` are omitted per-entry when the recording had no altitude/HR
  /// source. Empty for a run recorded before splits were uploaded, or a
  /// manual/GPS-only entry with none to begin with. See
  /// [CloudSyncService.uploadRun] (the writer) and
  /// [ActivityDetail.fromFeedRun] (the reader — builds [KmSplit]s from this
  /// and a coarse synthetic elevation/pace trace from the per-split deltas).
  final List<Map<String, dynamic>> splits;

  /// Number of comments on this run (batch-loaded by the feed query).
  final int commentCount;

  /// Number of cheers/reactions on this run (batch-loaded by the feed query).
  final int reactionCount;

  /// Whether the signed-in viewer has already reacted to this run.
  final bool viewerReacted;

  const FeedRun({
    required this.runId,
    required this.athleteId,
    required this.displayName,
    this.avatarUrl,
    this.location,
    required this.date,
    required this.distanceKm,
    required this.averagePace,
    required this.durationSeconds,
    this.elapsedSeconds,
    this.elevationGain = 0,
    this.workoutType = 'easy',
    this.routePolyline = '',
    this.isSubscribed = false,
    this.source = 'Endura Tracker',
    this.planName,
    this.planProgress,
    this.splits = const [],
    this.commentCount = 0,
    this.reactionCount = 0,
    this.viewerReacted = false,
  });

  /// Decoded `{lat, lng}` points for the route thumbnail. Empty when there's no
  /// usable polyline.
  List<Map<String, double>> get points => decodePolylineToPoints(routePolyline);

  /// Feed cards have no freeform title — derive a readable label from the
  /// workout type the coach engine assigned (or "Free Run" for unguided runs).
  String get title => switch (workoutType) {
    'easy' => 'Easy Run',
    'tempo' => 'Tempo Run',
    'interval' => 'Interval Workout',
    'long' => 'Long Run',
    'race' || 'race_pace' || 'raceSpecific' => 'Race Pace Run',
    'recovery' => 'Recovery Run',
    'free' || 'free_run' || 'freeRun' => 'Free Run',
    _ => 'Run',
  };

  /// [runRow] is a `runs` row; [profileRow] the matching `profiles` row (may be
  /// null if the profile couldn't be loaded — falls back to "Runner").
  factory FeedRun.fromRows(
    Map<String, dynamic> runRow,
    Map<String, dynamic>? profileRow, {
    int commentCount = 0,
    int reactionCount = 0,
    bool viewerReacted = false,
  }) {
    String? loc;
    if (profileRow != null) {
      final parts = [
        (profileRow['city'] as String?)?.trim(),
        (profileRow['country'] as String?)?.trim(),
      ].where((p) => p != null && p.isNotEmpty).toList();
      if (parts.isNotEmpty) loc = parts.join(', ');
    }
    final name = (profileRow?['display_name'] as String?)?.trim();
    final planName = (runRow['plan_name'] as String?)?.trim();
    return FeedRun(
      runId: (runRow['id'] as num).toInt(),
      athleteId: runRow['user_id'] as String,
      displayName: (name != null && name.isNotEmpty) ? name : 'Runner',
      avatarUrl: profileRow?['avatar_url'] as String?,
      location: loc,
      date: DateTime.parse(runRow['date'] as String).toUtc(),
      distanceKm: (runRow['distance_km'] as num).toDouble(),
      averagePace: runRow['average_pace'] as String? ?? '--:--',
      durationSeconds: (runRow['duration_seconds'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (runRow['elapsed_seconds'] as num?)?.toInt(),
      elevationGain: (runRow['elevation_gain'] as num?)?.toDouble() ?? 0,
      workoutType: runRow['workout_type'] as String? ?? 'easy',
      routePolyline: runRow['route_polyline'] as String? ?? '',
      isSubscribed: profileRow?['is_pro'] as bool? ?? false,
      planName: (planName != null && planName.isNotEmpty) ? planName : null,
      planProgress: (runRow['plan_progress'] as String?)?.trim().isNotEmpty ==
              true
          ? (runRow['plan_progress'] as String).trim()
          : null,
      splits: _decodeSplits(runRow['splits']),
      commentCount: commentCount,
      reactionCount: reactionCount,
      viewerReacted: viewerReacted,
    );
  }

  /// Parses the `runs.splits` jsonb column (a `List` of small maps) into
  /// `List<Map<String, dynamic>>`. Tolerant of `null` (older rows / runs
  /// with none) and any unexpected shape — never throws.
  static List<Map<String, dynamic>> _decodeSplits(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
}
