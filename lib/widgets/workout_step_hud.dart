/// WorkoutStepHud — the in-run "which interval am I on" card, shown on the
/// active run screen when a structured scheduled workout is being tracked.
///
/// Shows the current block ("Step 2 of 5 · Interval — 1.0 km"), its target pace
/// window against the runner's rolling pace with a colour verdict, and a manual
/// "Next Step" button (auto-advance by GPS distance is intentionally not wired).
library;

import 'package:flutter/material.dart';

import '../engines/config/workout_template_library.dart'
    show BlockType, ResolvedBlock;
import '../theme/app_colors.dart';

/// Where the rolling pace sits relative to the step's target window.
enum StepPaceVerdict {
  /// No target (RPE-only block) or no pace reading yet.
  none,

  /// Inside the target window.
  inside,

  /// Faster than the window — "surging".
  surging,

  /// Slower than the window, but within ~15 s/km — "easing".
  easing,

  /// More than ~15 s/km off the window in either direction.
  off,
}

/// Classify [rollingPaceSecPerKm] against [block]'s pace window.
/// Lower seconds/km = faster.
StepPaceVerdict stepPaceVerdict(ResolvedBlock block, int? rollingPaceSecPerKm) {
  if (block.isRpeOnly ||
      rollingPaceSecPerKm == null ||
      rollingPaceSecPerKm <= 0) {
    return StepPaceVerdict.none;
  }
  final lo = block.paceMinSecondsPerKm; // fastest edge (smallest number)
  final hi = block.paceMaxSecondsPerKm; // slowest edge (largest number)
  if (rollingPaceSecPerKm >= lo && rollingPaceSecPerKm <= hi) {
    return StepPaceVerdict.inside;
  }
  const slack = 15;
  if (rollingPaceSecPerKm < lo) {
    return (lo - rollingPaceSecPerKm) <= slack
        ? StepPaceVerdict.surging
        : StepPaceVerdict.off;
  }
  return (rollingPaceSecPerKm - hi) <= slack
      ? StepPaceVerdict.easing
      : StepPaceVerdict.off;
}

class WorkoutStepHud extends StatelessWidget {
  /// 0-based index of the active block.
  final int stepIndex;
  final List<ResolvedBlock> blocks;

  /// Runner's current rolling pace, seconds per km (0 / null = no reading).
  final int? rollingPaceSecPerKm;

  /// Advance to the next block. Null / disabled on the last step.
  final VoidCallback? onNextStep;

  const WorkoutStepHud({
    super.key,
    required this.stepIndex,
    required this.blocks,
    required this.rollingPaceSecPerKm,
    this.onNextStep,
  });

  ResolvedBlock get _block => blocks[stepIndex];
  bool get _isLast => stepIndex >= blocks.length - 1;

  String get _stepTitle {
    final n = stepIndex + 1;
    final total = blocks.length;
    final label = _block.label ?? _blockTypeLabel(_block.type);
    return 'Step $n of $total · $label — ${_block.formattedDistance}';
  }

  static String _blockTypeLabel(BlockType t) => switch (t) {
    BlockType.warmup => 'Warm-up',
    BlockType.cooldown => 'Cool-down',
    BlockType.recovery => 'Recovery',
    BlockType.main => 'Interval',
  };

  ({Color fg, String text}) _paceVerdict(AppColors c) {
    switch (stepPaceVerdict(_block, rollingPaceSecPerKm)) {
      case StepPaceVerdict.none:
        return (fg: c.textTertiary, text: '—');
      case StepPaceVerdict.inside:
        return (fg: c.success, text: 'On target');
      case StepPaceVerdict.surging:
        return (fg: c.chartAccent, text: 'Surging');
      case StepPaceVerdict.easing:
        return (fg: c.chartAccent, text: 'Easing off');
      case StepPaceVerdict.off:
        return (fg: c.danger, text: 'Off target');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final verdict = _paceVerdict(c);
    final rolling = (rollingPaceSecPerKm ?? 0) > 0
        ? _fmtPace(rollingPaceSecPerKm!)
        : '—:––';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _stepTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target ${_block.formattedPace}',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          rolling,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: verdict.fg,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/km · ${verdict.text}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: verdict.fg,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_isLast)
                TextButton(
                  onPressed: onNextStep,
                  style: TextButton.styleFrom(
                    foregroundColor: c.onAccent,
                    backgroundColor: c.accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Text(
                    'Next Step',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtPace(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}
