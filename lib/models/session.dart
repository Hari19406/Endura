class Session {
  final int duration;
  final DateTime timestamp;


  Session({
    required this.duration,
    required this.timestamp,
  });

  // Optional: Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'duration': duration,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Optional: Create from JSON
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      duration: json['duration'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  // Optional: Format duration for display (e.g., "2m 30s")
  String getFormattedDuration() {
    int minutes = duration ~/ 60;
    int seconds = duration % 60;
    
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
  String getFormattedTimestamp() {
    return "${timestamp.hour.toString().padLeft(2, '0')}:"
           "${timestamp.minute.toString().padLeft(2, '0')}";
  }
}