/// UnlockTrainingBottomSheet — shown instead of a workout's detail sheet when
/// the tapped day falls in a week the athlete hasn't unlocked: the same rule
/// [plan_overview_screen.dart]'s week lock uses (`!isPro && week beyond the
/// current one`). Never performs a purchase itself — the CTA opens the full
/// `PaywallScreen`, which already owns the RevenueCat offering/purchase flow;
/// duplicating that here would mean two places that can drift out of sync.
library;

import 'package:flutter/material.dart';

import '../screens/paywall_screen.dart';
import '../services/analytics_service.dart' show Analytics;
import '../theme/app_colors.dart';

class UnlockTrainingBottomSheet extends StatelessWidget {
  const UnlockTrainingBottomSheet({super.key});

  /// Opens the sheet and logs the tap. Use this rather than
  /// `showModalBottomSheet` directly so every call site is tracked the same
  /// way.
  static Future<void> show(BuildContext context) {
    Analytics.capture('locked_workout_tapped');
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const UnlockTrainingBottomSheet(),
    );
  }

  Widget _perk(BuildContext context, IconData icon, String text) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.premiumGold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: Icon(Icons.close_rounded, color: c.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: c.premiumGold.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 28,
                      color: c.premiumGold,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: c.premiumGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PREMIUM WORKOUT',
                      style: textTheme.labelSmall?.copyWith(
                        color: c.premiumGold,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'UNLOCK YOUR TRAINING',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This workout is part of your premium training plan. '
                  'Upgrade to unlock personalized workouts and reach your '
                  'goals faster.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "WHAT YOU'LL UNLOCK",
                        style: textTheme.labelSmall?.copyWith(
                          color: c.textTertiary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _perk(
                        context,
                        Icons.tune_rounded,
                        'Personalized workouts tailored to your pace and goal',
                      ),
                      _perk(
                        context,
                        Icons.auto_graph_rounded,
                        'A plan that adapts week to week as you progress',
                      ),
                      _perk(
                        context,
                        Icons.calendar_month_rounded,
                        'Your full multi-week training calendar, unlocked',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PaywallScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.premiumGold,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Unlock Premium Access',
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
