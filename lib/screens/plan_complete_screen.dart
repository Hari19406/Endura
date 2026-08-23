import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engines/memory/engine_memory.dart';
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PLAN COMPLETE SCREEN
//
// Shown in-place on the home screen (replaces the WorkoutCard) when
// EngineMemory.isPlanComplete is true and isInMaintenance is false.
//
// Stats pulled directly from EngineMemory so no extra data fetching is needed.
// ─────────────────────────────────────────────────────────────────────────────

class PlanCompleteCard extends StatelessWidget {
  final EngineMemory memory;

  /// Called when the user taps "Start your next plan".
  /// The caller should navigate to the shortened re-onboarding flow.
  final VoidCallback onStartNextPlan;

  /// Called when the user taps "I need a break — remind me in 2 weeks".
  final VoidCallback onRemindLater;

  /// Display label for the completed race (e.g. "10K").
  final String completedRaceLabel;

  /// Total km run during the plan (loaded by home screen).
  final double totalKmCompleted;

  /// vDOT at plan start (stored before plan started, passed in by caller).
  final int vdotBefore;

  /// Whether to display distances in miles instead of km.
  final bool useMiles;

  const PlanCompleteCard({
    super.key,
    required this.memory,
    required this.onStartNextPlan,
    required this.onRemindLater,
    required this.completedRaceLabel,
    required this.totalKmCompleted,
    required this.vdotBefore,
    this.useMiles = false,
  });

  @override
  Widget build(BuildContext context) {
    final totalRuns = memory.totalRunsCompleted;
    final vdotAfter = memory.vdotScore;
    final vdotGain = vdotAfter - vdotBefore;

    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Celebration badge ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF004D40).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🎉', style: TextStyle(fontSize: 13)),
                  SizedBox(width: 6),
                  Text(
                    'PLAN COMPLETE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF00796B),
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Headline ───────────────────────────────────────────────────
            Text(
              'You finished your\n$completedRaceLabel plan 🎉',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                letterSpacing: -0.6,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "That's a serious commitment. Max noticed.",
              style: TextStyle(
                fontSize: 13,
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // ── Stats row ──────────────────────────────────────────────────
            Row(
              children: [
                _statChip(
                  context,
                  label: 'Runs',
                  value: '$totalRuns',
                  icon: Icons.directions_run_rounded,
                ),
                const SizedBox(width: 10),
                _statChip(
                  context,
                  label: UnitUtils.unitLabel(useMiles),
                  value: UnitUtils.displayDistance(
                    totalKmCompleted,
                    useMiles,
                  ).toStringAsFixed(0),
                  icon: Icons.straighten_rounded,
                ),
                if (vdotGain > 0) ...[
                  const SizedBox(width: 10),
                  _statChip(
                    context,
                    label: 'vDOT',
                    value: '$vdotBefore → $vdotAfter',
                    icon: Icons.trending_up_rounded,
                    highlight: true,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            // ── Primary CTA ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onStartNextPlan();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Start your next plan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.onAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Secondary link ─────────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onRemindLater();
                },
                child: Text(
                  'I need a break — remind me in 2 weeks',
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textTertiary,
                    decoration: TextDecoration.underline,
                    decorationColor: c.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    bool highlight = false,
  }) {
    final c = context.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFF004D40).withOpacity(0.08)
              : c.divider,
          borderRadius: BorderRadius.circular(10),
          border: highlight
              ? Border.all(
                  color: const Color(0xFF00796B).withOpacity(0.25),
                  width: 1,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 13,
              color: highlight ? const Color(0xFF00796B) : c.textTertiary,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: highlight ? const Color(0xFF00796B) : c.textPrimary,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: c.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
