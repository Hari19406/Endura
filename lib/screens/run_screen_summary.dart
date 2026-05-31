import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/database_service.dart';
import '../engines/runtime/engine_runtime.dart';
import '../engines/pace_trend_calculator.dart';
import '../services/coach_message_builder.dart' as message;
import '../services/cloud_sync_service.dart';
import '../engines/config/workout_template_library.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engines/memory/engine_memory_service.dart';
import '../engines/plan/week_projection_service.dart';
import '../engines/plan/workout_resolver.dart';
import '../engines/core/pace_table.dart';
import '../engines/core/vdot_calculator.dart';
import '../services/training_days_service.dart';
import '../utils/stats.dart' show loadSavedRuns, RunHistory;
import '../engines/daily/dynamic_scaler.dart';

class RunSummaryScreen extends StatefulWidget {
  final double distanceKm;
  final int durationSeconds;
  final String averagePace;
  final List<LatLng> routePoints;
  final DateTime runDate;
  final int warmupDurationSeconds;
  final int cooldownDurationSeconds;
  final VoidCallback onDone;
  final message.CoachMessage? activeCoachMessage;

  const RunSummaryScreen({
    super.key,
    required this.distanceKm,
    required this.durationSeconds,
    required this.averagePace,
    required this.routePoints,
    required this.runDate,
    this.warmupDurationSeconds = 0,
    this.cooldownDurationSeconds = 0,
    required this.onDone,
    this.activeCoachMessage,
  });

  @override
  State<RunSummaryScreen> createState() => _RunSummaryScreenState();
}

class _RunSummaryScreenState extends State<RunSummaryScreen> {
  int? _rpe;
  bool _engineProcessed = false;
  late Future<_SummaryData> _summaryFuture;

  message.PaceRange? get _targetPaceRange {
    final workout = widget.activeCoachMessage?.resolvedWorkout;
    if (workout == null) return null;
    final workBlocks = workout.blocks.where((b) => b.type == BlockType.main);
    if (workBlocks.isEmpty) return null;
    final nonRpe = workBlocks.where((b) => !b.isRpeOnly);
    if (nonRpe.isEmpty) return null;
    final fastest = nonRpe.map((b) => b.paceMinSecondsPerKm).reduce((a, b) => a < b ? a : b);
    final slowest = nonRpe.map((b) => b.paceMaxSecondsPerKm).reduce((a, b) => a > b ? a : b);
    return message.PaceRange(
      minSecondsPerKm: fastest,
      maxSecondsPerKm: slowest,
    );
  }

