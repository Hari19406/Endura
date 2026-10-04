// lib/widgets/target_pace_indicator.dart
//
// Reusable widget that compares currentPace (seconds/km) against a
// PaceRange from CoachMessage.workoutPlan.main.paceRange.
// Completely self-contained — no engine imports, no state management.

import 'package:flutter/material.dart';
import '../services/coach_message_builder.dart' as message;
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PACE STATUS ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum PaceStatus { onPace, tooSlow, tooFast, noData }

// ─────────────────────────────────────────────────────────────────────────────
// PACE COMPARISON HELPER
// Pure function — no side effects, no Flutter imports needed.
// currentPace and paceRange are both in seconds/km.
// Lower seconds/km = faster pace.
// ─────────────────────────────────────────────────────────────────────────────

class PaceComparator {
  /// Returns null if currentPace is invalid (0, NaN, Infinity).
  static PaceStatus compare({
    required double currentPaceSecondsPerKm,
    required message.PaceRange targetRange,
  }) {
    // Guard: pace not yet available (start of run)
    if (currentPaceSecondsPerKm <= 0 ||
        currentPaceSecondsPerKm.isNaN ||
        currentPaceSecondsPerKm.isInfinite ||
        currentPaceSecondsPerKm > 1800) {
      // >30 min/km is not a real running pace
      return PaceStatus.noData;
    }

    final min = targetRange.minSecondsPerKm; // fastest bound (lower seconds)
    final max = targetRange.maxSecondsPerKm; // slowest bound (higher seconds)

    // Within range → ON PACE
    if (currentPaceSecondsPerKm >= min && currentPaceSecondsPerKm <= max) {
      return PaceStatus.onPace;
    }

    // Faster than min bound → TOO FAST
    if (currentPaceSecondsPerKm < min) return PaceStatus.tooFast;

    // Slower than max bound → TOO SLOW
    return PaceStatus.tooSlow;
  }

  /// Format int seconds/km → "M:SS"
  static String formatPace(int secondsPerKm) {
    if (secondsPerKm <= 0) return '--:--';
    final m = secondsPerKm ~/ 60;
    final s = secondsPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Format a PaceRange as "M:SS–M:SS/km" (or "/mi" when [useMiles]).
  /// [range] is always canonical km — only the rendered text converts.
  static String formatRange(message.PaceRange range, {bool useMiles = false}) {
    final lo = UnitUtils.displayPaceSeconds(
      range.minSecondsPerKm.toDouble(),
      useMiles,
    ).round();
    final hi = UnitUtils.displayPaceSeconds(
      range.maxSecondsPerKm.toDouble(),
      useMiles,
    ).round();
    return '${formatPace(lo)}–${formatPace(hi)}${UnitUtils.perUnitLabel(useMiles)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARGET PACE INDICATOR WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class TargetPaceIndicator extends StatelessWidget {
  /// Current GPS pace in seconds/km. Pass 0.0 when not yet available.
  final double currentPaceSecondsPerKm;

  /// From CoachMessage.workoutPlan.main.paceRange.
  /// Pass null for free runs — widget renders a "FREE RUN" badge.
  final message.PaceRange? targetRange;

  /// Display-unit preference. [currentPaceSecondsPerKm]/[targetRange] stay
  /// canonical km — only the rendered text converts.
  final bool useMiles;

  const TargetPaceIndicator({
    super.key,
    required this.currentPaceSecondsPerKm,
    required this.targetRange,
    this.useMiles = false,
  });

  // ── Visual config per status ─────────────────────────────────────────────

  Color _statusColor(BuildContext context, PaceStatus s) {
    final c = context.colors;
    switch (s) {
      case PaceStatus.onPace:
        return c.success;
      case PaceStatus.tooSlow:
        return c.danger;
      case PaceStatus.tooFast:
        return c.workoutTempo;
      case PaceStatus.noData:
        return c.textTertiary;
    }
  }

  String _statusLabel(PaceStatus s) {
    switch (s) {
      case PaceStatus.onPace:
        return 'ON PACE';
      case PaceStatus.tooSlow:
        return 'TOO SLOW';
      case PaceStatus.tooFast:
        return 'TOO FAST';
      case PaceStatus.noData:
        return 'WAITING';
    }
  }

  IconData _statusIcon(PaceStatus s) {
    switch (s) {
      case PaceStatus.onPace:
        return Icons.check_circle_outline;
      case PaceStatus.tooSlow:
        return Icons.arrow_downward_rounded;
      case PaceStatus.tooFast:
        return Icons.arrow_upward_rounded;
      case PaceStatus.noData:
        return Icons.hourglass_empty_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // No target → free run badge
    if (targetRange == null) {
      return _buildFreeRunBadge();
    }

    final status = PaceComparator.compare(
      currentPaceSecondsPerKm: currentPaceSecondsPerKm,
      targetRange: targetRange!,
    );

    final color = _statusColor(context, status);
    final label = _statusLabel(status);
    final icon = _statusIcon(status);
    final range = PaceComparator.formatRange(targetRange!, useMiles: useMiles);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          // ── Target range label ───────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TARGET',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  range,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    letterSpacing: -0.3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          // ── Divider ──────────────────────────────────────────────────────
          Container(
            width: 1,
            height: 32,
            color: context.colors.border,
            margin: const EdgeInsets.symmetric(horizontal: 14),
          ),

          // ── Status badge ─────────────────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFreeRunBadge() {
    return Builder(
      builder: (context) {
        final c = context.colors;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.divider,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(Icons.directions_run, size: 15, color: c.textTertiary),
              const SizedBox(width: 8),
              Text(
                'FREE RUN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.textTertiary,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                'No target pace',
                style: TextStyle(fontSize: 11, color: c.textFaint),
              ),
            ],
          ),
        );
      },
    );
  }
}
