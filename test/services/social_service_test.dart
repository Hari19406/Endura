/// SocialService — asymmetric (one-way) follow graph + "Follows you" lookup.
///
/// Exercised against an in-memory [FollowStore] so no live Supabase session is
/// needed. The key invariant under test: following someone creates exactly one
/// directed edge and never the reverse.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/social_service.dart';

class FollowEdge {
  final String follower;
  final String following;
  const FollowEdge(this.follower, this.following);
  @override
  bool operator ==(Object o) =>
      o is FollowEdge && o.follower == follower && o.following == following;
  @override
  int get hashCode => Object.hash(follower, following);
  @override
  String toString() => '$follower→$following';
}

class InMemoryFollowStore implements FollowStore {
  final Set<FollowEdge> edges = {};
  final List<FollowEdge> insertLog = [];
  final List<FollowEdge> deleteLog = [];

  @override
  Future<bool> exists(String followerId, String followingId) async =>
      edges.contains(FollowEdge(followerId, followingId));

  @override
  Future<void> add(String followerId, String followingId) async {
    final e = FollowEdge(followerId, followingId);
    insertLog.add(e);
    edges.add(e);
  }

  @override
  Future<void> remove(String followerId, String followingId) async {
    final e = FollowEdge(followerId, followingId);
    deleteLog.add(e);
    edges.remove(e);
  }

  @override
  Future<Set<String>> followerIdsAmong(
    String meId,
    List<String> candidateFollowerIds,
  ) async {
    final set = candidateFollowerIds.toSet();
    return edges
        .where((e) => e.following == meId && set.contains(e.follower))
        .map((e) => e.follower)
        .toSet();
  }
}

/// In-memory [FeedStore]: holds follow edges, run rows, and profile rows and
/// implements exactly the filtering/ordering the real Supabase store performs
/// server-side, so [SocialService.fetchFriendsFeed]'s own logic is what's under
/// test.
class InMemoryFeedStore implements FeedStore {
  final Set<FollowEdge> follows = {};
  final List<Map<String, dynamic>> runs = [];
  final Map<String, Map<String, dynamic>> profiles = {};
  final Map<int, int> commentCounts = {};
  final Map<int, int> reactionCounts = {};

  /// "$userId:$runId" pairs — who has reacted to what.
  final Set<String> reactedPairs = {};

  int runsForUsersCalls = 0;

  @override
  Future<List<String>> followingIds(String me) async => follows
      .where((e) => e.follower == me)
      .map((e) => e.following)
      .toList();

  @override
  Future<List<Map<String, dynamic>>> runsForUsers(
    List<String> userIds, {
    DateTime? before,
    required int limit,
  }) async {
    runsForUsersCalls++;
    if (userIds.isEmpty) return [];
    final set = userIds.toSet();
    final rows =
        runs
            .where((r) => set.contains(r['user_id'] as String))
            .where(
              (r) =>
                  before == null ||
                  DateTime.parse(r['date'] as String).isBefore(before),
            )
            .toList()
          ..sort(
            (a, b) => DateTime.parse(
              b['date'] as String,
            ).compareTo(DateTime.parse(a['date'] as String)),
          );
    return rows.take(limit).toList();
  }

  @override
  Future<Map<String, Map<String, dynamic>>> profilesByIds(
    List<String> ids,
  ) async {
    final set = ids.toSet();
    return {
      for (final e in profiles.entries)
        if (set.contains(e.key)) e.key: e.value,
    };
  }

  @override
  Future<Map<int, int>> commentCountsFor(List<int> runIds) async {
    final set = runIds.toSet();
    return {
      for (final e in commentCounts.entries)
        if (set.contains(e.key)) e.key: e.value,
    };
  }

  @override
  Future<Map<int, int>> reactionCountsFor(List<int> runIds) async {
    final set = runIds.toSet();
    return {
      for (final e in reactionCounts.entries)
        if (set.contains(e.key)) e.key: e.value,
    };
  }

  @override
  Future<Set<int>> reactedRunIdsFor(String userId, List<int> runIds) async {
    return {
      for (final id in runIds)
        if (reactedPairs.contains('$userId:$id')) id,
    };
  }
}

int _runSeq = 0;

