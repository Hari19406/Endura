import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';

import '../models/activity_telemetry.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';
import '../widgets/run_comments_sheet.dart';

/// Modern running-telemetry detail view: header + summary grid, route preview,
/// kilometre splits, a grade-adjusted-pace block, and up to four scrubbable
/// fl_chart panels (pace, elevation, heart rate + zones, cadence).
///
/// Every data-driven section renders conditionally so the screen degrades
/// gracefully on partial production payloads (no HR strap, no barometer, …).
///
/// Reached from the Activity Feed ([ActivityDetail.fromFeedRun]) and the
/// You / History tab ([ActivityDetail.fromRunRecord]); also from the Dev
/// Launcher via [ActivityDetail.mock].
class ActivityDetailScreen extends StatefulWidget {
  final ActivityDetail activity;

  /// Supplied only for the viewer's own recorded runs — enables the app-bar
  /// delete action. Runs the deletion, after which the screen pops `true`
  /// (the History tab refreshes on that result).
  final Future<void> Function()? onDelete;

  const ActivityDetailScreen({
    super.key,
    required this.activity,
    this.onDelete,
  });

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  // The feed has no server-side reaction store yet (see RunFeedCard._kudosed),
  // so this mirrors its local-only toggle until one exists.
  bool _reacted = false;
  late int _commentCount = widget.activity.commentCount;

  @override
  void initState() {
    super.initState();
    Analytics.capture(
      'activity_detail_viewed',
      properties: {
        'distance_km': widget.activity.distanceKm,
        'source': widget.activity.source,
      },
    );
  }

  ActivityDetail get a => widget.activity;

