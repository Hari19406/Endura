// lib/services/profile_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UserProfile model
// ─────────────────────────────────────────────────────────────────────────────

class UserProfile {
  final String? displayName;
  final String? gender;
  final DateTime? dob;
  final String? goal;
  final int? runsPerWeek;
  final List<int> trainingDays;
  final String? paceDistance;
  final int? paceMinutes;
  final int? paceSeconds;
  final DateTime? raceDate;
  final bool useMetric;

  const UserProfile({
    this.displayName,
    this.gender,
    this.dob,
    this.goal,
    this.runsPerWeek,
    this.trainingDays = const [],
    this.paceDistance,
    this.paceMinutes,
    this.paceSeconds,
    this.raceDate,
    this.useMetric = true,
  });

  Map<String, dynamic> toMap(String userId) => {
        'id': userId,
        if (displayName != null) 'display_name': displayName,
        if (gender != null) 'gender': gender,
        if (dob != null) 'dob': dob!.toIso8601String().substring(0, 10),
        if (goal != null) 'goal': goal,
        if (runsPerWeek != null) 'runs_per_week': runsPerWeek,
        if (trainingDays.isNotEmpty) 'training_days': trainingDays,
        if (paceDistance != null) 'pace_distance': paceDistance,
        if (paceMinutes != null) 'pace_minutes': paceMinutes,
        if (paceSeconds != null) 'pace_seconds': paceSeconds,
        if (raceDate != null) 'race_date': raceDate!.toIso8601String().substring(0, 10),
        'use_metric': useMetric,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        displayName: map['display_name'] as String?,
        gender: map['gender'] as String?,
        dob: map['dob'] != null ? DateTime.tryParse(map['dob'] as String) : null,
        goal: map['goal'] as String?,
        runsPerWeek: map['runs_per_week'] as int?,
        trainingDays: (map['training_days'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
        paceDistance: map['pace_distance'] as String?,
        paceMinutes: map['pace_minutes'] as int?,
        paceSeconds: map['pace_seconds'] as int?,
        raceDate: map['race_date'] != null
            ? DateTime.tryParse(map['race_date'] as String)
            : null,
        useMetric: map['use_metric'] as bool? ?? true,
      );

  UserProfile copyWith({
    String? displayName,
    String? gender,
    DateTime? dob,
    String? goal,
    int? runsPerWeek,
    List<int>? trainingDays,
    String? paceDistance,
    int? paceMinutes,
    int? paceSeconds,
    DateTime? raceDate,
    bool? useMetric,
  }) =>
      UserProfile(
        displayName: displayName ?? this.displayName,
        gender: gender ?? this.gender,
        dob: dob ?? this.dob,
        goal: goal ?? this.goal,
        runsPerWeek: runsPerWeek ?? this.runsPerWeek,
        trainingDays: trainingDays ?? this.trainingDays,
        paceDistance: paceDistance ?? this.paceDistance,
        paceMinutes: paceMinutes ?? this.paceMinutes,
        paceSeconds: paceSeconds ?? this.paceSeconds,
        raceDate: raceDate ?? this.raceDate,
        useMetric: useMetric ?? this.useMetric,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ProfileService
// ─────────────────────────────────────────────────────────────────────────────

class ProfileService {
  static final ProfileService instance = ProfileService._();
  ProfileService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  // ── Save (upsert) — call at end of onboarding ─────────────────────────────

  Future<bool> saveProfile(UserProfile profile) async {
    if (_userId == null) return false;
    try {
      await _client
          .from('profiles')
          .upsert(profile.toMap(_userId!));
      debugPrint('[ProfileService] profile saved');
      return true;
    } catch (e) {
      debugPrint('[ProfileService] saveProfile error: $e');
      return false;
    }
  }

  // ── Fetch — call on app start or profile screen load ──────────────────────

  Future<UserProfile?> fetchProfile() async {
    if (_userId == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', _userId!)
          .maybeSingle();
      if (row == null) return null;
      return UserProfile.fromMap(row);
    } catch (e) {
      debugPrint('[ProfileService] fetchProfile error: $e');
      return null;
    }
  }

  // ── Patch a single field — e.g. useMetric toggle from settings ────────────

  Future<bool> updateField(String field, dynamic value) async {
    if (_userId == null) return false;
    try {
      await _client.from('profiles').update({
        field: value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _userId!);
      return true;
    } catch (e) {
      debugPrint('[ProfileService] updateField error: $e');
      return false;
    }
  }

  // ── Delete — call alongside CloudSyncService.deleteAllCloudRuns() ─────────

  Future<bool> deleteProfile() async {
    if (_userId == null) return false;
    try {
      await _client.from('profiles').delete().eq('id', _userId!);
      debugPrint('[ProfileService] profile deleted');
      return true;
    } catch (e) {
      debugPrint('[ProfileService] deleteProfile error: $e');
      return false;
    }
  }
}
