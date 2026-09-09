import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/activity_telemetry.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';

/// Modern running-telemetry detail view: header + summary grid, route preview,
/// training impact, kilometre splits, and four scrubbable fl_chart panels
/// (pace, elevation, heart rate + zones, cadence).
///
/// Fed today by [ActivityDetail.mock] via the Dev Launcher.
class ActivityDetailScreen extends StatefulWidget {
  final ActivityDetail activity;

  const ActivityDetailScreen({super.key, required this.activity});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  bool _reacted = false;

  @override
  void initState() {
    super.initState();
    Analytics.capture('activity_detail_viewed', properties: {
      'distance_km': widget.activity.distanceKm,
      'source': widget.activity.source,
    });
  }

  ActivityDetail get a => widget.activity;

  // ── formatting helpers ─────────────────────────────────────────────────────

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fmtTimestamp(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${months[t.month - 1]} ${t.day}, ${t.year} · $hh:$mm';
  }

  String _paceFromSeconds(int sec) =>
      '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: c.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textPrimary),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).maybePop();
              },
            ),
            title: Text(
              'Activity',
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(c),
                  const SizedBox(height: 20),
                  _summaryGrid(c),
                  const SizedBox(height: 16),
                  _routeCard(c),
                  const SizedBox(height: 16),
                  _impactCard(c),
                  const SizedBox(height: 16),
                  _splitsCard(c),
                  const SizedBox(height: 16),
                  _paceCard(c),
                  const SizedBox(height: 16),
                  _elevationCard(c),
                  const SizedBox(height: 16),
                  _HrZonesCard(activity: a),
                  const SizedBox(height: 16),
                  _cadenceCard(c),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. Header ──────────────────────────────────────────────────────────────

  Widget _header(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: c.surfaceAlt,
              foregroundImage: (a.avatarUrl != null && a.avatarUrl!.isNotEmpty)
                  ? NetworkImage(a.avatarUrl!)
                  : null,
              child: Text(
                a.runnerName.isNotEmpty ? a.runnerName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.runnerName,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtTimestamp(a.timestamp),
                    style: TextStyle(color: c.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.watch_outlined, size: 12, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    a.source,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          a.title,
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 21,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.place_outlined, size: 13, color: c.textTertiary),
            const SizedBox(width: 4),
            Text(
              a.location,
              style: TextStyle(color: c.textTertiary, fontSize: 12.5),
            ),
          ],
        ),
      ],
    );
  }

  // ── 1b. 3×2 summary grid ───────────────────────────────────────────────────

  Widget _summaryGrid(AppColors c) {
    Widget cell(String label, String value, String unit) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: c.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  children: [
                    if (unit.isNotEmpty)
                      TextSpan(
                        text: ' $unit',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: c.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget divider() => Container(
          width: 1,
          height: 40,
          color: c.border,
          margin: const EdgeInsets.symmetric(horizontal: 10),
        );

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              cell('DISTANCE', a.distanceKm.toStringAsFixed(2), 'km'),
              divider(),
              cell('PACE', a.avgPace, '/km'),
              divider(),
              cell('TIME', _fmtDuration(a.movingTime), ''),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: c.divider),
          ),
          Row(
            children: [
              cell('ELEV GAIN', a.elevationGainM.round().toString(), 'm'),
              divider(),
              cell('CALORIES', a.calories.toString(), 'kcal'),
              divider(),
              cell('AVG HR', a.avgHr.toString(), 'bpm'),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. Route preview + social pills ────────────────────────────────────────

  Widget _routeCard(AppColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 190,
            width: double.infinity,
            child: a.routePoints.length > 1
                ? CustomPaint(
                    painter: _RoutePreviewPainter(
                      points: a.routePoints,
                      lineColor: c.chartAccent,
                    ),
                  )
                : Container(
                    color: const Color(0xFF0A0A0A),
                    child: const Center(
                      child: Icon(Icons.map_outlined,
                          color: Colors.white12, size: 56),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _socialPill(
                  c,
                  icon: _reacted
                      ? Icons.local_fire_department
                      : Icons.local_fire_department_outlined,
                  label: _reacted ? 'Reacted' : 'React',
                  active: _reacted,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _reacted = !_reacted);
                  },
                ),
                _socialPill(
                  c,
                  icon: Icons.mode_comment_outlined,
                  label: 'Comment',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Comments — coming soon')),
                    );
                  },
                ),
                _socialPill(
                  c,
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Share sheet — coming soon')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialPill(
    AppColors c, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17,
                  color: active ? c.chartAccent : c.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? c.chartAccent : c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 3. Training & fitness impact ──────────────────────────────────────────

  Widget _impactCard(AppColors c) {
    final ti = a.trainingImpact;
    final fitnessColor = c.chartAccent;
    final fatigueColor = c.elevationAccent;

    return _card(
      c,
      title: 'TRAINING & FITNESS IMPACT',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '+${ti.impactScore}',
          style: TextStyle(
            color: c.onAccent,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              _impactValue(c, 'FITNESS', ti.fitnessImpact, fitnessColor),
              Container(width: 1, height: 40, color: c.border),
              _impactValue(c, 'FATIGUE', ti.fatigueImpact, fatigueColor),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                  flex: (ti.fitnessRatio * 1000).round().clamp(1, 999),
                  child: Container(height: 10, color: fitnessColor),
                ),
                Expanded(
                  flex: ((1 - ti.fitnessRatio) * 1000).round().clamp(1, 999),
                  child: Container(height: 10, color: fatigueColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Aerobic base',
                style: TextStyle(fontSize: 10.5, color: c.textTertiary),
              ),
              Text(
                'Acute load',
                style: TextStyle(fontSize: 10.5, color: c.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _impactValue(AppColors c, String label, double v, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. Kilometre splits ───────────────────────────────────────────────────

  Widget _splitsCard(AppColors c) {
    final fastest = a.fastestSplitSeconds;
    final slowest = a.slowestSplitSeconds;
    return _card(
      c,
      title: 'KILOMETRE SPLITS',
      child: Column(
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              _splitHeaderCell(c, 'KM', width: 26),
              const SizedBox(width: 10),
              _splitHeaderCell(c, 'PACE', width: 44),
              const Expanded(child: SizedBox()),
              _splitHeaderCell(c, 'ELEV', width: 46, alignEnd: true),
              const SizedBox(width: 10),
              _splitHeaderCell(c, 'HR', width: 38, alignEnd: true),
            ],
          ),
          const SizedBox(height: 6),
          ...a.splits.map((s) {
            final frac = slowest == fastest
                ? 1.0
                : (slowest - s.paceSeconds) / (slowest - fastest);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${s.km}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 44,
                    child: Text(
                      s.paceLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (0.12 + frac * 0.88).clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: c.divider,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(c.chartAccent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 46,
                    child: Text(
                      '${s.elevationChangeM >= 0 ? '+' : ''}'
                      '${s.elevationChangeM.round()}',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${s.avgHr}',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.danger,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          Text(
            'Bar length ∝ speed · fastest ${_paceFromSeconds(fastest ~/ 1)}'
            ' relative to slowest ${_paceFromSeconds(slowest ~/ 1)}',
            style: TextStyle(fontSize: 10.5, color: c.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _splitHeaderCell(AppColors c, String t,
      {required double width, bool alignEnd = false}) {
    return SizedBox(
      width: width,
      child: Text(
        t,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: c.textTertiary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  // ── 5a. Pace chart (inverted Y) ──────────────────────────────────────────

  Widget _paceCard(AppColors c) {
    final spots = [
      for (final s in a.telemetrySeries)
        FlSpot(s.distanceKm, -s.paceSeconds.toDouble()),
    ];
    return _card(
      c,
      title: 'PACE',
      child: SizedBox(
        height: 150,
        child: _ScrubLineChart(
          spots: spots,
          color: c.chartAccent,
          xUnitLabel: 'km',
          formatY: (y) => _paceFromSeconds((-y).round()),
          yUnitLabel: '/km',
          fill: true,
        ),
      ),
    );
  }

  // ── 5b. Elevation profile ────────────────────────────────────────────────

  Widget _elevationCard(AppColors c) {
    final elevs = a.telemetrySeries.map((s) => s.elevationM).toList();
    final lo = elevs.reduce(math.min);
    final hi = elevs.reduce(math.max);
    final spots = [
      for (final s in a.telemetrySeries) FlSpot(s.distanceKm, s.elevationM),
    ];
    return _card(
      c,
      title: 'ELEVATION PROFILE',
      trailing: Text(
        '▲ ${(hi - lo).round()} m range · ${a.elevationGainM.round()} m gain',
        style: TextStyle(fontSize: 10.5, color: c.textTertiary),
      ),
      child: SizedBox(
        height: 130,
        child: _ScrubLineChart(
          spots: spots,
          color: c.cadenceAccent, // green
          xUnitLabel: 'km',
          formatY: (y) => '${y.round()}',
          yUnitLabel: 'm',
          fill: true,
          fillGradient: [
            c.cadenceAccent.withOpacity(0.35),
            c.cadenceAccent.withOpacity(0.02),
          ],
        ),
      ),
    );
  }

  // ── 5d. Cadence profile ──────────────────────────────────────────────────

  Widget _cadenceCard(AppColors c) {
    final spots = [
      for (final s in a.telemetrySeries)
        FlSpot(s.distanceKm, s.cadenceSpm.toDouble()),
    ];
    return _card(
      c,
      title: 'CADENCE',
      trailing: Text(
        'avg ${a.avgCadence} · peak ${a.peakCadence} spm',
        style: TextStyle(fontSize: 10.5, color: c.textTertiary),
      ),
      child: SizedBox(
        height: 130,
        child: _ScrubLineChart(
          spots: spots,
          color: c.elevationAccent, // orange
          xUnitLabel: 'km',
          formatY: (y) => '${y.round()}',
          yUnitLabel: 'spm',
          fill: true,
        ),
      ),
    );
  }

  // ── shared card chrome ───────────────────────────────────────────────────

  Widget _card(
    AppColors c, {
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: c.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Reusable scrubbable line chart (pace / elevation / cadence)
// ═══════════════════════════════════════════════════════════════════════════

class _ScrubLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final Color color;
  final String xUnitLabel;
  final String yUnitLabel;
  final String Function(double y) formatY;
  final bool fill;
  final List<Color>? fillGradient;

  const _ScrubLineChart({
    required this.spots,
    required this.color,
    required this.xUnitLabel,
    required this.yUnitLabel,
    required this.formatY,
    this.fill = false,
    this.fillGradient,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (spots.length < 2) {
      return Center(
        child: Text('Not enough data',
            style: TextStyle(fontSize: 12, color: c.textTertiary)),
      );
    }

    final ys = spots.map((s) => s.y).toList();
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final yPad = ((maxY - minY) * 0.15).clamp(1.0, double.infinity);
    final xMax = spots.last.x;
    final yInterval = ((maxY + yPad) - (minY - yPad)) / 3;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: xMax,
        minY: minY - yPad,
        maxY: maxY + yPad,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval <= 0 ? null : yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.divider, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: yInterval <= 0 ? null : yInterval,
              getTitlesWidget: (value, meta) {
                if (value <= meta.min || value >= meta.max) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '${formatY(value)} $yUnitLabel',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: c.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: xMax > 0 ? (xMax / 4).clamp(0.5, double.infinity) : 1,
              getTitlesWidget: (value, meta) {
                if (value < 0 || value > xMax + 0.01) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${value.toStringAsFixed(1)} $xUnitLabel',
                    style: TextStyle(fontSize: 9.5, color: c.textTertiary),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: c.border, width: 1)),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          getTouchedSpotIndicator: (bar, indexes) => indexes
              .map(
                (_) => TouchedSpotIndicatorData(
                  FlLine(color: color.withOpacity(0.55), strokeWidth: 1.5),
                  FlDotData(
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: 4,
                      color: c.surface,
                      strokeWidth: 2.5,
                      strokeColor: color,
                    ),
                  ),
                ),
              )
              .toList(),
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: c.surfaceAlt,
            tooltipRoundedRadius: 8,
            tooltipBorder: BorderSide(color: c.border),
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) => touchedSpots
                .map(
                  (spot) => LineTooltipItem(
                    '${formatY(spot.y)} $yUnitLabel\n',
                    TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text:
                            '${spot.x.toStringAsFixed(2)} $xUnitLabel',
                        style: TextStyle(
                          color: c.textTertiary,
                          fontWeight: FontWeight.w500,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.18,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: fill,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: fillGradient ??
                    [color.withOpacity(0.22), color.withOpacity(0.0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  5c. Heart rate + zones card (expandable)
// ═══════════════════════════════════════════════════════════════════════════

class _HrZonesCard extends StatefulWidget {
  final ActivityDetail activity;
  const _HrZonesCard({required this.activity});

  @override
  State<_HrZonesCard> createState() => _HrZonesCardState();
}

class _HrZonesCardState extends State<_HrZonesCard> {
  bool _expanded = true;

  static const _zoneColorsLight = [
    Color(0xFF9E9E9E), // Z1 gray
    Color(0xFF4A90E2), // Z2 blue
    Color(0xFF2FA36B), // Z3 green
    Color(0xFFF5A623), // Z4 orange
    Color(0xFFE5484D), // Z5 red
  ];

  Color _zoneColor(int zone) =>
      _zoneColorsLight[(zone - 1).clamp(0, _zoneColorsLight.length - 1)];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = widget.activity;
    final spots = [
      for (final s in a.telemetrySeries) FlSpot(s.distanceKm, s.hrBpm.toDouble()),
    ];
    final hrs = a.telemetrySeries.map((s) => s.hrBpm).toList();
    final minHr = hrs.isEmpty ? 100 : hrs.reduce(math.min);
    final maxHr = hrs.isEmpty ? 180 : hrs.reduce(math.max);
    final xMax = spots.isEmpty ? 1.0 : spots.last.x;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'HEART RATE & ZONES',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: c.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                'avg ${a.avgHr} · peak ${a.peakHr} bpm',
                style: TextStyle(fontSize: 10.5, color: c.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: spots.length < 2
                ? Center(
                    child: Text('Not enough data',
                        style:
                            TextStyle(fontSize: 12, color: c.textTertiary)),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: xMax,
                      minY: (minHr - 8).toDouble(),
                      maxY: (maxHr + 8).toDouble(),
                      clipData: const FlClipData.all(),
                      rangeAnnotations: RangeAnnotations(
                        horizontalRangeAnnotations: [
                          for (final z in a.hrZones)
                            if (z.bpmHigh >= minHr - 8 && z.bpmLow <= maxHr + 8)
                              HorizontalRangeAnnotation(
                                y1: z.bpmLow.toDouble(),
                                y2: z.bpmHigh.toDouble(),
                                color: _zoneColor(z.zone).withOpacity(0.12),
                              ),
                        ],
                      ),
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: math.max(
                                1, ((maxHr + 8) - (minHr - 8)) / 3),
                            getTitlesWidget: (value, meta) {
                              if (value <= meta.min || value >= meta.max) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  '${value.round()} bpm',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: c.textTertiary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 20,
                            interval: xMax > 0
                                ? (xMax / 4).clamp(0.5, double.infinity)
                                : 1,
                            getTitlesWidget: (value, meta) {
                              if (value < 0 || value > xMax + 0.01) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${value.toStringAsFixed(1)} km',
                                  style: TextStyle(
                                      fontSize: 9.5, color: c.textTertiary),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                            bottom: BorderSide(color: c.border, width: 1)),
                      ),
                      lineTouchData: LineTouchData(
                        enabled: true,
                        getTouchedSpotIndicator: (bar, indexes) => indexes
                            .map(
                              (_) => TouchedSpotIndicatorData(
                                FlLine(
                                    color: c.danger.withOpacity(0.55),
                                    strokeWidth: 1.5),
                                FlDotData(
                                  getDotPainter:
                                      (spot, percent, bar, index) =>
                                          FlDotCirclePainter(
                                    radius: 4,
                                    color: c.surface,
                                    strokeWidth: 2.5,
                                    strokeColor: c.danger,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        touchTooltipData: LineTouchTooltipData(
                          tooltipBgColor: c.surfaceAlt,
                          tooltipRoundedRadius: 8,
                          tooltipBorder: BorderSide(color: c.border),
                          tooltipPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItems: (touchedSpots) => touchedSpots
                              .map(
                                (spot) => LineTooltipItem(
                                  '${spot.y.round()} bpm\n',
                                  TextStyle(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          '${spot.x.toStringAsFixed(2)} km',
                                      style: TextStyle(
                                        color: c.textTertiary,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.18,
                          preventCurveOverShooting: true,
                          color: c.danger,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                c.danger.withOpacity(0.16),
                                c.danger.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          // Zone distribution stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                for (final z in a.hrZones)
                  Expanded(
                    flex: math.max(1, (z.percentage * 1000).round()),
                    child: Container(height: 10, color: _zoneColor(z.zone)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    _expanded ? 'Hide zone breakdown' : 'Show zone breakdown',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              children: [
                const SizedBox(height: 4),
                for (final z in a.hrZones) _zoneRow(c, z),
              ],
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _zoneRow(AppColors c, HrZone z) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _zoneColor(z.zone),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 26,
            child: Text(
              'Z${z.zone}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              z.label,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
          ),
          Text(
            z.bpmRange,
            style: TextStyle(
              fontSize: 11,
              color: c.textTertiary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            child: Text(
              z.durationLabel,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 34,
            child: Text(
              z.percentLabel,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _zoneColor(z.zone),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Route preview painter
// ═══════════════════════════════════════════════════════════════════════════

class _RoutePreviewPainter extends CustomPainter {
  final List<Map<String, double>> points;
  final Color lineColor;

  const _RoutePreviewPainter({required this.points, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A0A0A),
    );
    if (points.length < 2) return;

    double minLat = points.first['lat']!, maxLat = points.first['lat']!;
    double minLng = points.first['lng']!, maxLng = points.first['lng']!;
    for (final p in points) {
      minLat = math.min(minLat, p['lat']!);
      maxLat = math.max(maxLat, p['lat']!);
      minLng = math.min(minLng, p['lng']!);
      maxLng = math.max(maxLng, p['lng']!);
    }
    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    if (latRange == 0 || lngRange == 0) return;

    const padding = 28.0;
    final drawW = size.width - padding * 2;
    final drawH = size.height - padding * 2;
    if (drawW <= 0 || drawH <= 0) return;

    final scale = math.min(drawW / lngRange, drawH / latRange);
    final offX = padding + (drawW - lngRange * scale) / 2;
    final offY = padding + (drawH - latRange * scale) / 2;

    Offset toOffset(Map<String, double> p) => Offset(
          offX + (p['lng']! - minLng) * scale,
          offY + (maxLat - p['lat']!) * scale,
        );

    final path = Path()
      ..moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final o = toOffset(points[i]);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor.withOpacity(0.16)
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withOpacity(0.92)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    canvas.drawCircle(
        toOffset(points.first), 5, Paint()..color = const Color(0xFF4CAF50));
    canvas.drawCircle(toOffset(points.last), 5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(_RoutePreviewPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.lineColor != lineColor;
}
