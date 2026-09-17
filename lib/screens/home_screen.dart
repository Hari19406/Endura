import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../utils/stats.dart';
import '../engines/coach_engine_v2.dart';
import '../engines/plan/plan_store.dart';
import '../engines/plan/plan_materialization_coordinator.dart';
import '../engines/plan/materialized_plan.dart';
import '../services/plan_adaptation_coordinator.dart';
import '../services/workout_compliance_coordinator.dart';
import '../services/workout_compliance_matcher.dart';
import '../widgets/build_plan_hero_card.dart';
import '../widgets/plan_adaptation_card.dart';
import '../widgets/previous_plans_section.dart';
import '../widgets/unlock_training_bottom_sheet.dart';
import '../models/scheduled_workout_context.dart';
import '../engines/progression_decision.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engines/memory/engine_memory_service.dart';
import '../engines/memory/engine_memory.dart';
import '../utils/database_service.dart';
import '../models/weekly_plan.dart';
import '../models/workout_type.dart';
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
import '../screens/plan_complete_screen.dart';
import '../screens/manage_plan_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/paywall_screen.dart';
import '../screens/plan_overview_screen.dart';
import '../utils/workout_type_style.dart';
import '../services/analytics_service.dart';
import '../services/revenue_cat_service.dart';
import '../services/weather_service.dart';
import '../utils/unit_utils.dart';

// Import the shortened onboarding for post-plan re-onboarding.
import '../onboarding/onboarding_screen.dart' show OnboardingScreen;

enum WorkoutCategory { easy, tempo, interval, long, rest }

class WorkoutDisplayStyle {
  final WorkoutCategory category;
  final String badgeLabel;
  final IconData icon;

  const WorkoutDisplayStyle({
    required this.category,
    required this.badgeLabel,
    required this.icon,
  });
}

/// Badge/icon accent for a workout category — resolves through the shared
/// [AppColors] workout-type tokens instead of a locally hardcoded palette.
Color workoutCategoryColor(BuildContext context, WorkoutCategory category) {
  final c = context.colors;
  return switch (category) {
    WorkoutCategory.easy => c.workoutEasy,
    WorkoutCategory.tempo => c.workoutTempo,
    WorkoutCategory.interval => c.workoutInterval,
    WorkoutCategory.long => c.workoutLong,
    WorkoutCategory.rest => c.workoutRest,
  };
}

