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
}
