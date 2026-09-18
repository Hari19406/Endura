/// BuildPlanHeroCard — the empty-state hero shown on the coach screen when
/// the athlete has no active plan. Single CTA into the plan-creation wizard
/// (OnboardingScreen); every color/text style comes from `context.colors`
/// (the app's AppColors ThemeExtension) and `Theme.of(context).textTheme` so
/// the visual theme can be swapped centrally.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BuildPlanHeroCard extends StatelessWidget {
  /// "Start my new plan" — launches the plan-creation wizard.
  final VoidCallback onStartPlan;

  const BuildPlanHeroCard({super.key, required this.onStartPlan});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: c.heroGradientEnd.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: c.heroGradientEnd.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              '✨ 2 min setup',
              style: textTheme.labelSmall?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Build your first plan',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Professional training, personalized to you—built to make you more consistent, fitter, and faster.',
            style: textTheme.bodyMedium?.copyWith(
              color: c.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FeatureTag(icon: Icons.tune_rounded, label: 'Adaptive'),
              _FeatureTag(
                icon: Icons.calendar_today_rounded,
                label: 'Schedule-friendly',
              ),
              _FeatureTag(
                icon: Icons.verified_user_outlined,
                label: 'Coach-backed',
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Same heroGradient treatment as the "View Workout" button.
          Material(
            color: Colors.transparent,
            child: Ink(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: c.heroGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: onStartPlan,
                borderRadius: BorderRadius.circular(12),
                child: Center(
                  child: Text(
                    'Start my new plan',
                    style: textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: c.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Built by expert coaching logic and adjusted week to week as you progress.',
                  style: textTheme.bodySmall?.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// CoachPrinciplesCard — social-proof strip shown beneath [BuildPlanHeroCard].
/// No coach photo assets exist in the app yet, so the avatar cluster uses
/// generic icon avatars rather than referencing images that don't exist.
class CoachPrinciplesCard extends StatelessWidget {
  const CoachPrinciplesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AvatarCluster(color: c),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Built by expert coaches',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Real coaching principles baked into your plan so you can train confidently from day one.',
                  style: textTheme.bodySmall?.copyWith(
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarCluster extends StatelessWidget {
  final AppColors color;

  const _AvatarCluster({required this.color});

  static const double _size = 34;
  static const double _overlap = 20;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + _overlap * 2,
      height: _size,
      child: Stack(
        children: [
          for (int i = 0; i < 3; i++)
            Positioned(
              left: i * _overlap,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.alphaBlend(
                    color.heroGradientEnd.withValues(alpha: 0.28),
                    color.surface,
                  ),
                  border: Border.all(color: color.surface, width: 2),
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: color.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
