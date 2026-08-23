class RunData {
  final double distance;
  final DateTime date;
  final String pace;

  RunData({required this.distance, required this.date, required this.pace});
}

enum AchievementType {
  firstRun,
  first5K,
  first10K,
  firstHalfMarathon,
  firstMarathon,
  longestRunPR,
  fastestPacePR,
  weekStreak,
  monthStreak,
  distance50Total,
  distance100Total,
  distance500Total,
  distance1000Total,
  tenRuns,
  fiftyRuns,
  hundredRuns,
  earlyBird,
  nightOwl,
  speedDemon,
  enduranceKing,
}

class Achievement {
  final AchievementType type;
  final String title;
  final String description;
  final DateTime unlockedAt;
  final int tier; // 1 = bronze, 2 = silver, 3 = gold, 4 = platinum

  Achievement({
    required this.type,
    required this.title,
    required this.description,
    required this.unlockedAt,
    this.tier = 1,
  });

  String get tierName {
    switch (tier) {
      case 1:
        return 'Bronze';
      case 2:
        return 'Silver';
      case 3:
        return 'Gold';
      case 4:
        return 'Platinum';
      default:
        return 'Bronze';
    }
  }
}

class AchievementEngine {
  final List<RunData> runs;

  AchievementEngine(this.runs);

