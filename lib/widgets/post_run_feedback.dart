// lib/widgets/post_run_feedback.dart
//
// Evaluates how well the user executed the assigned workout pace.
// Reuses PaceComparator from target_pace_indicator.dart — zero logic
// duplication. Accepts nullable targetRange so callers never need to
// guard before passing it in.

import 'package:flutter/material.dart';
import '../services/coach_message_builder.dart' as message;
import 'target_pace_indicator.dart' show PaceComparator, PaceStatus;

// ─────────────────────────────────────────────────────────────────────────────
// POST RUN FEEDBACK WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class PostRunFeedback extends StatelessWidget {
  /// Average pace of the completed run as "M:SS" string.
  final String avgPace;

  /// Target pace range from CoachMessage.workoutPlan.main.paceRange.
  /// Null = free run — renders a generic "good effort" message.
  final message.PaceRange? targetRange;

  const PostRunFeedback({
    super.key,
    required this.avgPace,
    required this.targetRange,
  });

  @override
  Widget build(BuildContext context) {
    // No target pace assigned → free run feedback
    if (targetRange == null) {
      return _buildFreeRunFeedback();
    }

    final avgPaceSeconds = _parseAvgPace(avgPace);

    // Unparseable pace → graceful fallback
    if (avgPaceSeconds <= 0) {
      return _buildFreeRunFeedback();
    }

    final status = PaceComparator.compare(
      currentPaceSecondsPerKm: avgPaceSeconds.toDouble(),
      targetRange: targetRange!,
    );

    // noData shouldn't happen here (we checked above), but handle safely
    if (status == PaceStatus.noData) {
      return _buildFreeRunFeedback();
    }

    return _buildPaceFeedback(avgPaceSeconds, status);
  }

  // ── Pace comparison card ─────────────────────────────────────────────────

  Widget _buildPaceFeedback(int avgPaceSeconds, PaceStatus status) {
    final _FeedbackConfig cfg = _configForStatus(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HOW YOU DID',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF999999),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cfg.bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cfg.borderColor),
          ),
          child: Column(
            children: [
              // ── Target row ─────────────────────────────────────────────
              _buildRow(
                label: 'Target pace',
                value: PaceComparator.formatRange(targetRange!),
                valueColor: const Color(0xFF666666),
              ),
              const SizedBox(height: 10),

              // ── Your pace row ──────────────────────────────────────────
              _buildRow(
                label: 'Your pace',
                value: '$avgPace/km',
                valueColor: const Color(0xFF0A0A0A),
                valueBold: true,
              ),

              const SizedBox(height: 14),
              Divider(color: cfg.borderColor, height: 1),
              const SizedBox(height: 14),

              // ── Status chip ────────────────────────────────────────────
              Row(
                children: [
                  Icon(cfg.icon, size: 16, color: cfg.accentColor),
                  const SizedBox(width: 8),
                  Text(
                    cfg.statusLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cfg.accentColor,
                    ),
                  ),
                ],
              ),

              // ── Coach note ─────────────────────────────────────────────
              if (cfg.note != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Text(
                    cfg.note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow({
    required String label,
    required String value,
    required Color valueColor,
    bool valueBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  // ── Free run / no target feedback ────────────────────────────────────────

  Widget _buildFreeRunFeedback() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HOW YOU DID',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF999999),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.directions_run,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Easy run complete',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0A0A0A),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Good effort — keep it comfortable.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Config per status ─────────────────────────────────────────────────────

  _FeedbackConfig _configForStatus(PaceStatus status) {
    switch (status) {
      case PaceStatus.onPace:
        return _FeedbackConfig(
          statusLabel: 'On target',
          icon: Icons.check_circle_outline_rounded,
          accentColor: const Color(0xFF2E7D32),
          bgColor: const Color(0xFFF1F8F1),
          borderColor: const Color(0xFFC8E6C9),
          note: null,
        );
      case PaceStatus.tooFast:
        return _FeedbackConfig(
          statusLabel: 'Went too fast',
          icon: Icons.arrow_upward_rounded,
          accentColor: const Color(0xFFF57C00),
          bgColor: const Color(0xFFFFF8F0),
          borderColor: const Color(0xFFFFE0B2),
          note: 'Consider backing off next time — '
              'saving energy helps later in the run.',
        );
      case PaceStatus.tooSlow:
        return _FeedbackConfig(
          statusLabel: 'Went too slow',
          icon: Icons.arrow_downward_rounded,
          accentColor: const Color(0xFF666666),
          bgColor: const Color(0xFFF5F5F5),
          borderColor: const Color(0xFFE0E0E0),
          note: 'Try to push the effort next time — '
              'aim for the lower end of the target.',
        );
      case PaceStatus.noData:
        // Should never reach here — handled before calling this
        return _FeedbackConfig(
          statusLabel: 'No data',
          icon: Icons.info_outline,
          accentColor: const Color(0xFF999999),
          bgColor: const Color(0xFFF5F5F5),
          borderColor: const Color(0xFFEEEEEE),
          note: null,
        );
    }
  }

  // ── Pace parser ───────────────────────────────────────────────────────────
  // Parses "M:SS" or "MM:SS" → seconds. Returns 0 on failure.

  int _parseAvgPace(String pace) {
    try {
      final clean = pace.replaceAll('/km', '').trim();
      final parts = clean.split(':');
      if (parts.length != 2) return 0;
      final minutes = int.parse(parts[0]);
      final seconds = int.parse(parts[1]);
      if (minutes < 0 || seconds < 0 || seconds >= 60) return 0;
      return minutes * 60 + seconds;
    } catch (_) {
      return 0;
    }
  }
}

// ── Internal config model ─────────────────────────────────────────────────────

class _FeedbackConfig {
  final String statusLabel;
  final IconData icon;
  final Color accentColor;
  final Color bgColor;
  final Color borderColor;
  final String? note;

  const _FeedbackConfig({
    required this.statusLabel,
    required this.icon,
    required this.accentColor,
    required this.bgColor,
    required this.borderColor,
    required this.note,
  });
}