  /// MET-based estimate (assumes 70 kg — we don't collect weight). Mirrors
  /// `RunDetailScreen._estimateCalories` so history parity is kept when the
  /// record carries no stored value.
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
    return (met * assumedWeightKg * (durationSeconds / 3600)).round();
  }

  int? get _displayCalories {
    if (a.calories != null) return a.calories;
    final est = _estimateCalories(a.distanceKm, a.movingTime.inSeconds);
    return est > 0 ? est : null;
  }

  Future<void> _confirmDelete() async {
    HapticFeedback.lightImpact();
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Delete workout?'),
        content: const Text(
          "This run will be permanently removed from your history. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(dctx, true);
            },
            child: Text('Delete', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onDelete!.call();
    if (mounted) Navigator.pop(context, true);
  }

  // ── social actions (shared with the Feed tab) ────────────────────────────

  /// Opens the same comments bottom sheet the feed uses
  /// ([showRunCommentsSheet]) for this activity's backing run.
  Future<void> _openComments() async {
    HapticFeedback.lightImpact();
    final id = a.runId;
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Comments aren't available for this run yet."),
          ),
        );
      return;
    }
    final count = await showRunCommentsSheet(
      context,
      runId: id,
      initialCount: _commentCount,
    );
    if (mounted && count != _commentCount) {
      setState(() => _commentCount = count);
    }
  }

  /// Same share payload the feed's [RunFeedCard._share] builds — a one-line
  /// run summary via `share_plus`.
  Future<void> _share() async {
    HapticFeedback.lightImpact();
    final useMiles = UnitUtils.useMilesNotifier.value;
    final dist =
        '${UnitUtils.displayDistance(a.distanceKm, useMiles).toStringAsFixed(2)} '
        '${UnitUtils.unitLabel(useMiles)}';
    final text =
        "Check out ${a.runnerName}'s $dist run on Endura! "
        'Time: ${_fmtDuration(a.movingTime)}, '
        'Pace: ${UnitUtils.formatPaceString(a.avgPace, useMiles)}.';
    await SharePlus.instance.share(ShareParams(text: text));
    Analytics.capture(
      'activity_shared',
      properties: {
        if (a.runId != null) 'run_id': a.runId!,
        'source': 'activity_detail',
      },
    );
  }

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
            actions: [
              if (widget.onDelete != null)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: c.textPrimary,
                    size: 20,
                  ),
                  tooltip: 'Delete workout',
                  onPressed: _confirmDelete,
                ),
              IconButton(
                icon: Icon(Icons.ios_share, color: c.textPrimary, size: 20),
                tooltip: 'Share',
                onPressed: _share,
              ),
            ],
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
                  if (a.splits.isNotEmpty) ...[
                    _splitsCard(c),
                    const SizedBox(height: 16),
                  ],
                  if (a.avgGapPace != null) ...[
                    _gapBlock(c),
                    const SizedBox(height: 16),
                  ],
                  if (a.hasPaceSeries) ...[
                    _paceCard(c),
                    const SizedBox(height: 16),
                  ],
                  if (a.hasElevationData) ...[
                    _elevationCard(c),
                    const SizedBox(height: 16),
                  ],
                  if (a.hasHrData) ...[
                    _HrZonesCard(activity: a),
                    const SizedBox(height: 16),
                  ],
                  if (a.hasCadenceSeries) _cadenceCard(c),
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
              cell(
                'ELEV GAIN',
                a.elevationGainM == null
                    ? '—'
                    : a.elevationGainM!.round().toString(),
                a.elevationGainM == null ? '' : 'm',
              ),
              divider(),
              cell(
                'CALORIES',
                _displayCalories?.toString() ?? '—',
                _displayCalories == null ? '' : 'kcal',
              ),
              divider(),
              cell(
                'AVG HR',
                a.effectiveAvgHr?.toString() ?? '—',
                a.effectiveAvgHr == null ? '' : 'bpm',
              ),
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
                      child: Icon(
                        Icons.map_outlined,
                        color: Colors.white12,
                        size: 56,
                      ),
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
                  label: _commentCount > 0
                      ? 'Comment · $_commentCount'
                      : 'Comment',
                  onTap: _openComments,
                ),
                _socialPill(
                  c,
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: _share,
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
              Icon(
                icon,
                size: 17,
                color: active ? c.chartAccent : c.textSecondary,
              ),
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

  // ── 3. Grade-adjusted pace + moving/elapsed time ─────────────────────────

  Widget _gapBlock(AppColors c) {
    final delta = a.gapDeltaSeconds; // GAP − raw, negative = GAP faster
    final elapsed = a.elapsedTime;
    final hasStops = elapsed != null && elapsed > a.movingTime;

    Widget deltaPill() {
      if (delta == null || delta == 0) {
        return _pill(c, 'matches raw pace', c.textTertiary);
      }
      final faster = delta < 0;
      final mag = _paceFromSeconds(delta.abs());
      return _pill(
        c,
        '${faster ? '−' : '+'}$mag /km than raw pace',
        faster ? c.success : c.danger,
      );
    }

    return _card(
      c,
      title: 'GRADE-ADJUSTED PACE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AVG GAP',
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
                        text: a.avgGapPace,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: -1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        children: [
                          TextSpan(
                            text: ' /km',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    deltaPill(),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 66, color: c.border),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _timeRow(c, 'MOVING', _fmtDuration(a.movingTime)),
                  const SizedBox(height: 10),
                  _timeRow(
                    c,
                    'ELAPSED',
                    elapsed == null ? '—' : _fmtDuration(elapsed),
                    dim: !hasStops,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeRow(AppColors c, String label, String value, {bool dim = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
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
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: dim ? c.textTertiary : c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _pill(AppColors c, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  // ── 4. Kilometre splits ───────────────────────────────────────────────────

  Widget _splitsCard(AppColors c) {
    final fastest = a.fastestSplitSeconds;
    final slowest = a.slowestSplitSeconds;
    final showElev = a.anySplitHasElevation;
    final showHr = a.anySplitHasHr;
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
              if (showElev) ...[
                _splitHeaderCell(c, 'ELEV', width: 46, alignEnd: true),
                const SizedBox(width: 10),
              ],
              if (showHr) _splitHeaderCell(c, 'HR', width: 38, alignEnd: true),
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                          c.chartAccent,
                        ),
                      ),
                    ),
                  ),
                  if (showElev) ...[
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 46,
                      child: Text(
                        s.elevationChangeM == null
                            ? '—'
                            : '${s.elevationChangeM! >= 0 ? '+' : ''}'
                                  '${s.elevationChangeM!.round()}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                  if (showHr) ...[
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 38,
                      child: Text(
                        s.avgHr == null ? '—' : '${s.avgHr}',
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

  Widget _splitHeaderCell(
    AppColors c,
    String t, {
    required double width,
    bool alignEnd = false,
  }) {
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
        if (s.paceSeconds != null)
          FlSpot(s.distanceKm, -s.paceSeconds!.toDouble()),
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
    final elevs = a.telemetrySeries
        .map((s) => s.elevationM)
        .whereType<double>()
        .toList();
    final lo = elevs.reduce(math.min);
    final hi = elevs.reduce(math.max);
    final spots = [
      for (final s in a.telemetrySeries)
        if (s.elevationM != null) FlSpot(s.distanceKm, s.elevationM!),
    ];
    return _card(
      c,
      title: 'ELEVATION PROFILE',
      trailing: Text(
        '▲ ${(hi - lo).round()} m range · ${a.elevationGainM!.round()} m gain',
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
    final cadences = a.telemetrySeries
        .map((s) => s.cadenceSpm)
        .whereType<int>()
        .toList();
    final spots = [
      for (final s in a.telemetrySeries)
        if (s.cadenceSpm != null)
          FlSpot(s.distanceKm, s.cadenceSpm!.toDouble()),
    ];
    final avgCad =
        a.avgCadence ??
        (cadences.isEmpty
            ? null
            : (cadences.reduce((x, y) => x + y) / cadences.length).round());
    final peakCad =
        a.peakCadence ?? (cadences.isEmpty ? null : cadences.reduce(math.max));
    return _card(
      c,
      title: 'CADENCE',
      trailing: Text(
        [
              if (avgCad != null) 'avg $avgCad',
              if (peakCad != null) 'peak $peakCad',
            ].join(' · ') +
            (avgCad != null || peakCad != null ? ' spm' : ''),
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
//  Shared chart-scrub styling
// ═══════════════════════════════════════════════════════════════════════════

/// Black or white, whichever reads better on [bg].
Color _readableOn(Color bg) =>
    bg.computeLuminance() > 0.55 ? const Color(0xFF0B0B0C) : Colors.white;

/// A [LineTouchData] with a clean vertical cursor line, a filled thumb dot, and
/// a floating colored pill badge showing the scrubbed value + distance.
LineTouchData _scrubTouchData(
  AppColors c, {
  required Color pinColor,
  required String Function(LineBarSpot spot) label,
  required String xUnitLabel,
}) {
  final onPin = _readableOn(pinColor);
  return LineTouchData(
    enabled: true,
    getTouchedSpotIndicator: (bar, indexes) => indexes
        .map(
          (_) => TouchedSpotIndicatorData(
            FlLine(color: c.textTertiary.withOpacity(0.9), strokeWidth: 1.5),
            FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 5,
                color: pinColor,
                strokeWidth: 3,
                strokeColor: c.surface,
              ),
            ),
          ),
        )
        .toList(),
    touchTooltipData: LineTouchTooltipData(
      tooltipBgColor: pinColor,
      tooltipRoundedRadius: 20,
      tooltipBorder: BorderSide.none,
      tooltipPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      getTooltipItems: (touchedSpots) => touchedSpots
          .map(
            (spot) => LineTooltipItem(
              '${label(spot)}  ',
              TextStyle(
                color: onPin,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              children: [
                TextSpan(
                  text: '@ ${spot.x.toStringAsFixed(2)} $xUnitLabel',
                  style: TextStyle(
                    color: onPin.withOpacity(0.75),
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          )
          .toList(),
    ),
  );
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
        child: Text(
          'Not enough data',
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
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
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
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
        lineTouchData: _scrubTouchData(
          c,
          pinColor: color,
          label: (spot) => '${formatY(spot.y)} $yUnitLabel',
          xUnitLabel: xUnitLabel,
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
                colors:
                    fillGradient ??
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
      for (final s in a.telemetrySeries)
        if (s.hrBpm != null) FlSpot(s.distanceKm, s.hrBpm!.toDouble()),
    ];
    final hrs = a.telemetrySeries.map((s) => s.hrBpm).whereType<int>().toList();
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
                'avg ${a.effectiveAvgHr ?? '—'} · '
                'peak ${a.effectivePeakHr ?? '—'} bpm',
                style: TextStyle(fontSize: 10.5, color: c.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: spots.length < 2
                ? Center(
                    child: Text(
                      'Not enough data',
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                    ),
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
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: math.max(
                              1,
                              ((maxHr + 8) - (minHr - 8)) / 3,
                            ),
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
                                      FontFeature.tabularFigures(),
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
                                    fontSize: 9.5,
                                    color: c.textTertiary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          bottom: BorderSide(color: c.border, width: 1),
                        ),
                      ),
                      lineTouchData: _scrubTouchData(
                        c,
                        pinColor: c.danger,
                        label: (spot) => '${spot.y.round()} bpm',
                        xUnitLabel: 'km',
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
          const SizedBox(height: 16),
          _segmentedZoneBar(c, a, a.effectiveAvgHr ?? (minHr + maxHr) ~/ 2),
          const SizedBox(height: 12),
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

  /// 5 equal-width colored segments (Z1 gray → Z5 red) with a white marker
  /// pinned at the average heart rate, captioned "Avg X bpm • Z{N}".
  Widget _segmentedZoneBar(AppColors c, ActivityDetail a, int avgHr) {
    final lo = a.hrZones.first.bpmLow;
    final hi = a.hrZones.last.bpmHigh;
    final frac = hi <= lo ? 0.5 : ((avgHr - lo) / (hi - lo)).clamp(0.0, 1.0);

    var activeZone = a.hrZones.first.zone;
    for (final z in a.hrZones) {
      if (avgHr >= z.bpmLow) activeZone = z.zone;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, cons) {
            const markerW = 3.0;
            final x = (frac * cons.maxWidth - markerW / 2).clamp(
              0.0,
              cons.maxWidth - markerW,
            );
            return SizedBox(
              height: 26,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 7,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        children: [
                          for (var i = 0; i < a.hrZones.length; i++) ...[
                            if (i > 0) const SizedBox(width: 2),
                            Expanded(
                              child: Container(
                                height: 12,
                                color: _zoneColor(a.hrZones[i].zone),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: x,
                    top: 0,
                    child: Container(
                      width: markerW,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Avg $avgHr bpm • Z$activeZone',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Text(
              '$lo–$hi bpm',
              style: TextStyle(
                fontSize: 10.5,
                color: c.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
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
      toOffset(points.first),
      5,
      Paint()..color = const Color(0xFF4CAF50),
    );
    canvas.drawCircle(toOffset(points.last), 5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(_RoutePreviewPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.lineColor != lineColor;
}
