// lib/screens/athlete_profile_screen.dart
//
// Strava-style athlete profile. `athleteId == null` (or == the signed-in user)
// renders the own-profile variant with an Edit button and a live Stats tab
// computed from local run history. Another athlete renders a Follow toggle; the
// Stats tab is a privacy placeholder because `runs` is RLS-private per user.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../engines/pr_engine.dart';
import '../models/athlete_profile.dart';
import '../models/shoe.dart';
import '../services/best_efforts_service.dart';
import '../services/profile_service.dart';
import '../services/shoe_service.dart';
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';
import '../utils/unit_utils.dart';
import '../widgets/athlete_profile_header.dart';
import '../widgets/shoe_edit_sheet.dart';
import '../widgets/shoe_locker_view.dart';
import 'athlete_list_screen.dart';
import 'edit_athlete_profile_screen.dart';

class AthleteProfileScreen extends StatefulWidget {
  /// Null → the signed-in user's own profile.
  final String? athleteId;
  const AthleteProfileScreen({super.key, this.athleteId});

  @override
  State<AthleteProfileScreen> createState() => _AthleteProfileScreenState();
}

class _AthleteProfileScreenState extends State<AthleteProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  bool _loading = true;
  bool _isSelf = false;
  AthleteProfile? _profile;
  SocialCounts _counts = SocialCounts.zero;
  bool _isFollowing = false;
  bool _followBusy = false;

  List<Shoe> _shoes = [];
  _AthleteStats? _stats; // self only
  int _activityCount = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final targetId = widget.athleteId ?? myId;
    final isSelf = targetId != null && targetId == myId;

    if (targetId == null) {
      setState(() => _loading = false);
      return;
    }

    final profile = isSelf
        ? await ProfileService.instance.fetchAthleteProfile()
        : await SocialService.instance.getAthlete(targetId);

    final counts = await SocialService.instance.counts(targetId);
    final shoes = await ShoeService.instance.locker(userId: targetId);
    final following = isSelf
        ? false
        : await SocialService.instance.isFollowing(targetId);

    _AthleteStats? stats;
    int activityCount = 0;
    if (isSelf) {
      final runs = await DatabaseService.instance.getAllRuns();
      final bestEfforts = await DatabaseService.instance.getAllCategoryPRs();
      stats = _AthleteStats.fromRuns(runs, bestEfforts);
      activityCount = runs.length;
    }

    if (!mounted) return;
    setState(() {
      _isSelf = isSelf;
      _profile = profile;
      _counts = counts;
      _isFollowing = following;
      _shoes = shoes;
      _stats = stats;
      _activityCount = isSelf ? activityCount : 0;
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    final id = _profile?.id;
    if (id == null || _followBusy) return;

    // Optimistic: flip the button and the follower count immediately.
    final wasFollowing = _isFollowing;
    final prevCounts = _counts;
    setState(() {
      _followBusy = true;
      _isFollowing = !wasFollowing;
      _counts = SocialCounts(
        followers: (_counts.followers + (_isFollowing ? 1 : -1))
            .clamp(0, 1 << 30),
        following: _counts.following,
      );
    });

    final result = await SocialService.instance.toggleFollow(id);
    if (!mounted) return;
    setState(() {
      _followBusy = false;
      if (result == null) {
        // Write failed — roll back to the pre-tap state.
        _isFollowing = wasFollowing;
        _counts = prevCounts;
      } else {
        _isFollowing = result;
      }
    });
  }

  Future<void> _editProfile() async {
    final p = _profile;
    if (p == null) return;
    final updated = await Navigator.push<AthleteProfile>(
      context,
      MaterialPageRoute(builder: (_) => EditAthleteProfileScreen(profile: p)),
    );
    if (updated != null && mounted) setState(() => _profile = updated);
  }

  Future<void> _addOrEditShoe([Shoe? existing]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      builder: (_) => ShoeEditSheet(existing: existing),
    );
    if (changed == true) {
      final shoes = await ShoeService.instance.locker();
      if (mounted) setState(() => _shoes = shoes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _profile?.name ?? (_isSelf ? 'Profile' : 'Athlete'),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontSize: 18,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
          ? _NotFound(isSelf: _isSelf)
          : Column(
              children: [
                AthleteProfileHeader(
                  profile: _profile!,
                  counts: _counts,
                  isSelf: _isSelf,
                  isFollowing: _isFollowing,
                  activityCount: _isSelf ? _activityCount : null,
                  onEditProfile: _isSelf ? _editProfile : null,
                  onToggleFollow: _isSelf ? null : _toggleFollow,
                  onTapFollowers: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AthleteListScreen(
                        userId: _profile!.id,
                        mode: AthleteListMode.followers,
                      ),
                    ),
                  ),
                  onTapFollowing: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AthleteListScreen(
                        userId: _profile!.id,
                        mode: AthleteListMode.following,
                      ),
                    ),
                  ),
                ),
                TabBar(
                  controller: _tabs,
                  indicatorColor: c.accent,
                  indicatorWeight: 2,
                  labelColor: c.textPrimary,
                  unselectedLabelColor: c.textTertiary,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [Tab(text: 'Stats'), Tab(text: 'Gear')],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [_statsTab(context), _gearTab(context)],
                  ),
                ),
              ],
            ),
    );
  }

  // ── Stats tab ────────────────────────────────────────────────────────────

  Widget _statsTab(BuildContext context) {
    if (!_isSelf) return _publicStatsTab(context);
    final s = _stats;
    if (s == null || s.totalActivities == 0) {
      return _Placeholder(
        icon: Icons.timeline,
        text: 'No runs yet. Your stats will appear here.',
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: UnitUtils.useMilesNotifier,
      builder: (context, useMiles, _) {
        final unit = UnitUtils.unitLabel(useMiles);
        final pr = PREngine(s.prRuns, bestEfforts: s.bestEfforts).calculate();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _cardLabel(context, 'THIS WEEK'),
            const SizedBox(height: 12),
            _statRow(context, [
              _Metric(
                UnitUtils.displayDistance(s.weekKm, useMiles).toStringAsFixed(1),
                unit,
              ),
              _Metric(_fmtDuration(s.weekSeconds), 'time'),
              _Metric(s.weekRuns.toString(), s.weekRuns == 1 ? 'run' : 'runs'),
            ]),
            const SizedBox(height: 24),
            _cardLabel(context, 'ALL-TIME'),
            const SizedBox(height: 12),
            _statRow(context, [
              _Metric(
                UnitUtils.displayDistance(
                  s.totalKm,
                  useMiles,
                ).toStringAsFixed(0),
                unit,
              ),
              _Metric(_fmtDuration(s.totalSeconds), 'time'),
              _Metric(s.totalActivities.toString(), 'runs'),
            ]),
            const SizedBox(height: 12),
            _statRow(context, [
              _Metric(s.totalElevationM.toStringAsFixed(0), 'm elev'),
            ]),
            const SizedBox(height: 24),
            _cardLabel(context, 'PERSONAL RECORDS'),
            const SizedBox(height: 12),
            ...pr.allEntries.map((e) => _prRow(context, e)),
          ],
        );
      },
    );
  }

  Widget _prRow(BuildContext context, PREntry e) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            e.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                e.value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (e.unit != null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    e.unit!,
                    style: TextStyle(fontSize: 10, color: c.textTertiary),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Another athlete: high-level figures read from the denormalized aggregate
  /// columns on `profiles` (the raw `runs` table stays RLS-private).
  Widget _publicStatsTab(BuildContext context) {
    final p = _profile!;
    if (!p.hasPublicStats) {
      return _Placeholder(
        icon: Icons.timeline,
        text: 'No public stats yet.',
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: UnitUtils.useMilesNotifier,
      builder: (context, useMiles, _) {
        final unit = UnitUtils.unitLabel(useMiles);
        final km = p.totalDistanceMeters / 1000.0;
        final prs = <PREntry>[
          if (p.best5kSeconds != null)
            PREntry(label: 'Best 5K', value: _fmtClock(p.best5kSeconds!)),
          if (p.best10kSeconds != null)
            PREntry(label: 'Best 10K', value: _fmtClock(p.best10kSeconds!)),
          if (p.bestHalfMarathonSeconds != null)
            PREntry(
              label: 'Best half',
              value: _fmtClock(p.bestHalfMarathonSeconds!),
            ),
        ];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _cardLabel(context, 'ALL-TIME'),
            const SizedBox(height: 12),
            _statRow(context, [
              _Metric(
                UnitUtils.displayDistance(km, useMiles).toStringAsFixed(0),
                unit,
              ),
              _Metric(_fmtDuration(p.totalMovingSeconds), 'time'),
              _Metric(p.totalRuns.toString(), 'runs'),
            ]),
            const SizedBox(height: 12),
            _statRow(context, [
              _Metric(p.totalElevationMeters.toString(), 'm elev'),
            ]),
            if (prs.isNotEmpty) ...[
              const SizedBox(height: 24),
              _cardLabel(context, 'PERSONAL RECORDS'),
              const SizedBox(height: 12),
              ...prs.map((e) => _prRow(context, e)),
            ],
          ],
        );
      },
    );
  }

  static String _fmtClock(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  // ── Gear tab ─────────────────────────────────────────────────────────────

  Widget _gearTab(BuildContext context) => ShoeLockerView(
    shoes: _shoes,
    editable: _isSelf,
    onAdd: _isSelf ? () => _addOrEditShoe() : null,
    onEdit: _isSelf ? (s) => _addOrEditShoe(s) : null,
  );

  // ── small helpers ────────────────────────────────────────────────────────

  Widget _cardLabel(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: context.colors.textTertiary,
      letterSpacing: 1.2,
    ),
  );

  Widget _statRow(BuildContext context, List<_Metric> metrics) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: metrics
            .map(
              (m) => Expanded(
                child: Column(
                  children: [
                    Text(
                      m.value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.label,
                      style: TextStyle(fontSize: 11, color: c.textTertiary),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  static String _fmtDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    return '${m}m';
  }
}

// ── value types ────────────────────────────────────────────────────────────

class _Metric {
  final String value;
  final String label;
  _Metric(this.value, this.label);
}

class _AthleteStats {
  final double weekKm;
  final int weekSeconds;
  final int weekRuns;
  final double totalKm;
  final int totalSeconds;
  final int totalActivities;
  final double totalElevationM;
  final List<Run> prRuns;

  /// The athlete's #1 Best Effort per distance — the source of the 5K / 10K /
  /// half / marathon records (see PREngine).
  final Map<DistanceCategory, BestEffortRecord> bestEfforts;

  _AthleteStats({
    required this.weekKm,
    required this.weekSeconds,
    required this.weekRuns,
    required this.totalKm,
    required this.totalSeconds,
    required this.totalActivities,
    required this.totalElevationM,
    required this.prRuns,
    required this.bestEfforts,
  });

  factory _AthleteStats.fromRuns(
    List<RunRecord> runs,
    Map<DistanceCategory, BestEffortRecord> bestEfforts,
  ) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    double weekKm = 0, totalKm = 0, elev = 0;
    int weekSec = 0, totalSec = 0, weekRuns = 0;
    final prRuns = <Run>[];

    for (final r in runs) {
      totalKm += r.distanceKm;
      totalSec += r.durationSeconds;
      elev += r.elevationGain;
      prRuns.add(
        Run(
          distanceKm: r.distanceKm,
          durationSeconds: r.durationSeconds,
          date: r.date,
        ),
      );
      if (!r.date.isBefore(monday)) {
        weekKm += r.distanceKm;
        weekSec += r.durationSeconds;
        weekRuns++;
      }
    }

    return _AthleteStats(
      weekKm: weekKm,
      weekSeconds: weekSec,
      weekRuns: weekRuns,
      totalKm: totalKm,
      totalSeconds: totalSec,
      totalActivities: runs.length,
      totalElevationM: elev,
      prRuns: prRuns,
      bestEfforts: bestEfforts,
    );
  }
}

// ── small widgets ──────────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Placeholder({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  final bool isSelf;
  const _NotFound({required this.isSelf});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          isSelf
              ? 'Sign in to set up your athlete profile.'
              : 'This profile is unavailable or private.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textSecondary),
        ),
      ),
    );
  }
}
