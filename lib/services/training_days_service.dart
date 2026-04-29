// lib/services/training_days_service.dart
//
// Stores and retrieves the user's chosen training days.
// Indices: 0=Monday, 1=Tuesday, 2=Wednesday, 3=Thursday,
//          4=Friday, 5=Saturday, 6=Sunday

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'engine_state_sync_service.dart';

class TrainingDaysService {
  static const _key = 'training_day_indices';

  /// Smart defaults keyed by runs-per-week count.
  /// Patterns try to:
  ///   - space hard days with rest before them
  ///   - put the long run where the day after is a rest day
  static const Map<int, List<int>> _defaults = {
    1: [0],               // Mon
    2: [0, 3],            // Mon, Thu
    3: [0, 2, 4],         // Mon, Wed, Fri
    4: [0, 2, 3, 5],      // Mon, Wed, Thu, Sat
    5: [0, 1, 3, 4, 6],   // Mon, Tue, Thu, Fri, Sun
    6: [0, 1, 2, 4, 5, 6],// Mon, Tue, Wed, Fri, Sat, Sun
    7: [0, 1, 2, 3, 4, 5, 6],
  };

  /// Returns the smart default day indices for a given frequency.
  static List<int> defaultsFor(int n) =>
      List<int>.from(_defaults[n.clamp(1, 7)] ?? _defaults[4]!);

  /// Loads the saved training day indices. Returns null if never saved.
  static Future<List<int>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List).cast<int>();
    } catch (_) {
      return null;
    }
  }

  /// Loads saved days, or falls back to defaults for [fallbackCount].
  static Future<List<int>> loadOrDefault(int fallbackCount) async {
    return (await load()) ?? defaultsFor(fallbackCount);
  }

  /// Persists the training day indices.
  static Future<void> save(List<int> indices, {bool syncToCloud = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = [...indices]..sort();
    await prefs.setString(_key, jsonEncode(sorted));
    if (syncToCloud) {
      await EngineStateSyncService.instance.syncTrainingDays(sorted);
    }
  }

  /// Day labels for display (index 0–6 → Mon–Sun).
  static const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
}
