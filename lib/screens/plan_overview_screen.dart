import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../models/race_plan.dart';
import '../models/training_phase.dart';
import '../engines/plan/week_resolver.dart';
import '../engines/plan/materialized_plan.dart';
import '../engines/plan/plan_store.dart';
import '../engines/plan/plan_materialization_coordinator.dart';
import '../engines/config/workout_template_library.dart'
    show WorkoutIntent, RaceDistance;
import '../engines/config/archetype_table.dart' show ExperienceLevel;
import '../engines/memory/engine_memory_service.dart';
import '../engines/progression_decision.dart';
import '../models/scheduled_workout_context.dart';
import '../services/coach_message_builder.dart' as message;
import '../services/revenue_cat_service.dart';
import '../services/analytics_service.dart' show Analytics;
import '../services/plan_restart_service.dart';
import '../services/workout_compliance_coordinator.dart';
import '../services/workout_compliance_matcher.dart';
import '../utils/plan_calendar.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';
import '../widgets/ambient_scaffold.dart';
import '../widgets/restart_plan_banner.dart';
import '../widgets/unlock_training_bottom_sheet.dart';
import '../widgets/workout_step_timeline.dart';
import 'calendar_day_status.dart';
import 'paywall_screen.dart';
import 'pre_run_briefing_screen.dart';

/// Full multi-week plan overview / calendar (Runna/Endorphins-style).
///
/// Reads exclusively from the stored [MaterializedPlan] (via [PlanStore]) — no
/// legacy `WeeklyPlan`, no `markMissedDays`. Every current-or-past week's day
/// strip derives completion straight from [MaterializedDay.completion] (set by
/// `WorkoutComplianceMatcher`), so the calendar and the Coach card can never
/// drift apart. Future weeks project the same deterministic shape via
/// [WeekResolver]. Weeks past the trial window are locked — phase + volume
/// stay visible, the day strip does not.
class PlanOverviewScreen extends StatefulWidget {
  final RacePlan racePlan;
  final bool useMiles;
  final List<int> trainingDayIndices;
  final int? longRunDayIndex;

  const PlanOverviewScreen({
    super.key,
    required this.racePlan,
    required this.useMiles,
    required this.trainingDayIndices,
    this.longRunDayIndex,
  });

  @override
  State<PlanOverviewScreen> createState() => _PlanOverviewScreenState();
}

class _PlanOverviewScreenState extends State<PlanOverviewScreen> {
  static const _resolver = WeekResolver();

  /// The stored full plan, when it matches the current inputs. Each week's day
  /// strip is read from this; otherwise it falls back to a live resolve.
  MaterializedPlan? _materialized;

  /// Mutable copy of the race plan shown — starts from [widget.racePlan] but
  /// is replaced in place after "Restart plan from today" shifts its dates,
  /// so the screen reflects the new schedule without needing to be re-pushed.
  late RacePlan _racePlan = widget.racePlan;

  /// Whole days behind the next uncompleted workout's original schedule.
  /// Null hides the restart banner (no plan, or already on schedule).
  int? _daysBehindSchedule;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _currentWeekKey = GlobalKey();

  RacePlan get racePlan => _racePlan;
  bool get useMiles => widget.useMiles;
  List<int> get trainingDayIndices => widget.trainingDayIndices;
  int? get longRunDayIndex => widget.longRunDayIndex;

  @override
  void initState() {
    super.initState();
    _loadMaterialized();
    _loadRestartStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentWeek());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentWeek({bool retried = false}) {
    final ctx = _currentWeekKey.currentContext;
    if (ctx == null) {
      // The list is lazy: a far-down current week isn't built yet, so it has
      // no context to scroll to. Jump close by (rough per-card estimate) to
      // get it built, then align it precisely on the next frame.
      if (retried || !_scrollController.hasClients) return;
      final index = (racePlan.currentWeekNumber(DateTime.now()) - 1).clamp(
        0,
        racePlan.weeks.length - 1,
      );
      _scrollController.jumpTo(
        (index * 220.0).clamp(0.0, _scrollController.position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCurrentWeek(retried: true),
      );
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 1),
      alignment: 0.1,
    );
  }

