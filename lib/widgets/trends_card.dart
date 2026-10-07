// lib/widgets/trends_card.dart
//
// You → Stats "TRENDS" card: a range selector (8W / 6M / 1Y / All), a metric
// row, a headline with its change vs the previous equivalent period, and one
// compact chart. All maths lives in `trend_analytics.dart`; this widget only
// lays out what it returns. Missing HR is shown as missing (gaps and an
// "N of M runs" coverage caption), never filled in.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/best_efforts_service.dart';
import '../theme/app_colors.dart';
import '../utils/trend_analytics.dart';
import '../utils/unit_utils.dart';

typedef BestEffortSeriesLoader =
    Future<List<BestEffortPoint>> Function(DistanceCategory category);

class TrendsCard extends StatefulWidget {
  final List<TrendRun> runs;
  final BestEffortSeriesLoader loadBestEfforts;
  final bool useMiles;

  /// Test seam: "today" for the window maths.
  final DateTime? now;
  final TrendRange initialRange;
  final TrendMetric initialMetric;
  final DistanceCategory initialCategory;

  const TrendsCard({
    super.key,
    required this.runs,
    required this.loadBestEfforts,
    required this.useMiles,
    this.now,
    this.initialRange = TrendRange.weeks8,
    this.initialMetric = TrendMetric.distance,
    this.initialCategory = DistanceCategory.k5,
  });

  @override
  State<TrendsCard> createState() => _TrendsCardState();
}

class _TrendsCardState extends State<TrendsCard> {
  late TrendRange _range = widget.initialRange;
  late TrendMetric _metric = widget.initialMetric;
  late DistanceCategory _category = widget.initialCategory;

