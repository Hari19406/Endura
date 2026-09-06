// lib/models/shoe.dart
//
// A pair in the shoe locker. Distances are stored in metres (matches the
// `shoes` table); the UI converts to km/mi via UnitUtils.

class Shoe {
  final String? id; // null before first insert
  final String userId;
  final String brand;
  final String model;
  final String? nickname;
  final double distanceMeters;
  final double maxDistanceMeters;
  final bool isDefault;
  final bool isRetired;

  const Shoe({
    this.id,
    required this.userId,
    required this.brand,
    required this.model,
    this.nickname,
    this.distanceMeters = 0,
    this.maxDistanceMeters = 800000, // ~800 km, common road-shoe ceiling
    this.isDefault = false,
    this.isRetired = false,
  });

  double get distanceKm => distanceMeters / 1000.0;
  double get maxDistanceKm => maxDistanceMeters / 1000.0;

  /// 0.0–1.0 fill for the mileage bar.
  double get wearFraction => maxDistanceMeters <= 0
      ? 0
      : (distanceMeters / maxDistanceMeters).clamp(0.0, 1.0);

  /// True once the pair has run past its target distance.
  bool get isPastTarget => distanceMeters >= maxDistanceMeters;

  String get label => (nickname != null && nickname!.trim().isNotEmpty)
      ? nickname!.trim()
      : '$brand $model';

  /// Accepts both a Supabase row (bools, `user_id`) and a local SQLite row
  /// (0/1 ints, no `user_id` column — caller passes [fallbackUserId]).
  factory Shoe.fromMap(Map<String, dynamic> m, {String? fallbackUserId}) => Shoe(
    id: m['id'] as String?,
    userId: (m['user_id'] as String?) ?? fallbackUserId ?? '',
    brand: m['brand'] as String,
    model: m['model'] as String,
    nickname: m['nickname'] as String?,
    distanceMeters: (m['distance_meters'] as num?)?.toDouble() ?? 0,
    maxDistanceMeters: (m['max_distance_meters'] as num?)?.toDouble() ?? 800000,
    isDefault: _bool(m['is_default']),
    isRetired: _bool(m['is_retired']),
  );

  static bool _bool(Object? v) => v == true || v == 1;

  /// Editable-column payload for Supabase. Omits `id` (DB-generated) and
  /// `user_id` (set by the service from the auth session).
  Map<String, dynamic> toMap() => {
    'brand': brand,
    'model': model,
    'nickname': nickname,
    'distance_meters': distanceMeters,
    'max_distance_meters': maxDistanceMeters,
    'is_default': isDefault,
    'is_retired': isRetired,
  };

  /// Full local SQLite row (bools as 0/1, includes id + sync bookkeeping).
  Map<String, dynamic> toLocalMap({
    required bool synced,
    bool pendingDelete = false,
    DateTime? updatedAt,
  }) => {
    'id': id,
    'brand': brand,
    'model': model,
    'nickname': nickname,
    'distance_meters': distanceMeters,
    'max_distance_meters': maxDistanceMeters,
    'is_default': isDefault ? 1 : 0,
    'is_retired': isRetired ? 1 : 0,
    'updated_at': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
    'synced_to_cloud': synced ? 1 : 0,
    'pending_delete': pendingDelete ? 1 : 0,
  };

  Shoe copyWith({
    String? id,
    String? brand,
    String? model,
    String? nickname,
    double? distanceMeters,
    double? maxDistanceMeters,
    bool? isDefault,
    bool? isRetired,
  }) => Shoe(
    id: id ?? this.id,
    userId: userId,
    brand: brand ?? this.brand,
    model: model ?? this.model,
    nickname: nickname ?? this.nickname,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    maxDistanceMeters: maxDistanceMeters ?? this.maxDistanceMeters,
    isDefault: isDefault ?? this.isDefault,
    isRetired: isRetired ?? this.isRetired,
  );
}