  Future<void> _loadRestartStatus() async {
    final days = await PlanRestartService.daysBehindSchedule();
    if (!mounted) return;
    setState(() => _daysBehindSchedule = days);
  }

  /// After a successful restart: reload the race plan (its dates just
  /// shifted) and the materialized plan off the store, then re-check whether
  /// the banner should still show (it won't — the plan is back on schedule).
  Future<void> _onPlanRestarted() async {
    final memory = await EngineMemoryService().load();
    if (!mounted) return;
    setState(() {
      _racePlan = memory.racePlan ?? _racePlan;
      _materialized = null;
    });
    await _loadMaterialized();
    await _loadRestartStatus();
  }

  /// Loads the stored plan and gates it behind an inputs-fingerprint check —
  /// only trust it if it matches what this screen is currently showing, so a
  /// plan mid-recompute (e.g. right after ManagePlanScreen changes race
  /// distance) never renders the wrong shape. That recompute is normally
  /// fast, so on a mismatch (or a transient load failure) [isRetry] gives it
  /// one short second chance before giving up — without this, a screen
  /// opened during that narrow race window got stuck with `_materialized`
  /// permanently null and every day dot silently non-interactive.
  Future<void> _loadMaterialized({bool isRetry = false}) async {
    try {
      // Match any freshly-logged runs to their days first, so opening the
      // calendar never shows a completed run as still pending.
      await WorkoutComplianceCoordinator.instance.sync();
      final plan = await PlanStore.instance.load();
      if (!mounted) return;
      if (plan == null) {
        debugPrint(
          '[PlanOverviewScreen] _loadMaterialized: PlanStore has no plan.',
        );
        return;
      }
      // Only trust it if it was built for the same inputs we're showing.
      final fp = PlanMaterializationCoordinator.fingerprint(
        goalRace: racePlan.goalRace,
        raceDate: racePlan.raceDate,
        trainingDays: trainingDayIndices,
        longRunDayIndex: longRunDayIndex,
        experienceLevel: racePlan.experienceLevel,
      );
      // goalTimeSeconds is not on RacePlan; accept a fingerprint that matches
      // ignoring the trailing goal-time segment.
      final head = fp.substring(0, fp.lastIndexOf('|'));
      if (plan.inputsFingerprint.startsWith(head)) {
        setState(() => _materialized = plan);
        return;
      }

      debugPrint(
        '[PlanOverviewScreen] _loadMaterialized: fingerprint mismatch '
        '(stored="${plan.inputsFingerprint}", expected~="$head") — '
        '${isRetry ? "giving up after retry" : "retrying once"}.',
      );
      if (!isRetry) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        await _loadMaterialized(isRetry: true);
      }
    } catch (e, stack) {
      debugPrint('[PlanOverviewScreen] _loadMaterialized failed: $e\n$stack');
      if (!isRetry) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        await _loadMaterialized(isRetry: true);
      }
    }
  }

  /// A week's day shape — from the stored plan when we have it, else a live
  /// resolve (unchanged legacy path).
  WeekResolution _resolutionForWeek(WeekTarget week) {
    final mw = _materialized?.weekByNumber(week.week);
    if (mw != null) return _fromMaterialized(mw);
    return _resolveShape(week);
  }

  WeekResolution _fromMaterialized(MaterializedWeek mw) => WeekResolution(
    weekNumber: mw.weekNumber,
    phase: mw.phase,
    targetKm: mw.targetKm,
    days: [
      for (final d in mw.days)
        DaySlot(
          weekday: d.weekday,
          slotType: _slotFromMaterialized(d.slot),
          intent: d.intent,
          templateId: d.templateId,
          progressionStep: d.progressionStep,
          isRest: d.isRest,
          label: d.slot.name,
          distanceKm: d.workout?.totalDistanceKm,
        ),
    ],
  );

  static SlotType _slotFromMaterialized(MaterializedSlot s) => switch (s) {
    MaterializedSlot.easy => SlotType.easy,
    MaterializedSlot.quality1 => SlotType.quality1,
    MaterializedSlot.quality2 => SlotType.quality2,
    MaterializedSlot.longRun => SlotType.longRun,
    MaterializedSlot.mediumLong => SlotType.mediumLong,
    MaterializedSlot.rest => SlotType.rest,
  };

  RaceDistance get _raceDistance => switch (racePlan.goalRace) {
    '5k' => RaceDistance.fiveK,
    '10k' => RaceDistance.tenK,
    'half_marathon' => RaceDistance.halfMarathon,
    'marathon' => RaceDistance.marathon,
    _ => RaceDistance.fiveK,
  };

  ExperienceLevel get _experienceLevel => switch (racePlan.experienceLevel) {
    'intermediate' => ExperienceLevel.intermediate,
    'advanced' => ExperienceLevel.advanced,
    _ => ExperienceLevel.beginner,
  };

  WeekResolution _resolveShape(WeekTarget week) {
    final days = trainingDayIndices.isNotEmpty
        ? trainingDayIndices
        : const [0, 1, 2, 3];
    return _resolver.resolve(
      weekTarget: week,
      trainingDayIndices: days,
      raceDistance: _raceDistance,
      phase: week.phase,
      experienceLevel: _experienceLevel,
      currentWeeklyKm: week.targetKm,
      longRunDayIndex: longRunDayIndex,
      weekNumber: week.week,
      isCutbackWeek: week.week % 4 == 0,
      taperWeekNumber: 1,
    );
  }

  /// Monday of [weekNumber]. Both anchors are snapped to their week's Monday
  /// by [PlanCalendar.dateFor], so this is a real Monday even for plans stored
  /// before Monday-alignment (whose anchor was the raw creation timestamp).
  /// Prefers the stored plan's own anchor so the calendar's day dates line up
  /// exactly with what `WorkoutComplianceMatcher` matched against.
  DateTime _mondayOf(int weekNumber) {
    final anchor = _materialized?.builtAt ?? racePlan.createdAt;
    return PlanCalendar.dateFor(anchor, weekNumber, 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final currentWeekNumber = racePlan.currentWeekNumber(now);

    return AmbientScaffold(
      appBar: AppBar(
        title: Text(
          'Your Plan',
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        backgroundColor: c.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: RevenueCatService.isProNotifier,
            builder: (context, isPro, _) {
              return ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  _daysBehindSchedule != null && _daysBehindSchedule! > 0
                      ? 96
                      : 32,
                ),
                itemCount: racePlan.weeks.length,
                itemBuilder: (context, index) {
                  final week = racePlan.weeks[index];
                  final isCurrent = week.week == currentWeekNumber;
                  final isLocked = !isPro && week.week > currentWeekNumber;
                  final weekMonday = _mondayOf(week.week);
                  final resolution = _resolutionForWeek(week);
                  // The whole plan is materialized upfront, so real day data
                  // exists for future weeks too — but a locked week must never
                  // reveal it (paywall teaser stays shape-only), so gate on
                  // lock status rather than "has this week started yet".
                  final materializedWeek = isLocked
                      ? null
                      : _materialized?.weekByNumber(week.week);

                  return Padding(
                    key: isCurrent ? _currentWeekKey : null,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _WeekCard(
                      week: week,
                      weekStart: weekMonday,
                      resolution: resolution,
                      isCurrent: isCurrent,
                      isLocked: isLocked,
                      useMiles: useMiles,
                      materializedWeek: materializedWeek,
                      weekMonday: weekMonday,
                      planStart: _materialized?.planStartDate,
                      now: now,
                      onDayTap: _showDayDetail,
                      onLockedDayTap: isLocked
                          ? () => UnlockTrainingBottomSheet.show(context)
                          : null,
                      // Unlocked but the real day data hasn't loaded (or
                      // failed the fingerprint check) — same underlying bug
                      // class as home_screen.dart's day-dot tap: give visible
                      // feedback and retry, instead of a dot that looks
                      // tappable but silently does nothing.
                      onUnavailableTap: (!isLocked && materializedWeek == null)
                          ? _onUnavailableDayTap
                          : null,
                      onLockedTap: isLocked
                          ? () {
                              Analytics.capture(
                                'locked_week_tapped',
                                properties: {'week': week.week},
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PaywallScreen(),
                                ),
                              );
                            }
                          : null,
                    ),
                  );
                },
              );
            },
          ),
          if (_daysBehindSchedule != null && _daysBehindSchedule! > 0)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: RestartPlanBanner(onRestarted: _onPlanRestarted),
              ),
            ),
        ],
      ),
    );
  }

  void _onUnavailableDayTap() {
    debugPrint(
      '[PlanOverviewScreen] Day-dot tap on an unlocked week with no '
      'materialized data yet — retrying load.',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your plan is still loading — try again in a moment.'),
      ),
    );
    _loadMaterialized();
  }

  /// Tapping an unlocked day: a rest day still gets the lightweight bottom
  /// sheet (nothing to brief), but a training day now opens the full
  /// [PreRunBriefingScreen] — same screen Home's "today" card opens — instead
  /// of a workout-breakdown sheet, so "Start Run" / "Skip Workout" are one tap
  /// away from any day in the plan, not just today's.
  Future<void> _showDayDetail(
    MaterializedWeek week,
    MaterializedDay day,
    DateTime date,
  ) async {
    if (day.isRest || day.workout == null) {
      showPlanDayDetailSheet(context, day: day, date: date, useMiles: useMiles);
      return;
    }

    final coachContext = await _loadPreviewCoachContext();
    if (!mounted) return;

    final built = message.CoachMessageBuilder().buildMessage(
      context: coachContext,
      resolvedWorkout: day.workout!,
      phase: week.phase,
      weekNumber: week.weekNumber,
    );

    // Known plan coordinates for any not-yet-completed day (not just today) —
    // this is what "Link Activity"/"Skip Workout" act on; a completed day
    // gets none (nothing left to link/skip). Whether Start Run auto-links the
    // *new* run against this day (only if it's genuinely today) is decided
    // inside PreRunBriefingScreen itself.
    final plan = _materialized;
    final scheduledContext = (!day.isCompleted && plan != null)
        ? ScheduledWorkoutContext.fromParts(
            planId: plan.planId,
            planBuiltAt: plan.builtAt,
            weekNumber: week.weekNumber,
            weekday: day.weekday,
            workout: day.workout!,
          )
        : null;

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreRunBriefingScreen(
          coachMessage: built,
          onGoToRun: () {},
          scheduledContext: scheduledContext,
          onPlanChanged: () {
            setState(() => _materialized = null);
            _loadMaterialized();
          },
          dayStatus: calendarDayStatus(
            day,
            scheduledDate: date,
            now: DateTime.now(),
            planStart: plan?.planStartDate,
          ),
          completion: day.completion,
        ),
      ),
    );
  }

  /// A minimal [message.CoachContext] for previewing a plan day from this
  /// screen. Only the athlete's overall training state is available here
  /// (no run-history list is loaded on this screen) — recency/RPE-trend
  /// signals default to neutral, which the builder already renders as
  /// sensible fallback copy ("Max is still reading your rhythm...").
  Future<message.CoachContext> _loadPreviewCoachContext() async {
    final memory = await EngineMemoryService().load();
    final now = DateTime.now();
    final lastRun = memory.lastRunDate;
    return message.CoachContext(
      totalRunsCompleted: memory.totalRunsCompleted,
      daysSinceLastRun: lastRun == null ? 999 : now.difference(lastRun).inDays,
      progression: switch (memory.weeklyProgressionDecision) {
        ProgressionDecision.progress => message.ProgressionSignal.progressing,
        ProgressionDecision.regress => message.ProgressionSignal.steppingBack,
        _ => message.ProgressionSignal.holding,
      },
    );
  }
}

