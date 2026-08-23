import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../models/race_plan.dart';
import '../models/weekly_plan.dart';
import '../models/training_phase.dart';
import '../models/workout_type.dart';
import '../engines/plan/week_resolver.dart';
import '../engines/config/workout_template_library.dart'
    show WorkoutIntent, RaceDistance;
import '../engines/config/archetype_table.dart' show ExperienceLevel;
import '../services/revenue_cat_service.dart';
import '../services/analytics_service.dart' show Analytics;
import '../utils/unit_utils.dart';
import 'paywall_screen.dart';

/// Full multi-week plan overview (Runna/Endorphins-style).
///
/// Shows every week the engine already generated in [RacePlan.weeks], each
/// with its date range, total volume, and a day-by-day strip (label below
/// each circle: REST or the workout type). The current week uses the real
/// [activePlan] the Home screen already tracks (so completed/skipped days
/// show correctly); every other unlocked week uses [WeekResolver] to project
/// the same deterministic day shape the engine would assign. Weeks past the
/// trial window are locked — phase + volume stay visible, the day strip
/// does not, per the Runna-style "weekly shape only" pattern.
class PlanOverviewScreen extends StatelessWidget {
  final RacePlan racePlan;
  final WeeklyPlan? activePlan;
  final bool useMiles;
  final List<int> trainingDayIndices;
  final int? longRunDayIndex;

  const PlanOverviewScreen({
    super.key,
    required this.racePlan,
    required this.activePlan,
    required this.useMiles,
    required this.trainingDayIndices,
    this.longRunDayIndex,
  });

  static const _resolver = WeekResolver();

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

  DateTime _weekStart(int weekNumber) {
    final created = racePlan.createdAt;
    final createdDate = DateTime(created.year, created.month, created.day);
    return createdDate.add(Duration(days: (weekNumber - 1) * 7));
  }

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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final currentWeekNumber = racePlan.currentWeekNumber(DateTime.now());

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
      body: ValueListenableBuilder<bool>(
        valueListenable: RevenueCatService.isProNotifier,
        builder: (context, isPro, _) {
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: racePlan.weeks.length,
            itemBuilder: (context, index) {
              final week = racePlan.weeks[index];
              final isCurrent = week.week == currentWeekNumber;
              final isLocked = !isPro && week.week > currentWeekNumber;
              final weekStart = _weekStart(week.week);
              final resolution = _resolveShape(week);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _WeekCard(
                  week: week,
                  weekStart: weekStart,
                  resolution: resolution,
                  isCurrent: isCurrent,
                  isLocked: isLocked,
                  useMiles: useMiles,
                  activePlan: isCurrent ? activePlan : null,
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
  final WeeklyPlan? activePlan;
  final VoidCallback? onLockedTap;

  const _WeekCard({
    required this.week,
    required this.weekStart,
    required this.resolution,
    required this.isCurrent,
    required this.isLocked,
    required this.useMiles,
    this.activePlan,
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                Text(
                  week.phase.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: c.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _dateRangeLabel(weekStart),
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${volume.toStringAsFixed(1)} $unit',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  ' planned',
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                ),
                if (isLocked) ...[
                  const Spacer(),
                  Icon(Icons.lock_outline, size: 16, color: c.textTertiary),
                ],
              ],
            ),
            if (!isLocked) ...[
              const SizedBox(height: 16),
              activePlan != null
                  ? _ActiveDayStrip(plan: activePlan!)
                  : _ProjectedDayStrip(resolution: resolution),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Day strip — shared label/icon helpers ───────────────────────────────────

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

IconData _intentIcon(WorkoutIntent? intent) => switch (intent) {
  WorkoutIntent.endurance => Icons.landscape_outlined,
  WorkoutIntent.threshold => Icons.bolt,
  WorkoutIntent.vo2max => Icons.timer_outlined,
  WorkoutIntent.speed => Icons.timer_outlined,
  WorkoutIntent.raceSpecific => Icons.flag_outlined,
  _ => Icons.directions_run,
};

String _workoutTypeLabel(WorkoutType type) => switch (type) {
  WorkoutType.tempo => 'TEMPO',
  WorkoutType.interval => 'INT',
  WorkoutType.long => 'LONG',
  WorkoutType.quality => 'QUALITY',
  WorkoutType.rest => 'REST',
  WorkoutType.easy => 'EASY',
};

IconData _workoutTypeIcon(WorkoutType type) => switch (type) {
  WorkoutType.tempo => Icons.bolt,
  WorkoutType.interval => Icons.timer_outlined,
  WorkoutType.long => Icons.landscape_outlined,
  _ => Icons.directions_run,
};

class _DayCircle extends StatelessWidget {
  final int weekday; // 0=Mon..6=Sun
  final bool isRest;
  final bool isToday;
  final bool isCompleted;
  final bool isSkipped;
  final IconData? icon;
  final String label;

  const _DayCircle({
    required this.weekday,
    required this.isRest,
    required this.label,
    this.isToday = false,
    this.isCompleted = false,
    this.isSkipped = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Color bg = Colors.transparent;
    Color border = Colors.transparent;
    Widget? child;

    if (isCompleted) {
      bg = c.accent;
      child = Icon(Icons.check, size: 14, color: c.onAccent);
    } else if (isSkipped) {
      border = c.border;
      child = Icon(Icons.close, size: 12, color: c.textTertiary);
    } else if (isRest) {
      border = Colors.transparent;
    } else {
      border = isToday ? c.accent : c.border;
      child = Icon(
        icon ?? Icons.directions_run,
        size: 13,
        color: isToday ? c.accent : c.textSecondary,
      );
    }

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
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            border: border != Colors.transparent
                ? Border.all(color: border, width: 1.5)
                : null,
          ),
          child: child != null ? Center(child: child) : null,
        ),
        const SizedBox(height: 6),
        Text(
          isRest ? 'REST' : label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: isToday ? c.textPrimary : c.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Current week — real data from Home's active [WeeklyPlan] (completed /
/// skipped / today status included).
class _ActiveDayStrip extends StatelessWidget {
  final WeeklyPlan plan;

  const _ActiveDayStrip({required this.plan});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: plan.days.map((day) {
        final isToday =
            day.date.year == now.year &&
            day.date.month == now.month &&
            day.date.day == now.day;
        return _DayCircle(
          weekday: day.date.weekday - 1,
          isRest: day.isRestDay,
          isToday: isToday,
          isCompleted: day.isCompleted,
          isSkipped: day.isSkipped,
          icon: _workoutTypeIcon(day.workoutType),
          label: _workoutTypeLabel(day.workoutType),
        );
      }).toList(),
    );
  }
}

/// Any other unlocked week — deterministic shape from [WeekResolver], no
/// completion status since it hasn't happened yet.
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
          isRest: isRest,
          icon: isRest ? null : _intentIcon(slot.intent),
          label: isRest ? 'REST' : _intentLabel(slot.intent),
        );
      }),
    );
  }
}