  List<Achievement> checkAchievements() {
    final List<Achievement> unlocked = [];
    if (runs.isEmpty) return unlocked;

    final List<RunData> sortedRuns = List.from(runs)
      ..sort((a, b) => a.date.compareTo(b.date));

    // First run
    unlocked.add(
      Achievement(
        type: AchievementType.firstRun,
        title: 'First steps',
        description: 'Completed your first run!',
        unlockedAt: sortedRuns.first.date,
        tier: 1,
      ),
    );

    // Distance milestone runs
    _checkDistanceMilestone(
      sortedRuns,
      unlocked,
      5.0,
      AchievementType.first5K,
      'First 5K',
      'Completed your first 5 km run!',
      2,
    );
    _checkDistanceMilestone(
      sortedRuns,
      unlocked,
      10.0,
      AchievementType.first10K,
      'First 10K',
      'Conquered the 10 km milestone!',
      2,
    );
    _checkDistanceMilestone(
      sortedRuns,
      unlocked,
      21.1,
      AchievementType.firstHalfMarathon,
      'Half marathon hero',
      'Finished your first half marathon!',
      3,
    );
    _checkDistanceMilestone(
      sortedRuns,
      unlocked,
      42.2,
      AchievementType.firstMarathon,
      'Marathon legend',
      'Completed a full marathon!',
      4,
    );

    // Cumulative distance
    final double totalDistance = runs.fold(0, (sum, run) => sum + run.distance);

    if (totalDistance >= 50) {
      unlocked.add(
        Achievement(
          type: AchievementType.distance50Total,
          title: '50K club',
          description: 'Ran a total of 50 km!',
          unlockedAt: _getDateWhenDistanceReached(sortedRuns, 50),
          tier: 1,
        ),
      );
    }
    if (totalDistance >= 100) {
      unlocked.add(
        Achievement(
          type: AchievementType.distance100Total,
          title: '100K warrior',
          description: 'Accumulated 100 km of running!',
          unlockedAt: _getDateWhenDistanceReached(sortedRuns, 100),
          tier: 2,
        ),
      );
    }
    if (totalDistance >= 500) {
      unlocked.add(
        Achievement(
          type: AchievementType.distance500Total,
          title: 'Ultra runner',
          description: 'Surpassed 500 km total!',
          unlockedAt: _getDateWhenDistanceReached(sortedRuns, 500),
          tier: 3,
        ),
      );
    }
    if (totalDistance >= 1000) {
      unlocked.add(
        Achievement(
          type: AchievementType.distance1000Total,
          title: 'Legendary endurance',
          description: 'Achieved 1000 km of running!',
          unlockedAt: _getDateWhenDistanceReached(sortedRuns, 1000),
          tier: 4,
        ),
      );
    }

    // Run count
    if (runs.length >= 10) {
      unlocked.add(
        Achievement(
          type: AchievementType.tenRuns,
          title: 'Consistency starter',
          description: 'Completed 10 runs!',
          unlockedAt: sortedRuns[9].date,
          tier: 1,
        ),
      );
    }
    if (runs.length >= 50) {
      unlocked.add(
        Achievement(
          type: AchievementType.fiftyRuns,
          title: 'Dedicated runner',
          description: 'Completed 50 runs!',
          unlockedAt: sortedRuns[49].date,
          tier: 2,
        ),
      );
    }
    if (runs.length >= 100) {
      unlocked.add(
        Achievement(
          type: AchievementType.hundredRuns,
          title: 'Century club',
          description: 'Achieved 100 runs!',
          unlockedAt: sortedRuns[99].date,
          tier: 3,
        ),
      );
    }

    // Longest run PR
    final double longestDistance = runs
        .map((r) => r.distance)
        .reduce((a, b) => a > b ? a : b);
    final RunData longestRun = runs.firstWhere(
      (r) => r.distance == longestDistance,
    );
    if (longestDistance >= 1.0) {
      unlocked.add(
        Achievement(
          type: AchievementType.longestRunPR,
          title: 'Distance PB',
          description: 'Longest run: ${longestDistance.toStringAsFixed(2)} km',
          unlockedAt: longestRun.date,
          tier: longestDistance >= 21.1
              ? 3
              : longestDistance >= 10
              ? 2
              : 1,
        ),
      );
    }

    // Fastest pace PR
    final double fastestPace = _getFastestPace(runs);
    if (fastestPace > 0 && fastestPace < 999) {
      final RunData fastestRun = runs.firstWhere(
        (r) => _paceToSeconds(r.pace) == fastestPace,
      );
      unlocked.add(
        Achievement(
          type: AchievementType.fastestPacePR,
          title: 'Speed record',
          description: 'Fastest pace: ${_formatPace(fastestPace)} /km',
          unlockedAt: fastestRun.date,
          tier: fastestPace <= 240
              ? 3
              : fastestPace <= 300
              ? 2
              : 1,
        ),
      );
    }

    // Week streak
    final int maxWeekStreak = _calculateWeekStreak(sortedRuns);
    if (maxWeekStreak >= 2) {
      unlocked.add(
        Achievement(
          type: AchievementType.weekStreak,
          title: 'On a roll',
          description: 'Ran for $maxWeekStreak consecutive weeks',
          unlockedAt: DateTime.now(),
          tier: maxWeekStreak >= 8
              ? 3
              : maxWeekStreak >= 4
              ? 2
              : 1,
        ),
      );
    }

    // Month streak
    final int maxMonthStreak = _calculateMonthStreak(sortedRuns);
    if (maxMonthStreak >= 2) {
      unlocked.add(
        Achievement(
          type: AchievementType.monthStreak,
          title: 'Month after month',
          description: 'Ran in $maxMonthStreak consecutive months',
          unlockedAt: DateTime.now(),
          tier: maxMonthStreak >= 12
              ? 4
              : maxMonthStreak >= 6
              ? 3
              : maxMonthStreak >= 3
              ? 2
              : 1,
        ),
      );
    }

    // Early bird (5+ runs before 7 AM)
    final List<RunData> earlyRuns = runs.where((r) => r.date.hour < 7).toList();
    if (earlyRuns.length >= 5) {
      unlocked.add(
        Achievement(
          type: AchievementType.earlyBird,
          title: 'Early bird',
          description: 'Completed ${earlyRuns.length} runs before 7 AM',
          unlockedAt: earlyRuns[4].date,
          tier: 2,
        ),
      );
    }

    // Night owl (5+ runs after 8 PM)
    final List<RunData> nightRuns = runs
        .where((r) => r.date.hour >= 20)
        .toList();
    if (nightRuns.length >= 5) {
      unlocked.add(
        Achievement(
          type: AchievementType.nightOwl,
          title: 'Night owl',
          description: 'Completed ${nightRuns.length} runs after 8 PM',
          unlockedAt: nightRuns[4].date,
          tier: 2,
        ),
      );
    }

    // Speed demon (10+ runs under 5:00 /km)
    final List<RunData> fastRuns = runs.where((r) {
      final double pace = _paceToSeconds(r.pace);
      return pace > 0 && pace <= 300;
    }).toList();
    if (fastRuns.length >= 10) {
      unlocked.add(
        Achievement(
          type: AchievementType.speedDemon,
          title: 'Speed demon',
          description: 'Completed 10 runs under 5:00 /km',
          unlockedAt: fastRuns[9].date,
          tier: 3,
        ),
      );
    }

    // Endurance king (10+ runs of 10+ km)
    final List<RunData> longRuns = runs.where((r) => r.distance >= 10).toList();
    if (longRuns.length >= 10) {
      unlocked.add(
        Achievement(
          type: AchievementType.enduranceKing,
          title: 'Endurance king',
          description: 'Completed 10 runs of 10+ km',
          unlockedAt: longRuns[9].date,
          tier: 3,
        ),
      );
    }

    return unlocked;
  }