/// Opens the day-detail bottom sheet for an unlocked [day]. Shared with
/// home_screen.dart's "THIS WEEK" strip so both day-tap surfaces show the
/// exact same workout breakdown rather than maintaining two copies of it.
void showPlanDayDetailSheet(
  BuildContext context, {
  required MaterializedDay day,
  required DateTime date,
  required bool useMiles,
}) {
  final now = DateTime.now();
  final status = calendarDayStatus(day, scheduledDate: date, now: now);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _DayDetailSheet(
      day: day,
      date: date,
      status: status,
      useMiles: useMiles,
    ),
  );
}

// ── Week card ────────────────────────────────────────────────────────────────

class _WeekCard extends StatelessWidget {
  final WeekTarget week;
  final DateTime weekStart;
  final WeekResolution resolution;
  final bool isCurrent;
  final bool isLocked;
  final bool useMiles;

  /// The stored week — present for current + past weeks. Null ⇒ project the
  /// shape from [resolution] with no completion status.
  final MaterializedWeek? materializedWeek;
  final DateTime weekMonday;

  /// The plan's first day — week-1 days before it are pre-plan (muted,
  /// untappable, excluded from the week's workout/distance targets).
  final DateTime? planStart;
  final DateTime now;
  final void Function(
    MaterializedWeek week,
    MaterializedDay day,
    DateTime date,
  )?
  onDayTap;

