// lib/widgets/weather_performance_card.dart
//
// You → Stats "WEATHER PERFORMANCE" card, under Trends: how the athlete's own
// pace and HR differ across temperature / humidity bands, a heat-impact
// sentence once there is enough data, and a condition summary. All maths is in
// `weather_analytics.dart`. The copy deliberately says "observed", never
// "caused": these are differences between different runs.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';
import '../utils/weather_analytics.dart';

enum _WeatherView {
  tempPace('Temp · Pace'),
  humidityPace('Humidity · Pace'),
  tempHr('Temp · HR');

  const _WeatherView(this.label);
  final String label;
}

class WeatherPerformanceCard extends StatefulWidget {
  final List<WeatherRun> runs;
  final bool useMiles;

  const WeatherPerformanceCard({
    super.key,
    required this.runs,
    required this.useMiles,
  });

  @override
  State<WeatherPerformanceCard> createState() => _WeatherPerformanceCardState();
}

class _WeatherPerformanceCardState extends State<WeatherPerformanceCard> {
  _WeatherView _view = _WeatherView.tempPace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final report = WeatherAnalytics.analyze(widget.runs);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(20),
      child: report.runCount == 0 ? _empty(c) : _content(c, report),
    );
  }

  Widget _title(AppColors c) => Text(
    'WEATHER PERFORMANCE',
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: c.textTertiary,
      letterSpacing: 1.2,
    ),
  );

  Widget _empty(AppColors c) => Column(
    key: const Key('weather-empty'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c),
      const SizedBox(height: 12),
      Text(
        'Keep running with weather enabled to build your weather history.',
        style: TextStyle(fontSize: 13, color: c.textTertiary, height: 1.4),
      ),
    ],
  );

  // ── Content ───────────────────────────────────────────────────────────────

  List<WeatherBandStat> _bandsFor(WeatherReport r, _WeatherView v) =>
      v == _WeatherView.humidityPace ? r.humidity : r.temperature;

  bool _isHr(_WeatherView v) => v == _WeatherView.tempHr;

  Widget _content(AppColors c, WeatherReport report) {
    final hrAvailable = WeatherAnalytics.comparable(
      report.temperature,
      forHr: true,
    ).isNotEmpty;
    final view = (_view == _WeatherView.tempHr && !hrAvailable)
        ? _WeatherView.tempPace
        : _view;
    final views = [
      for (final v in _WeatherView.values)
        if (v != _WeatherView.tempHr || hrAvailable) v,
    ];

    final stats = _bandsFor(report, view);
    final plotted = WeatherAnalytics.comparable(stats, forHr: _isHr(view));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c),
        const SizedBox(height: 4),
        Text(
          '${report.runCount} ${report.runCount == 1 ? 'run' : 'runs'} with weather',
          key: const Key('weather-run-count'),
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < views.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _Pill(
                  key: Key('weather-view-${views[i].name}'),
                  label: views[i].label,
                  selected: views[i] == view,
                  onTap: () => setState(() => _view = views[i]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (plotted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Not enough runs to compare yet. Each band needs at least '
              '${WeatherAnalytics.minBandRuns} runs.',
              key: const Key('weather-chart-empty'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: c.textTertiary,
                height: 1.4,
              ),
            ),
          )
        else ...[
          SizedBox(height: 150, child: _chart(c, stats, plotted, view)),
          const SizedBox(height: 6),
          Text(
            _isHr(view)
                ? 'Average HR by band. Bands with fewer than '
                      '${WeatherAnalytics.minBandRuns} runs with HR are left out.'
                : 'Average pace by band — higher is faster. Bands with fewer '
                      'than ${WeatherAnalytics.minBandRuns} runs are left out.',
            key: const Key('weather-chart-note'),
            style: TextStyle(fontSize: 11, color: c.textTertiary, height: 1.3),
          ),
        ],
        const SizedBox(height: 16),
        _heatImpact(c, report),
        if (report.conditions.isNotEmpty) ...[
          const SizedBox(height: 16),
          _conditions(c, report),
        ],
        const SizedBox(height: 12),
        Text(
          'Observed differences between your own runs — not proof that weather '
          'caused them. Effort, route and fitness vary too.',
          key: const Key('weather-disclaimer'),
          style: TextStyle(fontSize: 11, color: c.textFaint, height: 1.3),
        ),
      ],
    );
  }

  // ── Chart ─────────────────────────────────────────────────────────────────

  String _pace(double secPerKm) {
    final secs = UnitUtils.displayPaceSeconds(
      secPerKm,
      widget.useMiles,
    ).round();
    return '${UnitUtils.formatSeconds(secs)} ${UnitUtils.perUnitLabel(widget.useMiles)}';
  }

  double? _value(WeatherBandStat s, bool hr) {
    if (hr) return s.hasEnoughHr ? s.avgHr : null;
    final pace = s.paceSecondsPerKm;
    if (pace == null || !s.hasEnoughRuns) return null;
    return -UnitUtils.displayPaceSeconds(pace, widget.useMiles);
  }

  Widget _chart(
    AppColors c,
    List<WeatherBandStat> all,
    List<WeatherBandStat> plotted,
    _WeatherView view,
  ) {
    final hr = _isHr(view);
    final color = hr ? c.hrAccent : c.chartAccent;
    final plottedKeys = {for (final s in plotted) s.key};

    final ys = [
      for (final s in all) plottedKeys.contains(s.key) ? _value(s, hr) : null,
    ];
    final present = ys.whereType<double>().toList();
    final lo = present.reduce((a, b) => a < b ? a : b);
    final hi = present.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo) * 0.25 < (hr ? 3.0 : 6.0)
        ? (hr ? 3.0 : 6.0)
        : (hi - lo) * 0.25;

    final spots = [
      for (var i = 0; i < ys.length; i++)
        ys[i] == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), ys[i]!),
    ];

    return LineChart(
      LineChartData(
        minX: -0.4,
        maxX: all.length - 0.6,
        minY: lo - pad,
        maxY: hi + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: c.divider)),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (value != i.toDouble() || i < 0 || i >= all.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${all[i].label}\nn=${hr ? all[i].hrRuns : all[i].runCount}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: c.textTertiary,
                      height: 1.2,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: c.background,
            getTooltipItems: (touched) => [
              for (final s in touched)
                LineTooltipItem(
                  '${all[s.x.round()].label}\n'
                  '${hr ? '${s.y.round()} bpm' : _pace(_backToSecPerKm(-s.y))}',
                  TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
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
                  FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  double _backToSecPerKm(double displayed) =>
      widget.useMiles ? displayed / 1.609344 : displayed;

  // ── Heat impact & conditions ──────────────────────────────────────────────

  Widget _heatImpact(AppColors c, WeatherReport report) {
    final impact = report.heatImpact;
    if (impact == null) {
      return Text(
        'Heat impact appears once you have '
        '${WeatherAnalytics.minHeatRuns}+ runs at 20–25° and '
        '${WeatherAnalytics.minHeatRuns}+ in a warmer band.',
        key: const Key('weather-heat-pending'),
        style: TextStyle(fontSize: 12, color: c.textTertiary, height: 1.4),
      );
    }

    final seconds =
        (impact.deltaSecondsPerKm.abs() * (widget.useMiles ? 1.609344 : 1))
            .round();
    final unit = UnitUtils.perUnitLabel(widget.useMiles);
    final counts = '${impact.hotRuns} vs ${impact.baselineRuns} runs';
    final text = impact.isNegligible
        ? 'Your pace at ${impact.hotLabel} was similar to ${impact.baselineLabel} '
              '($counts).'
        : 'Your runs at ${impact.hotLabel} were about $seconds s$unit '
              '${impact.deltaSecondsPerKm > 0 ? 'slower' : 'faster'} than at '
              '${impact.baselineLabel} ($counts).';

    return Container(
      key: const Key('weather-heat-impact'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.chartAccent.withValues(alpha: 0.08),
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        key: const Key('weather-heat-impact-text'),
        style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.4),
      ),
    );
  }

  Widget _conditions(AppColors c, WeatherReport report) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final s in report.conditions)
        Container(
          key: Key('weather-condition-${s.key}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            [
              '${s.key[0].toUpperCase()}${s.key.substring(1)}',
              '${s.runCount} ${s.runCount == 1 ? 'run' : 'runs'}',
              if (s.hasEnoughRuns && s.paceSecondsPerKm != null)
                _pace(s.paceSecondsPerKm!),
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ),
    ],
  );
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
