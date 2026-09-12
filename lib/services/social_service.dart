// lib/services/social_service.dart
//
// Athlete discovery + the follow graph. Backed by the `profiles` and `follows`
// tables (see supabase/migrations/2026090600000{0,1}_*). All reads rely on the
// public-read RLS policies, so they work for any signed-in user.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_comment.dart';
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

  /// Comment count per run id in [runIds] (missing key ⇒ 0).
  Future<Map<int, int>> commentCountsFor(List<int> runIds);

  /// Reaction ("cheer") count per run id in [runIds] (missing key ⇒ 0).
  Future<Map<int, int>> reactionCountsFor(List<int> runIds);

  /// Which of [runIds] [userId] has already reacted to.
  Future<Set<int>> reactedRunIdsFor(String userId, List<int> runIds);
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
        .select('id, display_name, avatar_url, city, country, is_pro')
        .inFilter('id', ids);
    return {
      for (final r in (rows as List))
        (r as Map<String, dynamic>)['id'] as String: r,
    };
  }

  @override
  Future<Map<int, int>> commentCountsFor(List<int> runIds) async {
    if (runIds.isEmpty) return {};
    // One round trip: pull just the run_id column for the page's runs and tally
    // client-side (a page is ~15 runs, so this stays tiny).
    final rows = await _c
        .from('activity_comments')
        .select('run_id')
        .inFilter('run_id', runIds);
    final counts = <int, int>{};
    for (final r in (rows as List)) {
      final id = ((r as Map<String, dynamic>)['run_id'] as num).toInt();
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<Map<int, int>> reactionCountsFor(List<int> runIds) async {
    if (runIds.isEmpty) return {};
    final rows = await _c
        .from('activity_reactions')
        .select('run_id')
        .inFilter('run_id', runIds);
    final counts = <int, int>{};
    for (final r in (rows as List)) {
      final id = ((r as Map<String, dynamic>)['run_id'] as num).toInt();
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<Set<int>> reactedRunIdsFor(String userId, List<int> runIds) async {
    if (runIds.isEmpty) return {};
    final rows = await _c
        .from('activity_reactions')
        .select('run_id')
        .eq('user_id', userId)
        .inFilter('run_id', runIds);
    return (rows as List)
        .map((r) => ((r as Map<String, dynamic>)['run_id'] as num).toInt())
        .toSet();
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

  /// The signed-in user's id, or null when signed out / no session. Used to
  /// tell "my comment" from "someone else's" in the comments sheet.
  String? get currentUserId {
    try {
      return _uid;
    } catch (_) {
      return null;
    }
  }

  // ── Discovery ─────────────────────────────────────────────────────────────

  /// Public athletes whose display name matches [query] (case-insensitive
  /// partial match, `ILIKE '%query%'`). Empty query → empty list. Each result
  /// carries avatar, display name and location for the search tile.
  Future<List<AthleteProfile>> searchAthletes(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final me = _uid;
      final safe = q.replaceAll('%', r'\%').replaceAll('_', r'\_');
      // `profiles.is_public` is `NOT NULL DEFAULT true` (see the social-cols
      // migration), so `.eq('is_public', true)` can't hide null rows — there
      // are none. Exclude yourself server-side so a full page of *other*
      // athletes comes back even when you'd have matched.
      var filter = _client
          .from('profiles')
          .select()
          .eq('is_public', true)
          .ilike('display_name', '%$safe%');
      if (me != null) filter = filter.neq('id', me);
      final rows = await filter.limit(limit);
      return (rows as List)
          .map((r) => AthleteProfile.fromMap(r as Map<String, dynamic>))
          .where((a) => a.id != me) // belt-and-suspenders
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
      final me = _uid;
      var filter = _client
          .from('profiles')
          .select()
          .eq('is_public', true)
          .not('display_name', 'is', null);
      if (me != null) filter = filter.neq('id', me);
      final rows = await filter
          .order('total_runs', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => AthleteProfile.fromMap(r as Map<String, dynamic>))
          .where((a) => a.id != me)
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

      final visibleRows = runRows
          // Defence in depth: never surface a run whose author we don't follow,
          // even if the backend ever returns one.
          .where((r) => followed.contains(r['user_id'] as String))
          .toList();

      final authorIds = visibleRows
          .map((r) => r['user_id'] as String)
          .toSet()
          .toList();
      final runIds = visibleRows
          .map((r) => (r['id'] as num).toInt())
          .toList();
      final profiles = await _feedStore.profilesByIds(authorIds);
      final commentCounts = await _feedStore.commentCountsFor(runIds);
      final reactionCounts = await _feedStore.reactionCountsFor(runIds);
      final reactedIds = await _feedStore.reactedRunIdsFor(me, runIds);

      return visibleRows
          .map((r) {
            final id = (r['id'] as num).toInt();
            return FeedRun.fromRows(
              r,
              profiles[r['user_id'] as String],
              commentCount: commentCounts[id] ?? 0,
              reactionCount: reactionCounts[id] ?? 0,
              viewerReacted: reactedIds.contains(id),
            );
          })
          .toList();
    } catch (e) {
      debugPrint('[SocialService] fetchFriendsFeed error: $e');
      return [];
    }
  }

  // ── Comments ─────────────────────────────────────────────────────────────

  /// All comments on [runId], oldest first, each carrying the commenter's
  /// display name + avatar. `[]` on error or when the run isn't visible.
  Future<List<ActivityComment>> fetchComments(int runId) async {
    try {
      final rows = await _client
          .from('activity_comments')
          .select('id, run_id, user_id, comment, created_at')
          .eq('run_id', runId)
          .order('created_at', ascending: true);
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return [];
      final ids = list.map((r) => r['user_id'] as String).toSet().toList();
      final profiles = await _feedStore.profilesByIds(ids);
      return list
          .map((r) => ActivityComment.fromRows(r, profiles[r['user_id']]))
          .toList();
    } catch (e) {
      debugPrint('[SocialService] fetchComments error: $e');
      return [];
    }
  }

  /// Inserts a comment as the signed-in user and returns the created row
  /// (with commenter identity filled in), or `null` on failure / empty text.
  Future<ActivityComment?> postComment(int runId, String comment) async {
    final text = comment.trim();
    if (text.isEmpty) return null;
    try {
      final me = _uid;
      if (me == null) return null;
      final row = await _client
          .from('activity_comments')
          .insert({'run_id': runId, 'user_id': me, 'comment': text})
          .select('id, run_id, user_id, comment, created_at')
          .single();
      final profiles = await _feedStore.profilesByIds([me]);
      Analytics.capture('run_commented', properties: {'run_id': runId});
      return ActivityComment.fromRows(row, profiles[me]);
    } catch (e) {
      debugPrint('[SocialService] postComment error: $e');
      return null;
    }
  }

  /// Deletes [commentId] — the RLS policy only allows deleting your own, so
  /// this is a no-op (returns false) against anyone else's comment.
  Future<bool> deleteComment(String commentId) async {
    try {
      final me = _uid;
      if (me == null) return false;
      await _client
          .from('activity_comments')
          .delete()
          .eq('id', commentId)
          .eq('user_id', me);
      Analytics.capture('comment_deleted', properties: {'comment_id': commentId});
      return true;
    } catch (e) {
      debugPrint('[SocialService] deleteComment error: $e');
      return false;
    }
  }

  // ── Reactions ("cheers") ─────────────────────────────────────────────────

  /// Toggles the signed-in user's reaction on [runId]. Pass the UI's current
  /// (pre-toggle) state as [currentlyReacted]. Returns the resulting state
  /// (`true` = now reacted) on success, or `null` on failure — the caller
  /// should roll its optimistic update back on `null`.
  Future<bool?> toggleReaction(int runId, {required bool currentlyReacted}) async {
    try {
      final me = _uid;
      if (me == null) return null;
      if (currentlyReacted) {
        await _client
            .from('activity_reactions')
            .delete()
            .eq('run_id', runId)
            .eq('user_id', me);
        Analytics.capture('run_unreacted', properties: {'run_id': runId});
        return false;
      }
      await _client.from('activity_reactions').upsert(
        {'run_id': runId, 'user_id': me},
        onConflict: 'run_id,user_id',
        ignoreDuplicates: true,
      );
      Analytics.capture('run_reacted', properties: {'run_id': runId});
      return true;
    } catch (e) {
      debugPrint('[SocialService] toggleReaction error: $e');
      return null;
    }
  }

  /// Live reaction count for one run — used when a card/screen doesn't already
  /// carry a batch-loaded count.
  Future<int> reactionCount(int runId) async {
    try {
      return await _client
          .from('activity_reactions')
          .count(CountOption.exact)
          .eq('run_id', runId);
    } catch (e) {
      debugPrint('[SocialService] reactionCount error: $e');
      return 0;
    }
  }

  /// Whether the signed-in user has already reacted to [runId].
  Future<bool> hasReacted(int runId) async {
    try {
      final me = _uid;
      if (me == null) return false;
      final row = await _client
          .from('activity_reactions')
          .select('id')
          .eq('run_id', runId)
          .eq('user_id', me)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('[SocialService] hasReacted error: $e');
      return false;
    }
  }
}