  /// Tapping any day dot while this week is locked — opens the
  /// [UnlockTrainingBottomSheet] teaser instead of a workout breakdown.
  final VoidCallback? onLockedDayTap;
  final VoidCallback? onLockedTap;

  /// Tapping any day dot on an *unlocked* week whose real data hasn't loaded
  /// yet — visible "still loading" feedback instead of a dead tap.
  final VoidCallback? onUnavailableTap;

  const _WeekCard({
    required this.week,
    required this.weekStart,
    required this.resolution,
    required this.isCurrent,
    required this.isLocked,
    required this.useMiles,
    required this.weekMonday,
    required this.now,
    this.planStart,
    this.materializedWeek,
    this.onDayTap,
    this.onLockedDayTap,
    this.onLockedTap,
    this.onUnavailableTap,
  });

  static String _dateRangeLabel(DateTime start) {
    final end = PlanCalendar.shiftDays(start, 6);
    final startFmt = DateFormat('MMM d').format(start);
    final endFmt = DateFormat('MMM d').format(end);
    return '$startFmt – $endFmt';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final volume = UnitUtils.displayDistance(resolution.targetKm, useMiles);
    final unit = UnitUtils.unitLabel(useMiles);

    return GestureDetector(
      onTap: onLockedTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent ? c.accent : c.border,
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCurrent
                            ? 'WEEK ${week.week} · THIS WEEK'
                            : 'WEEK ${week.week}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? c.accent : c.textTertiary,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dateRangeLabel(weekStart),
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      week.phase.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.textTertiary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (isLocked) ...[
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: c.textTertiary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '${volume.toStringAsFixed(1)} $unit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (!isLocked) ...[
              const SizedBox(height: 14),
              _WeekStatsRow(
                materializedWeek: materializedWeek,
                resolution: resolution,
                useMiles: useMiles,
                // Only week 1 can start mid-week; every other week's Monday
                // is after the plan start, which clamps this to 0.
                firstActiveWeekday: planStart == null
                    ? 0
                    : PlanCalendar.daysBetween(
                        weekMonday,
                        planStart!,
                      ).clamp(0, 6),
              ),
            ],
            const SizedBox(height: 16),
            // Locked weeks still show the day strip — shape only, via the
            // projected resolution rather than the real materialized data —
            // so tapping any dot reads as a deliberate paywall teaser
            // instead of the week simply vanishing.
            materializedWeek != null
                ? MaterializedWeekStrip(
                    week: materializedWeek!,
                    weekMonday: weekMonday,
                    planStart: planStart,
                    now: now,
                    useMiles: useMiles,
                    onDayTap: onDayTap,
                  )
                : _ProjectedDayStrip(
                    resolution: resolution,
                    weekMonday: weekMonday,
                    now: now,
                    useMiles: useMiles,
                    onLockedDayTap: isLocked
                        ? onLockedDayTap
                        : onUnavailableTap,
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Weekly stats row: workouts + distance completed vs. target ─────────────

class _WeekStatsRow extends StatelessWidget {
  /// Present for current + past weeks — completion counts read from here.
  final MaterializedWeek? materializedWeek;

  /// Always present — supplies the target counts/distance for both
  /// materialized and purely-projected (future) weeks.
  final WeekResolution resolution;
  final bool useMiles;

  /// First weekday index (0 = Monday) that belongs to the athlete this week —
  /// non-zero only for a partial first week. Earlier slots are pre-plan and
  /// don't count toward the workout/distance targets.
  final int firstActiveWeekday;

  const _WeekStatsRow({
    required this.materializedWeek,
    required this.resolution,
    required this.useMiles,
    this.firstActiveWeekday = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    final mw = materializedWeek;
    final activeTrainingDays = mw?.trainingDays
        .where((d) => d.weekday >= firstActiveWeekday)
        .toList();
    final totalWorkouts = activeTrainingDays != null
        ? activeTrainingDays.length
        : resolution.days.where((d) => !d.isRest).length;
    final completedWorkouts =
        activeTrainingDays?.where((d) => d.isCompleted).length ?? 0;

    // A partial first week's distance target is only what's left to run.
    final targetKm = (mw != null && firstActiveWeekday > 0)
        ? mw.days
              .where((d) => d.weekday >= firstActiveWeekday)
              .fold<double>(0, (s, d) => s + d.plannedKm)
        : resolution.targetKm;
    final completedKm =
        mw?.days.fold<double>(0, (s, d) => s + (d.completion?.actualKm ?? 0)) ??
        0;

    final targetDisplay = UnitUtils.displayDistance(targetKm, useMiles);
    final completedDisplay = UnitUtils.displayDistance(completedKm, useMiles);
    final unit = UnitUtils.unitLabel(useMiles);

    final ratio = targetKm > 0 ? (completedKm / targetKm).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Workouts $completedWorkouts/$totalWorkouts',
              style: textTheme.bodySmall?.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Distance ${completedDisplay.toStringAsFixed(1)} / ${targetDisplay.toStringAsFixed(1)} $unit',
              style: textTheme.bodySmall?.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: c.divider,
            valueColor: AlwaysStoppedAnimation<Color>(c.chartAccent),
          ),
        ),
      ],
    );
  }
}

// ── Day strip — shared label/color helpers ──────────────────────────────────
//
// Colors match WorkoutTypeStyle (lib/utils/workout_type_style.dart), used on
// History and Run Detail, so a workout type reads the same color everywhere.

const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String _intentLabel(WorkoutIntent? intent) => switch (intent) {
  WorkoutIntent.aerobicBase => 'EASY',
  WorkoutIntent.endurance => 'LONG',
  WorkoutIntent.threshold => 'TEMPO',
  WorkoutIntent.vo2max => 'INT',
  WorkoutIntent.speed => 'SPEED',
  WorkoutIntent.raceSpecific => 'RACE',
  null => 'REST',
};

class _DayCircle extends StatelessWidget {
  final int weekday; // 0=Mon..6=Sun
  final bool isToday;
  final CalendarDayStatus status;
  final Color color;
  final String label;

