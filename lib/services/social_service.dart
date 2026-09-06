// lib/services/social_service.dart
//
// Athlete discovery + the follow graph. Backed by the `profiles` and `follows`
// tables (see supabase/migrations/2026090600000{0,1}_*). All reads rely on the
// public-read RLS policies, so they work for any signed-in user.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/athlete_profile.dart';
import 'analytics_service.dart';

class SocialService {
  static final SocialService instance = SocialService._();
  SocialService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  // ── Discovery ─────────────────────────────────────────────────────────────

  /// Public athletes whose display name matches [query] (case-insensitive
  /// partial match, `ILIKE '%query%'`). Empty query → empty list. Each result
  /// carries avatar, display name and location for the search tile.
  Future<List<AthleteProfile>> searchAthletes(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final safe = q.replaceAll('%', r'\%').replaceAll('_', r'\_');
      final rows = await _client
          .from('profiles')
          .select()
          .eq('is_public', true)
          .ilike('display_name', '%$safe%')
          .limit(limit);
      return (rows as List)
          .map((r) => AthleteProfile.fromMap(r as Map<String, dynamic>))
          .where((a) => a.id != _uid) // don't surface yourself
          .toList();
    } catch (e) {
      debugPrint('[SocialService] searchAthletes error: $e');
      return [];
    }
  }

  /// Single athlete by id. Returns null if not found or not visible to caller.
  Future<AthleteProfile?> getAthlete(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return row == null ? null : AthleteProfile.fromMap(row);
    } catch (e) {
      debugPrint('[SocialService] getAthlete error: $e');
      return null;
    }
  }

  // ── Follow / unfollow ────────────────────────────────────────────────────

  Future<bool> follow(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return false;
    try {
      await _client.from('follows').upsert({
        'follower_id': me,
        'following_id': targetUserId,
      }, onConflict: 'follower_id,following_id', ignoreDuplicates: true);
      Analytics.capture('athlete_followed', properties: {'target': targetUserId});
      return true;
    } catch (e) {
      debugPrint('[SocialService] follow error: $e');
      return false;
    }
  }

  Future<bool> unfollow(String targetUserId) async {
    final me = _uid;
    if (me == null) return false;
    try {
      await _client
          .from('follows')
          .delete()
          .eq('follower_id', me)
          .eq('following_id', targetUserId);
      Analytics.capture('athlete_unfollowed', properties: {'target': targetUserId});
      return true;
    } catch (e) {
      debugPrint('[SocialService] unfollow error: $e');
      return false;
    }
  }

  /// Whether the signed-in user follows [targetUserId].
  Future<bool> isFollowing(String targetUserId) async {
    final me = _uid;
    if (me == null) return false;
    try {
      final row = await _client
          .from('follows')
          .select('follower_id')
          .eq('follower_id', me)
          .eq('following_id', targetUserId)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('[SocialService] isFollowing error: $e');
      return false;
    }
  }

  // ── Counts + lists ───────────────────────────────────────────────────────

  Future<SocialCounts> counts(String userId) async {
    try {
      final followers = await _client
          .from('follows')
          .count(CountOption.exact)
          .eq('following_id', userId);
      final following = await _client
          .from('follows')
          .count(CountOption.exact)
          .eq('follower_id', userId);
      return SocialCounts(followers: followers, following: following);
    } catch (e) {
      debugPrint('[SocialService] counts error: $e');
      return SocialCounts.zero;
    }
  }

  /// Athletes who follow [userId].
  Future<List<AthleteProfile>> followers(String userId, {int limit = 100}) =>
      _peopleVia(
        column: 'follower_id',
        matchColumn: 'following_id',
        userId: userId,
        limit: limit,
      );

  /// Athletes [userId] follows.
  Future<List<AthleteProfile>> following(String userId, {int limit = 100}) =>
      _peopleVia(
        column: 'following_id',
        matchColumn: 'follower_id',
        userId: userId,
        limit: limit,
      );

  Future<List<AthleteProfile>> _peopleVia({
    required String column,
    required String matchColumn,
    required String userId,
    required int limit,
  }) async {
    try {
      final edges = await _client
          .from('follows')
          .select(column)
          .eq(matchColumn, userId)
          .limit(limit);
      final ids = (edges as List)
          .map((e) => (e as Map<String, dynamic>)[column] as String)
          .toList();
      if (ids.isEmpty) return [];
      final rows = await _client
          .from('profiles')
          .select()
          .inFilter('id', ids);
      return (rows as List)
          .map((r) => AthleteProfile.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SocialService] _peopleVia error: $e');
      return [];
    }
  }
}
