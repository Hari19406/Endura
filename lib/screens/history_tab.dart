import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme/app_colors.dart';
import '../utils/database_service.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';
import '../widgets/route_trace_painter.dart';

/// The You screen's History tab.
///
/// Renders straight off [RunRecord] (a superset of RunHistory) so grouping and
/// filtering can reorder freely — the old implementation paired
/// `_runRecords[i]` with `_runHistory[i]` positionally, which only held while
/// the list was unsorted and unfiltered.
class HistoryTab extends StatefulWidget {
  final List<RunRecord> records;
  final Future<void> Function() onRefresh;
  final void Function(RunRecord) onOpenRun;

  const HistoryTab({
    super.key,
    required this.records,
    required this.onRefresh,
    required this.onOpenRun,
  });

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

/// A filter chip. A null [type] means "All".
class _TypeFilter {
  final String? type;
  final String label;
  const _TypeFilter(this.type, this.label);
}

const List<_TypeFilter> _filters = [
  _TypeFilter(null, 'All'),
  _TypeFilter('easy', 'Easy'),
  _TypeFilter('tempo', 'Tempo'),
  _TypeFilter('interval', 'Intervals'),
  _TypeFilter('long', 'Long'),
  _TypeFilter('free', 'Free Run'),
];

class _MonthSection {
  final DateTime month;
  final List<RunRecord> runs;
  const _MonthSection(this.month, this.runs);

  double get totalKm => runs.fold(0.0, (s, r) => s + r.distanceKm);
}

class _HistoryTabState extends State<HistoryTab> {
  String? _activeType;
  bool _useMiles = UnitUtils.useMilesNotifier.value;

  @override
  void initState() {
    super.initState();
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    super.dispose();
  }

  void _onUnitPrefChanged() {
    if (mounted) setState(() => _useMiles = UnitUtils.useMilesNotifier.value);
  }

  // ── Derived data ─────────────────────────────────────────────────────────

  List<RunRecord> get _filtered {
    if (_activeType == null) return widget.records;
    return widget.records
        .where((r) => r.workoutType.toLowerCase() == _activeType)
        .toList();
  }

  /// Runs grouped into months, newest month first. [HistoryTab.records]
  /// already arrives ordered `date DESC` from `getAllRuns()`.
  List<_MonthSection> _sections(List<RunRecord> runs) {
    final List<_MonthSection> out = [];
    for (final r in runs) {
      final month = DateTime(r.date.year, r.date.month);
      if (out.isNotEmpty && out.last.month == month) {
        out.last.runs.add(r);
      } else {
        out.add(_MonthSection(month, [r]));
      }
    }
    return out;
  }

  /// Total distance (km) per month for the last 12 months, oldest first.
  List<double> _monthlyTotals(List<RunRecord> runs) {
    final now = DateTime.now();
    final buckets = List<double>.filled(12, 0);
    for (final r in runs) {
      final monthsAgo =
          (now.year - r.date.year) * 12 + (now.month - r.date.month);
      if (monthsAgo >= 0 && monthsAgo < 12) {
        buckets[11 - monthsAgo] += r.distanceKm;
      }
    }
    return buckets;
  }