  /// Planned distance in km, null for a rest day. Rendered under [label] via
  /// [UnitUtils] so it always matches the athlete's km/miles preference.
  final double? distanceKm;
  final bool useMiles;
  final VoidCallback? onTap;

  const _DayCircle({
    required this.weekday,
    required this.status,
    required this.label,
    required this.color,
    this.distanceKm,
    this.useMiles = false,
    this.isToday = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rest = status == CalendarDayStatus.restDay;
    final missed = status == CalendarDayStatus.missed;
    final done = status == CalendarDayStatus.completed;
    final skipped = status == CalendarDayStatus.skipped;
    final prePlan = status == CalendarDayStatus.prePlan;
    final distanceLabel =
        rest || prePlan || distanceKm == null || distanceKm == 0
        ? null
        : '${UnitUtils.displayDistance(distanceKm!, useMiles).toStringAsFixed(1)} ${UnitUtils.unitLabel(useMiles)}';

    Widget? child;
    if (done) {
      child = const Icon(Icons.check_rounded, size: 15, color: Colors.black);
    } else if (skipped) {
      // A forward-skip glyph (not the "−" used for missed) so an intentional
      // skip never reads as an overdue/forgotten session.
      child = Icon(Icons.skip_next_rounded, size: 15, color: c.textTertiary);
    } else if (missed) {
      child = Icon(Icons.remove_rounded, size: 14, color: c.textTertiary);
    }

    final fill = switch (status) {
      CalendarDayStatus.completed => color,
      // Muted well below the normal missed fill — subtle, not alarming.
      CalendarDayStatus.skipped => c.divider.withValues(alpha: 0.5),
      CalendarDayStatus.missed => c.divider,
      // Pure white by design — a clean, empty rest slot. Needs its own
      // border (below) so it doesn't disappear against a light-theme card.
      CalendarDayStatus.restDay => c.workoutRest,
      CalendarDayStatus.upcoming => color,
      // Empty — the slot exists in the plan's shape but was never the
      // athlete's; no fill, no glyph.
      CalendarDayStatus.prePlan => Colors.transparent,
    };

    final circle = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: isToday
            ? Border.all(color: c.accent, width: 2)
            : prePlan
            ? Border.all(color: c.divider, width: 1)
            : skipped
            ? Border.all(color: c.textTertiary, width: 1.5)
            : rest
            ? Border.all(color: c.border, width: 1.5)
            : (missed ? Border.all(color: c.border, width: 1) : null),
      ),
      child: child != null ? Center(child: child) : null,
    );

