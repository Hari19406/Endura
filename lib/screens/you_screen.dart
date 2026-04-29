import 'package:flutter/material.dart';
import '../utils/stats.dart';
import '../engines/pr_engine.dart';
import '../engines/achievement_engine.dart' as achieve;
import 'settings_screen.dart';
import '../utils/database_service.dart';
import 'run_detail_screen.dart';
import '../utils/refreshable.dart';


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
  List<dynamic> _runHistory = [];
  List<dynamic> _runRecords = [];

  bool _isLoading = true;
  String _errorMessage = '';
  late TabController _tabController;
  DateTime _selectedWeekStart = DateTime.now();
  DateTime _selectedDay = DateTime.now();



  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedWeekStart = _getWeekStart(DateTime.now());
    _selectedDay = _getLastRunDayInWeek(_selectedWeekStart);
    loadData();
  }

  @override
  void dispose() {
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
      List<achieve.Achievement> achievements =
          achieveEngine.checkAchievements();

      if (mounted) {
        setState(() {
          _stats = stats;
          _prResults = prResults;
          _achievements = achievements;
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

  void _openRunDetail(dynamic run, {dynamic record}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(run: run, record: record),
      ),
    );
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

  String _formatPaceFromMinutes(double paceMinPerKm) {
    if (paceMinPerKm <= 0) return '--:--';
    int minutes = paceMinPerKm.floor();
    int seconds = ((paceMinPerKm - minutes) * 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'You',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0A0A0A),
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: Color(0xFF666666),
              size: 22,
            ),
            onPressed: _navigateToSettings,
            tooltip: 'Settings',
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF000000),
          indicatorWeight: 2,
          labelColor: const Color(0xFF000000),
          unselectedLabelColor: const Color(0xFF999999),
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF000000)))
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Color(0xFF999999)),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage,
                        style: const TextStyle(
                            color: Color(0xFF666666), fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: loadData,
                        child: const Text('Retry',
                            style: TextStyle(color: Color(0xFF000000))),
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
      color: const Color(0xFF000000),
      onRefresh: loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [


              // ② THIS WEEK
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
            ],
          ),
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

    double selectedDayDistance = _getDistanceForDay(_selectedDay);
    String selectedDayText = selectedDayDistance > 0
        ? '${_getDayName(_selectedDay)} • ${selectedDayDistance.toStringAsFixed(1)} km'
        : _getDayName(_selectedDay);

    bool isCurrentWeek = _isSameWeek(_selectedWeekStart, DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'THIS WEEK',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF999999),
                  letterSpacing: 1.2,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left,
                        color: Color(0xFF999999), size: 20),
                    onPressed: () {
                      DateTime prevWeek = _selectedWeekStart
                          .subtract(const Duration(days: 7));
                      if (prevWeek.isBefore(DateTime.now()
                          .subtract(const Duration(days: 365)))) return;
                      setState(() {
                        _selectedWeekStart = prevWeek;
                        _selectedDay =
                            _getLastRunDayInWeek(_selectedWeekStart);
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
                        _selectedDay =
                            _getLastRunDayInWeek(_selectedWeekStart);
                      });
                    },
                    child: Text(
                      dateRangeText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_right,
                      color: isCurrentWeek
                          ? const Color(0xFFCCCCCC)
                          : const Color(0xFF999999),
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
                              _selectedDay =
                                  _getLastRunDayInWeek(_selectedWeekStart);
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
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
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
                            totalDistance.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF000000),
                              letterSpacing: -0.5,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4, left: 4),
                            child: Text(
                              'km',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF999999),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'DISTANCE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF999999),
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
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF000000),
                          letterSpacing: -0.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'TIME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF999999),
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
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF000000),
                          letterSpacing: -0.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        totalRuns == 1 ? 'RUN' : 'RUNS',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF999999),
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

          Center(
            child: Text(
              weekRuns.isEmpty ? 'No runs this week' : selectedDayText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: weekRuns.isEmpty
                    ? const Color(0xFF999999)
                    : const Color(0xFF000000),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildWeekBarChart(_selectedWeekStart, _selectedDay, (DateTime day) {
            setState(() {
              _selectedDay = day;
            });
          }),
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
    final records = [
      {
        'value': _formatPaceFromMinutes(_prResults!.fastest1KmPace),
        'label': 'FASTEST 1KM',
      },
      {
        'value': _formatPaceFromMinutes(_prResults!.bestAveragePace),
        'label': 'BEST AVG PACE',
      },
      {
        'value': _prResults!.longestDistance.toStringAsFixed(1),
        'label': 'LONGEST RUN',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PERSONAL RECORDS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF999999),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ...records.asMap().entries.map((entry) {
            int index = entry.key;
            var record = entry.value;
            return Container(
              margin: EdgeInsets.only(
                  bottom: index < records.length - 1 ? 12 : 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                border: Border.all(color: const Color(0xFFF0F0F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    record['label']!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF999999),
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    record['value']!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                      letterSpacing: -0.3,
                      fontFeatures: [FontFeature.tabularFigures()],
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

  Widget _buildMilestonesCard() {
    List<achieve.Achievement> sortedAchievements = List.from(_achievements)
      ..sort((a, b) {
        int tierCompare = b.tier.compareTo(a.tier);
        if (tierCompare != 0) return tierCompare;
        try {
          return b.unlockedAt.compareTo(a.unlockedAt);
        } catch (e) {
          return 0;
        }
      });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MILESTONES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF999999),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ...sortedAchievements.asMap().entries.map((entry) {
            int index = entry.key;
            var achievement = entry.value;
            return Container(
              margin: EdgeInsets.only(
                  bottom: index < sortedAchievements.length - 1 ? 12 : 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                border: Border.all(color: const Color(0xFFF0F0F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          achievement.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF000000),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Completed ${_formatAchievementDate(achievement.unlockedAt)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF999999),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _getTierColor(achievement.tier),
                      shape: BoxShape.circle,
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

  Color _getTierColor(int tier) {
    switch (tier) {
      case 1:  return const Color(0xFF8D6E63);
      case 2:  return const Color(0xFF9E9E9E);
      case 3:  return const Color(0xFFF9A825);
      case 4:  return const Color(0xFF7E57C2);
      default: return const Color(0xFF000000);
    }
  }

  String _formatAchievementDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0)   return 'today';
    if (difference.inDays == 1)   return 'yesterday';
    if (difference.inDays < 30)   return '${difference.inDays} days ago';
    return 'on ${date.day}/${date.month}/${date.year}';
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

    final Color statusColor;
    final String statusLabel;
    final String statusMessage;

    if (avgRpe == null) {
      statusColor = const Color(0xFF999999);
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TRAINING STATUS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF999999),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(color: statusColor, width: 3),
                top: const BorderSide(color: Color(0xFFE8E8E8)),
                right: const BorderSide(color: Color(0xFFE8E8E8)),
                bottom: const BorderSide(color: Color(0xFFE8E8E8)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'READINESS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF999999),
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF666666),
                    height: 1.5,
                  ),
                ),
                if (avgRpe != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Avg RPE (last ${rpeValues.length} runs): ${avgRpe.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
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
      color: const Color(0xFF000000),
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
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.directions_run,
                            size: 32,
                            color: Color(0xFFCCCCCC),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No runs yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF000000),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your first run will show here',
                        style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
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
    return GestureDetector(
      onTap: () => _openRunDetail(run, record: record),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8E8E8)),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${run.distance.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                      letterSpacing: -0.3,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDate(run.date),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  run.averagePace,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF000000),
                    letterSpacing: -0.2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'PER KM',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF999999),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                if (run.rpe != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'RPE ${run.rpe}/10',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF999999),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
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

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  List<dynamic> _getRunsInWeek(DateTime weekStart) {
    return _runHistory
        .where((run) => _isSameWeek(weekStart, run.date))
        .toList();
  }

  DateTime _getLastRunDayInWeek(DateTime weekStart) {
    List<dynamic> weekRuns = _getRunsInWeek(weekStart);
    if (weekRuns.isEmpty) return weekStart;
    weekRuns.sort((a, b) => b.date.compareTo(a.date));
    return DateTime(weekRuns.first.date.year, weekRuns.first.date.month,
        weekRuns.first.date.day);
  }

  double _getDistanceForDay(DateTime day) {
    return _runHistory
        .where((run) => _isSameDay(run.date, day))
        .fold(0.0, (sum, run) => sum + run.distance);
  }

  String _getDayName(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  Widget _buildWeekBarChart(DateTime weekStart, DateTime selectedDay,
      Function(DateTime) onDayTap) {
    Map<int, double> dailyDistances = {};
    for (int i = 0; i < 7; i++) {
      dailyDistances[i] = 0.0;
    }
    for (var run in _runHistory) {
      if (_isSameWeek(weekStart, run.date)) {
        int dayIndex = run.date.weekday - 1; // Mon=0 … Sun=6
        dailyDistances[dayIndex] =
            (dailyDistances[dayIndex] ?? 0) + run.distance;
      }
    }
    double maxDistance =
        dailyDistances.values.reduce((a, b) => a > b ? a : b);
    if (maxDistance == 0) maxDistance = 1;

    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(7, (index) {
          final distance = dailyDistances[index] ?? 0;
          final heightFactor = (distance / maxDistance).clamp(0.0, 1.0);
          final day = weekStart.add(Duration(days: index));
          final isSelected = _isSameDay(day, selectedDay);

          return Expanded(
            child: GestureDetector(
              onTap: () => onDayTap(day),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 120 * heightFactor,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF000000)
                            : distance > 0
                                ? const Color(0xFFCCCCCC)
                                : const Color(0xFFF0F0F0),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dayLabels[index],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF000000)
                            : const Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
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