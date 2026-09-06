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
import '../services/profile_service.dart';
import '../services/shoe_service.dart';
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';
import '../utils/unit_utils.dart';
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
      stats = _AthleteStats.fromRuns(runs);
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
    setState(() => _followBusy = true);
    final s = SocialService.instance;
    final ok = _isFollowing ? await s.unfollow(id) : await s.follow(id);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _isFollowing = !_isFollowing;
        _counts = SocialCounts(
          followers: (_counts.followers + (_isFollowing ? 1 : -1))
              .clamp(0, 1 << 30),
          following: _counts.following,
        );
      }
      _followBusy = false;
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
      builder: (_) => _ShoeEditSheet(existing: existing),
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
                _header(context),
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

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    final c = context.colors;
    final p = _profile!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AthleteAvatar(athlete: p, radius: 34),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (p.username != null)
                      Text(
                        '@${p.username}',
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                    if (p.location != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: c.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            p.location!,
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (p.bio != null && p.bio!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              p.bio!.trim(),
              style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          _socialBar(context),
          const SizedBox(height: 14),
          _actionButton(context),
        ],
      ),
    );
  }

  Widget _socialBar(BuildContext context) {
    final id = _profile!.id;
    return Row(
      children: [
        _statCell(
          context,
          _counts.followers.toString(),
          'Followers',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AthleteListScreen(
                userId: id,
                mode: AthleteListMode.followers,
              ),
            ),
          ),
        ),
        _statCell(
          context,
          _counts.following.toString(),
          'Following',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AthleteListScreen(
                userId: id,
                mode: AthleteListMode.following,
              ),
            ),
          ),
        ),
        _statCell(
          context,
          _isSelf ? _activityCount.toString() : '—',
          'Activities',
        ),
      ],
    );
  }

  Widget _statCell(
    BuildContext context,
    String value,
    String label, {
    VoidCallback? onTap,
  }) {
    final c = context.colors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(BuildContext context) {
    final c = context.colors;
    if (_isSelf) {
      return _OutlineButton(label: 'Edit Profile', onTap: _editProfile);
    }
    final following = _isFollowing;
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: following ? c.surface : c.accent,
          border: Border.all(color: following ? c.border : c.accent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: _followBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                following ? 'Following' : 'Follow',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: following ? c.textPrimary : c.onAccent,
                ),
              ),
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
        final pr = PREngine(s.prRuns).calculate();
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

  _AthleteStats({
    required this.weekKm,
    required this.weekSeconds,
    required this.weekRuns,
    required this.totalKm,
    required this.totalSeconds,
    required this.totalActivities,
    required this.totalElevationM,
    required this.prRuns,
  });

  factory _AthleteStats.fromRuns(List<RunRecord> runs) {
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
    );
  }
}

// ── small widgets ──────────────────────────────────────────────────────────

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
      ),
    );
  }
}

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

// ── Add / edit shoe sheet ──────────────────────────────────────────────────

class _ShoeEditSheet extends StatefulWidget {
  final Shoe? existing;
  const _ShoeEditSheet({this.existing});

  @override
  State<_ShoeEditSheet> createState() => _ShoeEditSheetState();
}

class _ShoeEditSheetState extends State<_ShoeEditSheet> {
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _nickname;
  late final TextEditingController _startKm;
  late final TextEditingController _maxKm;
  late bool _isDefault;
  late bool _isRetired;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _brand = TextEditingController(text: s?.brand ?? '');
    _model = TextEditingController(text: s?.model ?? '');
    _nickname = TextEditingController(text: s?.nickname ?? '');
    _startKm = TextEditingController(
      text: s == null ? '' : s.distanceKm.toStringAsFixed(0),
    );
    _maxKm = TextEditingController(
      text: (s?.maxDistanceKm ?? 800).toStringAsFixed(0),
    );
    _isDefault = s?.isDefault ?? false;
    _isRetired = s?.isRetired ?? false;
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _nickname.dispose();
    _startKm.dispose();
    _maxKm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_brand.text.trim().isEmpty || _model.text.trim().isEmpty) return;
    setState(() => _busy = true);

    final svc = ShoeService.instance;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final startMeters = (double.tryParse(_startKm.text.trim()) ?? 0) * 1000;
    final maxMeters = (double.tryParse(_maxKm.text.trim()) ?? 800) * 1000;

    bool ok;
    if (_isEdit) {
      ok = await svc.update(
        widget.existing!.copyWith(
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          nickname: _nickname.text.trim().isEmpty
              ? null
              : _nickname.text.trim(),
          distanceMeters: startMeters,
          maxDistanceMeters: maxMeters,
          isDefault: _isDefault,
          isRetired: _isRetired,
        ),
      );
    } else {
      final created = await svc.add(
        Shoe(
          userId: uid,
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          nickname: _nickname.text.trim().isEmpty
              ? null
              : _nickname.text.trim(),
          distanceMeters: startMeters,
          maxDistanceMeters: maxMeters,
          isDefault: _isDefault,
        ),
      );
      ok = created != null;
    }

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _busy = true);
    final ok = await ShoeService.instance.delete(id);
    if (!mounted) return;
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEdit ? 'Edit shoe' : 'Add a shoe',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _tf(context, 'Brand', _brand),
          _tf(context, 'Model', _model),
          _tf(context, 'Nickname (optional)', _nickname),
          Row(
            children: [
              Expanded(child: _tf(context, 'Start dist (km)', _startKm, number: true)),
              const SizedBox(width: 12),
              Expanded(child: _tf(context, 'Target (km)', _maxKm, number: true)),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
            title: Text(
              'Default shoe',
              style: TextStyle(fontSize: 14, color: c.textPrimary),
            ),
            activeThumbColor: c.accent,
          ),
          if (_isEdit)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isRetired,
              onChanged: (v) => setState(() => _isRetired = v),
              title: Text(
                'Retired',
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
              activeThumbColor: c.accent,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_isEdit)
                TextButton(
                  onPressed: _busy ? null : _delete,
                  child: Text('Delete', style: TextStyle(color: c.danger)),
                ),
              const Spacer(),
              GestureDetector(
                onTap: _busy ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Save',
                          style: TextStyle(
                            color: c.onAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tf(
    BuildContext context,
    String label,
    TextEditingController controller, {
    bool number = false,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: TextStyle(color: c.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: c.textTertiary, fontSize: 13),
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.accent),
          ),
        ),
      ),
    );
  }
}