  int get _totalWorkoutSeconds =>
      widget.warmupDurationSeconds +
      widget.durationSeconds +
      widget.cooldownDurationSeconds;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _buildSummaryData();
  }

  Future<void> _finaliseRun(int rpe) async {
    if (_engineProcessed) return;
    _engineProcessed = true;

    try {
      final runs = await DatabaseService.instance.getRecentRuns(limit: 1);
      if (runs.isNotEmpty && runs.first.id != null) {
        await DatabaseService.instance.updateRunRpe(runs.first.id!, rpe);
        await CloudSyncService.instance.updateRunRpe(runs.first.id!, rpe);
      }
    } catch (e) {
      debugPrint('Error saving RPE: $e');
    }

    final completedTemplateId =
        widget.activeCoachMessage?.resolvedWorkout.templateId;
    final completedIntent = widget.activeCoachMessage?.workoutIntent;
    final workoutType = _resolveWorkoutType(completedIntent);
    final speed = widget.durationSeconds > 0
        ? (widget.distanceKm * 1000 / widget.durationSeconds)
        : 0.0;
 
    final memory = await EngineMemoryService().load();

    await EngineRuntime.processRun(
      durationMinutes: widget.durationSeconds / 60.0,
      speed: speed,
      runDate: widget.runDate,
      workoutType: workoutType,
      rpe: rpe,
      templateId: completedTemplateId,
      completedIntent: completedIntent,
      weeklyProgressionDecision: memory.weeklyProgressionDecision,
    );
  }

  String _resolveWorkoutType(WorkoutIntent? intent) {
    if (intent == null) return 'easy';
    return switch (intent) {
      WorkoutIntent.threshold    => 'tempo',
      WorkoutIntent.vo2max       => 'interval',
      WorkoutIntent.speed        => 'interval',
      WorkoutIntent.raceSpecific => 'tempo',
      WorkoutIntent.endurance    => 'long',
      WorkoutIntent.recovery     => 'recovery',
      WorkoutIntent.aerobicBase  => 'easy',
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SummaryData>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F5F7),
            body: Center(child: CircularProgressIndicator(color: Colors.black)),
          );
        }

        final data = snapshot.data ?? _SummaryData.empty();

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F7),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMap(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Header ──────────────────────────────────
                              Padding(
                                padding: const EdgeInsets.only(top: 18, bottom: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Workout complete',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _formatDate(widget.runDate),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF999999),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ── Stats card ───────────────────────────────
                              _buildStatsCard(),
                              const SizedBox(height: 12),

                              // ── Pace & performance card ──────────────────
                              _buildPaceCard(),
                              const SizedBox(height: 12),

                              // ── RPE card ─────────────────────────────────
                              _buildRpeCard(),
                              const SizedBox(height: 12),

                              // ── Next up card ─────────────────────────────
                              _buildNextWorkoutCard(data),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Done button ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _rpe == null
                          ? null
                          : () async {
                              await _finaliseRun(_rpe!);
                              await Future.delayed(
                                  const Duration(milliseconds: 200));
                              widget.onDone();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey.shade400,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _rpe == null ? 'Rate your effort to continue' : 'Done',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Stats card ────────────────────────────────────────────────────────────

  Widget _buildStatsCard() {
    return _Card(
      child: Column(
        children: [
          // Row 1: Distance · Duration · Avg pace
          IntrinsicHeight(
            child: Row(
              children: [
                _buildStatCell(_formatDistance(widget.distanceKm), 'km', 'Distance'),
                _buildCellDivider(),
                _buildStatCell(_formatDuration(widget.durationSeconds), '', 'Duration'),
                _buildCellDivider(),
                _buildStatCell(widget.averagePace, '/km', 'Avg pace'),
              ],
            ),
          ),
          Divider(color: Colors.grey.shade100, height: 1, thickness: 1),
          // Row 2: Total time · This week · Pace trend
          IntrinsicHeight(
            child: Row(
              children: [
                _buildStatCell(
                  _formatDuration(_totalWorkoutSeconds),
                  '',
                  'Total time',
                ),
                _buildCellDivider(),
                _buildStatCell(
                  _summaryFutureWeeklyKm,
                  'km',
                  'This week',
                ),
                _buildCellDivider(),
                _buildStatCellRaw(
                  _buildPaceTrendWidget(),
                  'Pace trend',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Weekly km is available after future resolves; use FutureBuilder snapshot
  // via a helper that reads from the already-resolved future result stored
  // in the outer FutureBuilder. We pass data down via a field set during build.
  String _summaryFutureWeeklyKm = '—';

  Widget _buildStatCell(String value, String unit, String label) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Color(0xFFAAAAAA))),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF999999),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCellRaw(Widget valueWidget, String label) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Color(0xFFAAAAAA))),
            const SizedBox(height: 4),
            valueWidget,
          ],
        ),
      ),
    );
  }

  Widget _buildPaceTrendWidget() {
    // Reads from _summaryFuture result — will be set via _latestData
    final trend = _latestData?.paceTrend ?? 'neutral';
    final label = _paceTrendLabel(trend);
    final color = trend == 'improving'
        ? const Color(0xFF388E3C)
        : trend == 'declining'
            ? const Color(0xFFD32F2F)
            : const Color(0xFF888888);
    return Text(label,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: color));
  }

  Widget _buildCellDivider() => Container(
        width: 0.5,
        color: const Color(0xFFF0F0F0),
      );

  // ── Pace & performance card ───────────────────────────────────────────────

  Widget _buildPaceCard() {
    final target = _targetPaceRange;
    final avgSec = _paceToSeconds(widget.averagePace);

    // Badge logic
    String badgeLabel;
    Color badgeBg;
    Color badgeText;
    if (target == null) {
      badgeLabel = 'Free run';
      badgeBg = const Color(0xFFF0F0F0);
      badgeText = const Color(0xFF888888);
    } else {
      final inRange = avgSec >= target.minSecondsPerKm &&
          avgSec <= target.maxSecondsPerKm;
      final faster = avgSec < target.minSecondsPerKm;
      if (inRange) {
        badgeLabel = 'On target ✓';
        badgeBg = const Color(0xFFE8F5EE);
        badgeText = const Color(0xFF2A7D3E);
      } else if (faster) {
        badgeLabel = 'Too fast';
        badgeBg = const Color(0xFFFFF8E1);
        badgeText = const Color(0xFFB36200);
      } else {
        badgeLabel = 'Too slow';
        badgeBg = const Color(0xFFFCE8E8);
        badgeText = const Color(0xFFB32020);
      }
    }

    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card header
            Row(
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.trending_up,
                      color: Color(0xFF2A9D4E), size: 15),
                ),
                const SizedBox(width: 8),
                const Text('Pace & performance',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black)),
              ],
            ),
            const SizedBox(height: 14),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: avg pace + badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Average pace',
                          style: TextStyle(
                              fontSize: 10, color: Color(0xFFAAAAAA))),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: widget.averagePace,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2A9D4E),
                              ),
                            ),
                            const TextSpan(
                              text: ' /km',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF2A9D4E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(badgeLabel,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: badgeText)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Right: target range + track (only if coached run)
                if (target != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Target range',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFFAAAAAA))),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatPaceSecs(target.minSecondsPerKm)} – ${_formatPaceSecs(target.maxSecondsPerKm)} /km',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2A9D4E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildRangeTrack(avgSec, target),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeTrack(int avgSec, message.PaceRange target) {
    // Clamp dot position within 0–1
    final rangeSec = target.maxSecondsPerKm - target.minSecondsPerKm;
    final raw = rangeSec > 0
        ? (avgSec - target.minSecondsPerKm) / rangeSec
        : 0.5;
    final frac = raw.clamp(0.0, 1.0);

    return LayoutBuilder(builder: (context, constraints) {
      final trackW = constraints.maxWidth;
      const dotR = 7.0;
      final dotLeft = (frac * (trackW - dotR * 2)).clamp(0.0, trackW - dotR * 2);

      return Column(
        children: [
          SizedBox(
            height: 14,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Track background
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                // Filled zone (full width = in range)
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A9D4E),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                // Dot
                Positioned(
                  left: dotLeft,
                  child: Container(
                    width: dotR * 2,
                    height: dotR * 2,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  // ── RPE card ──────────────────────────────────────────────────────────────

  static const List<_RpeLevel> _rpeLevels = [
    _RpeLevel(value: 1,  name: 'Very easy',      desc: 'Almost no effort, barely moving',                 color: Color(0xFF2DB87A)),
    _RpeLevel(value: 2,  name: 'Easy',            desc: 'Light and comfortable, breathing barely changes', color: Color(0xFF3DC882)),
    _RpeLevel(value: 3,  name: 'Light',           desc: 'Comfortable pace, easy conversation',             color: Color(0xFF72C226)),
    _RpeLevel(value: 4,  name: 'Somewhat easy',   desc: 'Slightly elevated breathing, relaxed',            color: Color(0xFF9DC91A)),
    _RpeLevel(value: 5,  name: 'Moderate',        desc: 'Steady effort, short sentences possible',         color: Color(0xFFD4960E)),
    _RpeLevel(value: 6,  name: 'Somewhat hard',   desc: 'Noticeably harder, breathing heavier',            color: Color(0xFFD4730E)),
    _RpeLevel(value: 7,  name: 'Hard',            desc: 'Pushing it, few words possible',                  color: Color(0xFFCC5410)),
    _RpeLevel(value: 8,  name: 'Very hard',       desc: 'Very tough, focused on form and breathing',       color: Color(0xFFC43612)),
    _RpeLevel(value: 9,  name: 'Extremely hard',  desc: 'Near limit, barely holding pace',                 color: Color(0xFFB82014)),
    _RpeLevel(value: 10, name: 'Max effort',      desc: 'All out — could not go harder',                   color: Color(0xFF9E1016)),
  ];

  Widget _buildRpeCard() {
    final selected = _rpe;
    final level = selected != null ? _rpeLevels[selected - 1] : null;

    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Text(
                  'HOW DID IT FEEL?',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFAAAAAA),
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'REQUIRED',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'Max uses this to decide your next workout.',
              style: TextStyle(fontSize: 11, color: Color(0xFFAAAAAA)),
            ),
            const SizedBox(height: 14),

            // Name + number
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  level?.name ?? 'Tap to rate your effort',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: level != null
                        ? level.color
                        : const Color(0xFFAAAAAA),
                  ),
                ),
                if (level != null)
                  Text(
                    '${level.value}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: level.color,
                    ),
                  ),
              ],
            ),
            if (level != null) ...[
              const SizedBox(height: 3),
              Text(
                level.desc,
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFAAAAAA),
                    height: 1.4),
              ),
            ],
            const SizedBox(height: 11),

            // Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 9,
                color: Colors.grey.shade100,
                child: AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  widthFactor:
                      selected != null ? selected / 10.0 : 0.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: level?.color ?? Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 11),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_rpeLevels.length, (i) {
                final lvl = _rpeLevels[i];
                final isSelected = selected == lvl.value;
                final isPast =
                    selected != null && lvl.value <= selected;
                return GestureDetector(
                  onTap: () => setState(() => _rpe = lvl.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 27,
                    height: 27,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPast
                          ? lvl.color.withOpacity(0.15)
                          : Colors.grey.shade100,
                      border: Border.all(
                        color: isSelected
                            ? lvl.color
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${lvl.value}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isPast
                              ? lvl.color
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ── Next up card ──────────────────────────────────────────────────────────

  Widget _buildNextWorkoutCard(_SummaryData data) {
    final accentColor = _intentAccentColor(data.nextIntent);
    final icon = _intentIcon(data.nextIntent);

    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.calendar_today_outlined,
                      color: Color(0xFF3949AB), size: 14),
                ),
                const SizedBox(width: 8),
                const Text('Next up',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.nextWorkoutLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                      if (data.nextWorkoutSubtext.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          data.nextWorkoutSubtext,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFAAAAAA),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Data builder ──────────────────────────────────────────────────────────

  _SummaryData? _latestData;

  Future<_SummaryData> _buildSummaryData() async {
    final recentRuns = await DatabaseService.instance.getRecentRuns(limit: 10);

    final paceTrend = PaceTrendCalculator.calculate(
      recentRuns.map((r) => _paceToSeconds(r.averagePace)).toList(),
    );
    final weeklyDistance = _calcWeeklyDistance(recentRuns);

    // Update the weekly km label for the stats card
    _summaryFutureWeeklyKm = weeklyDistance.toStringAsFixed(1);

    try {
      final prefs = await SharedPreferences.getInstance();
      final memory = await EngineMemoryService().load();
      final trainingDayIndices = await TrainingDaysService.loadOrDefault(4);

      final goalRace = prefs.getString('goal_race') ?? '5k';
      final runsPerWeek = trainingDayIndices.isNotEmpty
          ? trainingDayIndices.length
          : (prefs.getInt('runs_per_week') ?? 4);

      final paceTable = PaceTable(memory.vdotScore.clamp(30, 85));
      final raceDistance = _goalRaceToDistance(goalRace);

      final resolverContext = ResolverContext(
        paceTable: paceTable,
        goalRaceDistance: _raceDistanceToPR(raceDistance),
        goalRaceTimeSeconds: null,
      );

      final runHistory = await loadSavedRuns();
      final runHistoryTyped = runHistory
          .map((r) => RunHistory(
                distance: r.distance,
                averagePace: r.averagePace,
                date: r.date,
                gpsPoints: r.gpsPoints,
                rpe: r.rpe,
                workoutType: r.workoutType,
              ))
          .toList();

      final weekNum = memory.hasRacePlan
          ? memory.racePlan!.currentWeekNumber(DateTime.now())
          : memory.currentWeek;

      final phase = memory.hasRacePlan
          ? (memory.racePlan!.currentWeek(DateTime.now())?.phase ??
              memory.currentPhase)
          : memory.currentPhase;

      final recentAvg = runHistory.isEmpty
          ? 5.0
          : runHistory.take(5).fold(0.0, (s, r) => s + r.distance) /
              runHistory.take(5).length;
      final weeklyTargetKm = recentAvg * runsPerWeek;

      final service = WeekProjectionService();
      final projection = service.projectWeek(
        weekNumber: weekNum,
        phase: phase,
        trainingDayIndices: trainingDayIndices,
        resolverContext: resolverContext,
        scalingSignals: const ScalingSignals(),
        raceDistance: raceDistance,
        weeklyTargetKm: weeklyTargetKm,
        completedRuns: runHistoryTyped,
        lastCompletedIntent: memory.lastCompletedWorkoutIntent,
        lastCompletedTemplateId: memory.lastCompletedTemplateId,
        avgRpe: memory.averageRecentRpe(3),
      );

      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);

      ProjectedDay? nextDay;
      for (final day in projection.days) {
        final dayMidnight =
            DateTime(day.date.year, day.date.month, day.date.day);
        if (dayMidnight.isAfter(todayMidnight) &&
            day.status == DayStatus.projected &&
            day.intent != null) {
          nextDay = day;
          break;
        }
      }

      if (nextDay != null) {
        final intent = nextDay.intent!;
        final daysAhead = nextDay.date.difference(todayMidnight).inDays;
        final dayLabel =
            daysAhead == 1 ? 'Tomorrow' : _weekdayName(nextDay.weekday);
        final distStr = nextDay.distanceKm > 0
            ? ' · ${nextDay.distanceKm.toStringAsFixed(1)} km'
            : '';
        final label = '$dayLabel · ${_intentName(intent)}$distStr';
        final subtext = _intentSubtext(intent);

        final result = _SummaryData(
          paceTrend: paceTrend,
          weeklyDistance: weeklyDistance,
          nextIntent: intent,
          nextWorkoutLabel: label,
          nextWorkoutSubtext: subtext,
        );
        _latestData = result;
        return result;
      }
    } catch (e) {
      debugPrint('[RunSummaryScreen] next session projection failed: $e');
    }

    final result = _SummaryData(
      paceTrend: paceTrend,
      weeklyDistance: weeklyDistance,
      nextIntent: null,
      nextWorkoutLabel: 'Easy run — keep building your base.',
      nextWorkoutSubtext: '',
    );
    _latestData = result;
    return result;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _calcWeeklyDistance(List<RunRecord> runs) {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    return runs
        .where((r) => r.date.isAfter(sevenDaysAgo))
        .fold(0.0, (sum, r) => sum + r.distanceKm);
  }

  int _paceToSeconds(String pace) {
    try {
      final parts = pace.split(':');
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (_) {}
    return 0;
  }

  String _formatPaceSecs(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildMap() {
    if (widget.routePoints.isEmpty) {
      return Container(
        height: 220,
        color: Colors.grey.shade100,
        child: Center(
          child:
              Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade300),
        ),
      );
    }
    final lats = widget.routePoints.map((p) => p.latitude).toList();
    final lngs = widget.routePoints.map((p) => p.longitude).toList();
    final bounds = LatLngBounds(
      LatLng(lats.reduce((a, b) => a < b ? a : b),
          lngs.reduce((a, b) => a < b ? a : b)),
      LatLng(lats.reduce((a, b) => a > b ? a : b),
          lngs.reduce((a, b) => a > b ? a : b)),
    );
    return SizedBox(
      height: 240,
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
              bounds: bounds, padding: const EdgeInsets.all(40)),
          interactionOptions:
              const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=3Iy00qmbWys8hyAY1PIeg',
            userAgentPackageName: 'com.example.runapp',
            maxZoom: 19,
            subdomains: const ['a', 'b', 'c'],
            tileProvider: NetworkTileProvider(),
          ),
          PolylineLayer(polylines: [
            Polyline(
              points: widget.routePoints,
              strokeWidth: 4,
              color: Colors.black,
              borderStrokeWidth: 2,
              borderColor: Colors.white,
            )
          ]),
          MarkerLayer(markers: [
            Marker(
              point: widget.routePoints.first,
              width: 14, height: 14,
              child: Container(
                decoration: const BoxDecoration(
                    color: Color(0xFF388E3C), shape: BoxShape.circle),
              ),
            ),
            Marker(
              point: widget.routePoints.last,
              width: 14, height: 14,
              child: Container(
                decoration: const BoxDecoration(
                    color: Color(0xFFD32F2F), shape: BoxShape.circle),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  String _formatDistance(double km) =>
      km >= 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(2);

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    const weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _paceTrendLabel(String trend) => switch (trend) {
        'improving'         => '↑ Better',
        'declining'         => '↓ Declining',
        'insufficient_data' => '— No data',
        _                   => '→ Stable',
      };

  String _intentName(WorkoutIntent intent) => switch (intent) {
        WorkoutIntent.aerobicBase  => 'Easy Run',
        WorkoutIntent.endurance    => 'Long Run',
        WorkoutIntent.threshold    => 'Threshold Run',
        WorkoutIntent.vo2max       => 'Interval Session',
        WorkoutIntent.speed        => 'Speed Session',
        WorkoutIntent.raceSpecific => 'Race Pace Run',
        WorkoutIntent.recovery     => 'Recovery Run',
      };

  String _intentSubtext(WorkoutIntent intent) => switch (intent) {
        WorkoutIntent.aerobicBase  =>
          'Easy effort — conversational pace, keep it comfortable.',
        WorkoutIntent.endurance    => 'Long run — building your endurance base.',
        WorkoutIntent.threshold    =>
          'Comfortably hard — raises your lactate threshold.',
        WorkoutIntent.vo2max       =>
          'High-intensity intervals — develops raw speed and VO₂ max.',
        WorkoutIntent.speed        =>
          'Short, fast reps — improves running economy and turnover.',
        WorkoutIntent.raceSpecific =>
          'Race pace work — confidence and rhythm at goal pace.',
        WorkoutIntent.recovery     =>
          'Very easy — flushing fatigue, no fitness pressure.',
      };

  Color _intentAccentColor(WorkoutIntent? intent) => switch (intent) {
        WorkoutIntent.threshold    => const Color(0xFFBF360C),
        WorkoutIntent.vo2max       => const Color(0xFF0D47A1),
        WorkoutIntent.speed        => const Color(0xFF0D47A1),
        WorkoutIntent.endurance    => const Color(0xFF1B5E20),
        WorkoutIntent.recovery     => const Color(0xFF4A148C),
        WorkoutIntent.raceSpecific => const Color(0xFFBF360C),
        _                          => Colors.black,
      };

  IconData _intentIcon(WorkoutIntent? intent) => switch (intent) {
        WorkoutIntent.threshold    => Icons.bolt,
        WorkoutIntent.vo2max       => Icons.repeat_rounded,
        WorkoutIntent.speed        => Icons.flash_on,
        WorkoutIntent.endurance    => Icons.landscape_outlined,
        WorkoutIntent.recovery     => Icons.self_improvement,
        WorkoutIntent.raceSpecific => Icons.flag_outlined,
        _                          => Icons.directions_run,
      };

  String _weekdayName(int dayIndex) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[dayIndex.clamp(0, 6)];
  }

  RaceDistance _goalRaceToDistance(String goalRace) => switch (goalRace) {
        '5k'            => RaceDistance.fiveK,
        '10k'           => RaceDistance.tenK,
        'half_marathon' => RaceDistance.halfMarathon,
        'marathon'      => RaceDistance.marathon,
        _               => RaceDistance.fiveK,
      };

  PRDistance? _raceDistanceToPR(RaceDistance race) => switch (race) {
        RaceDistance.fiveK        => PRDistance.fiveK,
        RaceDistance.tenK         => PRDistance.tenK,
        RaceDistance.halfMarathon => PRDistance.halfMarathon,
        RaceDistance.marathon     => PRDistance.marathon,
      };
}

// ── Shared card wrapper ───────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 0.5),
      ),
      child: child,
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _SummaryData {
  final String paceTrend;
  final double weeklyDistance;
  final WorkoutIntent? nextIntent;
  final String nextWorkoutLabel;
  final String nextWorkoutSubtext;

  const _SummaryData({
    required this.paceTrend,
    required this.weeklyDistance,
    this.nextIntent,
    required this.nextWorkoutLabel,
    required this.nextWorkoutSubtext,
  });

  factory _SummaryData.empty() => const _SummaryData(
        paceTrend: 'neutral',
        weeklyDistance: 0.0,
        nextIntent: null,
        nextWorkoutLabel: 'Easy run — keep building your base.',
        nextWorkoutSubtext: '',
      );
}

// ── RPE level model ───────────────────────────────────────────────────────────

class _RpeLevel {
  final int value;
  final String name;
  final String desc;
  final Color color;

  const _RpeLevel({
    required this.value,
    required this.name,
    required this.desc,
    required this.color,
  });
}