// Model to hold a single run's data
class RunData {
  final double distance;
  final DateTime date;
  final String pace;

  RunData({
    required this.distance,
    required this.date,
    required this.pace,
  });
}

// Achievement types
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

// Achievement model
class Achievement {
  final AchievementType type;
  final String title;
  final String description;
  final String icon;
  final DateTime unlockedAt;
  final int tier; // 1 = bronze, 2 = silver, 3 = gold, 4 = platinum

  Achievement({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
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

  @override
  String toString() {
    return '''
$title ($tierName)
$description
Unlocked: ${unlockedAt.toString().split(' ')[0]}
''';
  }
}

// Main Achievement Engine
class AchievementEngine {
  final List<RunData> runs;

  AchievementEngine(this.runs);

  List<Achievement> checkAchievements() {
    List<Achievement> unlocked = [];

    if (runs.isEmpty) {
      return unlocked;
    }

    // Sort runs by date
    List<RunData> sortedRuns = List.from(runs)
      ..sort((a, b) => a.date.compareTo(b.date));

    // First Run
    unlocked.add(Achievement(
      type: AchievementType.firstRun,
      title: 'First Steps',
      description: 'Completed your first run!',
      icon: '🎉',
      unlockedAt: sortedRuns.first.date,
      tier: 1,
    ));

    // Distance milestones
    _checkDistanceMilestone(sortedRuns, unlocked, 5.0, AchievementType.first5K,
        'First 5K', 'Completed your first 5 kilometer run!', '🏃', 2);
    
    _checkDistanceMilestone(sortedRuns, unlocked, 10.0, AchievementType.first10K,
        'First 10K', 'Conquered the 10 kilometer milestone!', '🏅', 2);
    
    _checkDistanceMilestone(sortedRuns, unlocked, 21.1, AchievementType.firstHalfMarathon,
        'Half Marathon Hero', 'Finished your first half marathon!', '🎖️', 3);
    
    _checkDistanceMilestone(sortedRuns, unlocked, 42.2, AchievementType.firstMarathon,
        'Marathon Legend', 'Completed a full marathon!', '👑', 4);

    // Total distance achievements
    double totalDistance = runs.fold(0, (sum, run) => sum + run.distance);
    
    if (totalDistance >= 50) {
      unlocked.add(Achievement(
        type: AchievementType.distance50Total,
        title: '50K Club',
        description: 'Ran a total of 50 kilometers!',
        icon: '⭐',
        unlockedAt: _getDateWhenDistanceReached(sortedRuns, 50),
        tier: 1,
      ));
    }
    
    if (totalDistance >= 100) {
      unlocked.add(Achievement(
        type: AchievementType.distance100Total,
        title: '100K Warrior',
        description: 'Accumulated 100 kilometers of running!',
        icon: '🌟',
        unlockedAt: _getDateWhenDistanceReached(sortedRuns, 100),
        tier: 2,
      ));
    }
    
    if (totalDistance >= 500) {
      unlocked.add(Achievement(
        type: AchievementType.distance500Total,
        title: 'Ultra Runner',
        description: 'Surpassed 500 kilometers total!',
        icon: '💫',
        unlockedAt: _getDateWhenDistanceReached(sortedRuns, 500),
        tier: 3,
      ));
    }
    
    if (totalDistance >= 1000) {
      unlocked.add(Achievement(
        type: AchievementType.distance1000Total,
        title: 'Legendary Endurance',
        description: 'Achieved 1000 kilometers of running!',
        icon: '🏆',
        unlockedAt: _getDateWhenDistanceReached(sortedRuns, 1000),
        tier: 4,
      ));
    }

    // Run count achievements
    if (runs.length >= 10) {
      unlocked.add(Achievement(
        type: AchievementType.tenRuns,
        title: 'Consistency Starter',
        description: 'Completed 10 runs!',
        icon: '🎯',
        unlockedAt: sortedRuns[9].date,
        tier: 1,
      ));
    }
    
    if (runs.length >= 50) {
      unlocked.add(Achievement(
        type: AchievementType.fiftyRuns,
        title: 'Dedicated Runner',
        description: 'Completed 50 runs!',
        icon: '🔥',
        unlockedAt: sortedRuns[49].date,
        tier: 2,
      ));
    }
    
    if (runs.length >= 100) {
      unlocked.add(Achievement(
        type: AchievementType.hundredRuns,
        title: 'Century Club',
        description: 'Achieved 100 runs!',
        icon: '💯',
        unlockedAt: sortedRuns[99].date,
        tier: 3,
      ));
    }

    // Longest run PR
    double longestDistance = runs.map((r) => r.distance).reduce((a, b) => a > b ? a : b);
    RunData longestRun = runs.firstWhere((r) => r.distance == longestDistance);
    
    if (longestDistance >= 1.0) {
      unlocked.add(Achievement(
        type: AchievementType.longestRunPR,
        title: 'PB Distance',
        description: 'Longest run: ${longestDistance.toStringAsFixed(2)} km',
        icon: '📏',
        unlockedAt: longestRun.date,
        tier: longestDistance >= 21.1 ? 3 : longestDistance >= 10 ? 2 : 1,
      ));
    }

    // Fastest pace PR
    double fastestPace = _getFastestPace(runs);
    if (fastestPace > 0 && fastestPace < 999) {
      RunData fastestRun = runs.firstWhere((r) => _paceToSeconds(r.pace) == fastestPace);
      
      unlocked.add(Achievement(
        type: AchievementType.fastestPacePR,
        title: 'Speed Record',
        description: 'Fastest pace: ${_formatPace(fastestPace)} /km',
        icon: '⚡',
        unlockedAt: fastestRun.date,
        tier: fastestPace <= 240 ? 3 : fastestPace <= 300 ? 2 : 1, // 4:00, 5:00
      ));
    }

    // Week streak
    int maxWeekStreak = _calculateWeekStreak(sortedRuns);
    if (maxWeekStreak >= 2) {
      unlocked.add(Achievement(
        type: AchievementType.weekStreak,
        title: 'On Fire!',
        description: 'Ran for $maxWeekStreak consecutive weeks',
        icon: '🔥',
        unlockedAt: DateTime.now(),
        tier: maxWeekStreak >= 8 ? 3 : maxWeekStreak >= 4 ? 2 : 1,
      ));
    }

    // Early bird (runs before 7 AM)
    int earlyRuns = runs.where((r) => r.date.hour < 7).length;
    if (earlyRuns >= 5) {
      unlocked.add(Achievement(
        type: AchievementType.earlyBird,
        title: 'Early Bird',
        description: 'Completed $earlyRuns runs before 7 AM',
        icon: '🌅',
        unlockedAt: runs.where((r) => r.date.hour < 7).toList()[4].date,
        tier: 2,
      ));
    }

    // Night owl (runs after 8 PM)
    int nightRuns = runs.where((r) => r.date.hour >= 20).length;
    if (nightRuns >= 5) {
      unlocked.add(Achievement(
        type: AchievementType.nightOwl,
        title: 'Night Owl',
        description: 'Completed $nightRuns runs after 8 PM',
        icon: '🌙',
        unlockedAt: runs.where((r) => r.date.hour >= 20).toList()[4].date,
        tier: 2,
      ));
    }

    // Speed demon (average pace under 5:00 /km)
    List<RunData> fastRuns = runs.where((r) {
      double pace = _paceToSeconds(r.pace);
      return pace > 0 && pace <= 300;
    }).toList();
    
    if (fastRuns.length >= 10) {
      unlocked.add(Achievement(
        type: AchievementType.speedDemon,
        title: 'Speed Demon',
        description: 'Completed 10 runs under 5:00 /km pace',
        icon: '💨',
        unlockedAt: fastRuns[9].date,
        tier: 3,
      ));
    }

    // Endurance king (10+ km runs)
    List<RunData> longRuns = runs.where((r) => r.distance >= 10).toList();
    if (longRuns.length >= 10) {
      unlocked.add(Achievement(
        type: AchievementType.enduranceKing,
        title: 'Endurance King',
        description: 'Completed 10 runs of 10+ km',
        icon: '👑',
        unlockedAt: longRuns[9].date,
        tier: 3,
      ));
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
    String icon,
    int tier,
  ) {
    RunData? milestoneRun = sortedRuns.where((r) => r.distance >= targetDistance).firstOrNull;
    
    if (milestoneRun != null) {
      unlocked.add(Achievement(
        type: type,
        title: title,
        description: description,
        icon: icon,
        unlockedAt: milestoneRun.date,
        tier: tier,
      ));
    }
  }

  DateTime _getDateWhenDistanceReached(List<RunData> sortedRuns, double targetDistance) {
    double cumulative = 0;
    for (var run in sortedRuns) {
      cumulative += run.distance;
      if (cumulative >= targetDistance) {
        return run.date;
      }
    }
    return sortedRuns.last.date;
  }

  double _paceToSeconds(String pace) {
    if (pace == '--:--') return 999;

    try {
      List<String> parts = pace.split(':');
      if (parts.length != 2) return 999;

      int minutes = int.parse(parts[0]);
      int seconds = int.parse(parts[1]);

      return (minutes * 60 + seconds).toDouble();
    } catch (e) {
      return 999;
    }
  }

  double _getFastestPace(List<RunData> runs) {
    double fastest = 999;
    for (var run in runs) {
      double pace = _paceToSeconds(run.pace);
      if (pace < fastest) {
        fastest = pace;
      }
    }
    return fastest;
  }

  String _formatPace(double seconds) {
    int mins = (seconds / 60).floor();
    int secs = (seconds % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  int _calculateWeekStreak(List<RunData> sortedRuns) {
    if (sortedRuns.isEmpty) return 0;

    Map<int, List<RunData>> weekMap = {};
    
    for (var run in sortedRuns) {
      int weekNumber = _getWeekNumber(run.date);
      if (!weekMap.containsKey(weekNumber)) {
        weekMap[weekNumber] = [];
      }
      weekMap[weekNumber]!.add(run);
    }

    List<int> weeks = weekMap.keys.toList()..sort();
    
    int maxStreak = 1;
    int currentStreak = 1;

    for (int i = 1; i < weeks.length; i++) {
      if (weeks[i] == weeks[i - 1] + 1) {
        currentStreak++;
        if (currentStreak > maxStreak) {
          maxStreak = currentStreak;
        }
      } else {
        currentStreak = 1;
      }
    }

    return maxStreak;
  }

  int _getWeekNumber(DateTime date) {
    int dayOfYear = int.parse(date.difference(DateTime(date.year, 1, 1)).inDays.toString());
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }
}

// Example usage
void main() {
  List<RunData> runs = [
    RunData(distance: 2.5, date: DateTime(2024, 1, 1, 6, 30), pace: '5:30'),
    RunData(distance: 5.0, date: DateTime(2024, 1, 3, 7, 0), pace: '5:15'),
    RunData(distance: 3.2, date: DateTime(2024, 1, 5, 18, 30), pace: '5:45'),
    RunData(distance: 10.0, date: DateTime(2024, 1, 10, 6, 0), pace: '5:00'),
    RunData(distance: 7.5, date: DateTime(2024, 1, 15, 21, 0), pace: '4:50'),
    RunData(distance: 21.1, date: DateTime(2024, 1, 25, 8, 0), pace: '5:20'),
    RunData(distance: 8.0, date: DateTime(2024, 2, 1, 6, 15), pace: '4:45'),
    RunData(distance: 15.0, date: DateTime(2024, 2, 5, 7, 30), pace: '5:10'),
    RunData(distance: 12.0, date: DateTime(2024, 2, 10, 19, 0), pace: '4:55'),
    RunData(distance: 5.5, date: DateTime(2024, 2, 15, 6, 45), pace: '4:40'),
  ];

  AchievementEngine engine = AchievementEngine(runs);
  List<Achievement> achievements = engine.checkAchievements();

  print('🏆 UNLOCKED ACHIEVEMENTS (${achievements.length})\n');
  print('=' * 50);
  
  // Group by tier
  Map<int, List<Achievement>> byTier = {};
  for (var achievement in achievements) {
    if (!byTier.containsKey(achievement.tier)) {
      byTier[achievement.tier] = [];
    }
    byTier[achievement.tier]!.add(achievement);
  }

  // Display by tier (highest first)
  for (int tier = 4; tier >= 1; tier--) {
    if (byTier.containsKey(tier)) {
      print('\n${_getTierEmoji(tier)} ${_getTierName(tier)} Tier');
      print('-' * 50);
      for (var achievement in byTier[tier]!) {
        print('${achievement.icon} ${achievement.title}');
        print('   ${achievement.description}');
        print('   Unlocked: ${achievement.unlockedAt.toString().split(' ')[0]}');
        print('');
      }
    }
  }
}

String _getTierName(int tier) {
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

String _getTierEmoji(int tier) {
  switch (tier) {
    case 1:
      return '🥉';
    case 2:
      return '🥈';
    case 3:
      return '🥇';
    case 4:
      return '💎';
    default:
      return '🏅';
  }
}