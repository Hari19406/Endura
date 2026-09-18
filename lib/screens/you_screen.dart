import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../engines/pr_engine.dart';
import '../engines/achievement_engine.dart' as achieve;
import '../services/best_efforts_service.dart';
import 'best_efforts_detail_screen.dart';
import '../models/activity_telemetry.dart';
import '../models/athlete_profile.dart';
import '../models/shoe.dart';
import '../services/profile_service.dart';
import '../services/shoe_service.dart';
import '../services/social_service.dart';
import 'settings_screen.dart';
import '../utils/database_service.dart';
import 'activity_detail_screen.dart';
import 'feedback_screen.dart';
import '../utils/refreshable.dart';
import '../utils/unit_utils.dart';
import '../widgets/achievement_tile.dart';
import '../widgets/ambient_scaffold.dart';
import '../widgets/athlete_profile_header.dart';
import '../widgets/best_efforts_preview_card.dart';
import '../widgets/shoe_edit_sheet.dart';
import '../widgets/shoe_locker_view.dart';
import 'milestones_screen.dart';
import 'history_tab.dart';
import 'athlete_list_screen.dart';
import 'athlete_discovery_screen.dart';
import 'edit_athlete_profile_screen.dart';

class YouScreen extends StatefulWidget {
  const YouScreen({super.key});

