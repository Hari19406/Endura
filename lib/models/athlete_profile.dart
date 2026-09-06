// lib/models/athlete_profile.dart
//
// Public social identity for an athlete. This is the outward-facing slice of the
// `profiles` row — distinct from the coaching-config slice held by
// [UserProfile] in profile_service.dart. Both map to the same table.

class AthleteProfile {
  final String id; // == auth.users.id — the only stable athlete reference
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? city;
  final String? country;
  final bool isPublic;

  /// Has an active Endura Pro entitlement (denormalized `profiles.is_pro`).
  /// Drives the verified badge on the feed / profile header.
  final bool isSubscribed;

  // Denormalized run aggregates (written by the owner's device on run save).
  // Read-only here — never part of [toUpdateMap].
  final int totalDistanceMeters;
  final int totalRuns;
  final int totalMovingSeconds;
  final int totalElevationMeters;
  final int? best5kSeconds;
  final int? best10kSeconds;
  final int? bestHalfMarathonSeconds;

  const AthleteProfile({
    required this.id,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.city,
    this.country,
    this.isPublic = true,
    this.isSubscribed = false,
    this.totalDistanceMeters = 0,
    this.totalRuns = 0,
    this.totalMovingSeconds = 0,
    this.totalElevationMeters = 0,
    this.best5kSeconds,
    this.best10kSeconds,
    this.bestHalfMarathonSeconds,
  });

  bool get hasPublicStats => totalRuns > 0;

  /// Human label: display name, or "Runner" when it hasn't been set.
  String get name => (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!.trim()
      : 'Runner';

  String? get location {
    final parts = [
      city?.trim(),
      country?.trim(),
    ].where((p) => p != null && p.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory AthleteProfile.fromMap(Map<String, dynamic> m) => AthleteProfile(
    id: m['id'] as String,
    displayName: m['display_name'] as String?,
    avatarUrl: m['avatar_url'] as String?,
    bio: m['bio'] as String?,
    city: m['city'] as String?,
    country: m['country'] as String?,
    isPublic: m['is_public'] as bool? ?? true,
    isSubscribed: m['is_pro'] as bool? ?? false,
    totalDistanceMeters: (m['total_distance_meters'] as num?)?.round() ?? 0,
    totalRuns: (m['total_runs'] as num?)?.round() ?? 0,
    totalMovingSeconds: (m['total_moving_seconds'] as num?)?.round() ?? 0,
    totalElevationMeters: (m['total_elevation_meters'] as num?)?.round() ?? 0,
    best5kSeconds: (m['best_5k_seconds'] as num?)?.round(),
    best10kSeconds: (m['best_10k_seconds'] as num?)?.round(),
    bestHalfMarathonSeconds: (m['best_half_marathon_seconds'] as num?)?.round(),
  );

  /// Only the social columns — safe to `update()` without touching coaching state.
  /// Null-valued fields are included so a user can clear their bio/city/etc.
  Map<String, dynamic> toUpdateMap() => {
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'bio': bio,
    'city': city,
    'country': country,
    'is_public': isPublic,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  AthleteProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? city,
    String? country,
    bool? isPublic,
  }) => AthleteProfile(
    id: id,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    bio: bio ?? this.bio,
    city: city ?? this.city,
    country: country ?? this.country,
    isPublic: isPublic ?? this.isPublic,
    isSubscribed: isSubscribed,
    totalDistanceMeters: totalDistanceMeters,
    totalRuns: totalRuns,
    totalMovingSeconds: totalMovingSeconds,
    totalElevationMeters: totalElevationMeters,
    best5kSeconds: best5kSeconds,
    best10kSeconds: best10kSeconds,
    bestHalfMarathonSeconds: bestHalfMarathonSeconds,
  );
}

/// Follower / following tallies for an athlete.
class SocialCounts {
  final int followers;
  final int following;
  const SocialCounts({required this.followers, required this.following});
  static const zero = SocialCounts(followers: 0, following: 0);
}
