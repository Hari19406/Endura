/// AthleteProfile — public social identity mapping + display helpers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/athlete_profile.dart';

void main() {
  group('AthleteProfile.name', () {
    test('uses display name when set', () {
      const p = AthleteProfile(id: 'u1', displayName: 'Mo Farah');
      expect(p.name, 'Mo Farah');
    });

    test('falls back to "Runner" when display name is missing or blank', () {
      expect(const AthleteProfile(id: 'u1').name, 'Runner');
      expect(const AthleteProfile(id: 'u1', displayName: '   ').name, 'Runner');
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
        'display_name': 'Mo',
        'avatar_url': null,
        'bio': 'runs a lot',
        'city': 'Pune',
        'country': 'India',
      });
      expect(p.displayName, 'Mo');
      expect(p.bio, 'runs a lot');
      expect(p.isPublic, isTrue);
    });

    test('has no username concept', () {
      const p = AthleteProfile(id: 'u1', displayName: 'Mo');
      expect(p.toUpdateMap().containsKey('username'), isFalse);
    });

    test('toUpdateMap emits only social columns + updated_at', () {
      const p = AthleteProfile(id: 'u1', displayName: 'Mo', isPublic: false);
      final m = p.toUpdateMap();
      expect(
        m.keys,
        containsAll(<String>[
          'display_name',
          'avatar_url',
          'bio',
          'city',
          'country',
          'is_public',
          'updated_at',
        ]),
      );
      expect(m.containsKey('id'), isFalse);
      expect(m.containsKey('vdot_score'), isFalse);
      expect(m['is_public'], isFalse);
    });

    test('copyWith preserves id + aggregates, overrides social fields', () {
      final p = AthleteProfile.fromMap({
        'id': 'u1',
        'display_name': 'Old',
        'total_runs': 12,
        'total_distance_meters': 90000,
      });
      final q = p.copyWith(displayName: 'New', isPublic: false);
      expect(q.id, 'u1');
      expect(q.displayName, 'New');
      expect(q.isPublic, isFalse);
      expect(q.totalRuns, 12);
      expect(q.totalDistanceMeters, 90000);
    });
  });

  test('SocialCounts.zero', () {
    expect(SocialCounts.zero.followers, 0);
    expect(SocialCounts.zero.following, 0);
  });
}
