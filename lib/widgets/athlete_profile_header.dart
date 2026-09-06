// lib/widgets/athlete_profile_header.dart
//
// Strava-style identity header shared by the You tab (self) and
// AthleteProfileScreen (self or another athlete): avatar, name, location, bio,
// follower / following / activity counts, and the primary action button
// (Edit Profile for self, Follow / Following toggle for others).

import 'package:flutter/material.dart';

import '../models/athlete_profile.dart';
import '../screens/athlete_list_screen.dart' show AthleteAvatar;
import '../theme/app_colors.dart';

class AthleteProfileHeader extends StatelessWidget {
  final AthleteProfile profile;
  final SocialCounts counts;
  final bool isSelf;

  /// Other-athlete only.
  final bool isFollowing;
  final VoidCallback? onToggleFollow;

  /// Self only.
  final VoidCallback? onEditProfile;

  /// Activity count shown in the social bar (self only; "—" otherwise).
  final int? activityCount;

  final VoidCallback? onTapFollowers;
  final VoidCallback? onTapFollowing;

  final EdgeInsets padding;

  const AthleteProfileHeader({
    super.key,
    required this.profile,
    required this.counts,
    required this.isSelf,
    this.isFollowing = false,
    this.onToggleFollow,
    this.onEditProfile,
    this.activityCount,
    this.onTapFollowers,
    this.onTapFollowing,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 16),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AthleteAvatar(athlete: p, radius: 34),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        if (p.isSubscribed) ...[
                          const SizedBox(width: 5),
                          Icon(Icons.verified, size: 15, color: c.accent),
                        ],
                      ],
                    ),
                    if (p.location != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: c.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              p.location!,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (p.bio != null && p.bio!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              p.bio!.trim(),
              style: TextStyle(
                fontSize: 13,
                color: c.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCell(
                value: counts.followers.toString(),
                label: 'Followers',
                onTap: onTapFollowers,
              ),
              _StatCell(
                value: counts.following.toString(),
                label: 'Following',
                onTap: onTapFollowing,
              ),
              _StatCell(
                value: isSelf ? (activityCount ?? 0).toString() : '—',
                label: 'Activities',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _actionButton(context),
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context) {
    final c = context.colors;
    if (isSelf) {
      return GestureDetector(
        onTap: onEditProfile,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Edit Profile',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ),
      );
    }
    final following = isFollowing;
    return GestureDetector(
      onTap: onToggleFollow,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: following ? c.surface : c.accent,
          border: Border.all(color: following ? c.border : c.accent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          following ? 'Following' : 'Follow',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: following ? c.textPrimary : c.onAccent,
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _StatCell({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
