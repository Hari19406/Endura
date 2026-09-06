// lib/screens/feed_screen.dart
//
// Tab 0 — the friends activity feed. Runs by athletes the signed-in user
// follows, newest first, with pull-to-refresh and keyset (cursor) pagination.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/athlete_profile.dart';
import '../models/feed_run.dart';
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_format_utils.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';
import '../widgets/route_trace_painter.dart';
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
// ─────────────────────────────────────────────────────────────────────────────

class RunFeedCard extends StatelessWidget {
  final FeedRun run;
  final VoidCallback onTapAthlete;

  const RunFeedCard({super.key, required this.run, required this.onTapAthlete});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final typeColor = WorkoutTypeStyle.color(run.workoutType);
    final points = run.points;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            GestureDetector(
              onTap: onTapAthlete,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  AthleteAvatar(
                    athlete: AthleteProfile(
                      id: run.athleteId,
                      displayName: run.displayName,
                      avatarUrl: run.avatarUrl,
                    ),
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          run.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (run.location != null) run.location!,
                            relativeTime(run.date),
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Title ───────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: typeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    run.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Stats ───────────────────────────────────────────────────
            ValueListenableBuilder<bool>(
              valueListenable: UnitUtils.useMilesNotifier,
              builder: (context, useMiles, _) {
                final stats = <_Stat>[
                  _Stat(
                    'Distance',
                    '${UnitUtils.displayDistance(run.distanceKm, useMiles).toStringAsFixed(2)} '
                        '${UnitUtils.unitLabel(useMiles)}',
                  ),
                  _Stat(
                    'Avg pace',
                    UnitUtils.formatPaceString(run.averagePace, useMiles),
                  ),
                  _Stat('Time', _fmtDuration(run.durationSeconds)),
                  if (run.elevationGain > 0)
                    _Stat('Elev', '${run.elevationGain.round()} m'),
                ];
                return Row(
                  children: [
                    for (final s in stats)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.value,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                                letterSpacing: -0.3,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.label.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: c.textTertiary,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),

            // ── Route thumbnail ─────────────────────────────────────────
            if (points.length > 1) ...[
              const SizedBox(height: 14),
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: RouteTracePainter(
                    points: points,
                    color: typeColor,
                    strokeWidth: 2.2,
                    padding: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmtDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '--';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _Stat {
  final String label;
  final String value;
  const _Stat(this.label, this.value);
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
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
