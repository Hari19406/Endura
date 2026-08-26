import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';
import '../utils/database_service.dart';
import '../widgets/run_share_card.dart';
import '../services/profile_service.dart';

class RunDetailScreen extends StatefulWidget {
  final dynamic run;
  final dynamic record;
  const RunDetailScreen({super.key, required this.run, this.record});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  bool _useMiles = UnitUtils.useMilesNotifier.value;
  int _maxHrEstimate = 190;

  @override
  void initState() {
    super.initState();
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
    _loadMaxHrEstimate();
  }

  Future<void> _loadMaxHrEstimate() async {
    try {
      final profile = await ProfileService.instance.fetchProfile();
      final dob = profile?.dob;
      if (dob == null || !mounted) return;
      final age = DateTime.now().difference(dob).inDays ~/ 365;
      if (age > 0) setState(() => _maxHrEstimate = 220 - age);
    } catch (_) {
      // Keep the 190 fallback — never block the screen on this.
    }
  }

  void _onUnitPrefChanged() {
    if (mounted) setState(() => _useMiles = UnitUtils.useMilesNotifier.value);
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String _calcPaceString(double distanceKm, int seconds) {
    if (distanceKm <= 0 || seconds <= 0) return '0:00';
    final secPerKm = (seconds / distanceKm).round();
    final mins = secPerKm ~/ 60;
    final secs = secPerKm % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    final months = [
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
    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final day = days[date.weekday - 1];
    return '$day, ${months[date.month - 1]} ${date.day} · '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  // MET-based estimate (assumes 70kg — we don't collect user weight yet).
  // Faster paces burn more per hour than the old flat distance*65 formula
  // captured, since MET scales with speed, not just distance.
  int _estimateCalories(double distanceKm, int durationSeconds) {
    if (durationSeconds <= 0 || distanceKm <= 0) return 0;
    final speedKmh = distanceKm / (durationSeconds / 3600);
    final met = speedKmh >= 16
        ? 16.0
        : speedKmh >= 14
        ? 14.5
        : speedKmh >= 12
        ? 12.8
        : speedKmh >= 10
        ? 11.0
        : speedKmh >= 8
        ? 9.8
        : 7.0;
    const assumedWeightKg = 70.0;
    final hours = durationSeconds / 3600;
    return (met * assumedWeightKg * hours).round();
  }

  String _workoutLabel(String type) => WorkoutTypeStyle.label(type);

  Color _workoutColor(String type) => WorkoutTypeStyle.color(type);

  Future<void> _confirmDeleteWorkout() async {
    HapticFeedback.lightImpact();
    final c = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Delete workout?'),
        content: const Text(
          'This run will be permanently removed from your history. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(dialogContext, true);
            },
            child: Text('Delete', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final id = widget.record?.id as int?;
    if (id == null) return;

    await DatabaseService.instance.deleteRun(id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  List<Map<String, double>> _getGpsPoints() {
    try {
      final points = widget.run.gpsPoints;
      if (points == null || (points as List).isEmpty) return [];
      return List<Map<String, double>>.from(points);
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.run.distance as double;
    final pace = widget.run.averagePace as String;
    final date = widget.run.date as DateTime;
    final duration = widget.record?.durationSeconds as int? ?? 0;
    final workoutType = widget.record?.workoutType as String? ?? 'easy';
    final calories = _estimateCalories(distance, duration);
    final elevationGain =
        (widget.record?.elevationGain as num?)?.toDouble() ?? 0;
    final splits =
        (widget.record?.splits as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final wColor = _workoutColor(workoutType);
    final gpsPoints = _getGpsPoints();

    final elapsedSeconds = widget.record?.elapsedSeconds as int?;
    final avgHr = widget.record?.avgHeartRate as int?;
    final peakHr = widget.record?.peakHeartRate as int?;
    final avgCadence = widget.record?.avgCadence as int?;
    final peakCadence = widget.record?.peakCadence as int?;
    final gapAveragePace = widget.record?.gapAveragePace as String?;
    final trackSamples =
        (widget.record?.trackSamples as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width - 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 54,
              width: double.infinity,
              child: FloatingActionButton.extended(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  showRunShareSheet(
                    context,
                    ShareRunData(
                      distanceKm: distance,
                      averagePace: pace,
                      durationSeconds: duration,
                      date: date,
                      workoutType: workoutType,
                      gpsPoints: gpsPoints,
                      useMiles: _useMiles,
                    ),
                    source: 'run_detail',
                  );
                },
                backgroundColor: context.colors.accent,
                foregroundColor: context.colors.onAccent,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                icon: const Icon(Icons.ios_share, size: 20),
                label: const Text(
                  'Share',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _confirmDeleteWorkout,
                style: OutlinedButton.styleFrom(
                  backgroundColor: context.colors.surface,
                  foregroundColor: context.colors.danger,
                  side: BorderSide(
                    color: context.colors.danger.withOpacity(0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text(
                  'Delete workout',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: const Color(0xFF0A0A0A),
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  // Route painter or gradient background
                  Positioned.fill(
                    child: gpsPoints.length > 1
                        ? CustomPaint(
                            painter: _RoutePainter(
                              points: gpsPoints,
                              lineColor: wColor,
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFF0A0A0A),
                                  wColor.withOpacity(0.15),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.directions_run,
                                color: Colors.white12,
                                size: 80,
                              ),
                            ),
                          ),
                  ),

                  // Dark gradient overlay at bottom for text readability
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF0A0A0A).withOpacity(0.85),
                          ],
                          stops: const [0.4, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Text overlay at bottom
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: wColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: wColor.withOpacity(0.5)),
                          ),
                          child: Text(
                            _workoutLabel(workoutType).toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: wColor,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _formatDate(date),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primary stats
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.colors.border),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        _buildStat(
                          context,
                          label: 'DISTANCE',
                          value: UnitUtils.displayDistance(
                            distance,
                            _useMiles,
                          ).toStringAsFixed(2),
                          unit: UnitUtils.unitLabel(_useMiles),
                        ),
                        _buildDivider(context),
                        _buildStat(
                          context,
                          label: 'AVG PACE',
                          value: UnitUtils.formatPaceString(pace, _useMiles),
                          unit: UnitUtils.perUnitLabel(_useMiles),
                        ),
                        _buildDivider(context),
                        _buildStat(
                          context,
                          label: 'TIME',
                          value: _formatDuration(duration),
                          unit: '',
                        ),
                      ],
                    ),
                  ),
                  // Moving vs elapsed time — only shown when the run had
                  // pauses (otherwise the two are identical and a 3rd row
                  // conveys nothing new).
                  if (elapsedSeconds != null && elapsedSeconds > duration) ...[
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.colors.border),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          _buildStat(
                            context,
                            label: 'MOVING TIME',
                            value: _formatDuration(duration),
                            unit: '',
                          ),
                          _buildDivider(context),
                          _buildStat(
                            context,
                            label: 'ELAPSED TIME',
                            value: _formatDuration(elapsedSeconds),
                            unit: '',
                          ),
                          _buildDivider(context),
                          _buildStat(
                            context,
                            label: 'ELAPSED PACE',
                            value: UnitUtils.formatPaceString(
                              _calcPaceString(distance, elapsedSeconds),
                              _useMiles,
                            ),
                            unit: UnitUtils.perUnitLabel(_useMiles),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Secondary stats
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.colors.border),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        _buildStat(
                          context,
                          label: 'CALORIES',
                          value: '$calories',
                          unit: 'kcal',
                        ),
                        _buildDivider(context),
                        _buildStat(
                          context,
                          label: 'ELEVATION',
                          value: elevationGain > 0
                              ? elevationGain.round().toString()
                              : '—',
                          unit: elevationGain > 0 ? 'm gain' : '',
                        ),
                        if (gapAveragePace != null) ...[
                          _buildDivider(context),
                          _buildStat(
                            context,
                            label: 'GRADE-ADJ PACE',
                            value: UnitUtils.formatPaceString(
                              gapAveragePace,
                              _useMiles,
                            ),
                            unit: UnitUtils.perUnitLabel(_useMiles),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trackSamples.length >= 2) ...[
                    const SizedBox(height: 16),
                    _buildTrendCard(
                      context,
                      title: 'PACE TREND',
                      samples: trackSamples,
                      valueKey: 'pace',
                      color: context.colors.chartAccent,
                      invertY: true,
                    ),
                  ],
                  if (trackSamples.any((s) => s['alt'] != null)) ...[
                    const SizedBox(height: 16),
                    _buildTrendCard(
                      context,
                      title: 'ELEVATION PROFILE',
                      samples: trackSamples,
                      valueKey: 'alt',
                      color: context.colors.textSecondary,
                    ),
                  ],
                  if (avgHr != null) ...[
                    const SizedBox(height: 16),
                    _buildHrCard(context, avgHr, peakHr, trackSamples),
                  ],
                  if (avgCadence != null) ...[
                    const SizedBox(height: 16),
                    _buildCadenceCard(context, avgCadence, peakCadence, trackSamples),
                  ],
                  if (splits.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildSplitsCard(context, splits),
                  ],
                  if (widget.record?.id != null) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Activity #${widget.record!.id}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textFaint,
                        ),
                      ),
                    ),
                  ],
                  // Clearance for the floating Share + Delete buttons.
                  const SizedBox(height: 156),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(
    BuildContext context, {
    required String label,
    required String value,
    required String unit,
  }) {
    final c = context.colors;
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
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: TextStyle(
                fontSize: 11,
                color: c.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 48,
      color: context.colors.border,
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  // Splits are always shown in km — capture happens in km increments
  // regardless of the display unit toggle, so mixing units here would
  // require re-deriving split boundaries we didn't record.
  Widget _buildSplitsCard(
    BuildContext context,
    List<Map<String, dynamic>> splits,
  ) {
    final c = context.colors;
    final secondsList = splits.map((s) => s['seconds'] as int).toList();
    final minSec = secondsList.reduce(math.min);
    final maxSec = secondsList.reduce(math.max);
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
          Text(
            'SPLITS (KM)',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          ...splits.map((s) {
            final km = s['km'] as int;
            final secs = s['seconds'] as int;
            final frac = maxSec == minSec
                ? 1.0
                : (maxSec - secs) / (maxSec - minSec);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$km',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 0.15 + frac * 0.85,
                        minHeight: 8,
                        backgroundColor: c.divider,
                        valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Bare line chart (no card chrome) of one field from `trackSamples`
  /// against cumulative distance. Returns [SizedBox.shrink] if fewer than 2
  /// samples carry a non-null value for [valueKey] (never renders a chart
  /// from a single point).
  Widget _buildTrendChart(
    BuildContext context, {
    required List<Map<String, dynamic>> samples,
    required String valueKey,
    required Color color,
    bool invertY = false,
  }) {
    final c = context.colors;
    final spots = <FlSpot>[];
    for (final s in samples) {
      final v = s[valueKey];
      if (v == null) continue;
      final distKm = (s['d'] as num).toDouble() / 1000;
      final value = (v as num).toDouble();
      spots.add(FlSpot(distKm, invertY ? -value : value));
    }
    if (spots.length < 2) return const SizedBox.shrink();

    String formatY(double y) {
      final v = invertY ? -y : y;
      if (valueKey == 'pace') {
        final secs = v.round();
        return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
      }
      return v.toStringAsFixed(0);
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
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
              getTitlesWidget: (value, meta) => Text(
                formatY(value),
                style: TextStyle(fontSize: 10, color: c.textTertiary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              getTitlesWidget: (value, meta) => Text(
                '${value.toStringAsFixed(1)}${UnitUtils.unitLabel(_useMiles)}',
                style: TextStyle(fontSize: 10, color: c.textTertiary),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withOpacity(0.08)),
          ),
        ],
      ),
    );
  }

  /// Card chrome (title + surface) wrapping [_buildTrendChart] — used for
  /// the standalone pace-trend and elevation-profile cards.
  Widget _buildTrendCard(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> samples,
    required String valueKey,
    required Color color,
    bool invertY = false,
  }) {
    final c = context.colors;
    final usableSamples = samples.where((s) => s[valueKey] != null).length;
    if (usableSamples < 2) return const SizedBox.shrink();
    final chart = _buildTrendChart(
      context,
      samples: samples,
      valueKey: valueKey,
      color: color,
      invertY: invertY,
    );

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
          Text(
            title,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(height: 120, child: chart),
        ],
      ),
    );
  }

  Widget _buildHrCard(
    BuildContext context,
    int avgHr,
    int? peakHr,
    List<Map<String, dynamic>> samples,
  ) {
    final c = context.colors;
    final hasTrend = samples.any((s) => s['hr'] != null);
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
              _buildStat(context, label: 'AVG HR', value: '$avgHr', unit: 'bpm'),
              if (peakHr != null) ...[
                _buildDivider(context),
                _buildStat(
                  context,
                  label: 'PEAK HR',
                  value: '$peakHr',
                  unit: 'bpm',
                ),
              ],
            ],
          ),
          if (hasTrend) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: _buildTrendChart(
                context,
                samples: samples,
                valueKey: 'hr',
                color: c.danger,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildHrZoneBar(context, avgHr),
        ],
      ),
    );
  }

  Widget _buildHrZoneBar(BuildContext context, int avgHr) {
    final c = context.colors;
    final maxHr = _maxHrEstimate;
    final bands = [
      ('Z1', 0.50, 0.60, c.textTertiary),
      ('Z2', 0.60, 0.70, c.chartAccent),
      ('Z3', 0.70, 0.80, c.success),
      ('Z4', 0.80, 0.90, c.accent),
      ('Z5', 0.90, 1.00, c.danger),
    ];
    final avgPct = (avgHr / maxHr).clamp(0.0, 1.0);
    String activeZone = 'Z1';
    for (final b in bands) {
      if (avgPct >= b.$2) activeZone = b.$1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: bands
              .map(
                (b) => Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: b == bands.last ? 0 : 2),
                    decoration: BoxDecoration(
                      color: b.$1 == activeZone
                          ? b.$4
                          : b.$4.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        Text(
          '$activeZone avg · est. max $maxHr bpm',
          style: TextStyle(fontSize: 11, color: c.textFaint),
        ),
      ],
    );
  }

  Widget _buildCadenceCard(
    BuildContext context,
    int avgCadence,
    int? peakCadence,
    List<Map<String, dynamic>> samples,
  ) {
    final c = context.colors;
    final hasTrend = samples.any((s) => s['cad'] != null);
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
              _buildStat(
                context,
                label: 'AVG CADENCE',
                value: '$avgCadence',
                unit: 'spm',
              ),
              if (peakCadence != null) ...[
                _buildDivider(context),
                _buildStat(
                  context,
                  label: 'PEAK CADENCE',
                  value: '$peakCadence',
                  unit: 'spm',
                ),
              ],
            ],
          ),
          if (hasTrend) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: _buildTrendChart(
                context,
                samples: samples,
                valueKey: 'cad',
                color: c.chartAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<Map<String, double>> points;
  final Color lineColor;

  const _RoutePainter({required this.points, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A0A0A),
    );

    // Get bounds
    double minLat = points.first['lat']!;
    double maxLat = points.first['lat']!;
    double minLng = points.first['lng']!;
    double maxLng = points.first['lng']!;

    for (final p in points) {
      minLat = math.min(minLat, p['lat']!);
      maxLat = math.max(maxLat, p['lat']!);
      minLng = math.min(minLng, p['lng']!);
      maxLng = math.max(maxLng, p['lng']!);
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    if (latRange == 0 || lngRange == 0) return;

    // Padding so route doesn't touch edges
    const padding = 40.0;
    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height - padding * 2;

    // Scale maintaining aspect ratio
    final scaleX = drawWidth / lngRange;
    final scaleY = drawHeight / latRange;
    final scale = math.min(scaleX, scaleY);

    final offsetX = padding + (drawWidth - lngRange * scale) / 2;
    final offsetY = padding + (drawHeight - latRange * scale) / 2;

    Offset toOffset(Map<String, double> p) {
      final x = offsetX + (p['lng']! - minLng) * scale;
      // Flip Y — latitude increases upward but canvas Y increases downward
      final y = offsetY + (maxLat - p['lat']!) * scale;
      return Offset(x, y);
    }

    // Glow effect — draw wide faint line first
    final glowPaint = Paint()
      ..color = lineColor.withOpacity(0.15)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (int i = 1; i < points.length; i++) {
      final o = toOffset(points[i]);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, glowPaint);

    // Main route line
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    // Start dot — green
    final startOffset = toOffset(points.first);
    canvas.drawCircle(startOffset, 5, Paint()..color = const Color(0xFF4CAF50));

    // End dot — colored by workout type
    final endOffset = toOffset(points.last);
    canvas.drawCircle(endOffset, 5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) => false;
}
