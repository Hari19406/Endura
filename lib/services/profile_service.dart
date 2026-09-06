// lib/services/profile_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../engines/run_aggregates.dart';
import '../models/athlete_profile.dart';
import '../utils/database_service.dart' show RunRecord;

// ─────────────────────────────────────────────────────────────────────────────
// UserProfile model
// ─────────────────────────────────────────────────────────────────────────────

class UserProfile {
  final String? firstName;
  final String? gender;
  final DateTime? dob;
  final String? goal;
  final int? runsPerWeek;
  final List<int> trainingDays;
  final String? paceDistance;
  final int? paceHours;
  final int? paceMinutes;
  final int? paceSeconds;
  final DateTime? raceDate;
  final bool useMetric;
  final double? baselineWeeklyKm;
  // Plan state
  final DateTime? planStartDate;
  final int? planWeeks;
  final int? vdotScore;
  final bool? vdotIsProvisional;
  final String? experienceLevel;
  final String? goalIntent;
  final int? longRunDayIndex;
  final DateTime? planSnoozeUntil;
  final String? pushToken;
  final String? themeMode;

  const UserProfile({
    this.firstName,
    this.gender,
    this.dob,
    this.goal,
    this.runsPerWeek,
    this.trainingDays = const [],
    this.paceDistance,
    this.paceHours,
    this.paceMinutes,
    this.paceSeconds,
    this.raceDate,
    this.useMetric = true,
    this.baselineWeeklyKm,
    this.planStartDate,
    this.planWeeks,
    this.vdotScore,
    this.vdotIsProvisional,
    this.experienceLevel,
    this.goalIntent,
    this.longRunDayIndex,
    this.planSnoozeUntil,
    this.pushToken,
    this.themeMode,
  });

  Map<String, dynamic> toMap(String userId) => {
    'id': userId,
    if (firstName != null) 'first_name': firstName,
    if (gender != null) 'gender': gender,
    if (dob != null) 'dob': dob!.toIso8601String().substring(0, 10),
    if (goal != null) 'goal': goal,
    if (runsPerWeek != null) 'runs_per_week': runsPerWeek,
    if (trainingDays.isNotEmpty) 'training_days': trainingDays,
    if (paceDistance != null) 'pace_distance': paceDistance,
    if (paceHours != null) 'pace_hours': paceHours,
    if (paceMinutes != null) 'pace_minutes': paceMinutes,
    if (paceSeconds != null) 'pace_seconds': paceSeconds,
    if (raceDate != null)
      'race_date': raceDate!.toIso8601String().substring(0, 10),
    'use_metric': useMetric,
    if (baselineWeeklyKm != null)
      'baseline_weekly_mileage_km': baselineWeeklyKm,
    if (planStartDate != null)
      'plan_start_date': planStartDate!.toIso8601String().substring(0, 10),
    if (planWeeks != null) 'plan_weeks': planWeeks,
    if (vdotScore != null) 'vdot_score': vdotScore,
    if (vdotIsProvisional != null) 'vdot_is_provisional': vdotIsProvisional,
    if (experienceLevel != null) 'experience_level': experienceLevel,
    if (goalIntent != null) 'goal_intent': goalIntent,
    if (longRunDayIndex != null) 'long_run_day_index': longRunDayIndex,
    if (planSnoozeUntil != null)
      'plan_snooze_until': planSnoozeUntil!.toIso8601String().substring(0, 10),
    if (pushToken != null) 'push_token': pushToken,
    if (themeMode != null) 'theme_mode': themeMode,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    firstName: map['first_name'] as String?,
    gender: map['gender'] as String?,
    dob: map['dob'] != null ? DateTime.tryParse(map['dob'] as String) : null,
    goal: map['goal'] as String?,
    runsPerWeek: map['runs_per_week'] as int?,
    trainingDays: (map['training_days'] as List<dynamic>? ?? [])
        .map((e) => e as int)
        .toList(),
    paceDistance: map['pace_distance'] as String?,
    paceHours: map['pace_hours'] as int?,
    paceMinutes: map['pace_minutes'] as int?,
    paceSeconds: map['pace_seconds'] as int?,
    raceDate: map['race_date'] != null
        ? DateTime.tryParse(map['race_date'] as String)
        : null,
    useMetric: map['use_metric'] as bool? ?? true,
    baselineWeeklyKm: (map['baseline_weekly_mileage_km'] as num?)?.toDouble(),
    planStartDate: map['plan_start_date'] != null
        ? DateTime.tryParse(map['plan_start_date'] as String)
        : null,
    planWeeks: map['plan_weeks'] as int?,
    vdotScore: map['vdot_score'] as int?,
    vdotIsProvisional: map['vdot_is_provisional'] as bool?,
    experienceLevel: map['experience_level'] as String?,
    goalIntent: map['goal_intent'] as String?,
    longRunDayIndex: map['long_run_day_index'] as int?,
    planSnoozeUntil: map['plan_snooze_until'] != null
        ? DateTime.tryParse(map['plan_snooze_until'] as String)
        : null,
    pushToken: map['push_token'] as String?,
    themeMode: map['theme_mode'] as String?,
  );

