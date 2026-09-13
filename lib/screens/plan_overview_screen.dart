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
import '../services/revenue_cat_service.dart';
import '../services/analytics_service.dart' show Analytics;
import '../services/plan_restart_service.dart';
import '../services/workout_compliance_coordinator.dart';
import '../services/workout_compliance_matcher.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';
import '../widgets/restart_plan_banner.dart';
import '../widgets/workout_step_timeline.dart';
import 'calendar_day_status.dart';
import 'paywall_screen.dart';

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

  void _scrollToCurrentWeek() {
    final ctx = _currentWeekKey.currentContext;
    if (ctx == null) return;
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

  Future<void> _loadMaterialized() async {
    try {
      // Match any freshly-logged runs to their days first, so opening the
      // calendar never shows a completed run as still pending.
      await WorkoutComplianceCoordinator.instance.sync();
      final plan = await PlanStore.instance.load();
      if (plan == null || !mounted) return;
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
      }
    } catch (_) {
      // fall back to live resolve
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

  /// Monday of [weekNumber], anchored on the stored plan's own build date when
  /// we have it (so the calendar's day dates line up exactly with what
  /// `WorkoutComplianceMatcher` matched against), else the race-plan's.
  DateTime _mondayOf(int weekNumber) {
    final anchor = _materialized?.builtAt ?? racePlan.createdAt;
    final a = DateTime(anchor.year, anchor.month, anchor.day);
    return a.add(Duration(days: (weekNumber - 1) * 7));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final currentWeekNumber = racePlan.currentWeekNumber(now);

    return Scaffold(
      backgroundColor: c.background,
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
                  final isPastOrCurrent = week.week <= currentWeekNumber;
                  final isLocked = !isPro && week.week > currentWeekNumber;
                  final weekMonday = _mondayOf(week.week);
                  final resolution = _resolutionForWeek(week);
                  // Real day-by-day status only makes sense once a week has started.
                  final materializedWeek = isPastOrCurrent
                      ? _materialized?.weekByNumber(week.week)
                      : null;

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
                      now: now,
                      onDayTap: _showDayDetail,
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

  /// Tapping a day opens its resolved workout — the exact [MaterializedDay] the
  /// engine stored — plus its completion stats if a run has been matched.
  void _showDayDetail(MaterializedDay day, DateTime date) {
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
  final DateTime now;
  final void Function(MaterializedDay day, DateTime date)? onDayTap;
  final VoidCallback? onLockedTap;

  const _WeekCard({
    required this.week,
    required this.weekStart,
    required this.resolution,
    required this.isCurrent,
    required this.isLocked,
    required this.useMiles,
    required this.weekMonday,
    required this.now,
    this.materializedWeek,
    this.onDayTap,
    this.onLockedTap,
  });

  static String _dateRangeLabel(DateTime start) {
    final end = start.add(const Duration(days: 6));
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
              ),
              const SizedBox(height: 16),
              materializedWeek != null
                  ? MaterializedWeekStrip(
                      week: materializedWeek!,
                      weekMonday: weekMonday,
                      now: now,
                      onDayTap: onDayTap,
                    )
                  : _ProjectedDayStrip(resolution: resolution),
            ],
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

  const _WeekStatsRow({
    required this.materializedWeek,
    required this.resolution,
    required this.useMiles,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    final mw = materializedWeek;
    final totalWorkouts = mw != null
        ? mw.trainingDays.length
        : resolution.days.where((d) => !d.isRest).length;
    final completedWorkouts = mw?.trainingDays
            .where((d) => d.isCompleted)
            .length ??
        0;

    final targetKm = resolution.targetKm;
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
  final VoidCallback? onTap;

  const _DayCircle({
    required this.weekday,
    required this.status,
    required this.label,
    required this.color,
    this.isToday = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rest = status == CalendarDayStatus.restDay;
    final missed = status == CalendarDayStatus.missed;
    final done = status == CalendarDayStatus.completed;

    Widget? child;
    if (done) {
      child = const Icon(Icons.check_rounded, size: 15, color: Colors.black);
    } else if (missed) {
      child = Icon(Icons.remove_rounded, size: 14, color: c.textTertiary);
    }

    final fill = switch (status) {
      CalendarDayStatus.completed => color,
      CalendarDayStatus.missed => c.divider,
      CalendarDayStatus.restDay => c.divider,
      CalendarDayStatus.upcoming => color,
    };

    final circle = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: isToday
            ? Border.all(color: c.accent, width: 2)
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
        const SizedBox(height: 8),
        onTap == null
            ? circle
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: circle,
              ),
        const SizedBox(height: 6),
        Text(
          rest ? 'REST' : label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: missed
                ? c.textTertiary
                : (isToday ? c.textPrimary : c.textTertiary),
          ),
        ),
      ],
    );
  }
}

/// A current-or-past week rendered straight from the stored [MaterializedWeek]:
/// completion comes from [MaterializedDay.completion], "missed" is simply a
/// past training day with no completion, and every day is tappable.
class MaterializedWeekStrip extends StatelessWidget {
  final MaterializedWeek week;

  /// Monday (date-only) of this week.
  final DateTime weekMonday;
  final DateTime now;
  final void Function(MaterializedDay day, DateTime date)? onDayTap;

  const MaterializedWeekStrip({
    super.key,
    required this.week,
    required this.weekMonday,
    required this.now,
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
              final date = weekMonday.add(Duration(days: d.weekday));
              final status =
                  calendarDayStatus(d, scheduledDate: date, now: now);
              final isToday = date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
              return _DayCircle(
                weekday: d.weekday,
                status: status,
                isToday: isToday,
                color: d.isRest
                    ? Colors.transparent
                    : dayColorForIntent(d.intent),
                label: d.isRest ? 'REST' : _intentLabel(d.intent),
                onTap: onDayTap == null ? null : () => onDayTap!(d, date),
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

  const _ProjectedDayStrip({required this.resolution});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (weekday) {
        final slot = resolution.slotFor(weekday);
        final isRest = slot == null || slot.isRest;
        return _DayCircle(
          weekday: weekday,
          status: isRest
              ? CalendarDayStatus.restDay
              : CalendarDayStatus.upcoming,
          color: dayColorForIntent(isRest ? null : slot.intent),
          label: isRest ? 'REST' : _intentLabel(slot.intent),
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
      CalendarDayStatus.missed => ('MISSED', c.textTertiary),
      CalendarDayStatus.restDay => ('REST DAY', c.textTertiary),
      CalendarDayStatus.upcoming => ('SCHEDULED', c.accent),
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

