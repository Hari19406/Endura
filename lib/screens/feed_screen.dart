// lib/screens/feed_screen.dart
//
// Tab 0 — the friends activity feed. Runs by athletes the signed-in user
// follows, newest first, with pull-to-refresh and keyset (cursor) pagination.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/activity_telemetry.dart';
import '../models/athlete_profile.dart';
import '../models/feed_run.dart';
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_format_utils.dart';
import '../utils/unit_utils.dart';
import '../widgets/route_trace_painter.dart';
import '../widgets/run_comments_sheet.dart';
import 'activity_detail_screen.dart';
import 'athlete_discovery_screen.dart';
import 'athlete_list_screen.dart' show AthleteAvatar;
import 'athlete_profile_screen.dart';
import 'notifications_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 15;
  static const _infiniteScrollThreshold = 200.0;

  final ScrollController _scrollController = ScrollController();

  final List<FeedRun> _runs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _infiniteScrollThreshold) {
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = _runs.isEmpty;
        _error = null;
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }

    final before = refresh || _runs.isEmpty ? null : _runs.last.date;
    try {
      final page = await SocialService.instance.fetchFriendsFeed(
        before: before,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) _runs.clear();
        _runs.addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (refresh && _runs.isEmpty) _error = e;
      });
    }
  }

  void _openDiscovery() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AthleteDiscoveryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(
          'Activity Feed',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: c.textSecondary, size: 22),
            tooltip: 'Find runners',
            onPressed: _openDiscovery,
          ),
          IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              color: c.textSecondary,
              size: 22,
            ),
            tooltip: 'Notifications',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: c.accent,
        onRefresh: () => _load(refresh: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _runs.isEmpty) {
      return _FeedMessage(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load the feed",
        body: 'Check your connection and pull to refresh.',
      );
    }
    if (_runs.isEmpty) {
      return _EmptyFeed(onFindRunners: _openDiscovery);
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _runs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _runs.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RunFeedCard(
            run: _runs[i],
            onTapAthlete: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AthleteProfileScreen(athleteId: _runs[i].athleteId),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY CARD
//
// Deliberately a single (dark) look — the feed is a premium dark surface
// regardless of the app theme, so colours here are fixed rather than tokens.
// ─────────────────────────────────────────────────────────────────────────────

class _FeedPalette {
  static const surface = Color(0xFF12161A);
  static const border = Color(0xFF23262B);
  static const pill = Color(0xFF1A1F25);
  static const mapBase = Color(0xFF0E1114);
  static const route = Color(0xFF00B2FF);
  static const textHigh = Color(0xFFF3F5F7);
  static const textMid = Color(0xFF9BA3AD);
  static const textLow = Color(0xFF6A7178);
}

class RunFeedCard extends StatefulWidget {
  final FeedRun run;
  final VoidCallback onTapAthlete;

  const RunFeedCard({super.key, required this.run, required this.onTapAthlete});

  @override
  State<RunFeedCard> createState() => _RunFeedCardState();
}

class _RunFeedCardState extends State<RunFeedCard> {
  bool _kudosed = false;
  late int _comments = widget.run.commentCount;

  FeedRun get run => widget.run;

  void _snack(String msg) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Opens the full activity detail view. Reaction / comment-count changes
  /// made in there are applied back onto this card immediately (via the
  /// screen's `onReactedChanged` / `onCommentCountChanged`), not just on pop —
  /// so they survive however the athlete leaves that screen.
  Future<void> _openActivity() {
    HapticFeedback.lightImpact();
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityDetailScreen(
          activity: ActivityDetail.fromFeedRun(run, commentCountOverride: _comments),
          initialReacted: _kudosed,
          onReactedChanged: (v) {
            if (mounted) setState(() => _kudosed = v);
          },
          onCommentCountChanged: (v) {
            if (mounted) setState(() => _comments = v);
          },
        ),
      ),
    );
  }

  Future<void> _openComments() async {
    HapticFeedback.lightImpact();
    final count = await showRunCommentsSheet(
      context,
      runId: run.runId,
      initialCount: _comments,
    );
    if (mounted && count != _comments) setState(() => _comments = count);
  }

  Future<void> _share() async {
    HapticFeedback.lightImpact();
    final useMiles = UnitUtils.useMilesNotifier.value;
    final dist =
        '${UnitUtils.displayDistance(run.distanceKm, useMiles).toStringAsFixed(2)} '
        '${UnitUtils.unitLabel(useMiles)}';
    final text =
        "Check out ${run.displayName}'s $dist run on Endura! "
        'Time: ${_fmtDuration(run.durationSeconds)}, '
        'Pace: ${UnitUtils.formatPaceString(run.averagePace, useMiles)}.';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final points = run.points;
    return GestureDetector(
      onTap: _openActivity,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: _FeedPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _FeedPalette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  run.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _FeedPalette.textHigh,
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _statRibbon(),
              if (run.planName != null) ...[
                const SizedBox(height: 12),
                _planPill(),
              ],
              if (points.length > 1) ...[
                const SizedBox(height: 14),
                _map(points),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1, color: _FeedPalette.border),
              const SizedBox(height: 6),
              _socialBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.onTapAthlete,
          behavior: HitTestBehavior.opaque,
          child: AthleteAvatar(
            athlete: AthleteProfile(
              id: run.athleteId,
              displayName: run.displayName,
              avatarUrl: run.avatarUrl,
            ),
            radius: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: widget.onTapAthlete,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        run.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _FeedPalette.textHigh,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (run.isSubscribed) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.verified,
                        size: 14,
                        color: _FeedPalette.route,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${relativeTime(run.date)}  ·  ${run.source}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _FeedPalette.textMid,
                  ),
                ),
                if (run.location != null && run.location!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.public,
                        size: 12,
                        color: _FeedPalette.textLow,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          run.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _FeedPalette.textLow,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(
          width: 36,
          height: 36,
          child: PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_horiz,
              size: 20,
              color: _FeedPalette.textMid,
            ),
            padding: EdgeInsets.zero,
            color: _FeedPalette.pill,
            onSelected: (v) {
              if (v == 'profile') {
                widget.onTapAthlete();
              } else if (v == 'report') {
                _snack('Thanks — we\'ll take a look.');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'profile',
                child: Text(
                  'View profile',
                  style: TextStyle(color: _FeedPalette.textHigh),
                ),
              ),
              PopupMenuItem(
                value: 'report',
                child: Text(
                  'Report activity',
                  style: TextStyle(color: _FeedPalette.textHigh),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 4-stat ribbon ──────────────────────────────────────────────────────────

  Widget _statRibbon() {
    return ValueListenableBuilder<bool>(
      valueListenable: UnitUtils.useMilesNotifier,
      builder: (context, useMiles, _) {
        final cells = <(String, String)>[
          (
            'Distance',
            '${UnitUtils.displayDistance(run.distanceKm, useMiles).toStringAsFixed(2)} '
                '${UnitUtils.unitLabel(useMiles)}',
          ),
          ('Pace', UnitUtils.formatPaceString(run.averagePace, useMiles)),
          ('Time', _fmtDuration(run.durationSeconds)),
          (
            'Elev Gain',
            run.elevationGain > 0 ? '${run.elevationGain.round()} m' : '--',
          ),
        ];
        return Row(
          children: [
            for (final (label, value) in cells)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _FeedPalette.textLow,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _FeedPalette.textHigh,
                        letterSpacing: -0.3,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Training-plan pill ─────────────────────────────────────────────────────

  Widget _planPill() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _FeedPalette.pill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _FeedPalette.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 16, color: _FeedPalette.route),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.planName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _FeedPalette.textHigh,
                  ),
                ),
                if (run.planProgress != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    run.planProgress!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _FeedPalette.textMid,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _snack('Plan details are coming soon.'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _FeedPalette.route.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'View',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _FeedPalette.route,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Route map ──────────────────────────────────────────────────────────────

  Widget _map(List<Map<String, double>> points) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 224,
        width: double.infinity,
        color: _FeedPalette.mapBase,
        child: CustomPaint(
          size: Size.infinite,
          painter: RouteTracePainter(
            points: points,
            color: _FeedPalette.route,
            strokeWidth: 3.5,
            padding: 18,
          ),
        ),
      ),
    );
  }

  // ── Social interaction bar ─────────────────────────────────────────────────

  Widget _socialBar() {
    return Row(
      children: [
        Icon(
          _kudosed
              ? Icons.local_fire_department
              : Icons.local_fire_department_outlined,
          size: 18,
          color: _kudosed ? _FeedPalette.route : _FeedPalette.textLow,
        ),
        const SizedBox(width: 6),
        Text(
          _kudosed ? 'You reacted' : 'Be the first to react',
          style: const TextStyle(fontSize: 12, color: _FeedPalette.textMid),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(Icons.share, size: 18, color: _FeedPalette.textMid),
          onPressed: _share,
        ),
        const SizedBox(width: 4),
        _commentAction(),
        const SizedBox(width: 4),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(
            _kudosed ? Icons.favorite : Icons.favorite_border,
            size: 19,
            color: _kudosed ? _FeedPalette.route : _FeedPalette.textMid,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _kudosed = !_kudosed);
          },
        ),
      ],
    );
  }

  Widget _commentAction() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(
            Icons.mode_comment_outlined,
            size: 18,
            color: _FeedPalette.textMid,
          ),
          onPressed: _openComments,
        ),
        if (_comments > 0)
          Positioned(
            right: 0,
            top: 2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: _FeedPalette.route,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$_comments',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B0B0C),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _fmtDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '--';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY / ERROR STATES
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyFeed extends StatelessWidget {
  final VoidCallback onFindRunners;
  const _EmptyFeed({required this.onFindRunners});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(Icons.group_outlined, size: 40, color: c.textTertiary),
              const SizedBox(height: 16),
              Text(
                'See what friends are up to',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Follow other runners and their workouts will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: c.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onFindRunners,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Find Runners',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _FeedMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 24),
      children: [
        Icon(icon, size: 40, color: c.textTertiary),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
        ),
      ],
    );
  }
}
