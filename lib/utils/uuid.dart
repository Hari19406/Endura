// lib/utils/uuid.dart
//
// Tiny RFC-4122 v4 generator so offline-created rows (e.g. shoes) can carry a
// stable id that matches the Supabase `uuid` PK format without pulling in the
// `uuid` package.

import 'dart:math';

final Random _rng = Random.secure();

String uuidV4() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10
  String hex(int start, int end) => b
      .sublist(start, end)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
