import 'package:flutter/material.dart';
import '../utils/stats.dart';
import '../engines/coach_engine_v2.dart';
import '../engines/vdot_engine/run_history_service.dart';
import '../services/workout_selector.dart' as selector;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engines/memory/engine_memory_service.dart';
import '../engines/memory/engine_memory.dart';
import '../utils/database_service.dart';
import '../models/weekly_plan.dart';
import '../screens/pre_run_briefing_screen.dart';
import '../services/consistency_service.dart';
import '../utils/refreshable.dart';
import '../services/coach_message_builder.dart' as message;
import '../engines/planner/weekly_generator.dart';
import '../engines/planner/race_plan_builder.dart';
import '../services/cloud_sync_service.dart';
import '../services/skip_service.dart';
import '../services/training_days_service.dart';
import '../services/profile_service.dart';
import '../services/engine_state_sync_service.dart';
import '../engines/config/workout_template_library.dart';
import '../screens/pre_run_check.dart';

enum WorkoutCategory { easy, tempo, interval, long, recovery, rest }

class WorkoutDisplayStyle {
  final WorkoutCategory category;
  final Color accentColor;
  final String badgeLabel;
  final IconData icon;

  const WorkoutDisplayStyle({
    required this.category,
    required this.accentColor,
    required this.badgeLabel,
    required this.icon,
  });
}

WorkoutDisplayStyle _workoutDisplayStyle(WorkoutIntent intent) {
  return switch (intent) {
    WorkoutIntent.aerobicBase => const WorkoutDisplayStyle(
        category: WorkoutCategory.easy,
        accentColor: Color(0xFF004D40),
        badgeLabel: 'EASY',
        icon: Icons.directions_run,
      ),
    WorkoutIntent.endurance => const WorkoutDisplayStyle(
        category: WorkoutCategory.long,
        accentColor: Color(0xFF1B5E20),
        badgeLabel: 'ENDURANCE',
        icon: Icons.landscape_outlined,
      ),
    WorkoutIntent.threshold => const WorkoutDisplayStyle(
        category: WorkoutCategory.tempo,
        accentColor: Color(0xFFBF360C),
        badgeLabel: 'QUALITY',
        icon: Icons.bolt,
      ),
    WorkoutIntent.vo2max => const WorkoutDisplayStyle(
        category: WorkoutCategory.interval,
        accentColor: Color(0xFF0D47A1),
        badgeLabel: 'QUALITY',
        icon: Icons.repeat_rounded,
      ),
    WorkoutIntent.speed => const WorkoutDisplayStyle(
        category: WorkoutCategory.interval,
        accentColor: Color(0xFF0D47A1),
        badgeLabel: 'SPEED',
        icon: Icons.flash_on,
      ),
    WorkoutIntent.raceSpecific => const WorkoutDisplayStyle(
        category: WorkoutCategory.tempo,
        accentColor: Color(0xFFBF360C),
        badgeLabel: 'RACE PACE',
        icon: Icons.flag_outlined,
      ),
    WorkoutIntent.recovery => const WorkoutDisplayStyle(
        category: WorkoutCategory.recovery,
        accentColor: Color(0xFF4A148C),
        badgeLabel: 'RECOVERY',
        icon: Icons.self_improvement,
      ),
  };
}

class WorkoutDisplayModel {
  final WorkoutCategory category;
  final String title;
  final String coachingReason;
  final String? duration;
  final String? paceRange;
  final String? distance;
  final List<String> steps;
  final ResolvedWorkout? resolvedWorkout;
  final String goalText;
  final String feelText;
  final String phaseLabel;

  const WorkoutDisplayModel({
    required this.category,
    required this.title,
    required this.coachingReason,
    this.duration,
    this.paceRange,
    this.distance,
    required this.steps,
    this.resolvedWorkout,
    this.goalText = '',
    this.feelText = '',
    this.phaseLabel = '',
  });

