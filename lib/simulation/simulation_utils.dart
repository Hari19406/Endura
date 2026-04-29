import 'dart:math';

double updateFatigue(double current, double load) {
  // recovery (decay)
  double recovered = current * 0.90;

  // add new load
  double next = recovered + load * 0.25;

  return next.clamp(0, 100);
}

double updateReadiness(double fatigue) {
  return (100 - fatigue).clamp(0, 100);
}

double estimateLoad(double distanceKm, int rpe) {
  return distanceKm * rpe;
}

bool shouldSkip(double consistency) {
  return Random().nextDouble() > consistency;
}