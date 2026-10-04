// lib/screens/best_efforts_detail_screen.dart
//
// Full Best Efforts leaderboard: a tab per benchmark distance, each showing
// the top-10 fastest recorded segments for that distance. Tapping a row
// opens the run it came from.

import 'package:flutter/material.dart';

import '../models/activity_telemetry.dart';
import '../services/best_efforts_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';
import '../utils/unit_utils.dart';
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

  BestEffortsDetailScreen({
    super.key,
    this.initialCategory = DistanceCategory.k5,
    this.runnerName = 'You',
    this.avatarUrl,
    Future<List<BestEffortRecord>> Function(DistanceCategory category)?
    loadEntries,
    Future<RunRecord?> Function(int runId)? loadRun,
  }) : loadEntries =
           loadEntries ?? DatabaseService.instance.getBestEffortsForCategory,
       loadRun = loadRun ?? DatabaseService.instance.getRunById;

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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityDetailScreen(
          activity: ActivityDetail.fromRunRecord(
            run,
            runnerName: widget.runnerName,
            avatarUrl: widget.avatarUrl,
          ),
          onDelete: () => DatabaseService.instance.deleteRun(id),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _rankBadge(int rank) {
    final c = context.colors;
    if (rank > 3) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: c.background,
        child: Text(
          '$rank',
          style: TextStyle(
            color: c.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      );
    }
    // Medal palette (gold/silver/bronze) — no matching AppColors tokens.
    final (Color bg, Color text) = switch (rank) {
      1 => (const Color(0xFFFAC775), const Color(0xFF412402)), // Gold
      2 => (const Color(0xFFD3D1C7), const Color(0xFF444441)), // Silver
      _ => (const Color(0xFFF0997B), const Color(0xFF4A1B0C)), // Bronze
    };
    return CircleAvatar(
      radius: 14,
      backgroundColor: bg,
      child: Text(
        '$rank',
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        title: Text(
          'Best Efforts',
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
        ),
        iconTheme: IconThemeData(color: c.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: c.accent,
            unselectedLabelColor: c.textTertiary,
            indicatorColor: c.accent,
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
      body: _isLoading
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _rankBadge(rank),
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
                        Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
