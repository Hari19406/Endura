// lib/services/theme_service.dart
//
// Owns the app-wide ThemeMode (light / dark / system). Backed by
// SharedPreferences for instant local persistence and mirrored to the Supabase
// profile (theme_mode column) so the preference follows the user to new
// devices.
//
// Usage:
//   await ThemeController.instance.load();   // call once before runApp
//   ValueListenableBuilder(valueListenable: ThemeController.instance, ...)
//   ThemeController.instance.setMode(ThemeMode.dark);

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_service.dart';

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);
  static final ThemeController instance = ThemeController._();

  static const String _prefsKey = 'theme_mode';

  /// Load the saved preference from local storage. Safe to call before the
  /// Supabase session is known — the cloud value is reconciled later via
  /// [applyFromRemote].
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = _decode(prefs.getString(_prefsKey)) ?? ThemeMode.system;
    } catch (_) {
      value = ThemeMode.system;
    }
  }

  /// Update the mode: notifies listeners immediately, persists locally, and
  /// best-effort syncs to the Supabase profile.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;
    final encoded = _encode(mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {}
    // Fire-and-forget cloud sync; failures are non-fatal.
    ProfileService.instance.updateField('theme_mode', encoded);
  }

  /// Apply a value pulled from the remote profile (e.g. on a fresh device),
  /// updating local storage to match. Only applies when non-null/valid.
  Future<void> applyFromRemote(String? encoded) async {
    final mode = _decode(encoded);
    if (mode == null) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _encode(mode));
    } catch (_) {}
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode? _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }
}