  String _activeLabel() {
    if (_activeType == null) return 'LIFETIME';
    return '${WorkoutTypeStyle.label(_activeType!).toUpperCase()}S';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final runs = _filtered;

    if (widget.records.isEmpty) {
      return RefreshIndicator(
        color: c.accent,
        onRefresh: widget.onRefresh,
        child: _scrollableCenter(_buildEmptyState()),
      );
    }

    final sections = _sections(runs);
    final bottomInset = 24 + MediaQuery.of(context).viewPadding.bottom;

    return RefreshIndicator(
      color: c.accent,
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            sliver: SliverToBoxAdapter(child: _buildSummaryCard(runs)),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedHeaderDelegate(
              height: 60,
              color: c.background,
              child: _buildFilterRow(),
            ),
          ),
          if (runs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildFilteredEmptyState(),
            )
          else
            for (final section in sections) ...[
              SliverToBoxAdapter(child: _buildMonthHeader(section)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                sliver: SliverList.separated(
                  itemCount: section.runs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _buildRunCard(section.runs[i]),
                ),
              ),
            ],
          SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
        ],
      ),
    );
  }

  Widget _scrollableCenter(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );

  // ── Summary card ─────────────────────────────────────────────────────────

  Widget _buildSummaryCard(List<RunRecord> runs) {
    final c = context.colors;
    final totalKm = runs.fold(0.0, (s, r) => s + r.distanceKm);
    final totalSeconds = runs.fold(0, (s, r) => s + r.durationSeconds);
    final totalElev = runs.fold(0.0, (s, r) => s + r.elevationGain);
    final unit = UnitUtils.unitLabel(_useMiles);
    final distance = UnitUtils.displayDistance(totalKm, _useMiles);

    final meta = <String>[
      '${runs.length} ${runs.length == 1 ? 'run' : 'runs'}',
      if (totalSeconds > 0) _formatDuration(totalSeconds),
      if (totalElev > 0) '${totalElev.round()} m elev',
    ].join('  ·  ');

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _activeLabel(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: c.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  distance.toStringAsFixed(1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    letterSpacing: -1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            style: TextStyle(
              fontSize: 12,
              color: c.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (runs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: c.divider, height: 1, thickness: 1),
            const SizedBox(height: 16),
            _buildMonthlyTrendChart(_monthlyTotals(runs)),
          ],
        ],
      ),
    );
  }

  /// Same chart language as the Summary tab's 8-week trend — chartAccent line
  /// with a gradient fill, no dots, no border — bucketed by month instead.
  Widget _buildMonthlyTrendChart(List<double> monthlyKm) {
    final c = context.colors;
    final now = DateTime.now();
    final totals = monthlyKm
        .map((km) => UnitUtils.displayDistance(km, _useMiles))
        .toList();
    final maxDistance = totals.fold(0.0, (m, v) => v > m ? v : m);
    final maxY = maxDistance <= 0 ? 10.0 : maxDistance * 1.2;
    final unit = UnitUtils.unitLabel(_useMiles);

    DateTime monthFor(int index) =>
        DateTime(now.year, now.month - (totals.length - 1 - index));

    final spots = List.generate(
      totals.length,
      (i) => FlSpot(i.toDouble(), totals[i]),
    );

    return Semantics(
      // fl_chart paints to a canvas and exposes nothing to a screen reader,
      // so the trend is also stated in text.
      label:
          'Distance trend, last 12 months. '
          'Best month ${maxDistance.toStringAsFixed(1)} $unit.',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 120,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: c.divider, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: maxY,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '${value.toStringAsFixed(0)} $unit',
                        style: TextStyle(fontSize: 10, color: c.textTertiary),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 18,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= totals.length) {
                        return const SizedBox.shrink();
                      }
                      // Every 3rd month, so 12 labels don't collide on a
                      // 375px screen.
                      if (index % 3 != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _monthAbbr(monthFor(index).month),
                          style: TextStyle(fontSize: 10, color: c.textTertiary),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: c.chartAccent,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        c.chartAccent.withOpacity(0.25),
                        c.chartAccent.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }

  // ── Filter chips ─────────────────────────────────────────────────────────

  /// Horizontally scrollable rather than wrapped: a pinned sliver can't grow,
  /// and scrolling keeps every chip reachable (nothing is clipped away).
  Widget _buildFilterRow() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
      itemCount: _filters.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) => _buildChip(_filters[i]),
    );
  }

  Widget _buildChip(_TypeFilter filter) {
    final c = context.colors;
    final selected = _activeType == filter.type;
    final tint = filter.type == null
        ? c.chartAccent
        : WorkoutTypeStyle.color(context, filter.type!);

    return Semantics(
      button: true,
      selected: selected,
      label: filter.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _activeType = filter.type);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? tint.withOpacity(0.16) : c.surfaceAlt,
              border: Border.all(
                color: selected ? tint.withOpacity(0.55) : c.border,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              filter.label,
              style: TextStyle(
                fontSize: 13,
                // Weight shifts too — selection is never colour-only.
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? tint : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Month header ─────────────────────────────────────────────────────────

  Widget _buildMonthHeader(_MonthSection section) {
    final c = context.colors;
    final count = section.runs.length;
    final dist = UnitUtils.displayDistance(section.totalKm, _useMiles);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_monthName(section.month.month)} ${section.month.year}'
                  .toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Flexible(
            child: Text(
              '$count ${count == 1 ? 'run' : 'runs'}  ·  '
              '${dist.toStringAsFixed(1)} ${UnitUtils.unitLabel(_useMiles)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                color: c.textTertiary,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Run card ─────────────────────────────────────────────────────────────

  Widget _buildRunCard(RunRecord record) {
    final c = context.colors;
    final typeLabel = WorkoutTypeStyle.label(record.workoutType);
    final typeColor = WorkoutTypeStyle.color(context, record.workoutType);

    return Semantics(
      button: true,
      label: '$typeLabel run',
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onOpenRun(record),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRouteThumb(record, typeColor),
                const SizedBox(width: 14),
                Expanded(child: _buildCardBody(record, typeLabel, typeColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 64x64 GPS trace in the workout-type colour. Runs with no usable route
  /// (treadmill, or recorded before the polyline existed) get the type icon
  /// instead — never an empty box.
  Widget _buildRouteThumb(RunRecord record, Color typeColor) {
    final c = context.colors;
    final points = record.toRunHistory().gpsPoints;
    final hasRoute = points.length > 1;

    return ExcludeSemantics(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          // surfaceAlt is near-white in the light palette, so without a
          // border the tile disappears into the card and the trace floats.
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: hasRoute
            ? CustomPaint(
                size: Size.infinite,
                painter: RouteTracePainter(
                  points: points,
                  color: typeColor,
                  strokeWidth: 1.8,
                  padding: 6,
                ),
              )
            : Center(
                child: Icon(
                  Icons.directions_run,
                  size: 22,
                  color: typeColor.withOpacity(0.45),
                ),
              ),
      ),
    );
  }

  Widget _buildCardBody(RunRecord record, String typeLabel, Color typeColor) {
    final c = context.colors;
    final hasMeta =
        record.durationSeconds > 0 ||
        record.rpe != null ||
        record.elevationGain > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  typeLabel.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: typeColor,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _formatDate(record.date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  color: c.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '${UnitUtils.displayDistance(record.distanceKm, _useMiles).toStringAsFixed(1)} '
                '${UnitUtils.unitLabel(_useMiles)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                  letterSpacing: -0.3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  UnitUtils.formatPaceString(record.averagePace, _useMiles),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                    letterSpacing: -0.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'PER ${_useMiles ? 'MI' : 'KM'}',
                  style: TextStyle(
                    fontSize: 10,
                    color: c.textTertiary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (hasMeta) ...[
          const SizedBox(height: 10),
          Divider(color: c.divider, height: 1, thickness: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              if (record.durationSeconds > 0)
                _metaItem(
                  Icons.schedule,
                  _formatDuration(record.durationSeconds),
                ),
              if (record.rpe != null)
                _metaItem(Icons.speed, 'RPE ${record.rpe}/10'),
              if (record.elevationGain > 0)
                _metaItem(Icons.terrain, '${record.elevationGain.round()} m'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _metaItem(IconData icon, String text) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decorative: the adjacent text already carries the meaning.
        ExcludeSemantics(child: Icon(icon, size: 13, color: c.textTertiary)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: c.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ── Empty states ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: c.divider,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(Icons.directions_run, size: 32, color: c.textFaint),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No runs yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your first run will show here',
            style: TextStyle(fontSize: 13, color: c.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState() {
    final c = context.colors;
    final label = _activeType == null
        ? 'runs'
        : '${WorkoutTypeStyle.label(_activeType!).toLowerCase()}s';

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 48, 40, 40),
      child: Column(
        children: [
          Icon(Icons.filter_list_off, size: 28, color: c.textFaint),
          const SizedBox(height: 16),
          Text(
            'No $label yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _activeType = null);
            },
            child: Text(
              'Clear filter',
              style: TextStyle(color: c.chartAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── Formatting helpers ───────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    return '${minutes}m';
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _monthName(int month) => _months[month - 1];

  String _monthAbbr(int month) => _months[month - 1].substring(0, 3);
}

/// Fixed-height pinned sliver header painted on an opaque background so list
/// content never bleeds through while it is stuck to the top.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Color color;
  final Widget child;

  const _PinnedHeaderDelegate({
    required this.height,
    required this.color,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(color: color, height: height, child: child);

  @override
  bool shouldRebuild(_PinnedHeaderDelegate old) =>
      old.height != height || old.color != color || old.child != child;
}
