import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/race_plan.dart';
import '../models/weekly_plan.dart';
import '../models/training_phase.dart';
import '../models/workout_type.dart';
import '../services/revenue_cat_service.dart';
import '../services/analytics_service.dart' show Analytics;
import '../utils/unit_utils.dart';
import 'paywall_screen.dart';

/// Full multi-week plan overview (Runna/Endorphins-style).
///
/// Shows every week the engine already generated in [RacePlan.weeks].
/// The current week is expanded with a day-by-day strip (reusing the
/// [activePlan] the Home screen already tracks). Every other week shows
/// its shape (phase + volume) collapsed; weeks past the trial window are
/// locked — shape stays visible, session detail does not, per the
/// Runna-style "weekly shape only" pattern.
class PlanOverviewScreen extends StatelessWidget {
  final RacePlan racePlan;
  final WeeklyPlan? activePlan;
  final bool useMiles;

  const PlanOverviewScreen({
    super.key,
    required this.racePlan,
    required this.activePlan,
    required this.useMiles,
  });

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

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: isCurrent
                    ? _CurrentWeekCard(
                        week: week,
                        activePlan: activePlan,
                        useMiles: useMiles,
                      )
                    : _CollapsedWeekRow(
                        week: week,
                        isLocked: isLocked,
                        useMiles: useMiles,
                        onTap: isLocked
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

// ── Current week (expanded) ─────────────────────────────────────────────────

class _CurrentWeekCard extends StatelessWidget {
  final WeekTarget week;
  final WeeklyPlan? activePlan;
  final bool useMiles;

  const _CurrentWeekCard({
    required this.week,
    required this.activePlan,
    required this.useMiles,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final volume = UnitUtils.displayDistance(week.targetKm, useMiles);
    final unit = UnitUtils.unitLabel(useMiles);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.accent, width: 1.5),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WEEK ${week.week} · THIS WEEK',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.accent,
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
          const SizedBox(height: 6),
          Text(
            '${volume.toStringAsFixed(1)} $unit planned',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (activePlan != null)
            _DayStrip(plan: activePlan!, now: now)
          else
            Text(
              week.keySession,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  final WeeklyPlan plan;
  final DateTime now;

  const _DayStrip({required this.plan, required this.now});

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: plan.days.map((day) {
        final labelIndex = day.date.weekday - 1;
        final isToday =
            day.date.year == now.year &&
            day.date.month == now.month &&
            day.date.day == now.day;

        Color bg = Colors.transparent;
        Color border = c.border;
        Widget? child;

        if (day.isCompleted) {
          bg = c.accent;
          border = Colors.transparent;
          child = Icon(Icons.check, size: 14, color: c.onAccent);
        } else if (day.isSkipped) {
          border = c.border;
          child = Icon(Icons.close, size: 12, color: c.textTertiary);
        } else if (day.isRestDay) {
          border = Colors.transparent;
        } else {
          border = isToday ? c.accent : c.border;
          child = Icon(
            _workoutIcon(day.workoutType),
            size: 13,
            color: isToday ? c.accent : c.textSecondary,
          );
        }

        return Column(
          children: [
            Text(
              _dayLabels[labelIndex],
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
          ],
        );
      }).toList(),
    );
  }

  IconData _workoutIcon(WorkoutType type) => switch (type) {
    WorkoutType.tempo => Icons.bolt,
    WorkoutType.interval => Icons.timer_outlined,
    WorkoutType.long => Icons.landscape_outlined,
    WorkoutType.recovery => Icons.favorite_border,
    _ => Icons.directions_run,
  };
}

// ── Other weeks (collapsed) ─────────────────────────────────────────────────

class _CollapsedWeekRow extends StatelessWidget {
  final WeekTarget week;
  final bool isLocked;
  final bool useMiles;
  final VoidCallback? onTap;

  const _CollapsedWeekRow({
    required this.week,
    required this.isLocked,
    required this.useMiles,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final volume = UnitUtils.displayDistance(week.targetKm, useMiles);
    final unit = UnitUtils.unitLabel(useMiles);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                'Week ${week.week}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isLocked ? c.textTertiary : c.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                week.phase.displayName,
                style: TextStyle(
                  fontSize: 12,
                  color: isLocked ? c.textTertiary : c.textSecondary,
                ),
              ),
            ),
            if (isLocked)
              Icon(Icons.lock_outline, size: 16, color: c.textTertiary)
            else
              Text(
                '${volume.toStringAsFixed(1)} $unit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
