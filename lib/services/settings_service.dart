import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class Settings {
  final bool useMetric;
  final int? targetPaceSecPerKm;
  final bool notificationsEnabled;

  Settings({
    required this.useMetric,
    this.targetPaceSecPerKm,
    required this.notificationsEnabled,
  });

  Map<String, dynamic> toJson() {
    return {
      'useMetric': useMetric,
      'targetPaceSecPerKm': targetPaceSecPerKm,
      'notificationsEnabled': notificationsEnabled,
    };
  }

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      useMetric: json['useMetric'] as bool,
      targetPaceSecPerKm: json['targetPaceSecPerKm'] as int?,
      notificationsEnabled: json['notificationsEnabled'] as bool,
    );
  }

  Settings copyWith({
    bool? useMetric,
    int? targetPaceSecPerKm,
    bool? notificationsEnabled,
  }) {
    return Settings(
      useMetric: useMetric ?? this.useMetric,
      targetPaceSecPerKm: targetPaceSecPerKm ?? this.targetPaceSecPerKm,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  @override
  String toString() {
    return 'Settings(useMetric: $useMetric, targetPaceSecPerKm: $targetPaceSecPerKm, notificationsEnabled: $notificationsEnabled)';
  }
}

class SettingsService {
  static const String _settingsKey = 'app_settings';

  // Default settings values
  static Settings get defaultSettings => Settings(
        useMetric: true,
        targetPaceSecPerKm: null,
        notificationsEnabled: true,
      );

  /// Load settings from SharedPreferences
  /// Returns default settings if none are saved or if there's an error
  Future<Settings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);

      if (settingsJson == null) {
        // No saved settings, return defaults
        return defaultSettings;
      }

      final Map<String, dynamic> jsonMap = json.decode(settingsJson);
      return Settings.fromJson(jsonMap);
    } catch (e) {
      // If there's any error loading or parsing, return defaults
      print('Error loading settings: $e');
      return defaultSettings;
    }
  }

  /// Save settings to SharedPreferences
  /// Returns true if successful, false otherwise
  Future<bool> saveSettings(Settings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = json.encode(settings.toJson());
      return await prefs.setString(_settingsKey, settingsJson);
    } catch (e) {
      print('Error saving settings: $e');
      return false;
    }
  }

  /// Clear all saved settings and return to defaults
  Future<bool> clearSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_settingsKey);
    } catch (e) {
      print('Error clearing settings: $e');
      return false;
    }
  }

  /// Update specific setting fields without loading/saving entire object
  Future<bool> updateSettings({
    bool? useMetric,
    int? targetPaceSecPerKm,
    bool? notificationsEnabled,
  }) async {
    try {
      // Load current settings
      final currentSettings = await loadSettings();

      // Create updated settings
      final updatedSettings = currentSettings.copyWith(
        useMetric: useMetric,
        targetPaceSecPerKm: targetPaceSecPerKm,
        notificationsEnabled: notificationsEnabled,
      );

      // Save updated settings
      return await saveSettings(updatedSettings);
    } catch (e) {
      print('Error updating settings: $e');
      return false;
    }
  }

  /// Check if settings have been saved before
  Future<bool> hasSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_settingsKey);
    } catch (e) {
      print('Error checking for settings: $e');
      return false;
    }
  }
}

// Example usage:
void main() async {
  final settingsService = SettingsService();

  // Load settings (will return defaults if none saved)
  print('Loading settings...');
  final settings = await settingsService.loadSettings();
  print('Loaded: $settings');

  // Save new settings
  print('\nSaving custom settings...');
  final customSettings = Settings(
    useMetric: false,
    targetPaceSecPerKm: 360, // 6 minutes per km
    notificationsEnabled: false,
  );
  final saved = await settingsService.saveSettings(customSettings);
  print('Save successful: $saved');

  // Load again to verify
  print('\nLoading settings again...');
  final reloadedSettings = await settingsService.loadSettings();
  print('Reloaded: $reloadedSettings');

  // Update specific fields
  print('\nUpdating only notificationsEnabled...');
  await settingsService.updateSettings(notificationsEnabled: true);
  final updatedSettings = await settingsService.loadSettings();
  print('After update: $updatedSettings');

  // Check if settings exist
  print('\nChecking if settings exist...');
  final hasSettings = await settingsService.hasSettings();
  print('Has settings: $hasSettings');

  // Clear settings
  print('\nClearing settings...');
  await settingsService.clearSettings();
  final afterClear = await settingsService.loadSettings();
  print('After clear (should be defaults): $afterClear');
}