  factory WorkoutDisplayModel.fromCoachMessage(CoachMessage msg) {
    final displayStyle = _workoutDisplayStyle(msg.workoutIntent);
    final workout = msg.resolvedWorkout;

    final totalDist = workout.totalDistanceKm;
    final distance = '${totalDist.toStringAsFixed(1)} km';

    final dur = workout.estimatedDuration;
    final duration = '${dur.inMinutes} min';

    String? paceRange;
    final workBlocks = workout.blocks.where((b) => b.type == BlockType.main);
    if (workBlocks.isNotEmpty) {
      final nonRpeBlocks = workBlocks.where((b) => !b.isRpeOnly);
      if (nonRpeBlocks.isNotEmpty) {
        final fastest = nonRpeBlocks
            .map((b) => b.paceMinSecondsPerKm)
            .reduce((a, b) => a < b ? a : b);
        final slowest = nonRpeBlocks
            .map((b) => b.paceMaxSecondsPerKm)
            .reduce((a, b) => a > b ? a : b);
        if ((msg.workoutIntent == WorkoutIntent.aerobicBase ||
            msg.workoutIntent == WorkoutIntent.recovery ||
            msg.workoutIntent == WorkoutIntent.endurance) &&
            (slowest - fastest) >= 30) {
          final ceiling = (fastest / 5).round() * 5;
          paceRange = "Don't run faster than ${_fmtPace(ceiling)}/km";
        } else {
          final lo = (fastest / 5).round() * 5;
          final hi = (slowest / 5).round() * 5;
          paceRange = lo == hi
              ? '${_fmtPace(lo)}/km'
              : '${_fmtPace(lo)}–${_fmtPace(hi)}/km';
        } 
      }
    }

    List<String> steps = List<String>.from(msg.workoutSteps);

    if (steps.isEmpty &&
        displayStyle.category == WorkoutCategory.recovery) {
      steps = [
        'Run at a very easy, conversational pace for 20–30 min — '
            'you should be able to hold a full conversation throughout.',
        'Keep effort low (RPE 3–4 out of 10). '
            'The goal is active recovery, not fitness gains.',
        'Focus on relaxed form, light footfall, and easy breathing.',
      ];
    }

    return WorkoutDisplayModel(
      category: displayStyle.category,
      title: msg.workoutTitle,
      coachingReason: msg.reflectionText,
      duration: duration,
      paceRange: paceRange,
      distance: distance,
      steps: steps,
      resolvedWorkout: workout,
      goalText: msg.goalText,
      feelText: msg.feelText,
      phaseLabel: msg.phaseLabel,
    );
  }

  factory WorkoutDisplayModel.empty() {
    return const WorkoutDisplayModel(
      category: WorkoutCategory.rest,
      title: 'Log a run to unlock',
      coachingReason:
          'Your personalised workout will appear here after a couple of runs. '
          'Head to the Run tab to get started.',
      steps: [],
    );
  }

