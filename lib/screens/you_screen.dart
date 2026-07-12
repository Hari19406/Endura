import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_colors.dart';
import '../utils/stats.dart';
import '../engines/pr_engine.dart';
import '../engines/achievement_engine.dart' as achieve;
import 'settings_screen.dart';
import '../utils/database_service.dart';
import 'run_detail_screen.dart';
import 'feedback_screen.dart';
import '../utils/refreshable.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';


class YouScreen extends StatefulWidget {
  const YouScreen({super.key});

  @override
  State<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends State<YouScreen>
    with SingleTickerProviderStateMixin
    implements Refreshable {
  WeeklyStats? _stats;
  PRResults? _prResults;
  List<achieve.Achievement> _achievements = [];
  List<String> _newAchievements = [];
  List<dynamic> _runHistory = [];
  List<dynamic> _runRecords = [];

  bool _isLoading = true;
  String _errorMessage = '';
  late TabController _tabController;
  DateTime _selectedWeekStart = DateTime.now();
  bool _useMiles = false;



  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      WeeklyStats stats = await getWeeklyStats();
      List<dynamic> runs = await loadSavedRuns();
      final records = await DatabaseService.instance.getAllRuns();

      List<Run> prRuns = runs
          .map((r) => Run(
                distanceKm: r.distance,
                durationSeconds: _paceToSeconds(r.averagePace, r.distance),
                date: r.date,
              ))
          .toList();

      List<achieve.RunData> achieveRunData = runs
          .map((r) => achieve.RunData(
                distance: r.distance,
                pace: r.averagePace,
                date: r.date,
              ))
          .toList();

      PREngine prEngine = PREngine(prRuns);
      PRResults prResults = prEngine.calculate();
      achieve.AchievementEngine achieveEngine =
          achieve.AchievementEngine(achieveRunData);
      final List<achieve.Achievement> calculated =
          achieveEngine.checkAchievements();

      // Persist any newly earned achievements (INSERT OR IGNORE keeps dates frozen).
      final List<String> newlyUnlocked = [];
      for (final a in calculated) {
        final isNew = await DatabaseService.instance.saveAchievementIfNew(
          a.type.name, a.unlockedAt, a.tier,
        );
        if (isNew) newlyUnlocked.add(a.title);
      }

      // Merge calculated achievements with frozen unlock dates from DB.
      final frozenDates =
          await DatabaseService.instance.getAchievementDates();
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
          _stats = stats;
          _prResults = prResults;
          _achievements = achievements;
          _newAchievements = newlyUnlocked;
          _runRecords = records;
          _runHistory = runs;
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

  void _openRunDetail(dynamic run, {dynamic record}) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(run: run, record: record),
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
    if (difference.inDays == 0)      return 'Today';
    if (difference.inDays == 1)      return 'Yesterday';
    if (difference.inDays < 7)       return '${difference.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
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
            icon: Icon(
              Icons.settings_outlined,
              color: c.textSecondary,
              size: 22,
            ),
            onPressed: _navigateToSettings,
            tooltip: 'Settings',
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: c.accent,
          indicatorWeight: 2,
          labelColor: c.textPrimary,
          unselectedLabelColor: c.textTertiary,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: c.textTertiary),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage,
                        style: TextStyle(
                            color: c.textSecondary, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSummaryTab(),
                    _buildHistoryTab(),
                  ],
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
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ① THIS WEEK
              _buildWeeklySummaryCard(),
              const SizedBox(height: 16),

              // ③ PERSONAL RECORDS
              if (_prResults != null && _runHistory.isNotEmpty) ...[
                _buildPersonalRecordsCard(),
                const SizedBox(height: 16),
              ],

              // ④ MILESTONES
              if (_achievements.isNotEmpty) ...[
                _buildMilestonesCard(),
                const SizedBox(height: 16),
              ],