    return Column(
      children: [
        Text(
          _dayLabels[weekday],
          style: TextStyle(
            fontSize: 11,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            color: isToday ? c.textPrimary : c.textTertiary,
          ),
        ),
        // "Today" micro-marker — always reserves its 4px so every column's
        // circle stays aligned whether or not it is today's.
        const SizedBox(height: 3),
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isToday ? c.accent : Colors.transparent,
          ),
        ),
        const SizedBox(height: 5),
        onTap == null
            ? circle
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: circle,
              ),
        const SizedBox(height: 6),
        Text(
          rest
              ? 'REST'
              : prePlan
              ? '—'
              : skipped
              ? 'SKIPPED'
              : label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: prePlan
                ? c.textFaint
                : (missed || skipped)
                ? c.textTertiary
                : (isToday ? c.textPrimary : c.textTertiary),
          ),
        ),
        if (distanceLabel != null) ...[
          const SizedBox(height: 2),
          Text(
            distanceLabel,
            style: TextStyle(fontSize: 8, color: c.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// A current-or-past week rendered straight from the stored [MaterializedWeek]:
/// completion comes from [MaterializedDay.completion], "missed" is simply a
/// past training day with no completion, and every day is tappable — except
/// pre-plan slots (before [planStart]), which are muted and inert.
class MaterializedWeekStrip extends StatelessWidget {
  final MaterializedWeek week;

  /// Monday (date-only) of this week.
  final DateTime weekMonday;

  /// The plan's first day (date-only). Slots dated before it render as
  /// pre-plan. Null for a plan with no partial first week.
  final DateTime? planStart;
  final DateTime now;
  final bool useMiles;
  final void Function(
    MaterializedWeek week,
    MaterializedDay day,
    DateTime date,
  )?
  onDayTap;

  const MaterializedWeekStrip({
    super.key,
    required this.week,
    required this.weekMonday,
    required this.now,
    this.planStart,
    this.useMiles = false,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final days = [...week.days]..sort((a, b) => a.weekday.compareTo(b.weekday));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in days)
          Builder(
            builder: (_) {
              final date = PlanCalendar.shiftDays(weekMonday, d.weekday);
              final status = calendarDayStatus(
                d,
                scheduledDate: date,
                now: now,
                planStart: planStart,
              );
              final isToday =
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
              return _DayCircle(
                weekday: d.weekday,
                status: status,
                isToday: isToday,
                // For a rest day this resolves to c.workoutRest (pure
                // white) — unused by _DayCircle's fill switch for restDay
                // status anyway, but keeping it accurate avoids a stale
                // Colors.transparent value lying around.
                color: dayColorForIntent(context, d.intent),
                label: d.isRest ? 'REST' : _intentLabel(d.intent),
                distanceKm: d.plannedKm,
                useMiles: useMiles,
                onTap: (onDayTap == null || status == CalendarDayStatus.prePlan)
                    ? null
                    : () => onDayTap!(week, d, date),
              );
            },
          ),
      ],
    );
  }
}

/// A future week — deterministic shape from [WeekResolver], no completion
/// status since it has not happened yet.
class _ProjectedDayStrip extends StatelessWidget {
  final WeekResolution resolution;
  final bool useMiles;

  /// Set (non-null) only when this strip belongs to a locked week — tapping
  /// any day dot then opens the [UnlockTrainingBottomSheet] teaser. Null for
  /// an unlocked week whose real data just hasn't loaded yet, so those dots
  /// stay non-interactive rather than mis-firing the paywall.
  final VoidCallback? onLockedDayTap;

  /// Monday of this week + "now" — only used to ring today's dot. Lock status
  /// says whether the workout is available; the ring says where the athlete is
  /// on the calendar, so it is drawn for locked/projected weeks too.
  final DateTime weekMonday;
  final DateTime now;

  const _ProjectedDayStrip({
    required this.resolution,
    required this.weekMonday,
    required this.now,
    this.useMiles = false,
    this.onLockedDayTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (weekday) {
        final slot = resolution.slotFor(weekday);
        final isRest = slot == null || slot.isRest;
        final date = weekMonday.add(Duration(days: weekday));
        return _DayCircle(
          weekday: weekday,
          isToday:
              date.year == now.year &&
              date.month == now.month &&
              date.day == now.day,
          status: isRest
              ? CalendarDayStatus.restDay
              : CalendarDayStatus.upcoming,
          color: dayColorForIntent(context, isRest ? null : slot.intent),
          label: isRest ? 'REST' : _intentLabel(slot.intent),
          distanceKm: slot?.distanceKm,
          useMiles: useMiles,
          onTap: onLockedDayTap,
        );
      }),
    );
  }
}