  final Map<DistanceCategory, List<BestEffortPoint>> _efforts = {};
  final Set<DistanceCategory> _loading = {};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (_metric == TrendMetric.bestEffort) _ensureEfforts(_category);
  }

  @override
  void didUpdateWidget(TrendsCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.runs, widget.runs)) {
      // Runs reloaded (a run was added or deleted): efforts may have changed.
      _generation++;
      _efforts.clear();
      _loading.clear();
      if (_metric == TrendMetric.bestEffort) _ensureEfforts(_category);
    }
  }

  Future<void> _ensureEfforts(DistanceCategory category) async {
    if (_efforts.containsKey(category) || _loading.contains(category)) return;
    final generation = _generation;
    _loading.add(category);
    List<BestEffortPoint> points;
    try {
      points = TrendAnalytics.withProgressivePrs(
        await widget.loadBestEfforts(category),
      );
    } catch (_) {
      points = const [];
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading.remove(category);
      _efforts[category] = points;
    });
  }

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(20),
      child: widget.runs.isEmpty ? _empty(c) : _content(c),
    );
  }

  Widget _title(AppColors c) => Text(
    'TRENDS',
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: c.textTertiary,
      letterSpacing: 1.2,
    ),
  );

  Widget _empty(AppColors c) => Column(
    key: const Key('trends-empty'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c),
      const SizedBox(height: 12),
      Text(
        'Your trends will appear here once you have logged a run.',
        style: TextStyle(fontSize: 13, color: c.textTertiary, height: 1.4),
      ),
    ],
  );

  Widget _content(AppColors c) {
    final isEffort = _metric == TrendMetric.bestEffort;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _title(c),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in TrendRange.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _Pill(
                          key: Key('trends-range-${r.label}'),
                          label: r.label,
                          selected: r == _range,
                          onTap: () => setState(() => _range = r),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _chipRow([
          for (final m in TrendMetric.values)
            _Pill(
              key: Key('trends-metric-${m.name}'),
              label: m.label,
              selected: m == _metric,
              onTap: () {
                setState(() => _metric = m);
                if (m == TrendMetric.bestEffort) _ensureEfforts(_category);
              },
            ),
        ]),
        if (isEffort) ...[
          const SizedBox(height: 8),
          _chipRow([
            for (final d in DistanceCategory.values)
              _Pill(
                key: Key('trends-be-category-${d.name}'),
                label: d.label,
                selected: d == _category,
                onTap: () {
                  setState(() => _category = d);
                  _ensureEfforts(d);
                },
              ),
          ]),
        ],
        const SizedBox(height: 16),
        if (isEffort) ..._effortBody(c) else ..._metricBody(c),
      ],
    );
  }

  Widget _chipRow(List<Widget> chips) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          chips[i],
        ],
      ],
    ),
  );

  // ── Totals / pace / HR ────────────────────────────────────────────────────

  List<Widget> _metricBody(AppColors c) {
    final result = TrendAnalytics.build(widget.runs, _range, now: _now);
    final summary = result.summary;
    final value = summary.valueFor(_metric);
    final hasData = _hasData(summary);

    return [
      _headline(
        c,
        value == null || !hasData ? '—' : _format(_metric, value),
        _deltaText(result),
      ),
      if (_metric == TrendMetric.heartRate) ...[
        const SizedBox(height: 4),
        Text(
          '${summary.hrRuns} of ${summary.runCount} runs with heart rate',
          key: const Key('trends-hr-coverage'),
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
      ],
      if (_scaleCaption(result) case final caption?) ...[
        const SizedBox(height: 2),
        Text(
          caption,
          key: const Key('trends-scale'),
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
      ],
      const SizedBox(height: 12),
      if (!hasData)
        _noData(c, _noDataText(_metric))
      else
        SizedBox(
          height: 140,
          child: switch (_metric) {
            TrendMetric.pace || TrendMetric.heartRate => _lineChart(c, result),
            _ => _barChart(c, result),
          },
        ),
    ];
  }

  bool _hasData(TrendSummary s) => switch (_metric) {
    TrendMetric.pace => s.paceSecondsPerKm != null,
    TrendMetric.heartRate => s.avgHr != null,
    _ => s.runCount > 0,
  };

  String _noDataText(TrendMetric m) => switch (m) {
    TrendMetric.pace => 'No pace data in this period.',
    TrendMetric.heartRate => 'No heart-rate data in this period.',
    _ => 'No runs in this period.',
  };

  Widget _noData(AppColors c, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        text,
        key: const Key('trends-no-data'),
        style: TextStyle(fontSize: 13, color: c.textTertiary),
      ),
    ),
  );

  Widget _headline(AppColors c, String value, String? delta) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        key: const Key('trends-headline'),
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
          letterSpacing: -0.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      if (delta != null) ...[
        const SizedBox(height: 2),
        Text(
          delta,
          key: const Key('trends-delta'),
          style: TextStyle(fontSize: 12, color: c.textSecondary),
        ),
      ],
    ],
  );

  /// "▲ 12% vs previous 8 weeks" — null when there is nothing honest to
  /// compare (All, no previous data, or the previous value was zero).
  String? _deltaText(TrendResult result) {
    final previousLabel = result.range.previousLabel;
    final delta = result.deltaFor(_metric);
    if (previousLabel == null || delta == null) return null;

    switch (_metric) {
      case TrendMetric.pace:
        final cur = UnitUtils.displayPaceSeconds(
          delta.current,
          widget.useMiles,
        );
        final prev = UnitUtils.displayPaceSeconds(
          delta.previous,
          widget.useMiles,
        );
        final diff = (cur - prev).round();
        if (diff == 0) return 'Same pace as $previousLabel';
        final unit = UnitUtils.perUnitLabel(widget.useMiles);
        return '${UnitUtils.formatSeconds(diff.abs())} $unit '
            '${diff < 0 ? 'faster' : 'slower'} than $previousLabel';
      case TrendMetric.heartRate:
        final diff = (delta.current - delta.previous).round();
        if (diff == 0) return 'Same as $previousLabel';
        return '${diff > 0 ? '+' : '−'}${diff.abs()} bpm vs $previousLabel';
      default:
        final pct = delta.percent;
        if (pct == null) return null;
        final rounded = pct.round();
        if (rounded == 0) return 'No change vs $previousLabel';
        return '${rounded > 0 ? '▲' : '▼'} ${rounded.abs()}% vs $previousLabel';
    }
  }

  String? _scaleCaption(TrendResult result) {
    final values = <double>[
      for (final b in result.buckets)
        if (b.summary.valueFor(_metric) case final v?)
          if (b.summary.runCount > 0) v,
    ];
    if (values.isEmpty) return null;
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    switch (_metric) {
      case TrendMetric.pace:
        return 'Fastest ${_format(_metric, lo)} · Slowest ${_format(_metric, hi)}';
      case TrendMetric.heartRate:
        return 'Low ${_format(_metric, lo)} · High ${_format(_metric, hi)}';
      default:
        if (hi <= 0) return null;
        final unit = result.window.granularity == TrendGranularity.week
            ? 'week'
            : 'month';
        return 'Peak $unit ${_format(_metric, hi)}';
    }
  }

  String _format(TrendMetric metric, double v) {
    switch (metric) {
      case TrendMetric.distance:
        return '${UnitUtils.displayDistance(v, widget.useMiles).toStringAsFixed(1)} '
            '${UnitUtils.unitLabel(widget.useMiles)}';
      case TrendMetric.time:
        final total = v.round();
        final h = total ~/ 3600;
        final m = (total % 3600) ~/ 60;
        if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
        return '${m}m';
      case TrendMetric.runs:
        final n = v.round();
        return n == 1 ? '1 run' : '$n runs';
      case TrendMetric.elevation:
        return '${v.round()} m';
      case TrendMetric.pace:
        final secs = UnitUtils.displayPaceSeconds(v, widget.useMiles).round();
        return '${UnitUtils.formatSeconds(secs)} '
            '${UnitUtils.perUnitLabel(widget.useMiles)}';
      case TrendMetric.heartRate:
        return '${v.round()} bpm';
      case TrendMetric.bestEffort:
        return BestEffortsService.formatElapsed(v.round());
    }
  }

  // ── Charts ────────────────────────────────────────────────────────────────

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _bucketLabel(TrendBucket b, TrendGranularity g) =>
      g == TrendGranularity.week
      ? '${b.start.day} ${_months[b.start.month - 1]}'
      : '${_months[b.start.month - 1]} ${b.start.year}';

  /// Month name under the first bucket of each month (weekly) or every few
  /// months (monthly), with the year on January and on the first bucket.
  Widget _bottomTitle(TrendResult result, int index, AppColors c) {
    final buckets = result.buckets;
    if (index < 0 || index >= buckets.length) return const SizedBox.shrink();
    final g = result.window.granularity;
    final start = buckets[index].start;
    final month = start.month;

    if (g == TrendGranularity.week) {
      if (index > 0 && buckets[index - 1].start.month == month) {
        return const SizedBox.shrink();
      }
    } else {
      final step = (buckets.length / 6).ceil();
      if (index % step != 0) return const SizedBox.shrink();
    }
    final showYear = index == 0 || month == 1;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        showYear
            ? '${_months[month - 1]}\n’${(start.year % 100).toString().padLeft(2, '0')}'
            : _months[month - 1],
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: c.textTertiary, height: 1.2),
      ),
    );
  }

  FlTitlesData _titles(
    AppColors c,
    Widget Function(double value) bottom, {
    double interval = 1,
  }) => FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 30,
        interval: interval,
        getTitlesWidget: (value, meta) => bottom(value),
      ),
    ),
  );

  TextStyle _tooltipStyle(AppColors c) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: c.textPrimary,
  );

  Widget _barChart(AppColors c, TrendResult result) {
    final g = result.window.granularity;
    final values = [
      for (final b in result.buckets) b.summary.valueFor(_metric) ?? 0.0,
    ];
    // Distance charts in the user's unit so the axis matches the headline.
    double shown(double v) => _metric == TrendMetric.distance
        ? UnitUtils.displayDistance(v, widget.useMiles)
        : v;
    final maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);
    final maxY = maxValue <= 0 ? 1.0 : shown(maxValue) * 1.2;
    final many = values.length > 30;

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceBetween,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: c.divider)),
        ),
        titlesData: _titles(c, (v) => _bottomTitle(result, v.round(), c)),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: c.background,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final bucket = result.buckets[groupIndex];
              return BarTooltipItem(
                '${_bucketLabel(bucket, g)}\n'
                '${_format(_metric, values[groupIndex])}',
                _tooltipStyle(c),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: shown(values[i]),
                  width: many ? 3 : (values.length > 12 ? 6 : 12),
                  color: c.chartAccent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ],
            ),
        ],
      ),
      swapAnimationDuration: Duration.zero,
    );
  }

  /// Pace and HR as a line with real gaps: a bucket with no data is a break,
  /// never a zero or an interpolated point. Pace is plotted negated so a
  /// faster (smaller) pace sits higher.
  Widget _lineChart(AppColors c, TrendResult result) {
    final isPace = _metric == TrendMetric.pace;
    final color = isPace ? c.chartAccent : c.hrAccent;
    final g = result.window.granularity;

    double? raw(TrendBucket b) {
      final v = b.summary.valueFor(_metric);
      if (v == null || b.summary.runCount == 0) return null;
      return isPace ? -UnitUtils.displayPaceSeconds(v, widget.useMiles) : v;
    }

    final ys = [for (final b in result.buckets) raw(b)];
    final present = ys.whereType<double>().toList();
    final lo = present.reduce((a, b) => a < b ? a : b);
    final hi = present.reduce((a, b) => a > b ? a : b);
    final pad = _atLeast((hi - lo) * 0.2, isPace ? 5.0 : 2.0);

    final spots = [
      for (var i = 0; i < ys.length; i++)
        ys[i] == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), ys[i]!),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: _atLeast((ys.length - 1).toDouble(), 1),
        minY: lo - pad,
        maxY: hi + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: c.divider)),
        ),
        titlesData: _titles(c, (v) => _bottomTitle(result, v.round(), c)),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: c.background,
            getTooltipItems: (touched) => [
              for (final s in touched)
                LineTooltipItem(
                  '${_bucketLabel(result.buckets[s.x.round()], g)}\n'
                  '${_format(_metric, isPace ? _backToSecondsPerKm(-s.y) : s.y)}',
                  _tooltipStyle(c),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 2.5, color: color, strokeWidth: 0),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  static double _atLeast(double v, double min) => v < min ? min : v;

  double _backToSecondsPerKm(double displayed) =>
      widget.useMiles ? displayed / 1.609344 : displayed;

  // ── Best Effort progression ───────────────────────────────────────────────

  List<Widget> _effortBody(AppColors c) {
    final label = _category.label;
    if (_loading.contains(_category) && !_efforts.containsKey(_category)) {
      return [
        const SizedBox(
          height: 80,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }

    final all = _efforts[_category] ?? const <BestEffortPoint>[];
    if (all.isEmpty) {
      return [
        _noDataKeyed(
          c,
          'No $label efforts yet. They appear after runs that cover this '
          'distance with GPS data.',
          const Key('trends-be-empty'),
        ),
      ];
    }

    final window = TrendAnalytics.windowFor(
      _range,
      now: _now,
      firstRunDate: all.first.date,
    );
    final points = TrendAnalytics.pointsInWindow(all, window);
    if (points.isEmpty) {
      return [
        _noDataKeyed(
          c,
          'No $label efforts in this period.',
          const Key('trends-be-empty'),
        ),
      ];
    }

    final best = points.map((p) => p.seconds).reduce((a, b) => a < b ? a : b);
    final prs = points.where((p) => p.isPr).length;
    return [
      _headline(c, BestEffortsService.formatElapsed(best), null),
      const SizedBox(height: 4),
      Text(
        '${points.length} ${points.length == 1 ? 'effort' : 'efforts'}'
        ' · $prs ${prs == 1 ? 'PR' : 'PRs'} in this period',
        key: const Key('trends-be-summary'),
        style: TextStyle(fontSize: 12, color: c.textTertiary),
      ),
      const SizedBox(height: 12),
      SizedBox(height: 150, child: _effortChart(c, points)),
      const SizedBox(height: 8),
      Row(
        key: const Key('trends-be-legend'),
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: c.chartAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'PR when set',
            style: TextStyle(fontSize: 11, color: c.textTertiary),
          ),
        ],
      ),
    ];
  }

  Widget _noDataKeyed(AppColors c, String text, Key key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        text,
        key: key,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: c.textTertiary, height: 1.4),
      ),
    ),
  );

  Widget _effortChart(AppColors c, List<BestEffortPoint> points) {
    final first = TrendAnalytics.dateOnly(points.first.date);
    double x(BestEffortPoint p) => TrendAnalytics.daysBetween(
      first,
      TrendAnalytics.dateOnly(p.date),
    ).toDouble();

    // Faster (smaller) times plot higher.
    final spots = [for (final p in points) FlSpot(x(p), -p.seconds.toDouble())];
    final prSpots = [
      for (final p in points)
        if (p.isPr) FlSpot(x(p), -p.seconds.toDouble()),
    ];
    final ys = spots.map((s) => s.y);
    final lo = ys.reduce((a, b) => a < b ? a : b);
    final hi = ys.reduce((a, b) => a > b ? a : b);
    final yPad = _atLeast((hi - lo) * 0.2, 5);
    final span = spots.last.x - spots.first.x;
    final xPad = span <= 0 ? 1.0 : _atLeast(span * 0.04, 1);
    final minX = spots.first.x - xPad;
    final maxX = spots.last.x + xPad;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: lo - yPad,
        maxY: hi + yPad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: c.divider)),
        ),
        titlesData: _titles(c, (v) {
          final days = v.round();
          if (v < minX || v > maxX) return const SizedBox.shrink();
          final d = DateTime(first.year, first.month, first.day + days);
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${d.day} ${_months[d.month - 1]}',
              style: TextStyle(fontSize: 10, color: c.textTertiary),
            ),
          );
        }, interval: _atLeast((maxX - minX) / 3, 1)),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: c.background,
            getTooltipItems: (touched) => [
              for (final s in touched)
                LineTooltipItem(
                  BestEffortsService.formatElapsed((-s.y).round()),
                  _tooltipStyle(c),
                ),
            ],
          ),
        ),
        lineBarsData: [
          // Every effort in the period.
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: c.chartAccent.withValues(alpha: 0.45),
            barWidth: 1.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 2.5,
                color: c.textTertiary,
                strokeWidth: 0,
              ),
            ),
          ),
          // PR points only, drawn on top: no line, a larger ringed dot.
          LineChartBarData(
            spots: prSpots,
            isCurved: false,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 5,
                color: c.chartAccent,
                strokeWidth: 2,
                strokeColor: c.surface,
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? c.chartAccent.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(color: selected ? c.chartAccent : c.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? c.textPrimary : c.textTertiary,
          ),
        ),
      ),
    );
  }
}
