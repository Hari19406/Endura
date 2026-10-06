// lib/services/athlete_physiology.dart
//
// Resolves the athlete's max heart rate for HR zones. Priority:
//   1. a value the user entered in Settings
//   2. 208 − 0.7 × age, from the DOB mirrored in SharedPreferences ('dob')
//   3. the highest peak_heart_rate recorded across the user's runs
//   4. 190 bpm
// Every source is validated; an implausible one falls through to the next.

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/database_service.dart';

enum MaxHrSource { userSet, ageFormula, observed, fallback }

class MaxHrResolution {
  final int bpm;
  final MaxHrSource source;

  const MaxHrResolution(this.bpm, this.source);

  /// Used when nothing better is known.
  static const fallback = MaxHrResolution(
    AthletePhysiology.fallbackMaxHr,
    MaxHrSource.fallback,
  );

  /// Short human label for [source], e.g. "User set".
  String get sourceLabel => switch (source) {
    MaxHrSource.userSet => 'User set',
    MaxHrSource.ageFormula => 'From age',
    MaxHrSource.observed => 'Observed',
    MaxHrSource.fallback => 'Default',
  };

  /// "Max HR: 190 bpm · Default"
  String get caption => 'Max HR: $bpm bpm · $sourceLabel';

  @override
  bool operator ==(Object other) =>
      other is MaxHrResolution && other.bpm == bpm && other.source == source;

  @override
  int get hashCode => Object.hash(bpm, source);
}

class AthletePhysiology {
  /// [observedPeakLoader] defaults to the highest stored `peak_heart_rate`;
  /// it is injectable so tests don't need sqflite.
  AthletePhysiology({Future<int?> Function()? observedPeakLoader})
    : _observedPeakLoader =
          observedPeakLoader ??
          (() => DatabaseService.instance.getMaxPeakHeartRate());

  static final AthletePhysiology instance = AthletePhysiology();

  static const String maxHrPrefsKey = 'max_hr';
  static const String _dobPrefsKey = 'dob';

  static const int fallbackMaxHr = 190;

  /// Plausible range for a human maximum heart rate. Applies to user input
  /// and to the observed peak (an easy run's 150 bpm peak is not a max).
  static const int minMaxHr = 120;
  static const int maxMaxHr = 230;

  final Future<int?> Function() _observedPeakLoader;

  static bool isPlausibleMaxHr(int? bpm) =>
      bpm != null && bpm >= minMaxHr && bpm <= maxMaxHr;

  /// Whole years between [dob] and [now]; null when the age is implausible
  /// (future DOB, or outside 10–100).
  static int? ageFromDob(DateTime dob, DateTime now) {
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 10 && age <= 100 ? age : null;
  }

  /// `208 − 0.7 × age`, rounded.
  static int maxHrFromAge(int age) => (208 - 0.7 * age).round();

  /// Pure resolution of the priority order — no I/O.
  static MaxHrResolution resolve({
    int? userSet,
    DateTime? dob,
    int? observedPeak,
    DateTime? now,
  }) {
    if (isPlausibleMaxHr(userSet)) {
      return MaxHrResolution(userSet!, MaxHrSource.userSet);
    }
    if (dob != null) {
      final age = ageFromDob(dob, now ?? DateTime.now());
      if (age != null) {
        final fromAge = maxHrFromAge(age);
        if (isPlausibleMaxHr(fromAge)) {
          return MaxHrResolution(fromAge, MaxHrSource.ageFormula);
        }
      }
    }
    if (isPlausibleMaxHr(observedPeak)) {
      return MaxHrResolution(observedPeak!, MaxHrSource.observed);
    }
    return MaxHrResolution.fallback;
  }

  Future<int?> loadUserMaxHr() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(maxHrPrefsKey);
    return isPlausibleMaxHr(v) ? v : null;
  }

  /// Saves the user's max HR; null clears it (back to automatic).
  /// Returns false, saving nothing, if [bpm] is not plausible.
  Future<bool> setUserMaxHr(int? bpm) async {
    final prefs = await SharedPreferences.getInstance();
    if (bpm == null) {
      await prefs.remove(maxHrPrefsKey);
      return true;
    }
    if (!isPlausibleMaxHr(bpm)) return false;
    await prefs.setInt(maxHrPrefsKey, bpm);
    return true;
  }

  /// Resolves the max HR from stored settings, the stored DOB and the run
  /// history. Never throws — a failing source just falls through.
  Future<MaxHrResolution> resolveMaxHr({DateTime? now}) async {
    int? userSet;
    DateTime? dob;
    try {
      final prefs = await SharedPreferences.getInstance();
      userSet = prefs.getInt(maxHrPrefsKey);
      final dobStr = prefs.getString(_dobPrefsKey);
      dob = dobStr == null ? null : DateTime.tryParse(dobStr);
    } catch (_) {}

    // Cheaper to skip the DB when a higher-priority source already wins.
    int? observed;
    final early = resolve(userSet: userSet, dob: dob, now: now);
    if (early.source == MaxHrSource.fallback) {
      try {
        observed = await _observedPeakLoader();
      } catch (_) {}
    }
    return resolve(
      userSet: userSet,
      dob: dob,
      observedPeak: observed,
      now: now,
    );
  }
}
