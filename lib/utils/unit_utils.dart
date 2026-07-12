import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for the user's distance-unit preference.
/// Backed by the same `distance_unit` SharedPreferences key the Settings
/// screen writes to (`'km'` or `'miles'`).
class UnitUtils {
  static const String prefsKey = 'distance_unit';

  /// Live value of the unit preference. Seeded by [init] at app startup and
  /// updated by [setMiles] whenever the user flips the Settings toggle, so
  /// any screen listening to this notifier updates immediately without
  /// needing a manual refresh.
  static final ValueNotifier<bool> useMilesNotifier = ValueNotifier<bool>(false);

  /// Loads the stored preference into [useMilesNotifier]. Call once at app
  /// startup.
  static Future<void> init() async {
    useMilesNotifier.value = await isMiles();
  }

  /// Persists the preference and updates [useMilesNotifier] so all
  /// listening screens reflect the change immediately.
  static Future<void> setMiles(bool useMiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, useMiles ? 'miles' : 'km');
    useMilesNotifier.value = useMiles;
  }

  static Future<bool> isMiles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsKey) == 'miles';
  }

  static double kmToMiles(double km) => km * 0.621371;

  /// Converts [km] to the display value for the given unit preference.
  static double displayDistance(double km, bool useMiles) =>
      useMiles ? kmToMiles(km) : km;

  static String unitLabel(bool useMiles) => useMiles ? 'mi' : 'km';

  static String perUnitLabel(bool useMiles) => useMiles ? '/mi' : '/km';

  /// Converts a pace expressed in seconds-per-km to seconds-per-unit for display.
  static double displayPaceSeconds(double secondsPerKm, bool useMiles) =>
      useMiles ? secondsPerKm * 1.609344 : secondsPerKm;

  /// Formats a "m:ss" pace string already in seconds-per-km for the given unit.
  static String formatPaceString(String paceMinSec, bool useMiles) {
    if (!useMiles) return paceMinSec;
    final parts = paceMinSec.split(':');
    if (parts.length != 2) return paceMinSec;
    final mins = int.tryParse(parts[0]);
    final secs = int.tryParse(parts[1]);
    if (mins == null || secs == null) return paceMinSec;
    final totalSeconds = displayPaceSeconds((mins * 60 + secs).toDouble(), true);
    return formatSeconds(totalSeconds.round());
  }

  static String formatSeconds(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