  void _checkDistanceMilestone(
    List<RunData> sortedRuns,
    List<Achievement> unlocked,
    double targetDistance,
    AchievementType type,
    String title,
    String description,
    int tier,
  ) {
    final RunData? milestoneRun = sortedRuns
        .where((r) => r.distance >= targetDistance)
        .firstOrNull;
    if (milestoneRun != null) {
      unlocked.add(
        Achievement(
          type: type,
          title: title,
          description: description,
          unlockedAt: milestoneRun.date,
          tier: tier,
        ),
      );
    }
  }

  DateTime _getDateWhenDistanceReached(
    List<RunData> sortedRuns,
    double targetDistance,
  ) {
    double cumulative = 0;
    for (final run in sortedRuns) {
      cumulative += run.distance;
      if (cumulative >= targetDistance) return run.date;
    }
    return sortedRuns.last.date;
  }

  double _paceToSeconds(String pace) {
    if (pace == '--:--') return 999;
    try {
      final List<String> parts = pace.split(':');
      if (parts.length != 2) return 999;
      final int minutes = int.parse(parts[0]);
      final int seconds = int.parse(parts[1]);
      return (minutes * 60 + seconds).toDouble();
    } catch (e) {
      return 999;
    }
  }

  double _getFastestPace(List<RunData> runs) {
    double fastest = 999;
    for (final run in runs) {
      final double pace = _paceToSeconds(run.pace);
      if (pace < fastest) fastest = pace;
    }
    return fastest;
  }

  String _formatPace(double seconds) {
    final int mins = (seconds / 60).floor();
    final int secs = (seconds % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  int _calculateWeekStreak(List<RunData> sortedRuns) {
    if (sortedRuns.isEmpty) return 0;

    final Map<int, bool> weeksSeen = {};
    for (final run in sortedRuns) {
      weeksSeen[_isoWeekNumber(run.date)] = true;
    }

    final List<int> weeks = weeksSeen.keys.toList()..sort();
    int maxStreak = 1;
    int currentStreak = 1;

    for (int i = 1; i < weeks.length; i++) {
      if (weeks[i] == weeks[i - 1] + 1) {
        currentStreak++;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
      } else {
        currentStreak = 1;
      }
    }
    return maxStreak;
  }

  // ISO 8601 week number — avoids the year-boundary bug in the old impl.
  int _isoWeekNumber(DateTime date) {
    final int dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final int weekDay = date.weekday; // Mon=1 … Sun=7
    return ((dayOfYear - weekDay + 10) ~/ 7);
  }

  int _calculateMonthStreak(List<RunData> sortedRuns) {
    if (sortedRuns.isEmpty) return 0;

    // Use year*12 + month as a monotonically increasing month index.
    final Set<int> monthsSeen = {
      for (final r in sortedRuns) r.date.year * 12 + r.date.month,
    };

    final List<int> months = monthsSeen.toList()..sort();
    int maxStreak = 1;
    int currentStreak = 1;

    for (int i = 1; i < months.length; i++) {
      if (months[i] == months[i - 1] + 1) {
        currentStreak++;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
      } else {
        currentStreak = 1;
      }
    }
    return maxStreak;
  }
}
