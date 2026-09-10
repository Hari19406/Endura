/// PlanAdaptationCard — the inline, non-blocking coach banner shown above the
/// daily workout card when [PlanAdaptationCoordinator] detects a missed block
/// worth recalibrating for.
///
/// It never mutates anything itself: it shows Max's explanation and hands the
/// two choices back to the screen — "Review & Accept" (persist the recalibrated
/// plan) or "Dismiss" (remember this range so it stops nagging).
library;

import 'package:flutter/material.dart';

import '../services/plan_adaptation_service.dart' show MissedWindow;
import '../theme/app_colors.dart';

class PlanAdaptationCard extends StatelessWidget {
  /// Max's plain-language explanation of the change ([PlanRecalibration.
  /// coachExplanation]).
  final String explanation;

  /// The detected layoff window — only used to pick the heading.
  final MissedWindow window;

  /// Accept: persist the recalibrated plan and refresh.
  final VoidCallback onReviewAccept;

  /// Dismiss: record this range as handled so it does not prompt again.
  final VoidCallback onDismiss;

  /// True while the accept write is in flight — disables both buttons and
  /// shows a spinner on the primary one.
  final bool busy;

  const PlanAdaptationCard({
    super.key,
    required this.explanation,
    required this.window,
    required this.onReviewAccept,
    required this.onDismiss,
    this.busy = false,
  });

  String get _heading => switch (window) {
    MissedWindow.extended => 'Let’s rebuild your plan',
    _ => 'Max adjusted your plan',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.chartAccent.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: c.chartAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.auto_fix_high_rounded,
                    size: 16,
                    color: c.chartAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _heading,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              explanation,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: busy ? null : onReviewAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: c.onAccent,
                        disabledBackgroundColor: c.accent.withValues(alpha: 0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: busy
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(c.onAccent),
                              ),
                            )
                          : const Text(
                              'Review & Accept',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 42,
                  child: TextButton(
                    onPressed: busy ? null : onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: c.textTertiary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Dismiss',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