  UserProfile copyWith({
    String? firstName,
    String? gender,
    DateTime? dob,
    String? goal,
    int? runsPerWeek,
    List<int>? trainingDays,
    String? paceDistance,
    int? paceHours,
    int? paceMinutes,
    int? paceSeconds,
    DateTime? raceDate,
    bool? useMetric,
    double? baselineWeeklyKm,
    DateTime? planStartDate,
    int? planWeeks,
    int? vdotScore,
    bool? vdotIsProvisional,
    String? experienceLevel,
    String? goalIntent,
    int? longRunDayIndex,
    DateTime? planSnoozeUntil,
    String? pushToken,
    String? themeMode,
  }) => UserProfile(
    firstName: firstName ?? this.firstName,
    gender: gender ?? this.gender,
    dob: dob ?? this.dob,
    goal: goal ?? this.goal,
    runsPerWeek: runsPerWeek ?? this.runsPerWeek,
    trainingDays: trainingDays ?? this.trainingDays,
    paceDistance: paceDistance ?? this.paceDistance,
    paceHours: paceHours ?? this.paceHours,
    paceMinutes: paceMinutes ?? this.paceMinutes,
    paceSeconds: paceSeconds ?? this.paceSeconds,
    raceDate: raceDate ?? this.raceDate,
    useMetric: useMetric ?? this.useMetric,
    baselineWeeklyKm: baselineWeeklyKm ?? this.baselineWeeklyKm,
    planStartDate: planStartDate ?? this.planStartDate,
    planWeeks: planWeeks ?? this.planWeeks,
    vdotScore: vdotScore ?? this.vdotScore,
    vdotIsProvisional: vdotIsProvisional ?? this.vdotIsProvisional,
    experienceLevel: experienceLevel ?? this.experienceLevel,
    goalIntent: goalIntent ?? this.goalIntent,
    longRunDayIndex: longRunDayIndex ?? this.longRunDayIndex,
    planSnoozeUntil: planSnoozeUntil ?? this.planSnoozeUntil,
    pushToken: pushToken ?? this.pushToken,
    themeMode: themeMode ?? this.themeMode,
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
      await _client.from('profiles').upsert(profile.toMap(_userId!));
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

  // ── Sync plan state between local prefs and Supabase ─────────────────────
  // - If Supabase has no plan_start_date → existing user, push local data up
  // - If local has no plan_start_date → new device, pull from Supabase down
  // This handles both existing users (backfill) and new device restores.

  Future<void> syncPlanState() async {
    if (_userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final profile = await fetchProfile();

    final localPlanDate = prefs.getString('plan_start_date');
    final cloudPlanDate = profile?.planStartDate;

    if (cloudPlanDate == null && localPlanDate != null) {
      // Existing user — push local data up to Supabase
      debugPrint('[ProfileService] backfilling plan state to Supabase');
      final startDate = DateTime.tryParse(localPlanDate);
      final raceDateStr = prefs.getString('race_date');
      final dobStr = prefs.getString('dob');
      await saveProfile(
        UserProfile(
          firstName: prefs.getString('first_name'),
          gender: prefs.getString('gender'),
          dob: dobStr != null ? DateTime.tryParse(dobStr) : null,
          goal: prefs.getString('goal_race'),
          runsPerWeek: prefs.getInt('runs_per_week'),
          paceDistance: prefs.getString('pace_distance'),
          paceHours: prefs.getInt('pace_hours'),
          paceMinutes: prefs.getInt('pace_minutes'),
          paceSeconds: prefs.getInt('pace_seconds'),
          raceDate: raceDateStr != null ? DateTime.tryParse(raceDateStr) : null,
          useMetric: true,
          baselineWeeklyKm: prefs.getDouble('weekly_mileage_km'),
          planStartDate: startDate,
          planWeeks: prefs.getInt('plan_weeks'),
          vdotScore: prefs.getInt('vdot_score'),
          vdotIsProvisional: prefs.getBool('vdot_is_provisional'),
          experienceLevel: prefs.getString('experience_level'),
          goalIntent: prefs.getString('goal_intent'),
          longRunDayIndex: prefs.getInt('long_run_day_index'),
        ),
      );
    } else if (cloudPlanDate != null && localPlanDate == null) {
      // New device — pull from Supabase into local prefs
      debugPrint('[ProfileService] restoring plan state from Supabase');
      if (profile == null) return;
      await _writePrefsFromProfile(profile, prefs);
    }
  }

  Future<void> _writePrefsFromProfile(
    UserProfile p,
    SharedPreferences prefs,
  ) async {
    if (p.firstName != null) await prefs.setString('first_name', p.firstName!);
    if (p.gender != null) await prefs.setString('gender', p.gender!);
    if (p.goal != null) await prefs.setString('goal_race', p.goal!);
    if (p.experienceLevel != null)
      await prefs.setString('experience_level', p.experienceLevel!);
    if (p.goalIntent != null)
      await prefs.setString('goal_intent', p.goalIntent!);
    if (p.paceDistance != null)
      await prefs.setString('pace_distance', p.paceDistance!);
    if (p.dob != null) await prefs.setString('dob', p.dob!.toIso8601String());
    if (p.raceDate != null)
      await prefs.setString('race_date', p.raceDate!.toIso8601String());
    if (p.planStartDate != null)
      await prefs.setString(
        'plan_start_date',
        p.planStartDate!.toIso8601String(),
      );
    if (p.baselineWeeklyKm != null)
      await prefs.setDouble('weekly_mileage_km', p.baselineWeeklyKm!);
    if (p.runsPerWeek != null)
      await prefs.setInt('runs_per_week', p.runsPerWeek!);
    if (p.planWeeks != null) await prefs.setInt('plan_weeks', p.planWeeks!);
    if (p.vdotScore != null) await prefs.setInt('vdot_score', p.vdotScore!);
    if (p.longRunDayIndex != null)
      await prefs.setInt('long_run_day_index', p.longRunDayIndex!);
    if (p.paceHours != null) await prefs.setInt('pace_hours', p.paceHours!);
    if (p.paceMinutes != null)
      await prefs.setInt('pace_minutes', p.paceMinutes!);
    if (p.paceSeconds != null)
      await prefs.setInt('pace_seconds', p.paceSeconds!);
    if (p.vdotIsProvisional != null)
      await prefs.setBool('vdot_is_provisional', p.vdotIsProvisional!);
    if (p.planSnoozeUntil != null) {
      await prefs.setString(
        'plan_complete_snooze_until',
        p.planSnoozeUntil!.toIso8601String(),
      );
    }
    debugPrint('[ProfileService] local prefs restored from Supabase');
  }

  // ── Patch a single field — e.g. useMetric toggle from settings ────────────

  Future<bool> updateField(String field, dynamic value) async {
    if (_userId == null) return false;
    try {
      await _client
          .from('profiles')
          .update({
            field: value,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _userId!);
      return true;
    } catch (e) {
      debugPrint('[ProfileService] updateField error: $e');
      return false;
    }
  }

  // ── Social / athlete identity ────────────────────────────────────────────
  // The `profiles` row carries both coaching config (above) and public social
  // identity (below). These helpers touch only the social columns; see
  // AthleteProfile and supabase/migrations/20260906000000_extend_profiles_social.

  Future<AthleteProfile?> fetchAthleteProfile() async {
    if (_userId == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select(
            'id, username, display_name, avatar_url, bio, city, country, is_public',
          )
          .eq('id', _userId!)
          .maybeSingle();
      return row == null ? null : AthleteProfile.fromMap(row);
    } catch (e) {
      debugPrint('[ProfileService] fetchAthleteProfile error: $e');
      return null;
    }
  }

  /// Patches only the social columns. Returns true on success; false (with a
  /// logged reason) on RLS / unique-username / check-constraint failure.
  Future<bool> updateAthleteFields(AthleteProfile profile) async {
    if (_userId == null) return false;
    try {
      await _client
          .from('profiles')
          .update(profile.toUpdateMap())
          .eq('id', _userId!);
      return true;
    } catch (e) {
      debugPrint('[ProfileService] updateAthleteFields error: $e');
      return false;
    }
  }

  /// Recomputes the denormalized run aggregates from the full local run list
  /// and writes them to the signed-in user's `profiles` row. Called from the
  /// run-save path so another athlete's profile can show high-level stats
  /// without read access to the RLS-private `runs` table.
  Future<bool> pushRunAggregates(List<RunRecord> runs) async {
    if (_userId == null) return false;
    try {
      final agg = RunAggregates.fromRuns(runs);
      await _client
          .from('profiles')
          .update({
            ...agg.toMap(),
            'stats_updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _userId!);
      return true;
    } catch (e) {
      debugPrint('[ProfileService] pushRunAggregates error: $e');
      return false;
    }
  }

  /// Uploads a pre-compressed avatar image to the public `avatars` bucket at
  /// `avatars/<uid>.jpg`, points `profiles.avatar_url` at it (cache-busted),
  /// and returns the new URL. Null on failure.
  Future<String?> uploadAvatar(Uint8List jpegBytes) async {
    final uid = _userId;
    if (uid == null) return null;
    try {
      final path = '$uid.jpg';
      await _client.storage
          .from('avatars')
          .uploadBinary(
            path,
            jpegBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      final base = _client.storage.from('avatars').getPublicUrl(path);
      final url = '$base?v=${DateTime.now().millisecondsSinceEpoch}';
      await _client
          .from('profiles')
          .update({
            'avatar_url': url,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', uid);
      return url;
    } catch (e) {
      debugPrint('[ProfileService] uploadAvatar error: $e');
      return null;
    }
  }

  /// True if [username] is free (or already owned by the signed-in user).
  /// Case-insensitive — the column is `citext`.
  Future<bool> usernameAvailable(String username) async {
    try {
      final row = await _client
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle();
      return row == null || row['id'] == _userId;
    } catch (e) {
      debugPrint('[ProfileService] usernameAvailable error: $e');
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
