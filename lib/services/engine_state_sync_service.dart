import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../engines/memory/engine_memory.dart';

class EngineStateSyncService {
  static final EngineStateSyncService instance = EngineStateSyncService._();
  EngineStateSyncService._();

  static const String _engineMemoryKey = 'engine_memory_v3';
  static const String _trainingDaysKey = 'training_day_indices_v1';

  SupabaseClient get _client => Supabase.instance.client;

  User? get _user => _client.auth.currentUser;
  bool get isSignedIn => _user != null;

  Future<void> syncEngineMemory(EngineMemory memory) async {
    if (!isSignedIn) return;

    try {
      final metadata = Map<String, dynamic>.from(_user?.userMetadata ?? const {});
      metadata[_engineMemoryKey] = {
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'payload': memory.toJson(),
      };

      await _client.auth.updateUser(UserAttributes(data: metadata));
    } catch (e) {
      debugPrint('[EngineStateSync] syncEngineMemory error: $e');
    }
  }

  Future<void> syncTrainingDays(List<int> indices) async {
    if (!isSignedIn) return;

    try {
      final metadata = Map<String, dynamic>.from(_user?.userMetadata ?? const {});
      metadata[_trainingDaysKey] = {
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'payload': [...indices]..sort(),
      };

      await _client.auth.updateUser(UserAttributes(data: metadata));
    } catch (e) {
      debugPrint('[EngineStateSync] syncTrainingDays error: $e');
    }
  }

  /// Refreshes the auth session once and returns both engine memory and
  /// training days — avoids two round-trips when both are needed together.
  Future<({EngineMemory? memory, List<int>? trainingDays})> fetchCloudCoachingState() async {
    try {
      await _client.auth.refreshSession();
    } catch (_) {}
    final metadata = _user?.userMetadata;
    return (
      memory: _parseEngineMemory(metadata),
      trainingDays: _parseTrainingDays(metadata),
    );
  }

  EngineMemory? _parseEngineMemory(Map<String, dynamic>? metadata) {
    try {
      final raw = metadata?[_engineMemoryKey];
      if (raw is! Map) return null;
      final payload = raw['payload'];
      if (payload is! Map) return null;
      return EngineMemory.fromJson(Map<String, dynamic>.from(payload));
    } catch (e) {
      debugPrint('[EngineStateSync] parseEngineMemory error: $e');
      return null;
    }
  }

  List<int>? _parseTrainingDays(Map<String, dynamic>? metadata) {
    try {
      final raw = metadata?[_trainingDaysKey];
      if (raw is! Map) return null;
      final payload = raw['payload'];
      if (payload is! List) return null;
      return payload.whereType<num>().map((e) => e.toInt()).toList()..sort();
    } catch (e) {
      debugPrint('[EngineStateSync] parseTrainingDays error: $e');
      return null;
    }
  }
}