  @override
  State<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends State<YouScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin
    implements Refreshable {
  @override
  bool get wantKeepAlive => true;

  PRResults? _prResults;
  Map<DistanceCategory, BestEffortRecord> _bestEfforts = {};
  List<achieve.Achievement> _achievements = [];
  List<String> _newAchievements = [];
  List<dynamic> _runHistory = [];
  List<dynamic> _runRecords = [];

  bool _isLoading = true;
  String _errorMessage = '';
  late TabController _tabController;
  DateTime _selectedWeekStart = DateTime.now();
  bool _useMiles = false;

  // ── Athlete identity header ───────────────────────────────────────────────
  AthleteProfile? _profile;
  SocialCounts _counts = SocialCounts.zero;
  List<Shoe> _shoes = [];
  int _activityCount = 0;
  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  /// Minimal profile built from the auth user, for when the `profiles` row
  /// isn't readable yet (first-time sync / missing row). Keeps the header from
  /// ever collapsing to nothing.
  AthleteProfile _fallbackProfile(User u) {
    final meta = u.userMetadata ?? const {};
    final metaName =
        (meta['name'] ?? meta['full_name'] ?? meta['display_name']) as String?;
    final name = (metaName != null && metaName.trim().isNotEmpty)
        ? metaName.trim()
        : (u.email != null && u.email!.contains('@')
              ? u.email!.split('@').first
              : null);
    return AthleteProfile(id: u.id, displayName: name);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedWeekStart = _getWeekStart(DateTime.now());
    _useMiles = UnitUtils.useMilesNotifier.value;
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
    loadData();
  }

  void _onUnitPrefChanged() {
    if (mounted) setState(() => _useMiles = UnitUtils.useMilesNotifier.value);
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Future<void> loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      List<dynamic> runs = await loadSavedRuns();
      final records = await DatabaseService.instance.getAllRuns();
      final bestEfforts = await DatabaseService.instance.getAllCategoryPRs();

      // ── Athlete identity header ──────────────────────────────────────────
      // Isolated: a Supabase hiccup here must not abort the whole load and
      // leave the header (and the rest of the You tab) blank.
      final myId = _myId;
      AthleteProfile? profile;
      SocialCounts counts = SocialCounts.zero;
      List<Shoe> shoes = const [];
      try {
        profile = await ProfileService.instance.fetchAthleteProfile();
        if (myId != null) {
          counts = await SocialService.instance.counts(myId);
        }
        shoes = await ShoeService.instance.locker();
      } catch (e, st) {
        debugPrint('[YouScreen] identity/header load failed: $e\n$st');
      }
      // fetchAthleteProfile() can return null on a first-time sync or a missing
      // row — fall back to the auth user so the header always renders.
      final authUser = Supabase.instance.client.auth.currentUser;
      profile ??= authUser != null ? _fallbackProfile(authUser) : null;

      List<Run> prRuns = runs
          .map(
            (r) => Run(
              distanceKm: r.distance,
              durationSeconds: _paceToSeconds(r.averagePace, r.distance),
              date: r.date,
            ),
          )
          .toList();

      List<achieve.RunData> achieveRunData = runs
          .map(
            (r) => achieve.RunData(
              distance: r.distance,
              pace: r.averagePace,
              date: r.date,
            ),
          )
          .toList();

      PREngine prEngine = PREngine(prRuns);
      PRResults prResults = prEngine.calculate();
      achieve.AchievementEngine achieveEngine = achieve.AchievementEngine(
        achieveRunData,
      );
      final List<achieve.Achievement> calculated = achieveEngine
          .checkAchievements();

      // Persist any newly earned achievements (INSERT OR IGNORE keeps dates frozen).
      final List<String> newlyUnlocked = [];
      for (final a in calculated) {
        final isNew = await DatabaseService.instance.saveAchievementIfNew(
          a.type.name,
          a.unlockedAt,
          a.tier,
        );
        if (isNew) newlyUnlocked.add(a.title);
      }

      // Merge calculated achievements with frozen unlock dates from DB.
      final frozenDates = await DatabaseService.instance.getAchievementDates();
      final List<achieve.Achievement> achievements = calculated.map((a) {
        final frozen = frozenDates[a.type.name];
        if (frozen == null) return a;
        return achieve.Achievement(
          type: a.type,
          title: a.title,
          description: a.description,
          unlockedAt: frozen,
          tier: a.tier,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _prResults = prResults;
          _bestEfforts = bestEfforts;
          _achievements = achievements;
          _newAchievements = newlyUnlocked;
          _runRecords = records;
          _runHistory = runs;
          _profile = profile;
          _counts = counts;
          _shoes = shoes;
          _activityCount = records.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading data: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _openRunDetail(RunRecord record) async {
    final id = record.id;
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ActivityDetailScreen(
          activity: ActivityDetail.fromRunRecord(
            record,
            runnerName: _profile?.displayName ?? 'You',
            avatarUrl: _profile?.avatarUrl,
          ),
          onDelete: id == null
              ? null
              : () => DatabaseService.instance.deleteRun(id),
        ),
      ),
    );
    if (deleted == true) loadData();
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  int _paceToSeconds(String pace, double distance) {
    if (pace == '--:--' || pace.isEmpty || distance <= 0) return 0;
    try {
      List<String> parts = pace.split(':');
      if (parts.length != 2) return 0;
      int minutes = int.parse(parts[0]);
      int seconds = int.parse(parts[1]);
      if (minutes < 0 || seconds < 0 || seconds >= 60) return 0;
      int paceSeconds = minutes * 60 + seconds;
      double totalSeconds = paceSeconds * distance;
      if (totalSeconds > 86400 || totalSeconds <= 0) return 0;
      return totalSeconds.round();
    } catch (e) {
      return 0;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
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

  void _openAthleteList(AthleteListMode mode) {
    final id = _myId;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AthleteListScreen(userId: id, mode: mode),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    return AmbientScaffold(
      safeArea: false,
      appBar: AppBar(
        title: Text(
          'You',
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AthleteDiscoveryScreen()),
            ),
            tooltip: 'Find runners',
          ),
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: c.textSecondary,
              size: 22,
            ),
            onPressed: _navigateToSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: c.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage,
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton(onPressed: loadData, child: const Text('Retry')),
                ],
              ),
            )
          : NestedScrollView(
              headerSliverBuilder: (context, _) => [
                // Always present — the header must never collapse to 0 height.
                SliverToBoxAdapter(
                  child: _profile != null
                      ? AthleteProfileHeader(
                          profile: _profile!,
                          counts: _counts,
                          isSelf: true,
                          activityCount: _activityCount,
                          onEditProfile: _editProfile,
                          onTapFollowers: () =>
                              _openAthleteList(AthleteListMode.followers),
                          onTapFollowing: () =>
                              _openAthleteList(AthleteListMode.following),
                        )
                      : const _ProfileHeaderSkeleton(),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    _SegmentedTabBar(controller: _tabController),
                    c.background,
                  ),
                ),
              ],
              // Tap-only: this TabBarView sits inside the root shell's own
              // horizontal PageView (Feed/Coach/Run/You), so letting it also
              // respond to horizontal drags would fight that outer swipe
              // gesture. The segmented pill above is how these sub-tabs are
              // meant to be switched.
              body: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildSummaryTab(),
                  HistoryTab(
                    records: _runRecords.cast<RunRecord>(),
                    onRefresh: loadData,
                    onOpenRun: _openRunDetail,
                  ),
                  ShoeLockerView(
                    shoes: _shoes,
                    editable: true,
                    onAdd: () => _addOrEditShoe(),
                    onEdit: (s) => _addOrEditShoe(s),
                  ),
                ],
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUMMARY TAB
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSummaryTab() {
    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        children: [
          // ① THIS WEEK
          _buildWeeklySummaryCard(),
          const SizedBox(height: 16),

          // ③ PERSONAL RECORDS
          if (_prResults != null && _runHistory.isNotEmpty) ...[
            _buildPersonalRecordsCard(),
            const SizedBox(height: 16),
          ],

          // ③b BEST EFFORTS
          if (_bestEfforts.isNotEmpty) ...[
            _buildBestEffortsCard(),
            const SizedBox(height: 16),
          ],

          // ④ MILESTONES
          if (_achievements.isNotEmpty) ...[
            _buildMilestonesCard(),
            const SizedBox(height: 16),
          ],

          // ⑤ FEEDBACK
          _buildFeedbackRow(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFeedbackRow() {
    final c = context.colors;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FeedbackScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.feedback_outlined, color: c.textSecondary, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Feedback & Support',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: c.textFaint, size: 20),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WEEKLY SUMMARY CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWeeklySummaryCard() {
    DateTime weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    String dateRangeText =
        '${_selectedWeekStart.day}–${weekEnd.day} ${_getMonthName(weekEnd.month)}';

    List<dynamic> weekRuns = _getRunsInWeek(_selectedWeekStart);
    double totalDistance = weekRuns.fold(0.0, (sum, run) => sum + run.distance);
    int totalSeconds = weekRuns.fold(
      0,
      (sum, run) => sum + _paceToSeconds(run.averagePace, run.distance),
    );
    String totalTime = _formatDuration(totalSeconds);
    int totalRuns = weekRuns.length;

    bool isCurrentWeek = _isSameWeek(_selectedWeekStart, DateTime.now());
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'THIS WEEK',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left,
                      color: c.textTertiary,
                      size: 20,
                    ),
                    onPressed: () {
                      DateTime prevWeek = _selectedWeekStart.subtract(
                        const Duration(days: 7),
                      );
                      if (prevWeek.isBefore(
                        DateTime.now().subtract(const Duration(days: 365)),
                      ))
                        return;
                      setState(() {
                        _selectedWeekStart = prevWeek;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedWeekStart = _getWeekStart(DateTime.now());
                      });
                    },
                    child: Text(
                      dateRangeText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_right,
                      color: isCurrentWeek ? c.textFaint : c.textTertiary,
                      size: 20,
                    ),
                    onPressed: isCurrentWeek
                        ? null
                        : () {
                            DateTime nextWeek = _selectedWeekStart.add(
                              const Duration(days: 7),
                            );
                            if (nextWeek.isAfter(DateTime.now())) return;
                            setState(() {
                              _selectedWeekStart = nextWeek;
                            });
                          },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            UnitUtils.displayDistance(
                              totalDistance,
                              _useMiles,
                            ).toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                              letterSpacing: -0.5,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4, left: 4),
                            child: Text(
                              UnitUtils.unitLabel(_useMiles),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: c.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'DISTANCE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: c.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        totalTime,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                          letterSpacing: -0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'TIME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: c.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$totalRuns',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                          letterSpacing: -0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        totalRuns == 1 ? 'RUN' : 'RUNS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: c.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'PAST 8 WEEKS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          _buildWeeklyTrendChart(_getWeeklyTotals(8)),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
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
    return months[month - 1];
  }

  Widget _buildPersonalRecordsCard() {
    final entries = _prResults!.allEntries;
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERSONAL RECORDS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ...entries.asMap().entries.map((entry) {
            final int index = entry.key;
            final pr = entry.value;
            return Container(
              margin: EdgeInsets.only(
                bottom: index < entries.length - 1 ? 12 : 0,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.background,
                border: Border.all(color: c.divider),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pr.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: c.textTertiary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (pr.setOn != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Set ${_formatDate(pr.setOn!)}',
                          style: TextStyle(fontSize: 10, color: c.textFaint),
                        ),
                      ],
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        pr.value,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                          letterSpacing: -0.3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (pr.unit != null)
                        Text(
                          pr.unit!,
                          style: TextStyle(fontSize: 10, color: c.textTertiary),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _openBestEffortsDetail(DistanceCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BestEffortsDetailScreen(
          initialCategory: category,
          runnerName: _profile?.displayName ?? 'You',
          avatarUrl: _profile?.avatarUrl,
        ),
      ),
    );
  }

  Widget _buildBestEffortsCard() {
    return BestEffortsPreviewCard(
      bestEfforts: _bestEfforts,
      onCategoryTap: _openBestEffortsDetail,
      onSeeAll: () => _openBestEffortsDetail(DistanceCategory.k5),
      formatDate: _formatDate,
    );
  }

  static const int _milestonesPreviewCount = 3;

  Widget _buildMilestonesCard() {
    final sortedAchievements = sortAchievements(_achievements);
    final preview = sortedAchievements.take(_milestonesPreviewCount).toList();
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MILESTONES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              if (sortedAchievements.length > _milestonesPreviewCount)
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          MilestonesScreen(achievements: _achievements),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: c.accent),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...preview.asMap().entries.map((entry) {
            final index = entry.key;
            return AchievementTile(
              achievement: entry.value,
              margin: EdgeInsets.only(
                bottom: index < preview.length - 1 ? 12 : 0,
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CALENDAR HELPERS — Monday-based (Mon=0 … Sun=6)
  // ─────────────────────────────────────────────────────────────────────────

  DateTime _getWeekStart(DateTime date) {
    int daysFromMonday = date.weekday - 1;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: daysFromMonday));
  }

  bool _isSameWeek(DateTime date1, DateTime date2) {
    return _getWeekStart(date1).isAtSameMomentAs(_getWeekStart(date2));
  }

  List<dynamic> _getRunsInWeek(DateTime weekStart) {
    return _runHistory
        .where((run) => _isSameWeek(weekStart, run.date))
        .toList();
  }

  /// Total distance per week for the [weeks] weeks ending at
  /// `_selectedWeekStart`, oldest first.
  List<double> _getWeeklyTotals(int weeks) {
    return List.generate(weeks, (i) {
      final weekStart = _selectedWeekStart.subtract(
        Duration(days: 7 * (weeks - 1 - i)),
      );
      return _getRunsInWeek(
        weekStart,
      ).fold(0.0, (sum, run) => sum + run.distance);
    });
  }

  Widget _buildWeeklyTrendChart(List<double> weeklyTotalsKm) {
    final c = context.colors;
    final weeklyTotals = weeklyTotalsKm
        .map((km) => UnitUtils.displayDistance(km, _useMiles))
        .toList();
    final maxDistance = weeklyTotals.fold(0.0, (m, v) => v > m ? v : m);
    final maxY = maxDistance <= 0 ? 10.0 : maxDistance * 1.2;
    final weeks = weeklyTotals.length;

    DateTime weekStartFor(int index) =>
        _selectedWeekStart.subtract(Duration(days: 7 * (weeks - 1 - index)));

    final spots = List.generate(
      weeks,
      (i) => FlSpot(i.toDouble(), weeklyTotals[i]),
    );

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY,
            getDrawingHorizontalLine: (value) =>
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
                interval: maxY,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '${value.toStringAsFixed(0)} ${UnitUtils.unitLabel(_useMiles)}',
                    style: TextStyle(fontSize: 10, color: c.textTertiary),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= weeks) {
                    return const SizedBox.shrink();
                  }
                  final month = weekStartFor(index).month;
                  final prevMonth = index == 0
                      ? null
                      : weekStartFor(index - 1).month;
                  if (month == prevMonth) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _getMonthName(month),
                      style: TextStyle(fontSize: 10, color: c.textTertiary),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: c.chartAccent,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.chartAccent.withOpacity(0.25),
                    c.chartAccent.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    return '${minutes}m';
  }
}

/// Pins the You-tab sub-tab bar below the (scroll-away) athlete profile header
/// inside the [NestedScrollView].
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final PreferredSizeWidget tabBar;
  final Color background;
  _SliverTabBarDelegate(this.tabBar, this.background);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: background, child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar || oldDelegate.background != background;
}

/// Stats / History / Gear as an elevated segmented pill instead of a flat
/// full-width bar with a Material underline indicator.
class _SegmentedTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;

  const _SegmentedTabBar({required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        height: 36,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border, width: 1),
        ),
        child: TabBar(
          controller: controller,
          // A Material 3 TabBar draws its own full-width bottom divider and
          // underline indicator by default — both are exactly the "flat
          // black bar" look being replaced, so both are switched off here.
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(2),
          indicator: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: c.accent.withValues(alpha: 0.28),
                blurRadius: 10,
                spreadRadius: -1,
              ),
            ],
          ),
          splashBorderRadius: BorderRadius.circular(8),
          labelColor: c.textPrimary,
          unselectedLabelColor: c.textTertiary,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: 'Stats'),
            Tab(text: 'History'),
            Tab(text: 'Gear'),
          ],
        ),
      ),
    );
  }
}

/// Shown in the header slot for the brief window before the profile resolves
/// (or if there's no auth user at all) so the layout never jumps.
class _ProfileHeaderSkeleton extends StatelessWidget {
  const _ProfileHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.divider,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 34, backgroundColor: c.divider),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(140, 18),
                  const SizedBox(height: 8),
                  bar(90, 12),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          bar(double.infinity, 40),
          const SizedBox(height: 14),
          bar(double.infinity, 40),
        ],
      ),
    );
  }
}
