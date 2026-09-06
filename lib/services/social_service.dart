// lib/services/social_service.dart
//
// Athlete discovery + the follow graph. Backed by the `profiles` and `follows`
// tables (see supabase/migrations/2026090600000{0,1}_*). All reads rely on the
// public-read RLS policies, so they work for any signed-in user.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/athlete_profile.dart';
import '../models/feed_run.dart';
import 'analytics_service.dart';

/// The raw `follows`-table primitives, behind an interface so the follow-graph
/// logic in [SocialService] can be unit-tested with an in-memory fake.
abstract class FollowStore {
  Future<bool> exists(String followerId, String followingId);
  Future<void> add(String followerId, String followingId);
  Future<void> remove(String followerId, String followingId);

  /// Of [candidateFollowerIds], those that have a row
  /// `follower_id = candidate AND following_id = meId`.
  Future<Set<String>> followerIdsAmong(
    String meId,
    List<String> candidateFollowerIds,
  );
}

class SupabaseFollowStore implements FollowStore {
  SupabaseClient get _c => Supabase.instance.client;

  @override
  Future<bool> exists(String followerId, String followingId) async {
    final row = await _c
        .from('follows')
        .select('follower_id')
        .eq('follower_id', followerId)
        .eq('following_id', followingId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<void> add(String followerId, String followingId) => _c
      .from('follows')
      .upsert(
        {'follower_id': followerId, 'following_id': followingId},
        onConflict: 'follower_id,following_id',
        ignoreDuplicates: true,
      );

  @override
  Future<void> remove(String followerId, String followingId) => _c
      .from('follows')
      .delete()
      .eq('follower_id', followerId)
      .eq('following_id', followingId);

  @override
  Future<Set<String>> followerIdsAmong(
    String meId,
    List<String> candidateFollowerIds,
  ) async {
    if (candidateFollowerIds.isEmpty) return {};
    final rows = await _c
        .from('follows')
        .select('follower_id')
        .eq('following_id', meId)
        .inFilter('follower_id', candidateFollowerIds);
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['follower_id'] as String)
        .toSet();
  }
}

/// The raw feed reads (follow edges + runs + profiles), behind an interface so
/// [SocialService.fetchFriendsFeed]'s filtering/pagination logic can be
/// unit-tested with an in-memory fake.
abstract class FeedStore {
  /// IDs the given user follows (`follows.following_id` where
  /// `follower_id = me`).
  Future<List<String>> followingIds(String me);

  /// `runs` rows for [userIds], newest first, with `date < before` when [before]
  /// is set. Returns at most [limit] rows. Returns `[]` for an empty [userIds].
  Future<List<Map<String, dynamic>>> runsForUsers(
    List<String> userIds, {
    DateTime? before,
    required int limit,
  });

  /// `profiles` rows for [ids], keyed by `id`.
  Future<Map<String, Map<String, dynamic>>> profilesByIds(List<String> ids);
}

class SupabaseFeedStore implements FeedStore {
  SupabaseClient get _c => Supabase.instance.client;

  @override
  Future<List<String>> followingIds(String me) async {
    final rows = await _c
        .from('follows')
        .select('following_id')
        .eq('follower_id', me);
    return (rows as List)
        .map((r) => (r as Map<String, dynamic>)['following_id'] as String)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> runsForUsers(
    List<String> userIds, {
    DateTime? before,
    required int limit,
  }) async {
    if (userIds.isEmpty) return [];
    var query = _c.from('runs').select().inFilter('user_id', userIds);
    if (before != null) {
      query = query.lt('date', before.toUtc().toIso8601String());
    }
    final rows = await query.order('date', ascending: false).limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, Map<String, dynamic>>> profilesByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final rows = await _c
        .from('profiles')
        .select('id, display_name, avatar_url, city, country')
        .inFilter('id', ids);
    return {
      for (final r in (rows as List))
        (r as Map<String, dynamic>)['id'] as String: r,
    };
  }
}

class SocialService {
  static final SocialService instance = SocialService._();
  SocialService._()
    : _store = SupabaseFollowStore(),
      _feedStore = SupabaseFeedStore(),
      _uidOverride = null;

  /// Test seam: inject a fake [FollowStore] / [FeedStore] and a fixed
  /// current-user id so the follow-graph and feed methods run without a live
  /// Supabase session.
  @visibleForTesting
  SocialService.forTest({
    required FollowStore store,
    required String uid,
    FeedStore? feedStore,
  }) : _store = store,
       _feedStore = feedStore ?? SupabaseFeedStore(),
       _uidOverride = uid;