/// Bottom sheet shown when a calendar day is tapped — the stored
/// [MaterializedDay]'s resolved workout, plus its completion stats.
class _DayDetailSheet extends StatelessWidget {
  final MaterializedDay day;
  final DateTime date;
  final CalendarDayStatus status;
  final bool useMiles;

  const _DayDetailSheet({
    required this.day,
    required this.date,
    required this.status,
    required this.useMiles,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (chipLabel, chipColor) = switch (status) {
      CalendarDayStatus.completed => ('COMPLETED', c.success),
      CalendarDayStatus.skipped => ('SKIPPED', c.textTertiary),
      CalendarDayStatus.missed => ('MISSED', c.textTertiary),
      CalendarDayStatus.restDay => ('REST DAY', c.textTertiary),
      CalendarDayStatus.upcoming => ('SCHEDULED', c.accent),
      CalendarDayStatus.prePlan => ('BEFORE YOUR PLAN', c.textTertiary),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEEE, MMM d').format(date),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      chipLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: chipColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (day.completion != null) ...[
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
                        WorkoutComplianceMatcher.completedStatsLabel(
                          day.completion!,
                          useMiles: useMiles,
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (day.isRest || day.workout == null)
                Text(
                  'Rest day — recovery is training too.',
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                )
              else
                WorkoutStepTimeline(workout: day.workout!, useMiles: useMiles),
            ],
          ),
        ),
      ),
    );
  }
}
