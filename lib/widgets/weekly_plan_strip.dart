import 'package:flutter/material.dart';
import '../models/weekly_plan.dart';
import '../models/workout_type.dart';

/// 7-day strip showing:
///   ✓  Completed workouts (past days with runs)
///   ○  Planned but not yet done (future days from WeeklyPlan)
///   –  Rest days
///   ●  Today highlight
///
/// This replaces the simple completed-only strip in [HomeScreen].
class WeeklyPlanStrip extends StatelessWidget {
  final WeeklyPlan plan;
  final Set<String> completedDayKeys; // 'yyyy-MM-dd' of days with actual runs

  const WeeklyPlanStrip({
    super.key,
    required this.plan,
    required this.completedDayKeys,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'THIS WEEK',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF999999),
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                _weekLabel(plan.weekStartDate),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF999999),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: plan.days.map((day) {
              final isToday = _isToday(day.date, now);
              final isDone = completedDayKeys.contains(_dayKey(day.date));
              final isPast = day.date.isBefore(
                DateTime(now.year, now.month, now.day),
              );
              return _DayCell(
                day: day,
                isToday: isToday,
                isCompleted: isDone,
                isPast: isPast && !isDone,
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          _Legend(),
        ],
      ),
    );
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool _isToday(DateTime d, DateTime now) =>
      d.year == now.year && d.month == now.month && d.day == now.day;

  static String _weekLabel(DateTime monday) {
    final end = monday.add(const Duration(days: 6));
    return '${monday.day}–${end.day} ${_monthAbbr(end.month)}';
  }

  static String _monthAbbr(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[m - 1];
  }
}

// ── Day cell ──────────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final PlannedDay day;
  final bool isToday;
  final bool isCompleted;
  final bool isPast; // past day with no run

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isCompleted,
    required this.isPast,
  });

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final labelIndex = day.date.weekday - 1; // Mon=0 … Sun=6

    Color bgColor;
    Color borderColor;
    Widget child;

    if (isCompleted) {
      bgColor = Colors.black;
      borderColor = Colors.transparent;
      child = const Icon(Icons.check, color: Colors.white, size: 14);
    } else if (day.isRestDay) {
      bgColor = Colors.transparent;
      borderColor = Colors.transparent;
      child = Text(
        '${day.date.day}',
        style: TextStyle(
          fontSize: 11,
          color: isPast ? const Color(0xFFDDDDDD) : const Color(0xFFCCCCCC),
        ),
      );
    } else if (isPast) {
      // Missed planned workout
      bgColor = Colors.transparent;
      borderColor = const Color(0xFFEEEEEE);
      child = Icon(
        _workoutIcon(day.workoutType),
        size: 13,
        color: const Color(0xFFCCCCCC),
      );
    } else if (isToday) {
      bgColor = const Color(0xFFF5F5F5);
      borderColor = Colors.black;
      child = Icon(
        _workoutIcon(day.workoutType),
        size: 13,
        color: Colors.black,
      );
    } else {
      // Future planned
      bgColor = _planBgColor(day.workoutType);
      borderColor = _planBorderColor(day.workoutType);
      child = Icon(
        _workoutIcon(day.workoutType),
        size: 13,
        color: _planIconColor(day.workoutType),
      );
    }

    return Column(
      children: [
        Text(
          _dayLabels[labelIndex],
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isToday ? Colors.black : const Color(0xFF999999),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: borderColor != Colors.transparent
                ? Border.all(color: borderColor, width: 1.5)
                : null,
          ),
          child: Center(child: child),
        ),
        const SizedBox(height: 4),
        Text(
          day.isRestDay ? '' : _shortLabel(day.workoutType),
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w500,
            color: isToday
                ? Colors.black
                : const Color(0xFFBBBBBB),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  IconData _workoutIcon(WorkoutType type) {
    switch (type) {
      case WorkoutType.tempo:
        return Icons.bolt;
      case WorkoutType.interval:
        return Icons.timer_outlined;
      case WorkoutType.long:
        return Icons.landscape_outlined;
      case WorkoutType.recovery:
        return Icons.favorite_border;
      case WorkoutType.rest:
        return Icons.bedtime_outlined;
      default:
        return Icons.directions_run;
    }
  }

  String _shortLabel(WorkoutType type) {
    switch (type) {
      case WorkoutType.tempo:
        return 'TEMPO';
      case WorkoutType.interval:
        return 'INT';
      case WorkoutType.long:
        return 'LONG';
      case WorkoutType.recovery:
        return 'REC';
      default:
        return 'EASY';
    }
  }

  Color _planBgColor(WorkoutType type) {
    switch (type) {
      case WorkoutType.tempo:
        return const Color(0xFFFFF3E0);
      case WorkoutType.interval:
        return const Color(0xFFE3F2FD);
      case WorkoutType.long:
        return const Color(0xFFE8F5E9);
      case WorkoutType.recovery:
        return const Color(0xFFF3E5F5);
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  Color _planBorderColor(WorkoutType type) {
    switch (type) {
      case WorkoutType.tempo:
        return const Color(0xFFFFCC80);
      case WorkoutType.interval:
        return const Color(0xFF90CAF9);
      case WorkoutType.long:
        return const Color(0xFFA5D6A7);
      case WorkoutType.recovery:
        return const Color(0xFFCE93D8);
      default:
        return const Color(0xFFDDDDDD);
    }
  }

  Color _planIconColor(WorkoutType type) {
    switch (type) {
      case WorkoutType.tempo:
        return const Color(0xFFEF6C00);
      case WorkoutType.interval:
        return const Color(0xFF1565C0);
      case WorkoutType.long:
        return const Color(0xFF2E7D32);
      case WorkoutType.recovery:
        return const Color(0xFF6A1B9A);
      default:
        return const Color(0xFF666666);
    }
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LegendDot(color: Colors.black, label: 'Done'),
        const SizedBox(width: 12),
        _LegendDot(color: const Color(0xFFEF6C00), label: 'Tempo'),
        const SizedBox(width: 12),
        _LegendDot(color: const Color(0xFF1565C0), label: 'Intervals'),
        const SizedBox(width: 12),
        _LegendDot(color: const Color(0xFF2E7D32), label: 'Long'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
        ),
      ],
    );
  }
}