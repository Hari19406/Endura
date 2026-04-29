import 'dart:math';

enum AbsenceLevel { none, short, moderate, extended }

class AbsenceResult {
  final AbsenceLevel level;
  final double volumeFactor;
  final bool forceEasyReturn;
  final bool requiresPlanRebase;
  final int daysMissed;

  const AbsenceResult({
    required this.level,
    required this.volumeFactor,
    required this.forceEasyReturn,
    required this.requiresPlanRebase,
    required this.daysMissed,
  });
}

class AbsenceDetector {
  static AbsenceResult assess({
    required DateTime? lastRunDate,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();

    if (lastRunDate == null) {
      return const AbsenceResult(
        level: AbsenceLevel.extended,
        volumeFactor: 0.60,
        forceEasyReturn: true,
        requiresPlanRebase: true,
        daysMissed: 999,
      );
    }

    final days = max(0, today.difference(lastRunDate).inDays);

    if (days <= 3) {
      return AbsenceResult(
        level: AbsenceLevel.none,
        volumeFactor: 1.0,
        forceEasyReturn: false,
        requiresPlanRebase: false,
        daysMissed: days,
      );
    }

    if (days <= 7) {
      return AbsenceResult(
        level: AbsenceLevel.short,
        volumeFactor: 0.90,
        forceEasyReturn: true,
        requiresPlanRebase: false,
        daysMissed: days,
      );
    }

    if (days <= 14) {
      return AbsenceResult(
        level: AbsenceLevel.moderate,
        volumeFactor: 0.75,
        forceEasyReturn: true,
        requiresPlanRebase: false,
        daysMissed: days,
      );
    }

    return AbsenceResult(
      level: AbsenceLevel.extended,
      volumeFactor: 0.60,
      forceEasyReturn: true,
      requiresPlanRebase: true,
      daysMissed: days,
    );
  }
}