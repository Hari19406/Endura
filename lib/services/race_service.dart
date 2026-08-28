import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/race_listing.dart';

class RaceService {
  static final RaceService instance = RaceService._();
  RaceService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Upcoming races, optionally filtered by city and/or country
  /// (case-insensitive substring match on each). Table is public-read (see
  /// supabase/migrations) so this works whether or not a user is signed in.
  Future<List<RaceListing>> upcomingRaces({
    String? city,
    String? country,
    int limit = 20,
  }) async {
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      var query = _client.from('races').select().gte('race_date', today);
      if (city != null && city.trim().isNotEmpty) {
        query = query.ilike('city', '%${city.trim()}%');
      }
      if (country != null && country.trim().isNotEmpty) {
        query = query.ilike('country', '%${country.trim()}%');
      }
      final rows = await query.order('race_date').limit(limit);
      return (rows as List)
          .map((r) => RaceListing.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[RaceService] upcomingRaces error: $e');
      return [];
    }
  }
}
