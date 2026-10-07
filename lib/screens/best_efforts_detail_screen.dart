// lib/screens/best_efforts_detail_screen.dart
//
// Full Best Efforts leaderboard: a tab per benchmark distance, each showing
// the top-10 fastest recorded segments for that distance. Tapping a row
// opens the run it came from.

import 'package:flutter/material.dart';

import '../models/activity_telemetry.dart';
import '../services/athlete_pace_zones.dart';
import '../services/athlete_physiology.dart';
import '../utils/pace_analytics.dart';
import '../services/best_efforts_service.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';
import '../utils/unit_utils.dart';
import '../widgets/ambient_scaffold.dart';
import '../widgets/best_effort_rank_badge.dart';
import 'activity_detail_screen.dart';

class BestEffortsDetailScreen extends StatefulWidget {
  final DistanceCategory initialCategory;
  final String runnerName;
  final String? avatarUrl;

  /// Overridable data sources — default to the real [DatabaseService].
  /// Injectable so widget tests can exercise this screen's tab/leaderboard
  /// UI without touching sqflite/Firebase (both unavailable under
  /// flutter_test).
  final Future<List<BestEffortRecord>> Function(DistanceCategory category)
  loadEntries;
  final Future<RunRecord?> Function(int runId) loadRun;
  final Future<MaxHrResolution> Function() loadMaxHr;
  final Future<PaceZoneConfig?> Function() loadPaceZones;
  final Future<List<RunBestEffort>> Function(String runId) loadRunBestEfforts;

  BestEffortsDetailScreen({
    super.key,
    this.initialCategory = DistanceCategory.k5,
    this.runnerName = 'You',
    this.avatarUrl,
    Future<List<BestEffortRecord>> Function(DistanceCategory category)?
    loadEntries,
    Future<RunRecord?> Function(int runId)? loadRun,
    Future<MaxHrResolution> Function()? loadMaxHr,
    Future<PaceZoneConfig?> Function()? loadPaceZones,
    Future<List<RunBestEffort>> Function(String runId)? loadRunBestEfforts,
  }) : loadEntries =
           loadEntries ?? DatabaseService.instance.getBestEffortsForCategory,
       loadRun = loadRun ?? DatabaseService.instance.getRunById,
       loadMaxHr = loadMaxHr ?? AthletePhysiology.instance.resolveMaxHr,
       loadPaceZones = loadPaceZones ?? AthletePaceZones.instance.resolve,
       loadRunBestEfforts =
           loadRunBestEfforts ?? DatabaseService.instance.getRunBestEfforts;

  @override
  State<BestEffortsDetailScreen> createState() =>
      _BestEffortsDetailScreenState();
}

class _BestEffortsDetailScreenState extends State<BestEffortsDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late DistanceCategory _selected;
  List<BestEffortRecord> _entries = [];
  bool _isLoading = true;
  bool _useMiles = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCategory;
    _useMiles = UnitUtils.useMilesNotifier.value;
    _tabController = TabController(
      length: DistanceCategory.values.length,
      vsync: this,
      initialIndex: DistanceCategory.values.indexOf(_selected),
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final category = DistanceCategory.values[_tabController.index];
      if (category == _selected) return;
      setState(() => _selected = category);
      _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final entries = await widget.loadEntries(_selected);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _openRun(BestEffortRecord entry) async {
    final id = int.tryParse(entry.runId);
    if (id == null) return;
    final run = await widget.loadRun(id);
    if (run == null || !mounted) return;
    final maxHr = await widget.loadMaxHr();
    final paceZones = await widget.loadPaceZones();
    final runEfforts = await widget.loadRunBestEfforts(entry.runId);
    if (!mounted) return;
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityDetailScreen(
          activity: ActivityDetail.fromRunRecord(
            run,
            runnerName: widget.runnerName,
            avatarUrl: widget.avatarUrl,
            maxHr: maxHr,
            paceZoneConfig: paceZones,
            bestEfforts: runEfforts,
          ),
          onDelete: () async {
            await DatabaseService.instance.deleteRun(id);
            ProfileService.instance.refreshRunAggregates();
          },
        ),
      ),
    );
    // Deleting a run can promote the next-fastest effort: re-rank the list.
    if (deleted == true && mounted) _load();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AmbientScaffold(
      safeArea: false,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Best Efforts',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: c.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: c.accent,
            unselectedLabelColor: c.textTertiary,
            indicatorColor: c.accent,
            dividerColor: c.divider,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            tabs: [
              for (final category in DistanceCategory.values)
                Tab(text: category.label),
            ],
          ),
        ),
      ),
      // extendBodyBehindAppBar lets the ambient glow run behind the
      // transparent header, so clear the status bar, toolbar and tab bar.
      body: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 48,
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : _entries.isEmpty
            ? Center(
                child: Text(
                  'No efforts recorded yet for ${_selected.label}',
                  style: TextStyle(color: c.textTertiary),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final rank = index + 1;
                  final paceSecPerKm =
                      entry.elapsedSeconds / (_selected.meters / 1000);
                  final displayPaceSeconds = UnitUtils.displayPaceSeconds(
                    paceSecPerKm,
                    _useMiles,
                  ).round();

                  return GestureDetector(
                    onTap: () => _openRun(entry),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          BestEffortRankBadge(rank: rank),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  BestEffortsService.formatElapsed(
                                    entry.elapsedSeconds,
                                  ),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${UnitUtils.formatSeconds(displayPaceSeconds)} ${UnitUtils.perUnitLabel(_useMiles)} pace',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _formatDate(entry.recordedAt),
                            style: TextStyle(fontSize: 12, color: c.textFaint),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: c.textFaint,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
