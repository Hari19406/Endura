// lib/services/consistency_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import '../utils/database_service.dart';

class ConsistencyData {
  final int currentStreak;      // consecutive weeks target was hit
  final int longestStreak;      // all-time best streak
  final int runsThisWeek;       // runs completed this week
  final int weeklyTarget;       // user's target from onboarding
  final bool targetHitThisWeek; // whether target already hit this week

  const ConsistencyData({
    required this.currentStreak,
    required this.longestStreak,
    required this.runsThisWeek,
    required this.weeklyTarget,
    required this.targetHitThisWeek,
  });

  // Completion percentage 0.0 to 1.0
  double get completionRatio =>
      weeklyTarget > 0 ? (runsThisWeek / weeklyTarget).clamp(0.0, 1.0) : 0.0;
}

class ConsistencyService {
  static Future<ConsistencyData> compute() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getInt('runs_per_week');
    final weeklyTarget = (storedValue ?? 4).clamp(1, 7);

    final allRuns = await DatabaseService.instance.getAllRuns();
    if (allRuns.isEmpty) {
      return ConsistencyData(
        currentStreak:      0,
        longestStreak:      0,
        runsThisWeek:       0,
        weeklyTarget:       weeklyTarget,
        targetHitThisWeek:  false,
      );
    }

    final now = DateTime.now();

    // Runs this week (Mon–Sun)
    final thisWeekStart = _getWeekStart(now);
    final runsThisWeek = allRuns
        .where((r) => r.date.isAfter(thisWeekStart) ||
            _isSameDay(r.date, thisWeekStart))
        .length;

    final targetHitThisWeek = runsThisWeek >= weeklyTarget;

    // Build weekly run counts going back up to 52 weeks
    // key = week start date string, value = run count
    final Map<String, int> weekCounts = {};
    for (final run in allRuns) {
      final weekStart = _getWeekStart(run.date);
      final key = '${weekStart.year}-${weekStart.month}-${weekStart.day}';
      weekCounts[key] = (weekCounts[key] ?? 0) + 1;
    }

    // Calculate current streak — count consecutive past weeks where target was hit
    // Start from last completed week (not current week)
    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 0;

    // If current week target already hit, count it
    if (targetHitThisWeek) currentStreak = 1;

    // Walk backwards week by week starting from last week
    for (int w = 1; w <= 52; w++) {
      final weekStart = _getWeekStart(
        now.subtract(Duration(days: w * 7)),
      );
      final key = '${weekStart.year}-${weekStart.month}-${weekStart.day}';
      final count = weekCounts[key] ?? 0;

      if (count >= weeklyTarget) {
        currentStreak++;
      } else {
        break; // streak broken — stop counting
      }
    }

    // Calculate longest streak — walk all weeks chronologically
    final sortedWeekKeys = weekCounts.keys.toList()..sort();
    DateTime? prevWeekStart;

    for (final key in sortedWeekKeys) {
      final parts = key.split('-');
      final weekStart = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      final count = weekCounts[key]!;

      // Check if this week is consecutive with previous week
      final isConsecutive = prevWeekStart != null &&
          weekStart.difference(prevWeekStart).inDays == 7;

      if (count >= weeklyTarget) {
        if (isConsecutive || prevWeekStart == null) {
          tempStreak++;
        } else {
          tempStreak = 1; // gap — reset
        }
        if (tempStreak > longestStreak) longestStreak = tempStreak;
      } else {
        tempStreak = 0;
      }

      prevWeekStart = weekStart;
    }

    // Longest streak can't be less than current
    if (currentStreak > longestStreak) longestStreak = currentStreak;

    return ConsistencyData(
      currentStreak:      currentStreak,
      longestStreak:      longestStreak,
      runsThisWeek:       runsThisWeek,
      weeklyTarget:       weeklyTarget,
      targetHitThisWeek:  targetHitThisWeek,
    );
  }

  static DateTime _getWeekStart(DateTime date) {
    // Week starts Monday
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: daysFromMonday));
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
