import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../engines/achievement_engine.dart' as achieve;

/// Shared achievement card used by both the You-screen Milestones preview
/// and the full Milestones list screen, so the two always render identically.
class AchievementTile extends StatelessWidget {
  final achieve.Achievement achievement;
  final EdgeInsets margin;

  const AchievementTile({
    super.key,
    required this.achievement,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.background,
        border: Border.all(color: c.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  achievement.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              tierBadge(context, achievement.tier),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            achievement.description,
            style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.3),
          ),
          const SizedBox(height: 5),
          Text(
            formatAchievementDate(achievement.unlockedAt),
            style: TextStyle(
              fontSize: 11,
              color: c.textFaint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// Tier medal hues (bronze/silver/gold/platinum) — fixed data-viz colours with
// no matching semantic token; (background, text) pairs.
const _kBronze = (Color(0xFFF0997B), Color(0xFF4A1B0C));
const _kSilver = (Color(0xFFD3D1C7), Color(0xFF444441));
const _kGold = (Color(0xFFFAC775), Color(0xFF412402));
const _kPlatinum = (Color(0xFFCECBF6), Color(0xFF26215C));

Widget tierBadge(BuildContext context, int tier) {
  final c = context.colors;
  final (Color bg, Color text, String label) = switch (tier) {
    1 => (_kBronze.$1, _kBronze.$2, 'Bronze'),
    2 => (_kSilver.$1, _kSilver.$2, 'Silver'),
    3 => (_kGold.$1, _kGold.$2, 'Gold'),
    4 => (_kPlatinum.$1, _kPlatinum.$2, 'Platinum'),
    _ => (c.border, c.textSecondary, 'Bronze'),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: text,
        letterSpacing: 0.3,
      ),
    ),
  );
}

String formatAchievementDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date).inDays;
  if (diff == 0) return 'Earned today';
  if (diff == 1) return 'Earned yesterday';
  if (diff < 30) return 'Earned $diff days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Earned ${date.day} ${months[date.month - 1]} ${date.year}';
}

/// Sorts achievements the same way everywhere they're listed: highest tier
/// first, then most recently unlocked.
List<achieve.Achievement> sortAchievements(
  List<achieve.Achievement> achievements,
) {
  final sorted = List<achieve.Achievement>.from(achievements);
  sorted.sort((a, b) {
    final tierCompare = b.tier.compareTo(a.tier);
    if (tierCompare != 0) return tierCompare;
    return b.unlockedAt.compareTo(a.unlockedAt);
  });
  return sorted;
}