Map<String, dynamic> _runRow(String userId, DateTime date, {double km = 5}) => {
  'id': ++_runSeq,
  'user_id': userId,
  'date': date.toUtc().toIso8601String(),
  'distance_km': km,
  'average_pace': '5:30',
  'duration_seconds': 1650,
  'workout_type': 'easy',
  'route_polyline': '',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = 'user-A';
  const other = 'user-B';

  late InMemoryFollowStore store;
  late SocialService social;

  setUp(() {
    store = InMemoryFollowStore();
    social = SocialService.forTest(store: store, uid: me);
  });

  group('toggleFollow — one-way only', () {
    test('follow creates exactly one edge and never the reciprocal', () async {
      final nowFollowing = await social.toggleFollow(other);

      expect(nowFollowing, isTrue);
      expect(store.edges, {const FollowEdge(me, other)});
      expect(store.insertLog, [const FollowEdge(me, other)]);
      // The reverse edge must not exist.
      expect(store.edges.contains(const FollowEdge(other, me)), isFalse);
      expect(await social.isFollowing(other), isTrue);
    });

    test('a second toggle unfollows — deletes only the (me → other) edge',
        () async {
      await social.toggleFollow(other); // follow
      final nowFollowing = await social.toggleFollow(other); // unfollow

      expect(nowFollowing, isFalse);
      expect(store.edges, isEmpty);
      expect(store.deleteLog, [const FollowEdge(me, other)]);
      expect(await social.isFollowing(other), isFalse);
    });

    test('following back is independent — two distinct edges, no auto-pairing',
        () async {
      // me follows other
      await social.toggleFollow(other);
      // other follows me (simulated via the other athlete's own service)
      final otherSideSocial =
          SocialService.forTest(store: store, uid: other);
      await otherSideSocial.toggleFollow(me);

      expect(store.edges, {
        const FollowEdge(me, other),
        const FollowEdge(other, me),
      });
      // Each follow was an explicit, separate insert.
      expect(store.insertLog.length, 2);
    });

    test('cannot follow yourself', () async {
      final result = await social.toggleFollow(me);
      expect(result, isNull);
      expect(store.edges, isEmpty);
      expect(store.insertLog, isEmpty);
    });
  });

  group('getFollowerIdsAmong', () {
    test('returns only candidates who follow me, ignoring who I follow',
        () async {
      store.edges.addAll(const [
        FollowEdge('C', me), // C follows me
        FollowEdge('D', me), // D follows me
        FollowEdge(me, 'E'), // I follow E (must NOT count)
        FollowEdge('C', 'D'), // unrelated edge
      ]);

      final result =
          await social.getFollowerIdsAmong(['C', 'D', 'E', 'F']);

      expect(result, {'C', 'D'});
      expect(result.contains('E'), isFalse); // I follow E, E doesn't follow me
      expect(result.contains('F'), isFalse); // no edge at all
    });

    test('empty candidate list short-circuits to empty set', () async {
      store.edges.add(const FollowEdge('C', me));
      expect(await social.getFollowerIdsAmong([]), isEmpty);
    });
  });

  group('fetchFriendsFeed', () {
    late InMemoryFeedStore feed;
    late SocialService svc;

    setUp(() {
      feed = InMemoryFeedStore();
      svc = SocialService.forTest(
        store: InMemoryFollowStore(),
        uid: me,
        feedStore: feed,
      );
    });

    test('follows nobody → empty, never queries runs', () async {
      final result = await svc.fetchFriendsFeed();
      expect(result, isEmpty);
      expect(feed.runsForUsersCalls, 0);
    });

    test('only surfaces runs by athletes I follow', () async {
      feed.follows.add(const FollowEdge(me, other)); // I follow B
      final now = DateTime.utc(2026, 9, 1, 12);
      feed.runs.addAll([
        _runRow(other, now), // followed  → in
        _runRow('stranger', now.add(const Duration(hours: 1))), // not → out
      ]);
      feed.profiles[other] = {'display_name': 'Bee', 'city': 'Pune'};

      final result = await svc.fetchFriendsFeed();

      expect(result.map((r) => r.athleteId), [other]);
      expect(result.single.displayName, 'Bee');
      expect(result.single.location, 'Pune');
    });

    test('newest first', () async {
      feed.follows.add(const FollowEdge(me, other));
      final base = DateTime.utc(2026, 9, 1);
      feed.runs.addAll([
        _runRow(other, base, km: 1),
        _runRow(other, base.add(const Duration(days: 2)), km: 3),
        _runRow(other, base.add(const Duration(days: 1)), km: 2),
      ]);

      final result = await svc.fetchFriendsFeed();

      expect(result.map((r) => r.distanceKm), [3, 2, 1]);
    });

    test('batch-loads comment counts per run (0 when absent)', () async {
      feed.follows.add(const FollowEdge(me, other));
      final base = DateTime.utc(2026, 9, 1);
      final withComments = _runRow(other, base.add(const Duration(days: 1)));
      final noComments = _runRow(other, base);
      feed.runs.addAll([withComments, noComments]);
      feed.commentCounts[withComments['id'] as int] = 3;

      final result = await svc.fetchFriendsFeed();

      expect(result[0].runId, withComments['id']);
      expect(result[0].commentCount, 3);
      expect(result[1].commentCount, 0);
    });

    test('batch-loads reaction counts + the viewer\'s own reaction state',
        () async {
      feed.follows.add(const FollowEdge(me, other));
      final base = DateTime.utc(2026, 9, 1);
      final popular = _runRow(other, base.add(const Duration(days: 1)));
      final unreacted = _runRow(other, base);
      feed.runs.addAll([popular, unreacted]);
      feed.reactionCounts[popular['id'] as int] = 5;
      feed.reactedPairs.add('$me:${popular['id']}');

      final result = await svc.fetchFriendsFeed();

      expect(result[0].runId, popular['id']);
      expect(result[0].reactionCount, 5);
      expect(result[0].viewerReacted, isTrue);
      expect(result[1].reactionCount, 0);
      expect(result[1].viewerReacted, isFalse);
    });

    test('keyset pagination with `before` — no overlap, limit honoured',
        () async {
      feed.follows.add(const FollowEdge(me, other));
      final base = DateTime.utc(2026, 9, 1);
      for (var i = 0; i < 3; i++) {
        feed.runs.add(
          _runRow(other, base.add(Duration(days: i)), km: (i + 1).toDouble()),
        );
      }

      final page1 = await svc.fetchFriendsFeed(limit: 2);
      expect(page1.map((r) => r.distanceKm), [3, 2]); // days 2, 1

      final page2 = await svc.fetchFriendsFeed(
        before: page1.last.date,
        limit: 2,
      );
      expect(page2.map((r) => r.distanceKm), [1]); // day 0 only
    });
  });
}