  static String _fmtPace(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKOUT CARD
// ─────────────────────────────────────────────────────────────────────────────

class WorkoutCard extends StatelessWidget {
  final WorkoutDisplayModel workout;
  final VoidCallback? onTap;

  const WorkoutCard({
    super.key,
    required this.workout,
    this.onTap,
  });

  WorkoutDisplayStyle get _style {
    switch (workout.category) {
      case WorkoutCategory.tempo:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.tempo,
          accentColor: Color(0xFFBF360C),
          badgeLabel: 'QUALITY',
          icon: Icons.bolt,
        );
      case WorkoutCategory.interval:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.interval,
          accentColor: Color(0xFF0D47A1),
          badgeLabel: 'QUALITY',
          icon: Icons.repeat_rounded,
        );
      case WorkoutCategory.long:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.long,
          accentColor: Color(0xFF1B5E20),
          badgeLabel: 'ENDURANCE',
          icon: Icons.landscape_outlined,
        );
      case WorkoutCategory.recovery:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.recovery,
          accentColor: Color(0xFF4A148C),
          badgeLabel: 'RECOVERY',
          icon: Icons.self_improvement,
        );
      case WorkoutCategory.rest:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.rest,
          accentColor: Color(0xFF37474F),
          badgeLabel: 'REST',
          icon: Icons.bedtime_outlined,
        );
      case WorkoutCategory.easy:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.easy,
          accentColor: Color(0xFF004D40),
          badgeLabel: 'EASY',
          icon: Icons.directions_run,
        );
    }
  }

  Color get _accent => _style.accentColor;
  String get _badge => _style.badgeLabel;
  IconData get _icon => _style.icon;
  bool get _isEmpty =>
      workout.category == WorkoutCategory.rest && workout.steps.isEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icon, size: 13, color: _accent),
                          const SizedBox(width: 6),
                          Text(
                            _badge,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _accent,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  workout.title,
                  style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w700,
                    color: const Color(0xFF0A0A0A), letterSpacing: -0.8, height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  workout.coachingReason,
                  style: TextStyle(
                    fontSize: 13, color: const Color(0xFF999999),
                    height: 1.5,
                  ),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (workout.distance != null)
                      _chipWidget(Icons.straighten, workout.distance!),
                    const Spacer(),
                    if (!_isEmpty && onTap != null)
                      GestureDetector(
                        onTap: onTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF333333),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View Workout',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 5),
                              Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipWidget(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF999999)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0A0A0A),
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final VoidCallback? onNavigateToYou;
  final VoidCallback? onNavigateToRun;
  final VoidCallback? onRunCompleted;
  final void Function(message.CoachMessage?)? onCoachMessageReady;

  const HomeScreen({
    super.key,
    this.onNavigateToYou,
    this.onNavigateToRun,
    this.onRunCompleted,
    this.onCoachMessageReady,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin
    implements Refreshable {
  RunHistory? _lastRun;
  CoachMessage? _coachMessage;
  WorkoutDisplayModel? _workoutModel;
  UserMetrics? _userMetrics;
  bool _isLoading = true;
  bool _isFetching = false;
  String _distanceUnit = 'km';
  List<RunHistory> _runHistory = [];
  bool _isLoaded = false;
  late final CoachEngine _coachEngine;
  WeeklyPlan? _activePlan;
  List<int> _trainingDayIndices = const [];
  ConsistencyData? _consistencyData;
  EngineMemory? _engineMemory;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _coachEngine = CoachEngine();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLoaded || _isLoading) {
      loadData();
      _isLoaded = true;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _distanceUnit = prefs.getString('distance_unit') ?? 'km';
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  bool _cloudRestoreAttempted = false;

  Future<void> _restoreFromCloudIfNeeded() async {
    if (_cloudRestoreAttempted) return;
    _cloudRestoreAttempted = true;
    try {
      await CloudSyncService.instance.downloadAndRestoreRuns();
      debugPrint('[HomeScreen] Cloud restore complete');
    } catch (e) {
      debugPrint('[HomeScreen] Cloud restore failed: $e');
    }
  }

  @override
  Future<void> loadData() async {
    debugPrint('HomeScreen loadData() started');
    if (_isFetching) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_isFetching) loadData();
      });
      return;
    }
    _isFetching = true;
    if (!mounted) {
      _isFetching = false;
      return;
    }
    setState(() => _isLoading = true);

    try {
      await EngineMemoryService().migrateFirstRunDateIfNeeded();
      await Future.wait([_restoreFromCloudIfNeeded(), _loadSettings()]);
      await _restoreCloudCoachingState();
      await _hydrateLocalProfileFromCloud();
      CloudSyncService.instance.syncPendingRuns();
      _syncLocalProfileToCloud();
      _trainingDayIndices = await TrainingDaysService.loadOrDefault(4);

      final List<RunHistory> runs = await loadSavedRuns();
      if (!mounted) return;

      final memory = await EngineMemoryService().load();
      _engineMemory = memory;
      _lastRun = runs.isNotEmpty ? runs.first : null;
      _runHistory = runs;

      if (memory.activePlan == null ||
          !_planCoversThisWeek(memory.activePlan!)) {
        final newPlan = WeeklyGenerator.generate(
          startDate: DateTime.now(),
          lastCompletedType: memory.lastCompletedType,
          lastNonRecoveryType: memory.lastNonRecoveryType,
          phase: memory.currentPhase,
          totalRunsCompleted: memory.totalRunsCompleted,
          trainingDayIndices: _trainingDayIndices,
        );
        await EngineMemoryService().saveActivePlan(newPlan);
        _engineMemory = memory.copyWith(activePlan: newPlan);
        _activePlan = newPlan;
      } else {
        _activePlan = memory.activePlan;
      }

      if (_activePlan != null) {
        final runDates = runs.map((r) => r.date).toList();
        final markedPlan = _activePlan!.markMissedDays(
          completedRunDates: runDates,
        );
        if (markedPlan.skippedCount != _activePlan!.skippedCount ||
            markedPlan.completedCount != _activePlan!.completedCount) {
          _activePlan = markedPlan;
          _engineMemory = _engineMemory!.copyWith(activePlan: markedPlan);
          await EngineMemoryService().saveActivePlan(markedPlan);
        }
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        final experienceLevel =
            prefs.getString('experience_level') ?? 'beginner';
        final goalRace = prefs.getString('goal_race') ?? '5k';
        final storedRunsPerWeek = prefs.getInt('runs_per_week');
        final runsPerWeek = _trainingDayIndices.isNotEmpty
            ? _trainingDayIndices.length
            : (storedRunsPerWeek ?? 4);

        final paceMin = prefs.getInt('pace_minutes');
        final paceSec = prefs.getInt('pace_seconds') ?? 0;
        final paceDistance = prefs.getString('pace_distance') ?? '5k';
        int? prTimeSeconds;
        String? prDistanceStr;
        if (paceMin != null) {
          prTimeSeconds = paceMin * 60 + paceSec;
          prDistanceStr = paceDistance;
        }
        final weeklyMileage = prefs.getDouble('weekly_mileage_km') ??
            _estimateWeeklyVolume(runs);

        final recentRuns = runs.take(5).toList();
        int avgEasyPace = experienceLevel == 'advanced'
            ? 300
            : experienceLevel == 'intermediate'
                ? 330
                : 360;
        if (recentRuns.isNotEmpty) {
          final paces = recentRuns
              .map((r) => _paceToSeconds(r.averagePace))
              .where((p) => p > 0)
              .toList();
          if (paces.isNotEmpty) {
            avgEasyPace =
                (paces.reduce((a, b) => a + b) / paces.length).round();
          }
        }

        final avgDistance = recentRuns.isEmpty
            ? 5.0
            : recentRuns.fold(0.0, (sum, r) => sum + r.distance) /
                recentRuns.length;
        final longestRun = runs.isEmpty
            ? 5.0
            : runs.map((r) => r.distance).reduce((a, b) => a > b ? a : b);

        _userMetrics = UserMetrics(
          avgEasyPace: avgEasyPace,
          tempoCapabilityPace: (avgEasyPace * 0.85).round(),
          intervalCapabilityPace: (avgEasyPace * 0.75).round(),
          recentAvgDistance: avgDistance,
          recentWeeklyVolumeKm: weeklyMileage > 0
              ? weeklyMileage
              : avgDistance * runsPerWeek,
          longestRecentRun: longestRun,
          runsPerWeek: runsPerWeek,
          goalRace: goalRace,
          experienceLevel: experienceLevel,
          avgRpe: _averageRecentRpe(runs),
          recentRpeTrend: _deriveRecentRpeTrend(runs),
          lastEasyRunTooHard: _lastEasyRunTooHard(runs),
          prTimeSeconds: prTimeSeconds,
          prDistance: prDistanceStr,
          weeklyMileageKm: weeklyMileage,
        );

        final runAnalysis = _buildRunAnalysis(runs);
        final historicalData = _buildHistoricalData(runs);

        _coachMessage = _coachEngine.getNextCoachMessage(
          userMetrics: _userMetrics!,
          runAnalysis: runAnalysis,
          historicalTrainingData: historicalData,
          lastWorkoutType: _resolveLastWorkoutId(memory.lastWorkoutType),
          memory: _engineMemory!,
          trainingDayIndices: _trainingDayIndices,
        );

        if (_coachMessage != null) {
          _workoutModel =
              WorkoutDisplayModel.fromCoachMessage(_coachMessage!);
        } else {
          _workoutModel = const WorkoutDisplayModel(
            category: WorkoutCategory.rest,
            title: 'Rest Day',
            coachingReason:
                'Your body needs recovery today. Take it easy and come back stronger tomorrow.',
            steps: [],
          );
        }

        widget.onCoachMessageReady?.call(_coachMessage);
      } catch (e, stack) {
        debugPrint('Error generating coach message: $e');
        debugPrint('$stack');
        _coachMessage = null;
        _workoutModel = const WorkoutDisplayModel(
          category: WorkoutCategory.easy,
          title: 'Easy Run',
          coachingReason:
              'Coach engine is recalibrating. Run easy today.',
          duration: '30 min',
          steps: [
            'Run at a comfortable, conversational pace for 30 minutes.'
          ],
        );
        _userMetrics = null;
        widget.onCoachMessageReady?.call(null);
      }

      _consistencyData = await ConsistencyService.compute();
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      _isFetching = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreCloudCoachingState() async {
    final cloudState = await EngineStateSyncService.instance.fetchCloudCoachingState();
    final cloudMemory = cloudState.memory;
    final cloudDays = cloudState.trainingDays;

    final localDays = await TrainingDaysService.load();
    if (cloudDays != null &&
        (localDays == null || !_intListsEqual(localDays, cloudDays))) {
      await TrainingDaysService.save(cloudDays, syncToCloud: false);
    } else if (cloudDays == null && localDays != null && localDays.isNotEmpty) {
      await EngineStateSyncService.instance.syncTrainingDays(localDays);
    }

    final localMemory = await EngineMemoryService().load();
    if (cloudMemory != null && _shouldRestoreCloudMemory(localMemory)) {
      await EngineMemoryService().save(cloudMemory, syncToCloud: false);
    } else if (cloudMemory == null && !_shouldRestoreCloudMemory(localMemory)) {
      await EngineStateSyncService.instance.syncEngineMemory(localMemory);
    }
  }

  bool _shouldRestoreCloudMemory(EngineMemory localMemory) {
    final hasMeaningfulLocalState = localMemory.totalRunsCompleted > 0 ||
        localMemory.activePlan != null ||
        localMemory.racePlan != null ||
        localMemory.lastRunDate != null ||
        localMemory.recentRpeEntries.isNotEmpty;
    return !hasMeaningfulLocalState;
  }

  bool _intListsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _hydrateLocalProfileFromCloud() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('goal_race') && prefs.containsKey('experience_level')) return;

    final profile = await ProfileService.instance.fetchProfile();
    if (profile == null) return;

    debugPrint('[HomeScreen] Rehydrating local profile from Supabase');

    if (!prefs.containsKey('goal_race') && profile.goal != null) {
      await prefs.setString('goal_race', profile.goal!);
    }
    if (!prefs.containsKey('experience_level')) {
      await prefs.setString('experience_level', 'intermediate');
    }
    if (profile.runsPerWeek != null) {
      await prefs.setInt('runs_per_week', profile.runsPerWeek!);
    }
    if (profile.paceDistance != null) {
      await prefs.setString('pace_distance', profile.paceDistance!);
    }
    if (profile.paceMinutes != null) {
      await prefs.setInt('pace_minutes', profile.paceMinutes!);
    }
    if (profile.paceSeconds != null) {
      await prefs.setInt('pace_seconds', profile.paceSeconds!);
    }
    if (profile.raceDate != null) {
      await prefs.setString('race_date', profile.raceDate!.toIso8601String());
    }
    if (profile.gender != null && !prefs.containsKey('gender')) {
      await prefs.setString('gender', profile.gender!);
    }
    if (profile.dob != null && !prefs.containsKey('dob')) {
      await prefs.setString('dob', profile.dob!.toIso8601String());
    }

    if (!prefs.containsKey('weekly_mileage_km')) {
      final fallbackWeeklyKm = switch (profile.runsPerWeek ?? 4) {
        <= 2 => 12.0,
        3 => 20.0,
        4 => 28.0,
        5 => 40.0,
        _ => 50.0,
      };
      await prefs.setDouble('weekly_mileage_km', fallbackWeeklyKm);
    }

    if (profile.trainingDays.isNotEmpty) {
      await TrainingDaysService.save(profile.trainingDays);
    }

    final raceDateRaw = prefs.getString('race_date');
    final weeklyKm = prefs.getDouble('weekly_mileage_km') ?? 0.0;
    final experienceLevel = prefs.getString('experience_level') ?? 'intermediate';
    final goalRace = prefs.getString('goal_race') ?? profile.goal ?? '5k';

    if (raceDateRaw != null) {
      final raceDate = DateTime.tryParse(raceDateRaw);
      if (raceDate != null) {
        final currentMemory = await EngineMemoryService().load();
        if (!currentMemory.hasRacePlan) {
          final racePlan = RacePlanBuilder.build(
            currentWeeklyKm: weeklyKm > 0 ? weeklyKm : 20.0,
            goalRace: goalRace,
            raceDate: raceDate,
            experienceLevel: experienceLevel,
          );
          await EngineMemoryService().saveRacePlan(racePlan);
        }
      }
    }
  }

  void _syncLocalProfileToCloud() {
    SharedPreferences.getInstance().then((prefs) {
      final goal = prefs.getString('goal_race');
      final experience = prefs.getString('experience_level');
      if (goal == null && experience == null) return;

      final raceDateRaw = prefs.getString('race_date');
      final profile = UserProfile(
        goal: goal,
        runsPerWeek: prefs.getInt('runs_per_week'),
        paceDistance: prefs.getString('pace_distance'),
        paceMinutes: prefs.getInt('pace_minutes'),
        paceSeconds: prefs.getInt('pace_seconds'),
        trainingDays: _trainingDayIndices,
        raceDate: raceDateRaw != null ? DateTime.tryParse(raceDateRaw) : null,
        gender: prefs.getString('gender'),
        dob: prefs.getString('dob') != null
            ? DateTime.tryParse(prefs.getString('dob')!)
            : null,
      );
      ProfileService.instance.saveProfile(profile);
    });
  }

  double _estimateWeeklyVolume(List<RunHistory> runs) {
    if (runs.isEmpty) return 0;
    final now = DateTime.now();
    final fourWeeksAgo = now.subtract(const Duration(days: 28));
    final recentRuns = runs.where((r) => r.date.isAfter(fourWeeksAgo)).toList();
    if (recentRuns.isEmpty) return 0;
    final totalKm = recentRuns.fold(0.0, (sum, r) => sum + r.distance);
    final weeks = now.difference(recentRuns.last.date).inDays / 7.0;
    return weeks > 0 ? totalKm / weeks : totalKm;
  }

  bool _planCoversThisWeek(WeeklyPlan plan) {
    final diff = DateTime.now().difference(plan.weekStartDate).inDays;
    return diff >= 0 && diff < 7;
  }

  void _handleSkip() {
    final plan = _activePlan;
    if (plan == null) return;
    SkipService.applySkip(
      skipDate: DateTime.now(),
      plan: plan,
      trainingDayIndices: _trainingDayIndices,
    ).then((result) async {
      await EngineMemoryService().saveActivePlan(result.plan);
      if (!mounted) return;
      setState(() {
         _activePlan = result.plan;
         _coachMessage = null;
         _workoutModel = const WorkoutDisplayModel(
            category: WorkoutCategory.rest,
            title: 'Rest Day',
            coachingReason: 'Skipped for today. Rest up and come back stronger.',
            steps: [],
          );
        });

    });
  }

  selector.RunAnalysis _buildRunAnalysis(List<RunHistory> runs) {
    return selector.RunAnalysis(
      avgRpe: _averageRecentRpe(runs),
      recentRpeTrend: _deriveRecentRpeTrend(runs),
      lastEasyRunTooHard: _lastEasyRunTooHard(runs),
    );
  }

  double? _averageRecentRpe(List<RunHistory> runs) {
    final recentRpe = [...runs]..sort((a, b) => b.date.compareTo(a.date));
    final values = recentRpe
        .where((r) => r.rpe != null)
        .take(3)
        .map((r) => r.rpe!.toDouble())
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  selector.RecentRpeTrend _deriveRecentRpeTrend(List<RunHistory> runs) {
    final rpeRuns = [...runs]..sort((a, b) => b.date.compareTo(a.date));
    final recentRpe = rpeRuns
        .where((r) => r.rpe != null)
        .take(4)
        .map((r) => r.rpe!.toDouble())
        .toList();
    if (recentRpe.length < 4) return selector.RecentRpeTrend.unknown;
    final latestAvg = (recentRpe[0] + recentRpe[1]) / 2.0;
    final previousAvg = (recentRpe[2] + recentRpe[3]) / 2.0;
    final delta = latestAvg - previousAvg;
    if (delta >= 0.75) return selector.RecentRpeTrend.increasing;
    if (delta <= -0.75) return selector.RecentRpeTrend.decreasing;
    return selector.RecentRpeTrend.stable;
  }

  bool _lastEasyRunTooHard(List<RunHistory> runs) {
    final sortedRuns = [...runs]..sort((a, b) => b.date.compareTo(a.date));
    for (final run in sortedRuns) {
      if (run.rpe == null) continue;
      if (run.workoutType == 'easy' || run.workoutType == 'recovery') {
        return run.rpe! >= 7;
      }
    }
    return false;
  }

  HistoricalTrainingData _buildHistoricalData(List<RunHistory> runs) {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final recentRuns = runs.where((r) => r.date.isAfter(weekAgo)).toList();

    int daysSinceQuality = 999;
    for (final run in runs) {
      if (run.workoutType == 'tempo' || run.workoutType == 'interval') {
        daysSinceQuality = now.difference(run.date).inDays;
        break;
      }
    }

    int daysSinceLong = 999;
    for (final run in runs) {
      if (run.workoutType == 'long') {
        daysSinceLong = now.difference(run.date).inDays;
        break;
      }
    }

    final savedRuns = runs
        .map((r) => SavedRun(
              distance: r.distance,
              averagePace: r.averagePace,
              date: r.date,
              gpsPoints: r.gpsPoints,
              rpe: r.rpe,
              workoutType: r.workoutType,
            ))
        .toList();

    return HistoricalTrainingData(
      daysSinceLastQuality: daysSinceQuality,
      daysSinceLastLongRun: daysSinceLong,
      weeklyVolume: recentRuns.fold(0.0, (sum, r) => sum + r.distance),
      recentRuns: savedRuns,
    );
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

  double _convertDistance(double km) =>
      _distanceUnit == 'miles' ? km * 0.621371 : km;

  String get _distanceLabel => _distanceUnit == 'miles' ? 'mi' : 'km';

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) {
      return 'Today at ${DateFormat('HH:mm').format(date)}';
    } else if (diff.inDays == 1) {
      return 'Yesterday at ${DateFormat('HH:mm').format(date)}';
    } else if (diff.inDays < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMM dd').format(date);
    }
  }

  selector.WorkoutId? _resolveLastWorkoutId(String lastWorkoutType) {
    switch (lastWorkoutType) {
      case 'tempo':    return selector.WorkoutId.tempoRun;
      case 'interval': return selector.WorkoutId.intervalWorkout;
      case 'long':     return selector.WorkoutId.longEasy;
      case 'recovery': return selector.WorkoutId.recoveryRun;
      case 'easy':     return selector.WorkoutId.easyRun;
      default:         return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Home', style: TextStyle(
          fontWeight: FontWeight.w600, color: Color(0xFF000000),
          fontSize: 16, letterSpacing: -0.3,
        )),
        centerTitle: true, elevation: 0,
        backgroundColor: const Color(0xFFFFFFFF),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF000000)))
          : _buildDashboardContent(),
    );
  }

  Widget _buildDashboardContent() {
    return RefreshIndicator(
      color: const Color(0xFF000000),
      onRefresh: loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionLabel("TODAY'S WORKOUT"),
              const SizedBox(height: 10),
              WorkoutCard(
                workout: _workoutModel ?? const WorkoutDisplayModel(
                  category: WorkoutCategory.rest,
                  title: 'Rest Day',
                  coachingReason: 'Rest up today. Your next workout is already lined up.',
                  steps: [],
                ),
                onTap: _coachMessage != null
                    ? () => showPreRunCheck(
                          context: context,
                          coachMessage: _coachMessage!,
                          onProceed: (scaled) => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PreRunBriefingScreen(
                                coachMessage: scaled,
                                onGoToRun: () => widget.onNavigateToRun?.call(),
                              ),
                            ),
                          ),
                          onSkip: _handleSkip,
                        )
                    : null,
              ),
              const SizedBox(height: 16),
              if (_lastRun == null && _workoutModel?.category != WorkoutCategory.rest) ...[
                _buildWelcomeHeroCard(),
                const SizedBox(height: 16),
              ],
              _buildSectionLabel('YOUR WEEK'),
              const SizedBox(height: 10),
              _buildBottomCarousel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(text, style: const TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600,
      color: Color(0xFF999999), letterSpacing: 1.2,
    ));
  }


  Widget _buildBottomCarousel() {
    final cardWidth = MediaQuery.of(context).size.width - 60;
    final cards = <Widget>[
      _buildWeeklyCarouselCard(cardWidth),
      _lastRun != null
          ? _buildLastRunCarouselCard(cardWidth)
          : _buildFirstRunPromptCard(cardWidth),
    ];
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 20),
        physics: const BouncingScrollPhysics(),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }

  Widget _carouselShell({required Widget child, required double width}) {
  return Container(
    width: width, height: 190,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEEEEEE)),
    ),
    padding: const EdgeInsets.all(18),
    child: child,
  );
}

  Widget _buildWeeklyCarouselCard(double width) {
  final now = DateTime.now();
  final todayIndex = now.weekday - 1;
  const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  final weekMonday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));

  final runsThisWeek = _consistencyData?.runsThisWeek ??
      _runHistory.where((r) {
        final diff = now.difference(r.date).inDays;
        return diff < 7;
      }).length;
  final weeklyTarget = _trainingDayIndices.length;
  final ratio = weeklyTarget > 0
      ? (runsThisWeek / weeklyTarget).clamp(0.0, 1.0)
      : 0.0;

  return _carouselShell(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('THIS WEEK', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: Color(0xFF999999), letterSpacing: 1.2,
        )),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            final isToday = i == todayIndex;
            final dayDate = weekMonday.add(Duration(days: i));
            final hasRun = _dayHasRun(dayDate);
            return Column(
              children: [
                Text(dayLabels[i], style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday ? const Color(0xFF0A0A0A) : const Color(0xFF999999),
                )),
                const SizedBox(height: 8),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasRun ? const Color(0xFF0A0A0A) : Colors.transparent,
                    border: Border.all(
                      color: hasRun
                          ? Colors.transparent
                          : const Color(0xFFDDDDDD),
                      width: 1.5,
                    ),
                  ),
                  child: hasRun
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : null,
                ),
              ],
            );
          }),
        ),
        const Spacer(),
        RichText(
          text: TextSpan(children: [
            TextSpan(
              text: '$runsThisWeek',
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0A0A0A),
              ),
            ),
            TextSpan(
              text: ' / $weeklyTarget runs',
              style: const TextStyle(fontSize: 14, color: Color(0xFF999999)),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio, minHeight: 3,
            backgroundColor: const Color(0xFFEEEEEE),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0A0A0A)),
          ),
        ),
      ],
    ),
  );
}

  bool _dayHasRun(DateTime day) {
    for (final RunHistory r in _runHistory) {
      if (r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day) return true;
    }
    return false;
  }

  Widget _buildLastRunCarouselCard(double width) {
  return _carouselShell(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('LAST RUN', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: Color(0xFF999999), letterSpacing: 1.2,
        )),
        const SizedBox(height: 2),
        Text(_formatDate(_lastRun!.date), style: const TextStyle(
          fontSize: 11, color: Color(0xFF999999),
        )),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DIST', style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w600,
                    color: Color(0xFF999999), letterSpacing: 0.8,
                  )),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _convertDistance(_lastRun!.distance).toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w600,
                          color: Color(0xFF0A0A0A), letterSpacing: -0.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 3),
                        child: Text(_distanceLabel, style: const TextStyle(
                          fontSize: 12, color: Color(0xFF999999),
                          fontWeight: FontWeight.w500,
                        )),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PACE', style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w600,
                    color: Color(0xFF999999), letterSpacing: 0.8,
                  )),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_lastRun!.averagePace, style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w600,
                        color: Color(0xFF0A0A0A), letterSpacing: -0.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      )),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4, left: 3),
                        child: Text('/km', style: TextStyle(
                          fontSize: 12, color: Color(0xFF999999),
                          fontWeight: FontWeight.w500,
                        )),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_lastRun!.rpe != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Text('RPE ${_lastRun!.rpe}/10', style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0A0A0A),
            )),
          ),
        ],
      ],
    ),
  );
}


  Widget _buildFirstRunPromptCard(double width) {
    return _carouselShell(
      width: width,
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_run,
                color: Color(0xFF999999), size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No runs yet', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: Color(0xFF0A0A0A),
                )),
                SizedBox(height: 4),
                Text(
                  'Head to the Run tab to record your first run',
                  style: TextStyle(
                    fontSize: 12, color: Color(0xFF999999), height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeroCard() {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      border: Border.all(color: const Color(0xFFEEEEEE)),
    ),
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFDDDDDD)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('WELCOME', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: Color(0xFF999999), letterSpacing: 2,
          )),
        ),
        const SizedBox(height: 20),
        const Text('Ready to\ntrain?', style: TextStyle(
          fontSize: 48, fontWeight: FontWeight.w800,
          color: Color(0xFF0A0A0A), height: 1.05, letterSpacing: -1.5,
        )),
        const SizedBox(height: 12),
        const Text(
          'Complete your first run to unlock\nyour adaptive plan.',
          style: TextStyle(fontSize: 13, color: Color(0xFF999999), height: 1.6),
        ),
      ],
    ),
  );
}
}
