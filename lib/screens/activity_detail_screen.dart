import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/activity_telemetry.dart';
import '../services/analytics_service.dart';
import '../services/best_efforts_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import '../utils/pace_analytics.dart';
import '../utils/run_effort_analytics.dart';
import '../utils/unit_utils.dart';
import '../widgets/ambient_scaffold.dart';
import '../widgets/best_effort_rank_badge.dart';
import '../widgets/run_comments_sheet.dart';
import '../widgets/run_share_card.dart';

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

  /// The caller's current "reacted" state for this activity (e.g. a feed
  /// card's own local toggle) — seeds this screen's React pill so the two
  /// stay consistent.
  final bool initialReacted;

  /// Fired the moment the React pill's toggle is confirmed (or rolled back),
  /// so the card that opened this screen can update its own state immediately
  /// — paired with [onReactionCountChanged], not just on pop.
  final ValueChanged<bool>? onReactedChanged;

  /// Fired alongside [onReactedChanged] with the resulting reaction count.
  final ValueChanged<int>? onReactionCountChanged;

  /// Fired the moment the comment count actually changes (a comment was
  /// posted, or the sheet reports a different count), so the caller's card can
  /// stay in sync without waiting for a pop result.
  final ValueChanged<int>? onCommentCountChanged;

  const ActivityDetailScreen({
    super.key,
    required this.activity,
    this.onDelete,
    this.initialReacted = false,
    this.onReactedChanged,
    this.onReactionCountChanged,
    this.onCommentCountChanged,
  });

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  late bool _reacted = widget.initialReacted;
  late int _reactionCount = widget.activity.reactionCount;
  late int _commentCount = widget.activity.commentCount;
  bool _reactionBusy = false;

  /// Resolved once per screen instance — comments and reactions both need the
  /// true Supabase `runs.id`; see [ActivityDetail.runIdIsCloud].
  int? _resolvedCloudRunId;
  bool _cloudRunIdResolveAttempted = false;

  /// Live unit preference — every distance/pace on this screen renders in
  /// this unit; the underlying [ActivityDetail] data always stays km-based.
  bool _useMiles = UnitUtils.useMilesNotifier.value;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      final a = widget.activity;
      final paceN = a.telemetrySeries
          .where((s) => s.paceSeconds != null)
          .length;
      final altN = a.telemetrySeries.where((s) => s.elevationM != null).length;
      debugPrint(
        '[ActivityDetail] ${a.distanceKm.toStringAsFixed(2)} km '
        'splits=${a.splits.length} samples=${a.telemetrySeries.length} '
        'paceSamples=$paceN altSamples=$altN gain=${a.elevationGainM} '
        '-> splitsCard=${a.splits.isNotEmpty} paceChart=${a.hasPaceSeries} '
        'elevChart=${a.hasElevationData}',
      );
    }
    Analytics.capture(
      'activity_detail_viewed',
      properties: {
        'distance_km': widget.activity.distanceKm,
        'source': widget.activity.source,
      },
    );
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
  }

  void _onUnitPrefChanged() {
    if (mounted) setState(() => _useMiles = UnitUtils.useMilesNotifier.value);
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    super.dispose();
  }

  ActivityDetail get a => widget.activity;

  /// Aligned, validated pace / HR / elevation — built once, shared by the
  /// combined card and the individual charts.
  late final RunEffortSeries _effort = a.effort;

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

  /// The true Supabase `runs.id` backing this activity, resolved once and
  /// cached for the life of this screen.
  ///
  /// [ActivityDetail.runId] is only a Supabase id — safe to use as-is — when
  /// [ActivityDetail.runIdIsCloud] is true (the Feed path). Runs opened from
  /// local storage (You/History) carry a local SQLite id instead, so the cloud
  /// id is resolved by date + distance first; there's no persisted
  /// local↔cloud mapping to read it from directly. Null when it can't be
  /// resolved (offline, unsynced, no signed-in user).
  Future<int?> _resolveRunId() async {
    if (a.runIdIsCloud) return a.runId;
    if (_cloudRunIdResolveAttempted) return _resolvedCloudRunId;
    _cloudRunIdResolveAttempted = true;
    _resolvedCloudRunId = await CloudSyncService.instance.resolveCloudRunId(
      date: a.timestamp,
      distanceKm: a.distanceKm,
    );
    return _resolvedCloudRunId;
  }

  /// Opens the same comments bottom sheet the feed uses
  /// ([showRunCommentsSheet]) for this activity's backing run.
  Future<void> _openComments() async {
    HapticFeedback.lightImpact();
    final id = await _resolveRunId();
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
    widget.onCommentCountChanged?.call(count);
  }

  /// Real, persisted cheer — optimistic UI, rolled back on failure (offline,
  /// unresolved cloud id, RLS denial, etc).
  Future<void> _toggleReaction() async {
    if (_reactionBusy) return;
    HapticFeedback.selectionClick();
    final wasReacted = _reacted;
    final prevCount = _reactionCount;
    setState(() {
      _reactionBusy = true;
      _reacted = !wasReacted;
      _reactionCount = prevCount + (_reacted ? 1 : -1);
    });
    widget.onReactedChanged?.call(_reacted);
    widget.onReactionCountChanged?.call(_reactionCount);

    final id = await _resolveRunId();
    bool? result;
    if (id != null) {
      result = await SocialService.instance.toggleReaction(
        id,
        currentlyReacted: wasReacted,
      );
    }
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _reactionBusy = false;
        _reacted = wasReacted;
        _reactionCount = prevCount;
      });
      widget.onReactedChanged?.call(_reacted);
      widget.onReactionCountChanged?.call(_reactionCount);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't update your reaction — check your connection.",
            ),
          ),
        );
    } else {
      setState(() => _reactionBusy = false);
    }
  }

  /// Branded, shareable run card (PNG via a RepaintBoundary snapshot) — the
  /// same export the post-run summary uses.
  Future<void> _shareCard() async {
    HapticFeedback.lightImpact();
    await showRunShareSheet(
      context,
      ShareRunData(
        distanceKm: a.distanceKm,
        averagePace: a.avgPace,
        durationSeconds: a.movingTime.inSeconds,
        date: a.timestamp,
        workoutType: a.workoutType,
        gpsPoints: a.routePoints,
        useMiles: _useMiles,
      ),
      source: 'activity_detail',
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
    return AmbientScaffold(
      safeArea: false,
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
                onPressed: _shareCard,
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
                  if (a.bestEfforts.isNotEmpty) ...[
                    _bestEffortsCard(c),
                    const SizedBox(height: 16),
                  ],
                  if (a.avgGapPace != null) ...[
                    _gapBlock(c),
                    const SizedBox(height: 16),
                  ],
                  if (_effort.supportsCombinedChart) ...[
                    _EffortCard(effort: _effort, useMiles: _useMiles),
                    const SizedBox(height: 16),
                  ],
                  if (a.hasPaceSeries) ...[
                    _paceCard(c),
                    const SizedBox(height: 16),
                  ],
                  if (a.paceZones.isNotEmpty) ...[
                    _paceZonesCard(c),
                    const SizedBox(height: 16),
                  ],
                  if (a.hasElevationData) ...[
                    _elevationCard(c),
                    const SizedBox(height: 16),
                  ],
                  if (a.hasHrData) ...[
                    _HrZonesCard(
                      activity: a,
                      useMiles: _useMiles,
                      effort: _effort,
                    ),
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
              cell(
                'DISTANCE',
                UnitUtils.displayDistance(
                  a.distanceKm,
                  _useMiles,
                ).toStringAsFixed(2),
                UnitUtils.unitLabel(_useMiles),
              ),
              divider(),
              cell(
                'PACE',
                UnitUtils.formatPaceString(a.avgPace, _useMiles),
                UnitUtils.perUnitLabel(_useMiles),
              ),
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
                      backgroundColor: c.background,
                      routeColor: c.textPrimary,
                      startColor: c.success,
                    ),
                  )
                : Container(
                    color: c.background,
                    child: Center(
                      child: Icon(
                        Icons.map_outlined,
                        color: c.textPrimary.withValues(alpha: 0.12),
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
                  label: _reacted
                      ? (_reactionCount > 1
                            ? 'Reacted · $_reactionCount'
                            : 'Reacted')
                      : (_reactionCount > 0
                            ? 'React · $_reactionCount'
                            : 'React'),
                  active: _reacted,
                  onTap: _toggleReaction,
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
                  onTap: _shareCard,
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

  // ── Best Efforts achieved in this run ────────────────────────────────────

  /// Each distance this run covered, with its rank among all of the athlete's
  /// efforts at that distance and the current all-time best for comparison.
  /// Straight from the stored Best Efforts — nothing is recomputed here.
  Widget _bestEffortsCard(AppColors c) {
    return _card(
      c,
      title: 'BEST EFFORTS',
      child: Column(
        children: [for (final e in a.bestEfforts) _bestEffortRow(c, e)],
      ),
    );
  }

  Widget _bestEffortRow(AppColors c, RunBestEffort e) {
    final time = BestEffortsService.formatElapsed(e.elapsedSeconds);
    final comparison = e.isPr
        ? 'All-time best'
        : 'Best ${BestEffortsService.formatElapsed(e.bestSeconds)}'
              ' \u00b7 +${BestEffortsService.formatElapsed(e.secondsOffBest)}';
    return Padding(
      key: Key('best-effort-row-${e.category.name}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          BestEffortRankBadge(rank: e.rank),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.category.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  comparison,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                time,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: e.isPr ? c.chartAccent : c.border),
                ),
                child: Text(
                  e.rankLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: e.isPr ? c.chartAccent : c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
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
      final mag = _paceFromSeconds(
        UnitUtils.displayPaceSeconds(delta.abs().toDouble(), _useMiles).round(),
      );
      return _pill(
        c,
        '${faster ? '−' : '+'}$mag ${UnitUtils.perUnitLabel(_useMiles)} '
        'than raw pace',
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
                        text: UnitUtils.formatPaceString(
                          a.avgGapPace!,
                          _useMiles,
                        ),
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: -1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        children: [
                          TextSpan(
                            text: ' ${UnitUtils.perUnitLabel(_useMiles)}',
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
    final splits = a.splitsForDisplay(useMiles: _useMiles);
    // Bar-scaling reference points only — excludes zero/garbage paces (a
    // sub-60s/km or /mi split is not a real running pace) so one bad split
    // can't collapse or blow out every other bar's relative length. Ordinary
    // splits are healed further upstream in splitsForDisplay(); this is a
    // second, independent guard on just the min/max the bars are scaled to.
    final validPaces = splits
        .map((s) => s.paceSeconds)
        .where((p) => p > 60)
        .toList();
    final fastest = validPaces.isEmpty ? 0 : validPaces.reduce(math.min);
    final slowest = validPaces.isEmpty ? 0 : validPaces.reduce(math.max);
    final showElev = a.anySplitHasElevation;
    final showHr = a.anySplitHasHr;
    final showGap = splits.any((s) => s.gapPaceSeconds != null);
    return _card(
      c,
      title: _useMiles ? 'MILE SPLITS' : 'KILOMETRE SPLITS',
      child: Column(
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              _splitHeaderCell(c, _useMiles ? 'MI' : 'KM', width: 26),
              const SizedBox(width: 10),
              _splitHeaderCell(c, 'PACE', width: 44),
              const Expanded(child: SizedBox()),
              if (showGap) ...[
                _splitHeaderCell(c, 'GAP', width: 40, alignEnd: true),
                const SizedBox(width: 10),
              ],
              if (showElev) ...[
                _splitHeaderCell(c, 'ELEV', width: 46, alignEnd: true),
                const SizedBox(width: 10),
              ],
              if (showHr) _splitHeaderCell(c, 'HR', width: 38, alignEnd: true),
            ],
          ),
          const SizedBox(height: 6),
          ...splits.map((s) {
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
                      s.isPartial
                          ? UnitUtils.displayDistance(
                              s.distanceKm,
                              _useMiles,
                            ).toStringAsFixed(1)
                          : '${s.km}',
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
                  if (showGap) ...[
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 40,
                      child: Text(
                        s.gapPaceLabel ?? '—',
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
            'Bar length ∝ speed · fastest ${_paceFromSeconds(fastest)}'
            ' relative to slowest ${_paceFromSeconds(slowest)}',
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

  /// Plot-ready runs for [channel]: only valid points, split at GPS/time
  /// gaps so no line is drawn across a dropout.
  List<List<FlSpot>> _effortRuns(
    EffortChannel channel,
    double Function(EffortPoint p) y,
  ) => [
    for (final run in _effort.runsFor(channel))
      [
        for (final p in run)
          FlSpot(UnitUtils.displayDistance(p.distanceKm, _useMiles), y(p)),
      ],
  ];

  Widget _paceCard(AppColors c) {
    final runs = _effortRuns(
      EffortChannel.pace,
      (p) => -UnitUtils.displayPaceSeconds(p.paceSecPerKm!, _useMiles),
    );
    return _card(
      c,
      title: 'PACE',
      child: SizedBox(
        height: 150,
        child: _ScrubLineChart(
          runs: runs,
          color: c.chartAccent,
          xUnitLabel: UnitUtils.unitLabel(_useMiles),
          formatY: (y) => _paceFromSeconds((-y).round()),
          yUnitLabel: UnitUtils.perUnitLabel(_useMiles),
          fill: true,
        ),
      ),
    );
  }

  // ── 5a-2. Pace zones ─────────────────────────────────────────────────────

  Color _paceZoneColor(AppColors c, int zone) => switch (zone) {
    1 => c.workoutEasy,
    2 => c.workoutLong,
    3 => c.workoutTempo,
    4 => c.workoutInterval,
    _ => c.danger,
  };

  String _paceEdge(int secPerKm) => _paceFromSeconds(
    UnitUtils.displayPaceSeconds(secPerKm.toDouble(), _useMiles).round(),
  );

  /// "7:04–7:47" for a closed zone, "7:47+" (slower than) or "<5:44" (faster
  /// than) for the open-ended ends, in the display unit.
  String _paceRange(PaceZoneStat z) {
    final slow = z.slowEdgeSecPerKm;
    final fast = z.fastEdgeSecPerKm;
    if (slow == null && fast != null) return '${_paceEdge(fast)}+';
    if (fast == null && slow != null) return '<${_paceEdge(slow)}';
    if (slow != null && fast != null) {
      return '${_paceEdge(fast)}–${_paceEdge(slow)}';
    }
    return '';
  }

  Widget _paceZonesCard(AppColors c) {
    final zones = a.paceZones;
    return _card(
      c,
      title: 'PACE ZONES',
      trailing: a.paceZonesVdot == null
          ? null
          : Text(
              'from vDOT ${a.paceZonesVdot} · ${UnitUtils.perUnitLabel(_useMiles)}',
              style: TextStyle(fontSize: 10.5, color: c.textTertiary),
            ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final z in zones)
                    if (z.percentage > 0)
                      Expanded(
                        flex: (z.percentage * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: _paceZoneColor(c, z.zone)),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final z in zones) _paceZoneRow(c, z),
        ],
      ),
    );
  }

  Widget _paceZoneRow(AppColors c, PaceZoneStat z) {
    final m = z.durationSeconds ~/ 60;
    final s = z.durationSeconds % 60;
    final duration = m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
    final color = _paceZoneColor(c, z.zone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
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
            _paceRange(z),
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
              duration,
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
              '${(z.percentage * 100).round()}%',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 5b. Elevation profile ────────────────────────────────────────────────

  Widget _elevationCard(AppColors c) {
    final range = _effort.rangeOf(EffortChannel.elevation);
    final lo = range?.$1 ?? 0.0;
    final hi = range?.$2 ?? 0.0;
    final runs = _effortRuns(EffortChannel.elevation, (p) => p.elevationM!);
    return _card(
      c,
      title: 'ELEVATION PROFILE',
      trailing: Text(
        '▲ ${(hi - lo).round()} m range · ${(a.elevationGainM ?? 0).round()} m gain',
        style: TextStyle(fontSize: 10.5, color: c.textTertiary),
      ),
      child: SizedBox(
        height: 130,
        child: _ScrubLineChart(
          runs: runs,
          color: c.cadenceAccent, // green
          xUnitLabel: UnitUtils.unitLabel(_useMiles),
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
          FlSpot(
            UnitUtils.displayDistance(s.distanceKm, _useMiles),
            s.cadenceSpm!.toDouble(),
          ),
    ];
    final runs = [spots];
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
          runs: runs,
          color: c.elevationAccent, // orange
          xUnitLabel: UnitUtils.unitLabel(_useMiles),
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
  /// One list per contiguous stretch; separate lists are NOT joined, so a
  /// GPS/time gap shows as a break in the line.
  final List<List<FlSpot>> runs;
  final Color color;
  final String xUnitLabel;
  final String yUnitLabel;
  final String Function(double y) formatY;
  final bool fill;
  final List<Color>? fillGradient;

  const _ScrubLineChart({
    required this.runs,
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
    final spots = [for (final r in runs) ...r];
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
          for (final run in runs)
            LineChartBarData(
              spots: run,
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
  final bool useMiles;
  final RunEffortSeries effort;
  const _HrZonesCard({
    required this.activity,
    required this.useMiles,
    required this.effort,
  });

  @override
  State<_HrZonesCard> createState() => _HrZonesCardState();
}

class _HrZonesCardState extends State<_HrZonesCard> {
  bool _expanded = true;

  // HR zone hues (Z1-Z5): fixed data-viz ramp, no matching semantic tokens.
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
    // Valid HR only (30–230 bpm), split at gaps so a dropout isn't bridged.
    final runs = [
      for (final run in widget.effort.runsFor(EffortChannel.hr))
        [
          for (final p in run)
            FlSpot(
              UnitUtils.displayDistance(p.distanceKm, widget.useMiles),
              p.hrBpm!.toDouble(),
            ),
        ],
    ];
    final spots = [for (final r in runs) ...r];
    final hrs = [
      for (final p in widget.effort.points)
        if (p.hrBpm != null) p.hrBpm!,
    ];
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
                                  '${value.toStringAsFixed(1)} '
                                  '${UnitUtils.unitLabel(widget.useMiles)}',
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
                        xUnitLabel: UnitUtils.unitLabel(widget.useMiles),
                      ),
                      lineBarsData: [
                        for (final run in runs)
                          LineChartBarData(
                            spots: run,
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
          if (a.maxHr != null) ...[
            const SizedBox(height: 8),
            Text(
              a.maxHr!.caption,
              style: TextStyle(fontSize: 10.5, color: c.textTertiary),
            ),
          ],
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
                        color: c.textPrimary,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: c.scrim.withValues(alpha: 0.35),
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
                color: c.textPrimary,
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
//  Combined pace · HR · elevation card
// ═══════════════════════════════════════════════════════════════════════════

/// Pace, heart rate and elevation on ONE distance axis with a shared cursor.
/// Each channel is scaled to its own range (so the axis carries no numbers);
/// the readout above the chart gives the real values at the cursor. On a
/// narrow screen at most two channels are shown at once.
class _EffortCard extends StatefulWidget {
  final RunEffortSeries effort;
  final bool useMiles;
  const _EffortCard({required this.effort, required this.useMiles});

  @override
  State<_EffortCard> createState() => _EffortCardState();
}

class _EffortCardState extends State<_EffortCard> {
  /// Channels currently drawn, in the order they were switched on.
  List<EffortChannel> _visible = const [];
  bool _initialised = false;

  /// Cursor position in display-unit distance (km or mi), or null.
  double? _cursorX;

  static const _maxVisibleNarrow = 2;
  static const _maxVisibleWide = 3;
  static const _narrowWidth = 380.0;

  int _maxVisible(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _narrowWidth
      ? _maxVisibleNarrow
      : _maxVisibleWide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _visible = widget.effort.availableChannels
          .take(_maxVisible(context))
          .toList();
      _initialised = true;
    }
  }

  void _toggle(EffortChannel channel) {
    HapticFeedback.selectionClick();
    final max = _maxVisible(context);
    setState(() {
      final next = [..._visible];
      if (next.contains(channel)) {
        if (next.length > 1) next.remove(channel); // keep at least one
      } else {
        next.add(channel);
        while (next.length > max) {
          next.removeAt(0); // drop the one switched on longest ago
        }
      }
      _visible = next;
    });
  }

  Color _color(AppColors c, EffortChannel ch) => switch (ch) {
    EffortChannel.pace => c.chartAccent,
    EffortChannel.hr => c.hrAccent,
    EffortChannel.elevation => c.cadenceAccent, // green, as the elevation card
  };

  String _name(EffortChannel ch) => switch (ch) {
    EffortChannel.pace => 'Pace',
    EffortChannel.hr => 'HR',
    EffortChannel.elevation => 'Elev',
  };

  double _x(EffortPoint p) =>
      UnitUtils.displayDistance(p.distanceKm, widget.useMiles);

  String _paceText(double secPerKm) {
    final s = UnitUtils.displayPaceSeconds(secPerKm, widget.useMiles).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Range label for a chip, e.g. "4:58–5:40 /km" (fastest first).
  String _rangeText(EffortChannel ch) {
    final r = widget.effort.rangeOf(ch);
    if (r == null) return '';
    return switch (ch) {
      EffortChannel.pace =>
        '${_paceText(r.$1)}\u2013${_paceText(r.$2)} '
            '${UnitUtils.perUnitLabel(widget.useMiles)}',
      EffortChannel.hr => '${r.$1.round()}\u2013${r.$2.round()} bpm',
      EffortChannel.elevation => '${r.$1.round()}\u2013${r.$2.round()} m',
    };
  }

  /// 0..1 height for [v] on [ch], with a minimum span so a flat channel
  /// doesn't turn noise into a mountain. Pace is inverted: faster = higher.
  double _norm(EffortChannel ch, double v) {
    final r = widget.effort.rangeOf(ch)!;
    final minSpan = switch (ch) {
      EffortChannel.pace => 30.0,
      EffortChannel.hr => 10.0,
      EffortChannel.elevation => 10.0,
    };
    var lo = r.$1;
    var hi = r.$2;
    if (hi - lo < minSpan) {
      final mid = (lo + hi) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    var t = (v - lo) / (hi - lo);
    if (ch == EffortChannel.pace) t = 1 - t;
    return 0.08 + t * 0.84;
  }

  EffortPoint? _pointAt(double displayX) {
    EffortPoint? best;
    var bestDist = double.infinity;
    for (final p in widget.effort.points) {
      final d = (_x(p) - displayX).abs();
      if (d < bestDist) {
        best = p;
        bestDist = d;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final channels = widget.effort.availableChannels;
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
            'PACE \u00b7 HR \u00b7 ELEVATION',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final ch in channels) _chip(c, ch)],
          ),
          const SizedBox(height: 12),
          _readout(c),
          const SizedBox(height: 8),
          SizedBox(height: 170, child: _chart(c)),
        ],
      ),
    );
  }

  Widget _chip(AppColors c, EffortChannel ch) {
    final on = _visible.contains(ch);
    final color = _color(c, ch);
    return GestureDetector(
      key: Key('effort-chip-${ch.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(ch),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? color.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? color : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: on ? color : c.textFaint,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _name(ch),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: on ? c.textPrimary : c.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _rangeText(ch),
              style: TextStyle(
                fontSize: 10.5,
                color: c.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readout(AppColors c) {
    final cursor = _cursorX;
    final p = cursor == null ? null : _pointAt(cursor);
    if (p == null) {
      return SizedBox(
        key: const Key('effort-readout'),
        height: 38,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Touch and drag across the chart to compare',
            style: TextStyle(fontSize: 11.5, color: c.textTertiary),
          ),
        ),
      );
    }

    // FittedBox: five cells share a 280 px card on a small phone, so long
    // labels/values scale down rather than overflow.
    Widget cell(String label, String value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: c.textTertiary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color ?? c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );

    final eff = widget.effort;
    final unit = UnitUtils.unitLabel(widget.useMiles);
    final g = p.gradient;
    return SizedBox(
      key: const Key('effort-readout'),
      height: 38,
      child: Row(
        children: [
          cell(unit.toUpperCase(), _x(p).toStringAsFixed(2)),
          if (eff.hasPace)
            cell(
              'PACE ${UnitUtils.perUnitLabel(widget.useMiles).toUpperCase()}',
              p.paceSecPerKm == null ? '\u2014' : _paceText(p.paceSecPerKm!),
              color: _color(c, EffortChannel.pace),
            ),
          if (eff.hasHr)
            cell(
              'HR BPM',
              p.hrBpm == null ? '\u2014' : '${p.hrBpm}',
              color: _color(c, EffortChannel.hr),
            ),
          if (eff.hasElevation) ...[
            cell(
              'ELEV M',
              p.elevationM == null ? '\u2014' : '${p.elevationM!.round()}',
              color: _color(c, EffortChannel.elevation),
            ),
            cell(
              'GRADE',
              g == null
                  ? '\u2014'
                  : '${g >= 0 ? '+' : ''}${(g * 100).toStringAsFixed(1)}%',
            ),
          ],
        ],
      ),
    );
  }

  Widget _chart(AppColors c) {
    final eff = widget.effort;
    final xMax = eff.points.isEmpty ? 1.0 : _x(eff.points.last);
    final safeXMax = xMax <= 0 ? 1.0 : xMax;

    // Elevation first so it sits behind the lines.
    final order = [
      for (final ch in [
        EffortChannel.elevation,
        EffortChannel.pace,
        EffortChannel.hr,
      ])
        if (_visible.contains(ch)) ch,
    ];

    final bars = <LineChartBarData>[];
    for (final ch in order) {
      final color = _color(c, ch);
      for (final run in eff.runsFor(ch)) {
        bars.add(
          LineChartBarData(
            spots: [
              for (final p in run) FlSpot(_x(p), _norm(ch, p.valueOf(ch)!)),
            ],
            isCurved: true,
            curveSmoothness: 0.18,
            preventCurveOverShooting: true,
            color: color,
            barWidth: ch == EffortChannel.elevation ? 1.5 : 2.3,
            dotData: FlDotData(show: run.length == 1),
            belowBarData: BarAreaData(
              show: ch == EffortChannel.elevation,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.30),
                  color.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        );
      }
    }

    // Shared cursor: a vertical line plus a dot on every drawn channel.
    final cursor = _cursorX;
    final cp = cursor == null ? null : _pointAt(cursor);
    final cursorX = cp == null ? null : _x(cp);
    if (cp != null) {
      for (final ch in order) {
        final v = cp.valueOf(ch);
        if (v == null) continue;
        bars.add(
          LineChartBarData(
            spots: [FlSpot(cursorX!, _norm(ch, v))],
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 4.5,
                color: _color(c, ch),
                strokeWidth: 2.5,
                strokeColor: c.surface,
              ),
            ),
          ),
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        void setCursor(double dx) {
          if (w <= 0) return;
          setState(() => _cursorX = (dx / w).clamp(0.0, 1.0) * safeXMax);
        }

        return GestureDetector(
          key: const Key('effort-chart'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => setCursor(d.localPosition.dx),
          onHorizontalDragStart: (d) => setCursor(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => setCursor(d.localPosition.dx),
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: safeXMax,
              minY: 0,
              maxY: 1,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 0.25,
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
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    interval: (safeXMax / 4).clamp(0.5, double.infinity),
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value > safeXMax + 0.01) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${value.toStringAsFixed(1)} '
                          '${UnitUtils.unitLabel(widget.useMiles)}',
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
                border: Border(bottom: BorderSide(color: c.border, width: 1)),
              ),
              lineTouchData: const LineTouchData(enabled: false),
              extraLinesData: cursorX == null
                  ? null
                  : ExtraLinesData(
                      verticalLines: [
                        VerticalLine(
                          x: cursorX,
                          color: c.textTertiary.withValues(alpha: 0.9),
                          strokeWidth: 1.5,
                        ),
                      ],
                    ),
              lineBarsData: bars,
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Route preview painter
// ═══════════════════════════════════════════════════════════════════════════

class _RoutePreviewPainter extends CustomPainter {
  final List<Map<String, double>> points;
  final Color lineColor;
  final Color backgroundColor;
  final Color routeColor;
  final Color startColor;

  const _RoutePreviewPainter({
    required this.points,
    required this.lineColor,
    required this.backgroundColor,
    required this.routeColor,
    required this.startColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
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
        ..color = routeColor.withValues(alpha: 0.92)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    canvas.drawCircle(toOffset(points.first), 5, Paint()..color = startColor);
    canvas.drawCircle(toOffset(points.last), 5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(_RoutePreviewPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.routeColor != routeColor ||
      oldDelegate.startColor != startColor;
}
