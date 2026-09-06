/// Shoe — shoe-locker model: mileage math + label + serialization.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/shoe.dart';

void main() {
  Shoe make({
    double distanceMeters = 0,
    double maxDistanceMeters = 800000,
    String? nickname,
    bool isRetired = false,
  }) => Shoe(
    userId: 'u1',
    brand: 'Nike',
    model: 'Pegasus 41',
    nickname: nickname,
    distanceMeters: distanceMeters,
    maxDistanceMeters: maxDistanceMeters,
    isRetired: isRetired,
  );

  group('mileage', () {
    test('distanceKm / maxDistanceKm convert from metres', () {
      final s = make(distanceMeters: 250000, maxDistanceMeters: 600000);
      expect(s.distanceKm, 250);
      expect(s.maxDistanceKm, 600);
    });

    test('wearFraction is clamped to 0..1', () {
      expect(make(distanceMeters: 0).wearFraction, 0);
      expect(make(distanceMeters: 400000).wearFraction, closeTo(0.5, 1e-9));
      expect(make(distanceMeters: 999999999).wearFraction, 1.0);
    });

    test('wearFraction is 0 when max is non-positive', () {
      expect(make(distanceMeters: 100, maxDistanceMeters: 0).wearFraction, 0);
    });

    test('isPastTarget flips at the target distance', () {
      expect(make(distanceMeters: 799999).isPastTarget, isFalse);
      expect(make(distanceMeters: 800000).isPastTarget, isTrue);
    });
  });

  group('label', () {
    test('uses nickname when present, else brand + model', () {
      expect(make(nickname: 'Daily trainer').label, 'Daily trainer');
      expect(make(nickname: '  ').label, 'Nike Pegasus 41');
      expect(make().label, 'Nike Pegasus 41');
    });
  });

  group('serialization', () {
    test('fromMap round-trips through toMap (minus id/user_id)', () {
      final original = make(distanceMeters: 123000, nickname: 'x');
      final restored = Shoe.fromMap({
        'id': 'shoe1',
        'user_id': 'u1',
        ...original.toMap(),
      });
      expect(restored.id, 'shoe1');
      expect(restored.brand, 'Nike');
      expect(restored.distanceMeters, 123000);
      expect(restored.nickname, 'x');
    });

    test('toMap omits id and user_id (service supplies them)', () {
      final m = make().toMap();
      expect(m.containsKey('id'), isFalse);
      expect(m.containsKey('user_id'), isFalse);
      expect(m['brand'], 'Nike');
    });

    test('fromMap tolerates missing optional columns', () {
      final s = Shoe.fromMap({
        'user_id': 'u1',
        'brand': 'Asics',
        'model': 'Nimbus',
      });
      expect(s.distanceMeters, 0);
      expect(s.maxDistanceMeters, 800000);
      expect(s.isDefault, isFalse);
      expect(s.isRetired, isFalse);
    });
  });
}
