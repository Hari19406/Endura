class Settings {
  final bool useMetric;
  final int? targetPaceSecPerKm;
  final bool notificationsEnabled;

  Settings({
    required this.useMetric,
    this.targetPaceSecPerKm,
    required this.notificationsEnabled,
  });

  // Convert Settings object to JSON
  Map<String, dynamic> toJson() {
    return {
      'useMetric': useMetric,
      'targetPaceSecPerKm': targetPaceSecPerKm,
      'notificationsEnabled': notificationsEnabled,
    };
  }

  // Create Settings object from JSON
  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      useMetric: json['useMetric'] as bool,
      targetPaceSecPerKm: json['targetPaceSecPerKm'] as int?,
      notificationsEnabled: json['notificationsEnabled'] as bool,
    );
  }

  // Optional: Create a copy of Settings with modified fields
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

  // Optional: Override toString for debugging
  @override
  String toString() {
    return 'Settings(useMetric: $useMetric, targetPaceSecPerKm: $targetPaceSecPerKm, notificationsEnabled: $notificationsEnabled)';
  }

  // Optional: Override equality operators
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Settings &&
        other.useMetric == useMetric &&
        other.targetPaceSecPerKm == targetPaceSecPerKm &&
        other.notificationsEnabled == notificationsEnabled;
  }

  @override
  int get hashCode {
    return Object.hash(useMetric, targetPaceSecPerKm, notificationsEnabled);
  }
}

// Example usage:
void main() {
  // Create a Settings instance
  final settings = Settings(
    useMetric: true,
    targetPaceSecPerKm: 300, // 5 minutes per km
    notificationsEnabled: true,
  );

  // Convert to JSON
  final json = settings.toJson();
  print('JSON: $json');
  // Output: JSON: {useMetric: true, targetPaceSecPerKm: 300, notificationsEnabled: true}

  // Convert from JSON
  final settingsFromJson = Settings.fromJson(json);
  print('From JSON: $settingsFromJson');
  // Output: From JSON: Settings(useMetric: true, targetPaceSecPerKm: 300, notificationsEnabled: true)

  // Create a copy with modified fields
  final updatedSettings = settings.copyWith(notificationsEnabled: false);
  print('Updated: $updatedSettings');
  // Output: Updated: Settings(useMetric: true, targetPaceSecPerKm: 300, notificationsEnabled: false)

  // Example with null targetPaceSecPerKm
  final settingsWithoutTarget = Settings(
    useMetric: false,
    targetPaceSecPerKm: null,
    notificationsEnabled: true,
  );
  print('Without target: ${settingsWithoutTarget.toJson()}');
  // Output: Without target: {useMetric: false, targetPaceSecPerKm: null, notificationsEnabled: true}
}