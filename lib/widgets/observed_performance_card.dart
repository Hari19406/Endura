import 'package:flutter/material.dart';

import '../screens/race_history_screen.dart';
import '../services/best_efforts_service.dart';
import '../theme/app_colors.dart';
import '../utils/observed_performance.dart';

/// You-tab "Current Performance" card: what the athlete's recent measured Best
/// Efforts suggest they could run at 5K / 10K / half / marathon, next to their
/// actual best. It is an observation only — separate from the training plan and
/// its paces — and a race-history entry point.
class ObservedPerformanceCard extends StatefulWidget {
  /// Loads the Best Efforts (3K and up, last 12 months) the predictions use.
  final Future<List<ObservedEffort>> Function(DateTime since) loadEfforts;

  /// The athlete's actual all-time bests (seconds), shown beside predictions.
  final Map<DistanceCategory, int> bests;

  /// Wired to the race-history screen by default; overridable for tests.
  final VoidCallback? onRaceHistory;
  final DateTime? now;

  const ObservedPerformanceCard({
    super.key,
    required this.loadEfforts,
    this.bests = const {},
    this.onRaceHistory,
    this.now,
  });

  @override
  State<ObservedPerformanceCard> createState() =>
      _ObservedPerformanceCardState();
}

class _ObservedPerformanceCardState extends State<ObservedPerformanceCard> {
  List<RacePrediction>? _predictions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = widget.now ?? DateTime.now();
    List<RacePrediction> result;
    try {
      final efforts = await widget.loadEfforts(
        now.subtract(const Duration(days: ObservedPerformance.windowDays)),
      );
      result = ObservedPerformance.predict(efforts, now: now);
    } catch (_) {
      result = const [];
    }
    if (mounted) setState(() => _predictions = result);
  }

  @override
  Widget build(BuildContext context) {
    final preds = _predictions;
    if (preds == null) return const SizedBox.shrink();
    final c = Theme.of(context).extension<AppColors>()!;

    return Container(
      key: const Key('observed-performance-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CURRENT PERFORMANCE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Observed from your recent Best Efforts — separate from your '
            'training plan paces.',
            key: const Key('observed-performance-caption'),
            style: TextStyle(fontSize: 12, color: c.textTertiary),
          ),
          const SizedBox(height: 12),
          if (preds.isEmpty)
            Text(
              'Not enough recent data yet. Run a 3K or longer Best Effort '
              'to see predictions.',
              key: const Key('observed-performance-empty'),
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            )
          else
            for (final p in preds) _row(c, p),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('observed-performance-race-history'),
            onTap:
                widget.onRaceHistory ??
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RaceHistoryScreen()),
                ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Race history',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(AppColors c, RacePrediction p) {
    final best = widget.bests[p.category];
    return Padding(
      key: Key('observed-row-${p.category.name}'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              p.category.label,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              BestEffortsService.formatElapsed(p.predictedSeconds),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (best != null)
            Text(
              'Best ${BestEffortsService.formatElapsed(best)}',
              style: TextStyle(
                fontSize: 11,
                color: c.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}
