/// PreviousPlansSection — "Previous" archive list on the coach screen, backed
/// by [PlanHistoryRepository]. Renders nothing (not even the header) until a
/// non-empty history is confirmed, per spec: an empty archive should not show
/// an empty section.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/plan_history_entry.dart';
import '../services/plan_history_repository.dart';
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';

class PreviousPlansSection extends StatefulWidget {
  final bool useMiles;

  const PreviousPlansSection({super.key, this.useMiles = false});

  @override
  State<PreviousPlansSection> createState() => _PreviousPlansSectionState();
}

class _PreviousPlansSectionState extends State<PreviousPlansSection> {
  /// Null while loading, so nothing renders until the fetch resolves.
  List<PlanHistoryEntry>? _entries;
  bool _expanded = false;

  static const _collapsedCount = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await PlanHistoryRepository.instance.fetchAll();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  void _openDetail(PlanHistoryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PlanHistoryDetailSheet(
        entry: entry,
        useMiles: widget.useMiles,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return const SizedBox.shrink();

    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final visible = _expanded ? entries : entries.take(_collapsedCount).toList();
    final canExpand = entries.length > _collapsedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Previous',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.border),
              ),
              child: Text(
                '${entries.length}',
                style: textTheme.labelSmall?.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            if (canExpand)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: c.textTertiary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (final entry in visible) ...[
          ArchivedPlanCard(
            entry: entry,
            useMiles: widget.useMiles,
            onTap: () => _openDetail(entry),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// A single past plan's summary card.
class ArchivedPlanCard extends StatelessWidget {
  final PlanHistoryEntry entry;
  final bool useMiles;
  final VoidCallback? onTap;

  const ArchivedPlanCard({
    super.key,
    required this.entry,
    this.useMiles = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    final totalDisplay = UnitUtils.displayDistance(
      entry.totalDistanceKm,
      useMiles,
    );
    final completedDisplay = UnitUtils.displayDistance(
      entry.completedDistanceKm,
      useMiles,
    );
    final unit = useMiles ? 'miles' : 'kilometers';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.planName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: c.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.military_tech_outlined,
                    size: 14,
                    color: c.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entry.durationWeeks} weeks · ${entry.planType}',
                    style: textTheme.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${completedDisplay.toStringAsFixed(1)} / ${totalDisplay.toStringAsFixed(1)} $unit',
                style: textTheme.bodySmall?.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: entry.completionRatio,
                  minHeight: 4,
                  backgroundColor: c.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(c.chartAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanHistoryDetailSheet extends StatelessWidget {
  final PlanHistoryEntry entry;
  final bool useMiles;

  const _PlanHistoryDetailSheet({required this.entry, required this.useMiles});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final totalDisplay = UnitUtils.displayDistance(
      entry.totalDistanceKm,
      useMiles,
    );
    final completedDisplay = UnitUtils.displayDistance(
      entry.completedDistanceKm,
      useMiles,
    );
    final unit = UnitUtils.unitLabel(useMiles);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.planName,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${entry.durationWeeks} weeks · ${entry.planType}',
              style: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: 18),
            _detailRow(
              context,
              'Distance',
              '${completedDisplay.toStringAsFixed(1)} / ${totalDisplay.toStringAsFixed(1)} $unit',
            ),
            _detailRow(
              context,
              'Started',
              DateFormat('MMM d, yyyy').format(entry.startedAt),
            ),
            _detailRow(
              context,
              'Ended',
              DateFormat('MMM d, yyyy').format(entry.endedAt),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: entry.completionRatio,
                minHeight: 5,
                backgroundColor: c.divider,
                valueColor: AlwaysStoppedAnimation<Color>(c.chartAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