  final FollowStore _store;
  final FeedStore _feedStore;
  final String? _uidOverride;

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _uidOverride ?? _client.auth.currentUser?.id;

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

  /// Popular public athletes (by lifetime run count) for the discovery screen's
  /// empty state. Excludes the signed-in user and rows with no display name.
  Future<List<AthleteProfile>> suggestedAthletes({int limit = 20}) async {
    try {
      final rows = await _client
          .from('profiles')
          .select()
          .eq('is_public', true)
          .not('display_name', 'is', null)
          .order('total_runs', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => AthleteProfile.fromMap(r as Map<String, dynamic>))
          .where((a) => a.id != _uid)
          .toList();
    } catch (e) {
      debugPrint('[SocialService] suggestedAthletes error: $e');
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

  /// Creates the single directed edge `(me → targetUserId)`. Never touches the
  /// reverse edge.
  Future<bool> follow(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return false;
    try {
      await _store.add(me, targetUserId);
      Analytics.capture('athlete_followed', properties: {'target': targetUserId});
      return true;
    } catch (e) {
      debugPrint('[SocialService] follow error: $e');
      return false;
    }
  }

  /// Removes the `(me → targetUserId)` edge only.
  Future<bool> unfollow(String targetUserId) async {
    final me = _uid;
    if (me == null) return false;
    try {
      await _store.remove(me, targetUserId);
      Analytics.capture(
        'athlete_unfollowed',
        properties: {'target': targetUserId},
      );
      return true;
    } catch (e) {
      debugPrint('[SocialService] unfollow error: $e');
      return false;
    }
  }

  /// Whether the signed-in user follows [targetUserId] — i.e. a row exists with
  /// `follower_id = me AND following_id = targetUserId`.
  Future<bool> isFollowing(String targetUserId) async {
    final me = _uid;
    if (me == null) return false;
    try {
      return await _store.exists(me, targetUserId);
    } catch (e) {
      debugPrint('[SocialService] isFollowing error: $e');
      return false;
    }
  }

  /// The IDs, out of [targetUserIds], of athletes who follow the signed-in
  /// user (rows with `following_id = me`). Batch lookup for "Follows you"
  /// badges on a list of search results.
  Future<Set<String>> getFollowerIdsAmong(List<String> targetUserIds) async {
    final me = _uid;
    if (me == null || targetUserIds.isEmpty) return {};
    try {
      return await _store.followerIdsAmong(me, targetUserIds);
    } catch (e) {
      debugPrint('[SocialService] getFollowerIdsAmong error: $e');
      return {};
    }
  }

  /// One-way follow toggle (Strava-style — never reciprocates):
  /// - already following → DELETE the single `(me, target)` row
  /// - not following     → INSERT exactly one `(me, target)` row
  ///
  /// Returns the resulting state (`true` = now following, `false` = now not),
  /// or `null` if the write failed or the target is invalid / yourself.
  Future<bool?> toggleFollow(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return null;
    final currentlyFollowing = await isFollowing(targetUserId);
    final ok = currentlyFollowing
        ? await unfollow(targetUserId)
        : await follow(targetUserId);
    return ok ? !currentlyFollowing : null;
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

  // ── Activity feed ────────────────────────────────────────────────────────

  /// Runs by athletes the signed-in user follows, newest first.
  ///
  /// Keyset pagination: pass the `date` of the last row you already have as
  /// [before] to get the next page (rows strictly older than that instant).
  /// Returns `[]` when the user follows nobody, isn't signed in, or on error.
  Future<List<FeedRun>> fetchFriendsFeed({
    DateTime? before,
    int limit = 15,
  }) async {
    final me = _uid;
    if (me == null) return [];
    try {
      final followedIds = await _feedStore.followingIds(me);
      if (followedIds.isEmpty) return [];
      final followed = followedIds.toSet();

      final runRows = await _feedStore.runsForUsers(
        followedIds,
        before: before,
        limit: limit,
      );
      if (runRows.isEmpty) return [];

      final authorIds = runRows
          .map((r) => r['user_id'] as String)
          .toSet()
          .toList();
      final profiles = await _feedStore.profilesByIds(authorIds);

      return runRows
          // Defence in depth: never surface a run whose author we don't follow,
          // even if the backend ever returns one.
          .where((r) => followed.contains(r['user_id'] as String))
          .map((r) => FeedRun.fromRows(r, profiles[r['user_id'] as String]))
          .toList();
    } catch (e) {
      debugPrint('[SocialService] fetchFriendsFeed error: $e');
      return [];
    }
  }
}