WorkoutDisplayStyle _workoutDisplayStyle(WorkoutIntent intent) {
  return switch (intent) {
    WorkoutIntent.aerobicBase => const WorkoutDisplayStyle(
      category: WorkoutCategory.easy,
      badgeLabel: 'EASY',
      icon: Icons.directions_run,
    ),
    WorkoutIntent.endurance => const WorkoutDisplayStyle(
      category: WorkoutCategory.long,
      badgeLabel: 'ENDURANCE',
      icon: Icons.landscape_outlined,
    ),
    WorkoutIntent.threshold => const WorkoutDisplayStyle(
      category: WorkoutCategory.tempo,
      badgeLabel: 'QUALITY',
      icon: Icons.bolt,
    ),
    WorkoutIntent.vo2max => const WorkoutDisplayStyle(
      category: WorkoutCategory.interval,
      badgeLabel: 'QUALITY',
      icon: Icons.repeat_rounded,
    ),
    WorkoutIntent.speed => const WorkoutDisplayStyle(
      category: WorkoutCategory.interval,
      badgeLabel: 'SPEED',
      icon: Icons.flash_on,
    ),
    WorkoutIntent.raceSpecific => const WorkoutDisplayStyle(
      category: WorkoutCategory.tempo,
      badgeLabel: 'RACE PACE',
      icon: Icons.flag_outlined,
    ),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKOUT DISPLAY MODEL
// ─────────────────────────────────────────────────────────────────────────────

class WorkoutDisplayModel {
  final WorkoutCategory category;
  final String title;
  final String coachingReason;
  final String coachingWhy;
  final String? duration;
  final String? paceRange;
  final String? distance;
  final List<String> steps;
  final ResolvedWorkout? resolvedWorkout;
  final String goalText;
  final String feelText;
  final String phaseLabel;
  final String feelHint;

  /// Set when a logged run has been matched to this scheduled day
  /// (WorkoutComplianceMatcher). The card then shows the actual stats + a
  /// completed badge instead of the Start-Run CTA.
  final bool completed;
  final String? completedStats;

  const WorkoutDisplayModel({
    required this.category,
    required this.title,
    required this.coachingReason,
    this.coachingWhy = '',
    this.duration,
    this.paceRange,
    this.distance,
    required this.steps,
    this.resolvedWorkout,
    this.goalText = '',
    this.feelText = '',
    this.phaseLabel = '',
    this.feelHint = '',
    this.completed = false,
    this.completedStats,
  });

  factory WorkoutDisplayModel.fromCoachMessage(
    CoachMessage msg, {
    DayCompletion? completion,
  }) {
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

    final steps = List<String>.from(msg.workoutSteps);

    final feelHint = switch (msg.workoutIntent) {
      WorkoutIntent.aerobicBase => 'Conversational pace',
      WorkoutIntent.endurance => 'Easy and steady',
      WorkoutIntent.threshold => 'Comfortably hard',
      WorkoutIntent.vo2max => 'Hard intervals',
      WorkoutIntent.speed => 'Short and snappy',
      WorkoutIntent.raceSpecific => 'Race pace',
    };

    return WorkoutDisplayModel(
      category: displayStyle.category,
      title: msg.workoutTitle,
      coachingReason: msg.reflectionText,
      coachingWhy: msg.acknowledgementText,
      duration: duration,
      paceRange: paceRange,
      distance: distance,
      steps: steps,
      resolvedWorkout: workout,
      goalText: msg.goalText,
      feelText: msg.feelText,
      phaseLabel: msg.phaseLabel,
      feelHint: feelHint,
      completed: completion != null,
      completedStats: completion == null
          ? null
          : WorkoutComplianceMatcher.completedStatsLabel(
              completion,
              useMiles: UnitUtils.useMilesNotifier.value,
            ),
    );
  }

  factory WorkoutDisplayModel.empty() {
    return const WorkoutDisplayModel(
      category: WorkoutCategory.rest,
      title: 'Your first run is waiting',
      coachingReason:
          "Max needs to see you run before building your plan. Head to the Run tab and log your first session.",
      coachingWhy: "It only takes one run — Max will take it from there.",
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
  final bool locked;

  const WorkoutCard({
    super.key,
    required this.workout,
    this.onTap,
    this.locked = false,
  });

  WorkoutDisplayStyle get _style {
    switch (workout.category) {
      case WorkoutCategory.tempo:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.tempo,
          badgeLabel: 'QUALITY',
          icon: Icons.bolt,
        );
      case WorkoutCategory.interval:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.interval,
          badgeLabel: 'QUALITY',
          icon: Icons.repeat_rounded,
        );
      case WorkoutCategory.long:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.long,
          badgeLabel: 'ENDURANCE',
          icon: Icons.landscape_outlined,
        );
      case WorkoutCategory.rest:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.rest,
          badgeLabel: 'REST',
          icon: Icons.bedtime_outlined,
        );
      case WorkoutCategory.easy:
        return const WorkoutDisplayStyle(
          category: WorkoutCategory.easy,
          badgeLabel: 'EASY',
          icon: Icons.directions_run,
        );
    }
  }

  Color _accent(BuildContext context) =>
      workoutCategoryColor(context, _style.category);
  String get _badge => _style.badgeLabel;
  IconData get _icon => _style.icon;
  bool get _isEmpty =>
      workout.category == WorkoutCategory.rest && workout.steps.isEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!locked) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _accent(context).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_icon, size: 13, color: _accent(context)),
                        const SizedBox(width: 6),
                        Text(
                          _badge,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _accent(context),
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (workout.feelHint.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.divider,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 11,
                            color: Color(0xFF00A08A),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            workout.feelHint,
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
            ],
            if (locked) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 22,
                    color: c.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Subscribe to Endura Pro to unlock today\'s workout',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                        letterSpacing: -0.4,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (onTap != null)
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: onTap == null
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            onTap!();
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Unlock Workout',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                  ),
                ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      workout.title,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                        letterSpacing: -0.8,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (workout.completed) ...[
                    const SizedBox(width: 12),
                    _CompletedBadge(),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              if (workout.completed) ...[
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: c.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        workout.completedStats ?? 'Completed',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (onTap != null)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onTap!();
                        },
                        child: Text(
                          'View',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ] else
                Row(
                  children: [
                    if (workout.distance != null)
                      _chipWidget(context, Icons.straighten, workout.distance!),
                    const Spacer(),
                    if (!_isEmpty && onTap != null)
                      GestureDetector(
                        onTap: onTap == null
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                onTap!();
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View Workout',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.onAccent,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: c.onAccent,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipWidget(BuildContext context, IconData icon, String label) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.divider,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c.textTertiary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small green "COMPLETED" pill shown on the WorkoutCard when a logged run has
/// been matched to today's scheduled session.
class _CompletedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.success.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 13, color: c.success),
          const SizedBox(width: 5),
          Text(
            'COMPLETED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: c.success,
            ),
          ),
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

  /// Emits the resolved plan slot for today's workout (or null on a rest / no-
  /// plan day) so the Record tab can start a guided run already linked to it.
  final void Function(ScheduledWorkoutContext?)? onScheduledContextReady;

  /// Coach tab → "Free Run": jump to the Record tab and start an unguided run.
  final VoidCallback? onQuickStartFreeRun;

  const HomeScreen({
    super.key,
    this.onNavigateToYou,
    this.onNavigateToRun,
    this.onRunCompleted,
    this.onCoachMessageReady,
    this.onScheduledContextReady,
    this.onQuickStartFreeRun,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin
    implements Refreshable {
  CoachMessage? _coachMessage;
  WorkoutDisplayModel? _workoutModel;
  bool _isLoading = true;
  bool _isFetching = false;
  String _distanceUnit = 'km';
  List<RunHistory> _runHistory = [];
  bool _isLoaded = false;
  late final CoachEngine _coachEngine;
  final message.CoachMessageBuilder _messageBuilder =
      message.CoachMessageBuilder();
  WeeklyPlan? _activePlan;

  /// Shown when the materialised plan has not landed yet (first run after
  /// onboarding, or a slow background materialisation). Never a recompute.
  static const _planResolvingModel = WorkoutDisplayModel(
    category: WorkoutCategory.easy,
    title: 'Preparing your plan',
    coachingReason:
        "Max is finishing your training plan. Give it a moment and pull to "
        "refresh — your first session will appear right here.",
    steps: [],
  );

  static const _restDayModel = WorkoutDisplayModel(
    category: WorkoutCategory.rest,
    title: 'Rest Day',
    coachingReason: 'Rest up today. Your next workout is already lined up.',
    steps: [],
  );
  List<int> _trainingDayIndices = const [];
  ConsistencyData? _consistencyData;
  EngineMemory? _engineMemory;

  /// The current week's materialized data — reused from the same
  /// `getTodayDayContext` call `loadData()` already makes, so the "THIS WEEK"
  /// strip's day-tap and distance labels need no extra load of their own.
  MaterializedWeek? _thisWeekMaterialized;

  /// The owning plan's id/build-anchor for [_thisWeekMaterialized] — needed to
  /// build a [ScheduledWorkoutContext] when a day-dot tap starts a run.
  String? _thisWeekPlanId;
  DateTime? _thisWeekPlanBuiltAt;

  // ── Plan adaptation (inline coach banner) ─────────────────────────────────
  /// A missed-block recalibration the athlete has not yet accepted or
  /// dismissed. Null when there is nothing to review.
  AdaptationPrompt? _adaptationPrompt;

  /// The `rangeKey` the athlete last accepted or dismissed — persisted so the
  /// same gap never re-prompts (a longer gap gets a new key and still can).
  String? _adaptationHandledKey;

  /// True while the accept write is in flight.
  bool _adaptationBusy = false;

  static const _adaptationHandledKeyPref = 'plan_adaptation_handled_key';

  /// Today's resolved plan slot — passed into the run tracker so a guided run
  /// drives the step HUD and links straight onto the plan day on save. Null on
  /// a rest / no-plan day.
  ScheduledWorkoutContext? _scheduledContext;

  // ── Greeting / header state ───────────────────────────────────────────────
  String _userName = '';
  DateTime? _raceDate;
  String _goalRaceName = '';
  WeatherSnapshot? _weather;

  // ── Post-plan flow state ───────────────────────────────────────────────────
  /// True when plan is complete and the celebration card should show.
  bool _showPlanComplete = false;

  /// vDOT before the plan started — stored in prefs during re-onboarding kick-off.
  int _vdotBeforePlan = 40;

  /// Total km run during the completed plan (approximated from run history).
  double _planTotalKm = 0.0;

  /// Display label for the completed race.
  String _completedRaceLabel = 'your';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _coachEngine = CoachEngine();
    _distanceUnit = UnitUtils.useMilesNotifier.value ? 'miles' : 'km';
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLoaded || _isLoading) {
      loadData();
      _isLoaded = true;
    }
  }

  void _onUnitPrefChanged() {
    if (mounted) {
      setState(
        () => _distanceUnit = UnitUtils.useMilesNotifier.value ? 'miles' : 'km',
      );
    }
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Resolve display name — first word only to avoid overflow.
      String name = prefs.getString('user_name') ?? '';
      if (name.isEmpty) {
        final user = Supabase.instance.client.auth.currentUser;
        final meta = user?.userMetadata;
        name =
            (meta?['name'] as String?) ?? (meta?['full_name'] as String?) ?? '';
        if (name.isEmpty) {
          name = user?.email?.split('@').first ?? '';
        }
      }
      if (mounted) {
        setState(() {
          _userName = name.split(' ').first;
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  bool _cloudRestoreAttempted = false;

  Future<void> _restoreFromCloudIfNeeded({bool force = false}) async {
    if (_cloudRestoreAttempted && !force) return;
    _cloudRestoreAttempted = true;
    try {
      await CloudSyncService.instance.downloadAndRestoreRuns();
      debugPrint('[HomeScreen] Cloud restore complete');
    } catch (e) {
      debugPrint('[HomeScreen] Cloud restore failed: $e');
    }
  }

  @override
  Future<void> loadData({bool forceCloudRestore = false}) async {
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
      await Future.wait([
        _restoreFromCloudIfNeeded(force: forceCloudRestore),
        _loadSettings(),
      ]);
      await _restoreCloudCoachingState();
      await _hydrateLocalProfileFromCloud();
      CloudSyncService.instance.syncPendingRuns();
      _syncLocalProfileToCloud();
      _trainingDayIndices = await TrainingDaysService.loadOrDefault(4);

      final List<RunHistory> runs = await loadSavedRuns();
      if (!mounted) return;

      var memory = await EngineMemoryService().load();

      // ── Post-plan state check (before anything else) ─────────────────────
      final postPlanResult = _coachEngine.checkAndApplyPostPlanState(memory);
      if (postPlanResult.justCompleted ||
          postPlanResult.justEnteredMaintenance) {
        await EngineMemoryService().save(postPlanResult.memory);
        memory = postPlanResult.memory;
      }

      _engineMemory = memory;
      _runHistory = runs;

      // ── Populate post-plan display fields ────────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      _vdotBeforePlan =
          memory.vdotAtPlanStart ??
          prefs.getInt('vdot_before_plan') ??
          memory.vdotScore;
      _completedRaceLabel = _raceLabel(prefs.getString('goal_race') ?? '5k');
      _planTotalKm = runs.fold(0.0, (sum, r) => sum + r.distance);

      // Race countdown chip — explicit race_date pref wins, otherwise use plan end date
      final raceDateStr = prefs.getString('race_date');
      _raceDate =
          (raceDateStr != null ? DateTime.tryParse(raceDateStr) : null) ??
          _engineMemory?.racePlan?.raceDate;
      _goalRaceName = _raceLabel(
        prefs.getString('goal_race') ??
            _engineMemory?.racePlan?.goalRace ??
            '5k',
      );

      if (memory.isPlanComplete && !memory.isInMaintenance) {
        final snoozeStr = prefs.getString('plan_complete_snooze_until');
        final snoozeUntil = snoozeStr != null
            ? DateTime.tryParse(snoozeStr)
            : null;
        final isSnoozed =
            snoozeUntil != null && DateTime.now().isBefore(snoozeUntil);
        if (!isSnoozed) {
          setState(() {
            _showPlanComplete = true;
            _isLoading = false;
          });
          _isFetching = false;
          return;
        }
      }
      _showPlanComplete = false;

      // ── Normal plan flow ─────────────────────────────────────────────────
      if (memory.activePlan == null ||
          !_planCoversThisWeek(memory.activePlan!)) {
        final newPlan = WeeklyGenerator.generate(
          startDate: DateTime.now(),
          lastCompletedType: memory.lastCompletedType,
          phase: memory.currentPhase,
          totalRunsCompleted: memory.totalRunsCompleted,
          trainingDayIndices: _trainingDayIndices,
        );
        await EngineMemoryService().saveActivePlan(newPlan);
        _engineMemory = memory.copyWith(activePlan: newPlan);
        _activePlan = newPlan;
        await Analytics.planCreated(
          goal: prefs.getString('goal_race') ?? 'unknown',
          level: prefs.getString('experience_level') ?? 'unknown',
        );
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

      // ── Post-run compliance matching (additive only) ───────────────────────
      // Link runs the athlete already logged back to the day they were
      // scheduled for, so the Coach card / calendar can show them ticked off.
      // Never moves or rewrites a workout — that is PlanAdaptation's job, which
      // stays unwired.
      await WorkoutComplianceCoordinator.instance.sync();

      // ── Today's session — read straight from the persisted MaterializedPlan.
      // No ad-hoc recomputation, no adaptation sweep: the Coach tab shows the
      // stored workout exactly as materialised. A missed day just stays
      // uncompleted — nothing is reshuffled behind the athlete's back.
      // (PlanAdaptation stays in the codebase as a pure utility, unwired.)
      try {
        final now = DateTime.now();
        final weekNumber = memory.racePlan?.currentWeekNumber(now) ?? 1;
        var dayContext = await PlanStore.instance.getTodayDayContext(
          weekNumber: weekNumber,
          now: now,
        );

        // Self-heal: a real racePlan skeleton exists but PlanStore has no
        // matching MaterializedPlan for it (the persist write raced
        // onboarding finishing, a reinstall's local cache cleared before
        // cloud sync landed, or any other drift). Nothing was ever rebuilding
        // this — the Coach card was showing "Preparing your plan" forever
        // with no path out. Rebuild once, right here, so today's workout can
        // still render on this same pass instead of leaving the athlete
        // stuck until they happen to hit a screen that does trigger a
        // recompute (ManagePlanScreen).
        if (dayContext == null && memory.racePlan != null) {
          debugPrint(
            '[HomeScreen] No MaterializedPlan for week $weekNumber — '
            'rebuilding from the stored racePlan skeleton.',
          );
          try {
            final rebuilt = await PlanMaterializationCoordinator.instance
                .recompute(
                  skeleton: memory.racePlan,
                  trainingDayIndices: _trainingDayIndices,
                  longRunDayIndex: memory.longRunDayIndex,
                  goalRace: memory.racePlan!.goalRace,
                  experienceLevel: memory.racePlan!.experienceLevel,
                  vdot: memory.vdotScore,
                  now: now,
                );
            if (rebuilt != null) {
              dayContext = rebuilt.contextForWeekday(
                weekNumber: weekNumber,
                weekdayIndex: now.weekday - 1,
              );
            }
          } catch (e, stack) {
            debugPrint('[HomeScreen] Plan rebuild failed: $e\n$stack');
          }
        }

        _thisWeekMaterialized = dayContext?.week;
        _thisWeekPlanId = dayContext?.plan.planId;
        _thisWeekPlanBuiltAt = dayContext?.plan.builtAt;

        if (dayContext == null) {
          _coachMessage = null;
          _workoutModel = _planResolvingModel;
          _scheduledContext = null;
        } else if (dayContext.isRest) {
          _coachMessage = null;
          _workoutModel = _restDayModel;
          _scheduledContext = null;
        } else {
          final next = _nextPlannedSession(dayContext.week, now);
          final built = _messageBuilder.buildMessage(
            context: _coachContextFrom(memory, runs, now),
            resolvedWorkout: dayContext.day.workout!,
            phase: dayContext.week.phase,
            weekNumber: dayContext.week.weekNumber,
            nextPlannedIntent: next.$1,
            nextPlannedLabel: next.$2,
          );
          _coachMessage = built;
          _workoutModel = WorkoutDisplayModel.fromCoachMessage(
            built,
            completion: dayContext.day.completion,
          );
          // Already logged today? Then there's nothing to start — leave the
          // link null so a bonus run stays a free run.
          _scheduledContext = dayContext.isCompleted
              ? null
              : ScheduledWorkoutContext.fromDayContext(dayContext);
        }

        widget.onCoachMessageReady?.call(_coachMessage);
        widget.onScheduledContextReady?.call(_scheduledContext);

        // Weekly planned volume comes straight off the materialised week.
        // setWeeklyPlannedKm early-returns when unchanged (~one write/week).
        final plannedKm = dayContext?.week.targetKm ?? 0;
        if (plannedKm > 0) {
          await EngineMemoryService().setWeeklyPlannedKm(plannedKm);
        }
      } catch (e, stack) {
        debugPrint('Error reading materialised plan: $e');
        debugPrint('$stack');
        _coachMessage = null;
        _workoutModel = _planResolvingModel;
        _scheduledContext = null;
        widget.onCoachMessageReady?.call(null);
        widget.onScheduledContextReady?.call(null);
      }

      // ── Missed-block detection → inline coach banner ────────────────────
      // Opt-in only: PlanAdaptationCoordinator computes what changed and the
      // athlete reviews it. Nothing is applied until they tap "Review &
      // Accept". Failure here never blocks the dashboard.
      try {
        _adaptationHandledKey = prefs.getString(_adaptationHandledKeyPref);
        final materialized = await PlanStore.instance.load();
        if (materialized != null && !_showPlanComplete) {
          final now = DateTime.now();
          final weeksToRace = _raceDate != null
              ? _raceDate!.difference(now).inDays ~/ 7
              : materialized.totalWeeks;
          final prompt = const PlanAdaptationCoordinator().detect(
            plan: materialized,
            completedRunDates: runs.map((r) => r.date),
            now: now,
            remainingWeeksToRace: weeksToRace < 0 ? 0 : weeksToRace,
          );
          final fresh =
              prompt != null && prompt.rangeKey != _adaptationHandledKey;
          if (fresh && _adaptationPrompt?.rangeKey != prompt.rangeKey) {
            Analytics.capture(
              'plan_adaptation_shown',
              properties: {
                'window': prompt.missedWindow.name,
                'missed_sessions': prompt.missedSessions,
              },
            );
          }
          _adaptationPrompt = fresh ? prompt : null;
        } else {
          _adaptationPrompt = null;
        }
      } catch (e) {
        debugPrint('[HomeScreen] adaptation detect failed: $e');
        _adaptationPrompt = null;
      }

      _consistencyData = await ConsistencyService.compute();
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      _isFetching = false;
      if (mounted) setState(() => _isLoading = false);
    }

    // Fire-and-forget — never blocks initial paint, chip just appears late.
    WeatherService.getCurrentWeather(forceRefresh: forceCloudRestore).then((
      weather,
    ) {
      if (mounted && weather != null) setState(() => _weather = weather);
    });
  }

  // ── Post-plan actions ──────────────────────────────────────────────────────

  /// User tapped "Start your next plan" — save vDOT snapshot, launch shortened onboarding.
  Future<void> _onStartNextPlan() async {
    HapticFeedback.mediumImpact();
    final memory = _engineMemory;
    if (memory == null) return;

    // Snapshot current vDOT so celebration card can show before→after next time.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vdot_before_plan', memory.vdotScore);
    await prefs.remove('plan_complete_snooze_until');

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          shortenedMode: true,
          onComplete: () {
            Navigator.of(context).pop();
            loadData();
          },
        ),
      ),
    );
  }

  /// User tapped "I need a break — remind me in 2 weeks".
  Future<void> _onRemindLater() async {
    final prefs = await SharedPreferences.getInstance();
    final remindDate = DateTime.now().add(const Duration(days: 14));
    await prefs.setString(
      'plan_complete_snooze_until',
      remindDate.toIso8601String(),
    );
    // Sync to Supabase so snooze survives a device switch
    ProfileService.instance
        .updateField(
          'plan_snooze_until',
          remindDate.toIso8601String().substring(0, 10),
        )
        .ignore();
    setState(() => _showPlanComplete = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Got it! We'll check in with you in 2 weeks."),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  String _raceLabel(String goalRace) => switch (goalRace) {
    '10k' => '10K',
    'half_marathon' => 'Half Marathon',
    'marathon' => 'Marathon',
    _ => '5K',
  };

  // ── Plan adaptation banner actions ───────────────────────────────────────

  /// "Review & Accept" — persist the recalibrated plan and refresh the
  /// dashboard off it. The range is also marked handled so it never re-prompts.
  Future<void> _onAcceptAdaptation() async {
    final prompt = _adaptationPrompt;
    if (prompt == null || _adaptationBusy) return;
    HapticFeedback.mediumImpact();
    setState(() => _adaptationBusy = true);
    try {
      await PlanStore.instance.saveAndSync(prompt.recalibration.updatedPlan);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_adaptationHandledKeyPref, prompt.rangeKey);
      _adaptationHandledKey = prompt.rangeKey;
      Analytics.capture(
        'plan_adaptation_accepted',
        properties: {
          'window': prompt.missedWindow.name,
          'missed_sessions': prompt.missedSessions,
        },
      );
    } catch (e) {
      debugPrint('[HomeScreen] adaptation accept failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _adaptationBusy = false;
      _adaptationPrompt = null;
    });
    await loadData();
  }

  /// "Dismiss" — remember this specific missed range so it stops nagging, but
  /// leave the plan untouched.
  Future<void> _onDismissAdaptation() async {
    final prompt = _adaptationPrompt;
    if (prompt == null) return;
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adaptationHandledKeyPref, prompt.rangeKey);
    _adaptationHandledKey = prompt.rangeKey;
    Analytics.capture(
      'plan_adaptation_dismissed',
      properties: {
        'window': prompt.missedWindow.name,
        'missed_sessions': prompt.missedSessions,
      },
    );
    if (!mounted) return;
    setState(() => _adaptationPrompt = null);
  }

  // ── Cloud / profile helpers (unchanged) ───────────────────────────────────

  Future<void> _restoreCloudCoachingState() async {
    final cloudState = await EngineStateSyncService.instance
        .fetchCloudCoachingState();
    final cloudMemory = cloudState.memory;
    final cloudDays = cloudState.trainingDays;

    // ── Training days: last-write-wins by timestamp, with the old
    // "local is empty" rule kept as a fallback for devices that predate
    // the updatedAt tracking (no local timestamp recorded yet). ─────────
    final localDays = await TrainingDaysService.load();
    final localDaysUpdatedAt = await TrainingDaysService.loadUpdatedAt();
    final cloudDaysNewer =
        cloudDays != null &&
        (localDaysUpdatedAt == null ||
            (cloudState.trainingDaysUpdatedAt?.isAfter(localDaysUpdatedAt) ??
                false));
    if (cloudDays != null &&
        (localDays == null || !_intListsEqual(localDays, cloudDays)) &&
        (cloudDaysNewer || localDays == null)) {
      await TrainingDaysService.save(cloudDays, syncToCloud: false);
    } else if (localDays != null &&
        (cloudDays == null || !_intListsEqual(localDays, cloudDays)) &&
        !cloudDaysNewer) {
      await EngineStateSyncService.instance.syncTrainingDays(localDays);
    }

    // ── Engine memory (active plan, vDOT, race plan, etc.): same
    // last-write-wins policy so a device that already has local state
    // (e.g. a dev simulator) still picks up a newer plan pushed from
    // another device, instead of being stuck forever on its own copy. ──
    final localMemory = await EngineMemoryService().load();
    final localMemoryUpdatedAt = await EngineMemoryService().loadUpdatedAt();
    final cloudMemoryNewer =
        cloudMemory != null &&
        (localMemoryUpdatedAt == null ||
            (cloudState.memoryUpdatedAt?.isAfter(localMemoryUpdatedAt) ??
                false));
    final shouldRestoreCloudMemory =
        cloudMemory != null &&
        (cloudMemoryNewer || _shouldRestoreCloudMemory(localMemory));

    if (shouldRestoreCloudMemory) {
      await EngineMemoryService().save(cloudMemory, syncToCloud: false);
    } else if (!cloudMemoryNewer) {
      await EngineStateSyncService.instance.syncEngineMemory(localMemory);
    }
  }

  bool _shouldRestoreCloudMemory(EngineMemory localMemory) {
    final hasMeaningfulLocalState =
        localMemory.totalRunsCompleted > 0 ||
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
    if (prefs.containsKey('goal_race') && prefs.containsKey('experience_level'))
      return;

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
    final experienceLevel =
        prefs.getString('experience_level') ?? 'intermediate';
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

  bool _planCoversThisWeek(WeeklyPlan plan) {
    final diff = DateTime.now().difference(plan.weekStartDate).inDays;
    return diff >= 0 && diff < 7;
  }

  void _handleSkip() {
    final plan = _activePlan;
    if (plan == null) return;
    Analytics.planDaySkipped();
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

  int _paceToSeconds(String pace) {
    try {
      final parts = pace.split(':');
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (_) {}
    return 0;
  }

  // ── Coach narrative from the persisted plan ──────────────────────────────

  /// Light context for [message.CoachMessageBuilder] — real signals only, no
  /// session recomputation. Drawn from engine memory + recent run history.
  message.CoachContext _coachContextFrom(
    EngineMemory memory,
    List<RunHistory> runs,
    DateTime now,
  ) {
    final lastRun = memory.lastRunDate;
    final daysSinceLastRun = lastRun == null
        ? 999
        : now.difference(lastRun).inDays;
    final pacedRuns = runs
        .where((r) => _paceToSeconds(r.averagePace) > 0)
        .length;

    return message.CoachContext(
      totalRunsCompleted: memory.totalRunsCompleted,
      daysSinceLastRun: daysSinceLastRun,
      avgRpe: _averageRecentRpe(runs),
      highRpeRecently: memory.hasHighRpe(n: 2, threshold: 8, withinDays: 3),
      easyRunFeltTooHard: _lastEasyRunTooHard(runs),
      progression: _progressionSignal(memory.weeklyProgressionDecision),
      wasDowngraded: false,
      scalingAdjustments: const [],
      paceTrending: false,
      paceInsufficientData: pacedRuns < 3,
    );
  }

  message.ProgressionSignal _progressionSignal(ProgressionDecision? d) =>
      switch (d) {
        ProgressionDecision.progress => message.ProgressionSignal.progressing,
        ProgressionDecision.regress => message.ProgressionSignal.steppingBack,
        _ => message.ProgressionSignal.holding,
      };

  /// The next non-rest session later in [week], for the "up next" hint.
  (WorkoutIntent?, String?) _nextPlannedSession(
    MaterializedWeek week,
    DateTime now,
  ) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final todayIdx = now.weekday - 1;
    for (var i = todayIdx + 1; i < 7; i++) {
      MaterializedDay? day;
      for (final d in week.days) {
        if (d.weekday == i) {
          day = d;
          break;
        }
      }
      if (day == null || day.isRest || day.intent == null) continue;
      final label = (i - todayIdx) == 1 ? 'Tomorrow' : names[i];
      return (day.intent, '$label · ${_intentLabel(day.intent!)}');
    }
    return (null, null);
  }

  String _intentLabel(WorkoutIntent intent) => switch (intent) {
    WorkoutIntent.aerobicBase => 'Easy Run',
    WorkoutIntent.endurance => 'Long Run',
    WorkoutIntent.threshold => 'Threshold Run',
    WorkoutIntent.vo2max => 'Interval Session',
    WorkoutIntent.speed => 'Speed Session',
    WorkoutIntent.raceSpecific => 'Race Pace Run',
  };

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    final greetingText = _userName.isNotEmpty
        ? '$_greeting, $_userName'
        : _greeting;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        toolbarHeight: 76,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              greetingText,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('EEEE, MMM d').format(DateTime.now()),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: c.surface,
        actions: [
          IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              color: c.textTertiary,
              size: 22,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.8, -0.9),
            radius: 1.4,
            colors: [
              c.heroGradientEnd.withOpacity(0.24),
              c.heroGradientStart.withOpacity(0.08),
              c.background,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildDashboardContent(),
      ),
    );
  }

  Widget _buildDashboardContent() {
    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: () => loadData(forceCloudRestore: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_raceDate != null && _raceDate!.isAfter(DateTime.now())) ...[
                _buildRaceCountdownChip(),
                const SizedBox(height: 14),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionLabel("TODAY'S WORKOUT"),
                  if (_weather != null) _buildWeatherChip(),
                ],
              ),
              const SizedBox(height: 10),

              // ── Inline coach banner: missed-block recalibration ──────────
              // Sits above the daily workout card. Opt-in — the plan only
              // changes if the athlete taps "Review & Accept".
              if (!_showPlanComplete &&
                  _engineMemory?.hasRacePlan == true &&
                  _adaptationPrompt != null) ...[
                PlanAdaptationCard(
                  explanation: _adaptationPrompt!.coachExplanation,
                  window: _adaptationPrompt!.missedWindow,
                  busy: _adaptationBusy,
                  onReviewAccept: _onAcceptAdaptation,
                  onDismiss: _onDismissAdaptation,
                ),
                const SizedBox(height: 12),
              ],

              // ── Plan complete card OR no-plan CTA OR normal workout card ──
              if (_showPlanComplete && _engineMemory != null)
                PlanCompleteCard(
                  memory: _engineMemory!,
                  completedRaceLabel: _completedRaceLabel,
                  totalKmCompleted: _planTotalKm,
                  vdotBefore: _vdotBeforePlan,
                  useMiles: _distanceUnit == 'miles',
                  onStartNextPlan: _onStartNextPlan,
                  onRemindLater: _onRemindLater,
                )
              else if (_engineMemory?.hasRacePlan != true) ...[
                BuildPlanHeroCard(onStartPlan: _onStartNextPlan),
                const SizedBox(height: 12),
                const CoachPrinciplesCard(),
                const SizedBox(height: 20),
                PreviousPlansSection(useMiles: _distanceUnit == 'miles'),
              ] else
                ValueListenableBuilder<bool>(
                  valueListenable: RevenueCatService.isProNotifier,
                  builder: (context, isPro, _) {
                    // Same lock rule as the day-dots (_onThisWeekDayTap /
                    // PlanOverviewScreen): only a week *beyond* the current one
                    // is paywalled, never the current week. This card always
                    // shows today's workout, so workoutWeekNumber is always
                    // currentWeekNumber in practice — this stays effectively
                    // always-unlocked-by-week, same "defensive, not exercised
                    // today" shape as the day-dot check, kept explicit so both
                    // gates read the same and don't drift apart again.
                    final currentWeekNumber = _engineMemory?.racePlan
                        ?.currentWeekNumber(DateTime.now());
                    final workoutWeekNumber =
                        _thisWeekMaterialized?.weekNumber ?? currentWeekNumber;
                    final isWorkoutLocked =
                        !isPro &&
                        currentWeekNumber != null &&
                        workoutWeekNumber != null &&
                        workoutWeekNumber > currentWeekNumber;

                    return WorkoutCard(
                      workout:
                          _workoutModel ??
                          const WorkoutDisplayModel(
                            category: WorkoutCategory.rest,
                            title: 'Rest Day',
                            coachingReason:
                                'Rest up today. Your next workout is already lined up.',
                            steps: [],
                          ),
                      locked: isWorkoutLocked,
                      onTap: isWorkoutLocked
                          ? () => Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PaywallScreen(),
                              ),
                            )
                          : (_coachMessage != null
                                ? () {
                                    showPreRunCheck(
                                      context: context,
                                      coachMessage: _coachMessage!,
                                      weather: _weather,
                                      onProceed: (scaled) => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PreRunBriefingScreen(
                                            coachMessage: scaled,
                                            onGoToRun: () =>
                                                widget.onNavigateToRun?.call(),
                                            scheduledContext: _scheduledContext,
                                          ),
                                        ),
                                      ),
                                      onSkip: _handleSkip,
                                    );
                                  }
                                : null),
                    );
                  },
                ),

              if (_engineMemory?.hasRacePlan == true) ...[
                const SizedBox(height: 10),
                Semantics(
                  button: true,
                  label: 'Manage plan',
                  child: GestureDetector(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ManagePlanScreen(onPlanChanged: loadData),
                        ),
                      );
                      // Belt-and-suspenders: ManagePlanScreen already calls
                      // onPlanChanged (loadData) itself before popping, but
                      // that call is fire-and-forget from a VoidCallback — if
                      // it lands mid another in-flight loadData() and gets
                      // silently rescheduled, the UI can be left showing a
                      // stale plan state after returning here (e.g. "Remove
                      // Plan" not flipping to the empty-state cards). Always
                      // reloading again on return from this route, driven by
                      // this screen's own awaited navigation rather than the
                      // child's callback, guarantees the refresh actually
                      // lands.
                      if (mounted) await loadData();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        border: Border.all(
                          color: context.colors.border,
                          width: 1.0,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Manage Plan',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: context.colors.textTertiary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildSectionLabel('INSIGHTS'),
              const SizedBox(height: 10),
              _buildBottomCarousel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRaceCountdownChip() {
    final days = _raceDate!.difference(DateTime.now()).inDays;
    final label = days == 0
        ? 'Race day — $_goalRaceName!'
        : days == 1
        ? '1 day to $_goalRaceName'
        : '$days days to $_goalRaceName';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFECB3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_outlined, size: 13, color: Color(0xFF856404)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF856404),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherChip() {
    final c = context.colors;
    final weather = _weather!;
    final icon = switch (weather.condition) {
      WeatherCondition.clear => Icons.wb_sunny_outlined,
      WeatherCondition.cloudy => Icons.cloud_outlined,
      WeatherCondition.rain => Icons.water_drop_outlined,
      WeatherCondition.snow => Icons.ac_unit,
      WeatherCondition.fog => Icons.foggy,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c.textTertiary),
        const SizedBox(width: 4),
        Text(
          '${weather.tempC.round()}°C',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: c.textTertiary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.colors.textTertiary,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildBottomCarousel() {
    // Coach tab is execution-only: just this week's adherence circles. Raw
    // mileage totals and the last-run recap live on the You tab now.
    final cardWidth = MediaQuery.of(context).size.width - 40;
    return _buildWeeklyCarouselCard(cardWidth);
  }

  Widget _carouselShell({required Widget child, required double width}) {
    return Container(
      width: width,
      height: 190,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border, width: 1.0),
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }

  Widget _buildWeeklyCarouselCard(double width) {
    final now = DateTime.now();
    final todayIndex = now.weekday - 1;
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final weekMonday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    final runsThisWeek =
        _consistencyData?.runsThisWeek ??
        _runHistory.where((r) {
          final diff = now.difference(r.date).inDays;
          return diff < 7;
        }).length;
    final weeklyTarget = _trainingDayIndices.length;
    final ratio = weeklyTarget > 0
        ? (runsThisWeek / weeklyTarget).clamp(0.0, 1.0)
        : 0.0;
    final c = context.colors;

    return GestureDetector(
      onTap: _openPlanOverview,
      child: _carouselShell(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                if (_engineMemory?.racePlan != null)
                  Icon(Icons.chevron_right, size: 16, color: c.textTertiary),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final isToday = i == todayIndex;
                final dayDate = weekMonday.add(Duration(days: i));
                final hasRun = _dayHasRun(dayDate);
                final plannedDay = _plannedDayFor(dayDate);
                final isRestPlanned =
                    plannedDay?.workoutType == WorkoutType.rest;
                final dayColor = plannedDay != null
                    ? dayColorForWorkoutType(context, plannedDay.workoutType)
                    : c.workoutRest;
                final showColor = hasRun || plannedDay != null;
                final materializedDay = _materializedDayForWeekday(i);
                final isSkipped = materializedDay?.isSkipped ?? false;
                final distanceKm = materializedDay?.plannedKm;
                final useMiles = _distanceUnit == 'miles';
                final distanceLabel =
                    materializedDay == null ||
                        materializedDay.isRest ||
                        distanceKm == null ||
                        distanceKm == 0
                    ? null
                    : '${UnitUtils.displayDistance(distanceKm, useMiles).toStringAsFixed(1)} ${UnitUtils.unitLabel(useMiles)}';

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Always attached — never silently inert. The color/label
                  // above come from the legacy `_activePlan` (`_plannedDayFor`),
                  // which can be populated even when `_thisWeekMaterialized`
                  // hasn't loaded/matched yet, so gating the tap on
                  // `materializedDay == null` made the dot look tappable
                  // while doing nothing. `_onThisWeekDayTap` resolves the
                  // real day itself, with a fresh-load fallback and visible
                  // feedback if it genuinely isn't ready.
                  onTap: () => _onThisWeekDayTap(i, dayDate),
                  child: Column(
                    children: [
                      Text(
                        dayLabels[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isToday ? c.textPrimary : c.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSkipped
                              // Muted well below the normal fill — a
                              // deliberate skip should never read as an
                              // overdue/forgotten session.
                              ? c.divider.withValues(alpha: 0.5)
                              : (showColor ? dayColor : Colors.transparent),
                          border: isToday
                              ? Border.all(color: c.accent, width: 2)
                              : isSkipped
                              ? Border.all(color: c.textTertiary, width: 1.5)
                              // Rest fills pure white — needs its own ring so
                              // it doesn't disappear against a light-theme
                              // card background, same as a truly empty dot.
                              : (isRestPlanned || !showColor)
                              ? Border.all(color: c.border, width: 1.5)
                              : null,
                        ),
                        child: isSkipped
                            ? Icon(
                                Icons.skip_next_rounded,
                                size: 16,
                                color: c.textTertiary,
                              )
                            : hasRun
                            ? const Icon(
                                Icons.check,
                                size: 15,
                                color: Colors.black,
                              )
                            : null,
                      ),
                      if (isSkipped) ...[
                        const SizedBox(height: 4),
                        Text(
                          'SKIPPED',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            color: c.textTertiary,
                          ),
                        ),
                      ] else if (distanceLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          distanceLabel,
                          style: TextStyle(fontSize: 8, color: c.textTertiary),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ),
            const Spacer(),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$runsThisWeek',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: ' / $weeklyTarget runs',
                    style: TextStyle(fontSize: 14, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 3,
                backgroundColor: c.divider,
                valueColor: AlwaysStoppedAnimation<Color>(c.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPlanOverview() {
    HapticFeedback.lightImpact();
    final racePlan = _engineMemory?.racePlan;
    if (racePlan == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanOverviewScreen(
          racePlan: racePlan,
          useMiles: UnitUtils.useMilesNotifier.value,
          trainingDayIndices: _trainingDayIndices,
          longRunDayIndex: _engineMemory?.longRunDayIndex,
        ),
      ),
    );
  }

  MaterializedDay? _materializedDayForWeekday(int weekday) {
    final days = _thisWeekMaterialized?.days;
    if (days == null) return null;
    for (final d in days) {
      if (d.weekday == weekday) return d;
    }
    return null;
  }

  /// Tapping a day dot on the "THIS WEEK" strip. `_thisWeekMaterialized` is
  /// set once by `loadData()`'s call to `PlanStore.getTodayDayContext` — if
  /// that call raced a still-materializing plan (or a plan fingerprint blip)
  /// and came back null, the dot still renders (color/label come from the
  /// separate legacy `_activePlan`) but had nothing to tap into. Rather than
  /// fail silently, re-fetch the plan directly here and try once more before
  /// giving the athlete visible feedback.
  Future<void> _onThisWeekDayTap(int weekdayIndex, DateTime dayDate) async {
    var week = _thisWeekMaterialized;
    var day = _materializedDayForWeekday(weekdayIndex);

    if (week == null || day == null) {
      debugPrint(
        '[HomeScreen] Day-dot tap: no cached MaterializedDay for weekday '
        '$weekdayIndex (week=${week?.weekNumber}) — retrying with a fresh '
        'PlanStore load.',
      );
      final now = DateTime.now();
      final weekNumber = _engineMemory?.racePlan?.currentWeekNumber(now);
      final plan = await PlanStore.instance.load();
      final freshWeek = weekNumber == null
          ? null
          : plan?.weekByNumber(weekNumber);
      final freshDay = freshWeek?.days
          .where((d) => d.weekday == weekdayIndex)
          .cast<MaterializedDay?>()
          .firstWhere((_) => true, orElse: () => null);

      if (freshWeek == null || freshDay == null) {
        debugPrint(
          '[HomeScreen] Day-dot tap: still no MaterializedDay after fresh '
          'load (plan=${plan != null}, weekNumber=$weekNumber) — plan is '
          'likely still being generated.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your plan is still being prepared — try again in a moment.',
              ),
            ),
          );
        }
        return;
      }

      week = freshWeek;
      day = freshDay;
      if (mounted) {
        setState(() {
          _thisWeekMaterialized = freshWeek;
          _thisWeekPlanId = plan!.planId;
          _thisWeekPlanBuiltAt = plan.builtAt;
        });
      }
    }

    if (!mounted) return;
    _handleThisWeekDayTap(week, day, dayDate);
  }

  /// This strip only ever shows the current week, which — same rule as
  /// PlanOverviewScreen's week lock — is never locked, so the lock check
  /// here is defensive rather than one that fires in practice today: the
  /// paywall only shows for a *future* week beyond the current one, never
  /// for anything in the active week or during an active trial (RevenueCat's
  /// entitlement covers the trial too, so `isProNotifier` is already true
  /// for it).
  void _handleThisWeekDayTap(
    MaterializedWeek week,
    MaterializedDay day,
    DateTime dayDate,
  ) {
    HapticFeedback.lightImpact();
    final currentWeekNumber = _engineMemory?.racePlan?.currentWeekNumber(
      DateTime.now(),
    );
    final isLocked =
        !RevenueCatService.isProNotifier.value &&
        currentWeekNumber != null &&
        week.weekNumber > currentWeekNumber;

    if (isLocked) {
      UnlockTrainingBottomSheet.show(context);
      return;
    }

    if (day.isRest || day.workout == null) {
      showPlanDayDetailSheet(
        context,
        day: day,
        date: dayDate,
        useMiles: _distanceUnit == 'miles',
      );
      return;
    }

    final memory = _engineMemory;
    if (memory == null) return;

    final now = DateTime.now();
    final built = _messageBuilder.buildMessage(
      context: _coachContextFrom(memory, _runHistory, now),
      resolvedWorkout: day.workout!,
      phase: week.phase,
      weekNumber: week.weekNumber,
    );

    // Known plan coordinates for any not-yet-completed day (not just today) —
    // this is what "Link Activity"/"Skip Workout" act on. A completed day
    // gets no scheduledContext at all: nothing left to link/skip, and a run
    // started from here is a free bonus run, not a re-completion. Whether
    // Start Run auto-links the *new* run against this day (only if it's
    // genuinely today) is decided inside PreRunBriefingScreen itself.
    final planId = _thisWeekPlanId;
    final planBuiltAt = _thisWeekPlanBuiltAt;
    final scheduledContext =
        (!day.isCompleted && planId != null && planBuiltAt != null)
        ? ScheduledWorkoutContext.fromParts(
            planId: planId,
            planBuiltAt: planBuiltAt,
            weekNumber: week.weekNumber,
            weekday: day.weekday,
            workout: day.workout!,
          )
        : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreRunBriefingScreen(
          coachMessage: built,
          onGoToRun: () => widget.onNavigateToRun?.call(),
          scheduledContext: scheduledContext,
          onPlanChanged: loadData,
        ),
      ),
    );
  }

  bool _dayHasRun(DateTime day) {
    for (final RunHistory r in _runHistory) {
      if (r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day)
        return true;
    }
    return false;
  }

  PlannedDay? _plannedDayFor(DateTime day) {
    final days = _activePlan?.days;
    if (days == null) return null;
    for (final d in days) {
      if (d.date.year == day.year &&
          d.date.month == day.month &&
          d.date.day == day.day) {
        return d;
      }
    }
    return null;
  }
}
