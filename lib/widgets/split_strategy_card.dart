import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/split_strategy.dart';
import '../utils/unit_utils.dart';

/// Compact "how did you pace this run" card for Activity Detail: negative /
/// even / positive split, each half's average pace, the difference, and a fade
/// flag when the second half was meaningfully slower.
class SplitStrategyCard extends StatelessWidget {
  final SplitStrategyAnalysis analysis;
  final bool useMiles;

  const SplitStrategyCard({
    super.key,
    required this.analysis,
    this.useMiles = false,
  });

  String _pace(double secPerKm) {
    final shown = UnitUtils.displayPaceSeconds(secPerKm, useMiles).round();
    return '${UnitUtils.formatSeconds(shown)}${UnitUtils.perUnitLabel(useMiles)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final a = analysis;
    final (title, color) = switch (a.strategy) {
      SplitStrategy.negative => ('Negative Split', c.success),
      SplitStrategy.even => ('Even Split', c.textPrimary),
      SplitStrategy.positive => ('Positive Split', c.textSecondary),
    };
    final diff = UnitUtils.displayPaceSeconds(
      a.differenceSecPerKm.abs(),
      useMiles,
    ).round();
    final unit = useMiles ? 'sec/mi' : 'sec/km';
    final diffText = a.strategy == SplitStrategy.even
        ? 'Within $diff $unit'
        : '$diff $unit ${a.differenceSecPerKm < 0 ? 'faster' : 'slower'}';

    return Container(
      key: const Key('split-strategy-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPLIT STRATEGY',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                title,
                key: const Key('split-strategy-title'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (a.fade) ...[
                const SizedBox(width: 10),
                Container(
                  key: const Key('split-strategy-fade'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    'Fade',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _row(c, 'First half', _pace(a.firstHalfPace)),
          _row(c, 'Second half', _pace(a.secondHalfPace)),
          const SizedBox(height: 4),
          Text(
            diffText,
            key: const Key('split-strategy-diff'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(AppColors c, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
