/// AthleteProfile — public social identity mapping + display helpers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/athlete_profile.dart';

void main() {
  group('AthleteProfile.name', () {
    test('prefers display name', () {
      const p = AthleteProfile(
        id: 'u1',
        displayName: 'Mo Farah',
        username: 'mo',
      );
      expect(p.name, 'Mo Farah');
    });

    test('falls back to @username, then Runner', () {
      const withUser = AthleteProfile(id: 'u1', username: 'mo');
      expect(withUser.name, '@mo');
      const bare = AthleteProfile(id: 'u1');
      expect(bare.name, 'Runner');
      const blankDisplay = AthleteProfile(id: 'u1', displayName: '   ');
      expect(blankDisplay.name, 'Runner');
    });
  });

  group('AthleteProfile.location', () {
    test('joins city and country, skips blanks', () {
      expect(
        const AthleteProfile(id: 'u1', city: 'Pune', country: 'India').location,
        'Pune, India',
      );
      expect(
        const AthleteProfile(id: 'u1', city: 'Pune').location,
        'Pune',
      );
      expect(const AthleteProfile(id: 'u1', city: '  ').location, isNull);
      expect(const AthleteProfile(id: 'u1').location, isNull);
    });
  });

  group('serialization', () {
    test('fromMap reads snake_case, defaults is_public to true', () {
      final p = AthleteProfile.fromMap({
        'id': 'u1',
        'username': 'mo',
        'display_name': 'Mo',
        'avatar_url': null,
        'bio': 'runs a lot',
        'city': 'Pune',
        'country': 'India',
      });
      expect(p.username, 'mo');
      expect(p.bio, 'runs a lot');
      expect(p.isPublic, isTrue);
    });

    test('toUpdateMap emits only social columns + updated_at', () {
      const p = AthleteProfile(
        id: 'u1',
        username: 'mo',
        displayName: 'Mo',
        isPublic: false,
      );
      final m = p.toUpdateMap();
      expect(m.keys, containsAll(<String>['username', 'display_name', 'bio', 'city', 'country', 'is_public', 'updated_at']));
      expect(m.containsKey('id'), isFalse);
      expect(m.containsKey('vdot_score'), isFalse);
      expect(m['is_public'], isFalse);
    });

    test('copyWith preserves id and overrides fields', () {
      const p = AthleteProfile(id: 'u1', username: 'old');
      final q = p.copyWith(username: 'new', isPublic: false);
      expect(q.id, 'u1');
      expect(q.username, 'new');
      expect(q.isPublic, isFalse);
    });
  });

  test('SocialCounts.zero', () {
    expect(SocialCounts.zero.followers, 0);
    expect(SocialCounts.zero.following, 0);
  });
}
