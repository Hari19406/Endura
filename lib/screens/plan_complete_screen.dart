import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engines/memory/engine_memory.dart';

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

  /// Called when the user taps "Just keep me running".
  /// The caller should immediately enter maintenance mode.
  final VoidCallback onEnterMaintenance;

  /// Display label for the completed race (e.g. "10K").
  final String completedRaceLabel;

  /// Total km run during the plan (loaded by home screen).
  final double totalKmCompleted;

  /// vDOT at plan start (stored before plan started, passed in by caller).
  final int vdotBefore;

  const PlanCompleteCard({
    super.key,
    required this.memory,
    required this.onStartNextPlan,
    required this.onEnterMaintenance,
    required this.completedRaceLabel,
    required this.totalKmCompleted,
    required this.vdotBefore,
  });

  @override
  Widget build(BuildContext context) {
    final totalRuns = memory.totalRunsCompleted;
    final vdotAfter = memory.vdotScore;
    final vdotGain = vdotAfter - vdotBefore;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
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
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0A0A0A),
                letterSpacing: -0.6,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "That's a serious commitment. Max noticed.",
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF666666),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // ── Stats row ──────────────────────────────────────────────────
            Row(
              children: [
                _statChip(
                  label: 'Runs',
                  value: '$totalRuns',
                  icon: Icons.directions_run_rounded,
                ),
                const SizedBox(width: 10),
                _statChip(
                  label: 'km',
                  value: totalKmCompleted.toStringAsFixed(0),
                  icon: Icons.straighten_rounded,
                ),
                if (vdotGain > 0) ...[
                  const SizedBox(width: 10),
                  _statChip(
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
                    color: const Color(0xFF0A0A0A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Start your next plan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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
                  onEnterMaintenance();
                },
                child: const Text(
                  'Just keep me running',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF999999),
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF999999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip({
    required String label,
    required String value,
    required IconData icon,
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFF004D40).withOpacity(0.08)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: highlight
              ? Border.all(
                  color: const Color(0xFF00796B).withOpacity(0.25), width: 1)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 13,
              color: highlight
                  ? const Color(0xFF00796B)
                  : const Color(0xFF999999),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: highlight
                    ? const Color(0xFF00796B)
                    : const Color(0xFF0A0A0A),
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF999999),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAINTENANCE BADGE
//
// Small widget shown above the WorkoutCard when isInMaintenance is true.
// ─────────────────────────────────────────────────────────────────────────────

class MaintenanceBadge extends StatelessWidget {
  final VoidCallback onStartNewPlan;

  const MaintenanceBadge({super.key, required this.onStartNewPlan});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB2DFDB), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.loop_rounded, size: 16, color: Color(0xFF00796B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Maintenance Mode',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00796B),
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onStartNewPlan,
                  child: const Text(
                    'Start a new plan anytime →',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF00796B),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF00796B),
                    ),
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