              // ⑤ TRAINING STATUS
              if (_stats != null && _stats!.totalRuns > 0) ...[
                _buildTrainingStatusCard(),
                const SizedBox(height: 16),
              ],

              // ⑥ FEEDBACK
              _buildFeedbackRow(),
              const SizedBox(height: 8),
            ],
          ),
        ),
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
    double totalDistance =
        weekRuns.fold(0.0, (sum, run) => sum + run.distance);
    int totalSeconds = weekRuns.fold(
        0, (sum, run) => sum + _paceToSeconds(run.averagePace, run.distance));
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
                    icon: Icon(Icons.chevron_left,
                        color: c.textTertiary, size: 20),
                    onPressed: () {
                      DateTime prevWeek = _selectedWeekStart
                          .subtract(const Duration(days: 7));
                      if (prevWeek.isBefore(DateTime.now()
                          .subtract(const Duration(days: 365)))) return;
                      setState(() {
                        _selectedWeekStart = prevWeek;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
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
                      color: isCurrentWeek
                          ? c.textFaint
                          : c.textTertiary,
                      size: 20,
                    ),
                    onPressed: isCurrentWeek
                        ? null
                        : () {
                            DateTime nextWeek = _selectedWeekStart
                                .add(const Duration(days: 7));
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
                            UnitUtils.displayDistance(totalDistance, _useMiles).toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                              letterSpacing: -0.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
              margin:
                  EdgeInsets.only(bottom: index < entries.length - 1 ? 12 : 0),
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
                          style: TextStyle(
                            fontSize: 10,
                            color: c.textFaint,
                          ),
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
                          style: TextStyle(
                            fontSize: 10,
                            color: c.textTertiary,
                          ),
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

  Widget _buildMilestonesCard() {
    final List<achieve.Achievement> sortedAchievements =
        List.from(_achievements)
          ..sort((a, b) {
            final int tierCompare = b.tier.compareTo(a.tier);
            if (tierCompare != 0) return tierCompare;
            return b.unlockedAt.compareTo(a.unlockedAt);
          });

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
            'MILESTONES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ...sortedAchievements.asMap().entries.map((entry) {
            final int index = entry.key;
            final achievement = entry.value;
            return Container(
              margin: EdgeInsets.only(
                  bottom: index < sortedAchievements.length - 1 ? 12 : 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.background,
                border: Border.all(color: c.divider),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          achievement.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTierBadge(achievement.tier),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    achievement.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _formatAchievementDate(achievement.unlockedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: c.textFaint,
                      fontWeight: FontWeight.w500,
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

  Widget _buildTierBadge(int tier) {
    final (Color bg, Color text, String label) = switch (tier) {
      1 => (const Color(0xFFF0997B), const Color(0xFF4A1B0C), 'Bronze'),
      2 => (const Color(0xFFD3D1C7), const Color(0xFF444441), 'Silver'),
      3 => (const Color(0xFFFAC775), const Color(0xFF412402), 'Gold'),
      4 => (const Color(0xFFCECBF6), const Color(0xFF26215C), 'Platinum'),
      _ => (const Color(0xFFE8E8E8), const Color(0xFF666666), 'Bronze'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: text,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String _formatAchievementDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'Earned today';
    if (diff == 1) return 'Earned yesterday';
    if (diff < 30) return 'Earned $diff days ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Earned ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _buildTrainingStatusCard() {
    final recentRuns = _runHistory.take(3).toList();
    final rpeValues = recentRuns
        .where((r) => r.rpe != null)
        .map<double>((r) => (r.rpe as num).toDouble())
        .toList();
    final avgRpe = rpeValues.isEmpty
        ? null
        : rpeValues.reduce((a, b) => a + b) / rpeValues.length;

    final c = context.colors;
    final Color statusColor;
    final String statusLabel;
    final String statusMessage;

    if (avgRpe == null) {
      statusColor = c.textTertiary;
      statusLabel = 'No data';
      statusMessage = 'Complete a few runs with RPE feedback to see your training status.';
    } else if (avgRpe >= 7.0) {
      statusColor = const Color(0xFFD32F2F);
      statusLabel = 'High effort';
      statusMessage = 'Recent runs have felt hard. Consider an easy day or rest.';
    } else if (avgRpe >= 5.5) {
      statusColor = const Color(0xFFF57C00);
      statusLabel = 'Moderate';
      statusMessage = 'Effort is building. Monitor how you feel before pushing harder.';
    } else {
      statusColor = const Color(0xFF388E3C);
      statusLabel = 'On track';
      statusMessage = 'Effort levels look good. You\'re managing load well.';
    }

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
            'TRAINING STATUS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(
                left: BorderSide(color: statusColor, width: 3),
                top: BorderSide(color: c.border),
                right: BorderSide(color: c.border),
                bottom: BorderSide(color: c.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'READINESS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      statusLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  statusMessage,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textSecondary,
                    height: 1.5,
                  ),
                ),
                if (avgRpe != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Avg RPE (last ${rpeValues.length} runs): ${avgRpe.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY TAB
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: loadData,
      child: _runHistory.isEmpty
          ? Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: context.colors.divider,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.directions_run,
                            size: 32,
                            color: context.colors.textFaint,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No runs yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your first run will show here',
                        style: TextStyle(
                            fontSize: 13, color: context.colors.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _runHistory.length,
              itemBuilder: (context, index) {
                final run = _runHistory[index];
                final record =
                    index < _runRecords.length ? _runRecords[index] : null;
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: index < _runHistory.length - 1 ? 12 : 0),
                  child: _buildRunHistoryCard(run, record: record),
                );
              },
            ),
    );
  }

  Widget _buildRunHistoryCard(dynamic run, {dynamic record}) {
    final c = context.colors;
    final workoutType = record?.workoutType as String? ?? 'easy';
    final durationSeconds = record?.durationSeconds as int?;
    final typeLabel = WorkoutTypeStyle.label(workoutType);
    final typeColor = WorkoutTypeStyle.color(workoutType);

    return GestureDetector(
      onTap: () => _openRunDetail(run, record: record),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(run.date),
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${UnitUtils.displayDistance(run.distance, _useMiles).toStringAsFixed(1)} ${UnitUtils.unitLabel(_useMiles)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      letterSpacing: -0.3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      UnitUtils.formatPaceString(run.averagePace, _useMiles),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                        letterSpacing: -0.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PER ${_useMiles ? 'MI' : 'KM'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: c.textTertiary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (durationSeconds != null || run.rpe != null) ...[
              const SizedBox(height: 10),
              Divider(color: c.divider, height: 1, thickness: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (durationSeconds != null) ...[
                    Icon(Icons.schedule, size: 13, color: c.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(durationSeconds),
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (durationSeconds != null && run.rpe != null)
                    const SizedBox(width: 14),
                  if (run.rpe != null) ...[
                    Icon(Icons.speed, size: 13, color: c.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      'RPE ${run.rpe}/10',
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CALENDAR HELPERS — Monday-based (Mon=0 … Sun=6)
  // ─────────────────────────────────────────────────────────────────────────

  DateTime _getWeekStart(DateTime date) {
    int daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: daysFromMonday));
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
      final weekStart =
          _selectedWeekStart.subtract(Duration(days: 7 * (weeks - 1 - i)));
      return _getRunsInWeek(weekStart)
          .fold(0.0, (sum, run) => sum + run.distance);
    });
  }

  Widget _buildWeeklyTrendChart(List<double> weeklyTotalsKm) {
    final c = context.colors;
    final weeklyTotals = weeklyTotalsKm
        .map((km) => UnitUtils.displayDistance(km, _useMiles))
        .toList();
    final maxDistance =
        weeklyTotals.fold(0.0, (m, v) => v > m ? v : m);
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
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                  final prevMonth =
                      index == 0 ? null : weekStartFor(index - 1).month;
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