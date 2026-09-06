/// uuidV4 — offline id generator for locally-created rows.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/uuid.dart';

void main() {
  final re = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('matches the RFC-4122 v4 shape', () {
    for (var i = 0; i < 200; i++) {
      expect(re.hasMatch(uuidV4()), isTrue, reason: 'bad uuid: ${uuidV4()}');
    }
  });

  test('is practically unique', () {
    final seen = <String>{};
    for (var i = 0; i < 5000; i++) {
      expect(seen.add(uuidV4()), isTrue);
    }
  });
}
