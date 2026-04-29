import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/database_service.dart';
import '../engines/runtime/engine_runtime.dart';
import '../engines/pace_trend_calculator.dart';
import '../services/coach_message_builder.dart' as message;
import '../widgets/post_run_feedback.dart';
import '../services/cloud_sync_service.dart';
import '../engines/config/workout_template_library.dart';

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

    await EngineRuntime.processRun(
      durationMinutes: widget.durationSeconds / 60.0,
      speed: speed,
      runDate: widget.runDate,
      workoutType: workoutType,
      rpe: rpe,
      templateId: completedTemplateId,
      completedIntent: completedIntent,
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
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator(color: Colors.black)),
          );
        }

        final data = snapshot.data ?? _SummaryData.empty();

        return Scaffold(
          backgroundColor: Colors.white,
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
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Header ──────────────────────────────────
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Workout complete',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(widget.runDate),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  if (_totalWorkoutSeconds > widget.durationSeconds) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Total time: ${_formatDuration(_totalWorkoutSeconds)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade400,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(height: 28),
                              _buildStatsRow(),
                              const SizedBox(height: 24),
                              Divider(color: Colors.grey.shade100, height: 1),
                              const SizedBox(height: 24),

                              PostRunFeedback(
                                avgPace: widget.averagePace,
                                targetRange: _targetPaceRange,
                              ),

                              const SizedBox(height: 24),
                              Divider(color: Colors.grey.shade100, height: 1),
                              const SizedBox(height: 24),

                              _buildRpeSection(),

                              const SizedBox(height: 24),
                              Divider(color: Colors.grey.shade100, height: 1),
                              const SizedBox(height: 24),

                              _buildLoadSection(data),

                              const SizedBox(height: 24),
                              Divider(color: Colors.grey.shade100, height: 1),
                              const SizedBox(height: 24),

                              _buildNextWorkoutSection(data),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Done button — locked until RPE selected ──────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _rpe == null ? 'Rate your effort to continue' : 'Done',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
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

  // ── RPE Section ───────────────────────────────────────────────────────────

  Widget _buildRpeSection() {
    const options = [
      _RpeOption(
        emoji: '😌',
        label: 'Easy',
        sublabel: 'Could have gone much longer',
        rpeValue: 3,
        color: Color(0xFF1976D2),
      ),
      _RpeOption(
        emoji: '👌',
        label: 'Just right',
        sublabel: 'Controlled, felt as expected',
        rpeValue: 5,
        color: Color(0xFF388E3C),
      ),
      _RpeOption(
        emoji: '😤',
        label: 'Hard',
        sublabel: 'Pushed through, needed focus',
        rpeValue: 7,
        color: Color(0xFFF57C00),
      ),
      _RpeOption(
        emoji: '😮‍💨',
        label: 'Very hard',
        sublabel: 'Near limit, tough to finish',
        rpeValue: 9,
        color: Color(0xFFD32F2F),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'HOW DID IT FEEL?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF999999),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'REQUIRED',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Max uses this to decide your next workout.',
          style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
        const SizedBox(height: 14),
        Row(
          children: List.generate(options.length, (i) {
            final opt = options[i];
            final isSelected = _rpe == opt.rpeValue;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _rpe = opt.rpeValue),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: EdgeInsets.only(right: i == options.length - 1 ? 0 : 8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? opt.color.withOpacity(0.08)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? opt.color : Colors.grey.shade200,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(opt.emoji,
                          style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 6),
                      Text(
                        opt.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? opt.color
                              : const Color(0xFF1C1C1E),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          opt.sublabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF999999),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Data builder ──────────────────────────────────────────────────────────

  Future<_SummaryData> _buildSummaryData() async {
    final recentRuns = await DatabaseService.instance.getRecentRuns(limit: 10);
    final paceTrend = PaceTrendCalculator.calculate(
      recentRuns.map((r) => _paceToSeconds(r.averagePace)).toList(),
    );
    final weeklyDistance = _calcWeeklyDistance(recentRuns);
    final daysSinceQuality = _calcDaysSince(recentRuns, {'tempo', 'interval'});
    final daysSinceLong = _calcDaysSince(recentRuns, {'long'});
    final nextWorkout = _suggestNext(
      daysSinceLastQuality: daysSinceQuality,
      daysSinceLastLong: daysSinceLong,
    );
    return _SummaryData(
      paceTrend: paceTrend,
      weeklyDistance: weeklyDistance,
      nextWorkout: nextWorkout,
    );
  }

  double _calcWeeklyDistance(List<RunRecord> runs) {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    return runs
        .where((r) => r.date.isAfter(sevenDaysAgo))
        .fold(0.0, (sum, r) => sum + r.distanceKm);
  }

  int _calcDaysSince(List<RunRecord> runs, Set<String> types) {
    for (final run in runs) {
      if (types.contains(run.workoutType)) {
        return DateTime.now().difference(run.date).inDays;
      }
    }
    return 999;
  }

  String _suggestNext({
    required int daysSinceLastQuality,
    required int daysSinceLastLong,
  }) {
    if (daysSinceLastLong >= 7) {
      return 'Long easy run — it\'s been a week since your last long run.';
    }
    if (daysSinceLastQuality >= 3) {
      return 'Tempo or interval session — time for a quality workout.';
    }
    return 'Easy run — keep building your base.';
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

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildMap() {
    if (widget.routePoints.isEmpty) {
      return Container(
        height: 220,
        color: Colors.grey.shade100,
        child: Center(
          child: Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade300),
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

  Widget _buildStatsRow() {
    return Row(children: [
      _buildStat(_formatDistance(widget.distanceKm), 'km', 'Distance'),
      _buildDivider(),
      _buildStat(_formatDuration(widget.durationSeconds), '', 'Time'),
      _buildDivider(),
      _buildStat(widget.averagePace, '/km', 'Avg pace'),
    ]);
  }

  Widget _buildStat(String value, String unit, String label) {
    return Expanded(
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.black)),
            if (unit.isNotEmpty)
              Text(unit,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5)),
      ]),
    );
  }

  Widget _buildDivider() =>
      Container(width: 1, height: 40, color: Colors.grey.shade200);

  Widget _buildLoadSection(_SummaryData data) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('TRAINING LOAD',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF999999),
              letterSpacing: 1.2)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: _buildLoadStat(
              'This week',
              '${data.weeklyDistance.toStringAsFixed(1)} km',
              Colors.black87),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildLoadStat(
            'Pace trend',
            _paceTrendLabel(data.paceTrend),
            data.paceTrend == 'improving'
                ? const Color(0xFF388E3C)
                : data.paceTrend == 'declining'
                    ? const Color(0xFFD32F2F)
                    : Colors.grey.shade600,
          ),
        ),
      ]),
    ]);
  }

  Widget _buildLoadStat(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: valueColor)),
        const SizedBox(height: 4),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]),
    );
  }

  Widget _buildNextWorkoutSection(_SummaryData data) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('NEXT UP',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF999999),
              letterSpacing: 1.2)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.directions_run,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(data.nextWorkout,
                style: const TextStyle(
                    fontSize: 14, color: Colors.black87, height: 1.4)),
          ),
        ]),
      ),
    ]);
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _paceTrendLabel(String trend) {
    return switch (trend) {
      'improving'          => '↑ Improving',
      'declining'          => '↓ Declining',
      'insufficient_data'  => '— Not enough data',
      _                    => '→ Stable',
    };
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _SummaryData {
  final String paceTrend;
  final double weeklyDistance;
  final String nextWorkout;

  const _SummaryData({
    required this.paceTrend,
    required this.weeklyDistance,
    required this.nextWorkout,
  });

  factory _SummaryData.empty() => const _SummaryData(
        paceTrend: 'neutral',
        weeklyDistance: 0.0,
        nextWorkout: 'Easy run — keep building your base.',
      );
}

// ── RPE option model ──────────────────────────────────────────────────────────

class _RpeOption {
  final String emoji;
  final String label;
  final String sublabel;
  final int rpeValue;
  final Color color;

  const _RpeOption({
    required this.emoji,
    required this.label,
    required this.sublabel,
    required this.rpeValue,
    required this.color,
  });
}