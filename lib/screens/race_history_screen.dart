import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/best_efforts_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';
import '../utils/race_history.dart';
import '../utils/unit_utils.dart';
import '../widgets/ambient_scaffold.dart';

/// Races the athlete has marked (Activity Detail → flag), grouped by standard
/// distance, each with its change against the previous race at that distance.
class RaceHistoryScreen extends StatefulWidget {
  /// Overridable for tests; defaults to the local database.
  final Future<List<RaceRun>> Function()? loadRaces;
  final bool? useMiles;

  const RaceHistoryScreen({super.key, this.loadRaces, this.useMiles});

  @override
  State<RaceHistoryScreen> createState() => _RaceHistoryScreenState();
}

class _RaceHistoryScreenState extends State<RaceHistoryScreen> {
  List<RaceRun>? _races;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<RaceRun> races;
    try {
      races = await (widget.loadRaces ?? DatabaseService.instance.getRaceRuns)();
    } catch (_) {
      races = const [];
    }
    if (mounted) setState(() => _races = races);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final races = _races;
    final groups = races == null ? const <RaceHistoryGroup>[] : RaceHistory.group(races);
    final other = races == null ? 0 : RaceHistory.otherCount(races);

    return AmbientScaffold(
      safeArea: false,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Race History',
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
      ),
      body: races == null
          ? const SizedBox.shrink()
          : ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                20,
                40,
              ),
              children: [
                if (groups.isEmpty)
                  _empty(c)
                else
                  for (final g in groups) ...[
                    _group(c, g),
                    const SizedBox(height: 16),
                  ],
                if (other > 0)
                  Text(
                    '$other marked ${other == 1 ? 'race is' : 'races are'} at '
                    'a non-standard distance and not listed.',
                    key: const Key('race-history-other'),
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
              ],
            ),
    );
  }

  Widget _empty(AppColors c) => Container(
    key: const Key('race-history-empty'),
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      'No races yet. Open a run and tap the flag to mark it as a race.',
      style: TextStyle(fontSize: 14, color: c.textSecondary),
    ),
  );

  Widget _group(AppColors c, RaceHistoryGroup g) {
    final useMiles = widget.useMiles ?? UnitUtils.useMilesNotifier.value;
    return Container(
      key: Key('race-group-${g.category.name}'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.category.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          for (final e in g.entries) _entry(c, e, useMiles),
        ],
      ),
    );
  }

  Widget _entry(AppColors c, RaceHistoryEntry e, bool useMiles) {
    final pace = UnitUtils.displayPaceSeconds(e.race.paceSecPerKm, useMiles);
    final d = e.deltaSeconds;
    final deltaText = d == null
        ? 'First race'
        : d == 0
        ? 'Same time'
        : '${d < 0 ? '−' : '+'}${BestEffortsService.formatElapsed(d.abs())}';
    final deltaColor = d == null || d == 0
        ? c.textTertiary
        : d < 0
        ? c.success
        : c.textSecondary;
    return Padding(
      key: Key('race-entry-${e.race.id}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  BestEffortsService.formatElapsed(e.race.durationSeconds),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat.yMMMd().format(e.race.date)} · '
                  '${UnitUtils.formatSeconds(pace.round())}'
                  '${UnitUtils.perUnitLabel(useMiles)}',
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
              ],
            ),
          ),
          Text(
            deltaText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: deltaColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
