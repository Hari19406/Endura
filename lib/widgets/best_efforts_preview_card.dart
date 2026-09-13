// lib/widgets/best_efforts_preview_card.dart
//
// You-screen "Best Efforts" card: the #1 all-time record for a handful of
// key benchmark distances, each tappable into the full leaderboard. Pulled
// out as its own widget (same pattern as AchievementTile) so it can be
// pumped and tested without the rest of YouScreen's Supabase/DB wiring.

import 'package:flutter/material.dart';

import '../services/best_efforts_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';

class BestEffortsPreviewCard extends StatelessWidget {
  final Map<DistanceCategory, BestEffortRecord> bestEfforts;
  final List<DistanceCategory> previewCategories;
  final void Function(DistanceCategory category) onCategoryTap;
  final VoidCallback onSeeAll;
  final String Function(DateTime date) formatDate;

  const BestEffortsPreviewCard({
    super.key,
    required this.bestEfforts,
    required this.onCategoryTap,
    required this.onSeeAll,
    required this.formatDate,
    this.previewCategories = const [
      DistanceCategory.k1,
      DistanceCategory.mi1,
      DistanceCategory.k5,
      DistanceCategory.k10,
    ],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BEST EFFORTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              GestureDetector(
                onTap: onSeeAll,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.accent,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: c.accent),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: previewCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final category = previewCategories[index];
                final record = bestEfforts[category];
                return GestureDetector(
                  onTap: () => onCategoryTap(category),
                  child: Container(
                    width: 116,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.background,
                      border: Border.all(color: c.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: c.textTertiary,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          record != null
                              ? BestEffortsService.formatElapsed(
                                  record.elapsedSeconds,
                                )
                              : '--:--',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        if (record != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            formatDate(record.recordedAt),
                            style: TextStyle(fontSize: 10, color: c.textFaint),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
