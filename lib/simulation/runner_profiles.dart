class RunnerProfile {
  final String name;
  final double baseWeeklyKm;
  final int easyPace;
  final double consistency;
  final double aggression;
  final double recoveryAbility;

  const RunnerProfile({
    required this.name,
    required this.baseWeeklyKm,
    required this.easyPace,
    required this.consistency,
    required this.aggression,
    required this.recoveryAbility,
  });
}

final runners = [
  RunnerProfile(
    name: "Beginner",
    baseWeeklyKm: 15,
    easyPace: 420,
    consistency: 0.6,
    aggression: 0.3,
    recoveryAbility: 0.5,
  ),
  RunnerProfile(
    name: "Intermediate",
    baseWeeklyKm: 30,
    easyPace: 360,
    consistency: 0.8,
    aggression: 0.5,
    recoveryAbility: 0.7,
  ),
];