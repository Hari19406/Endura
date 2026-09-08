import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/race_listing.dart';

class RaceService {
  static final RaceService instance = RaceService._();
  RaceService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// A small, always-available list of well-known races. Shown immediately while
  /// the live `races` query loads, and kept as a fallback when that query is
  /// empty (no network / Supabase not configured / no rows for the region).
  /// Dates roll to next year once this year's edition is within ~3 weeks, so
  /// every entry is genuinely upcoming.
  List<RaceListing> get popularRaces {
    final now = DateTime.now();
    DateTime next(int month, int day) {
      var d = DateTime(now.year, month, day);
      if (d.isBefore(now.add(const Duration(days: 21)))) {
        d = DateTime(now.year + 1, month, day);
      }
      return d;
    }

    RaceListing r(
      String id,
      String name,
      DateTime date,
      String city,
      String country,
      String distance,
    ) => RaceListing(
      id: 'preset_$id',
      source: 'preset',
      name: name,
      raceDate: date,
      city: city,
      country: country,
      distanceLabel: distance,
    );

    return <RaceListing>[
      r('tokyo_m', 'Tokyo Marathon', next(3, 2), 'Tokyo', 'Japan', 'Marathon'),
      r('boston_m', 'Boston Marathon', next(4, 21), 'Boston', 'USA', 'Marathon'),
      r('london_m', 'London Marathon', next(4, 27), 'London', 'UK', 'Marathon'),
      r('peachtree_10k', 'Peachtree Road Race', next(7, 4), 'Atlanta', 'USA',
          '10K'),
      r('greatnorth_hm', 'Great North Run', next(9, 7), 'Newcastle', 'UK',
          'Half Marathon'),
      r('berlin_m', 'Berlin Marathon', next(9, 21), 'Berlin', 'Germany',
          'Marathon'),
      r('longbeach_hm', 'Long Beach Half Marathon', next(10, 12), 'Long Beach',
          'USA', 'Half Marathon'),
      r('melbourne_hm', 'Melbourne Half Marathon', next(10, 12), 'Melbourne',
          'Australia', 'Half Marathon'),
      r('chicago_m', 'Chicago Marathon', next(10, 12), 'Chicago', 'USA',
          'Marathon'),
      r('delhi_hm', 'Vedanta Delhi Half Marathon', next(10, 19), 'New Delhi',
          'India', 'Half Marathon'),
      r('nyc_m', 'New York City Marathon', next(11, 2), 'New York', 'USA',
          'Marathon'),
      r('philly_hm', 'Philadelphia Half Marathon', next(11, 22), 'Philadelphia',
          'USA', 'Half Marathon'),
      r('turkeytrot_5k', 'Turkey Trot 5K', next(11, 27), 'Nationwide', 'USA',
          '5K'),
      r('mumbai_m', 'Tata Mumbai Marathon', next(1, 19), 'Mumbai', 'India',
          'Marathon'),
      r('bengaluru_10k', 'TCS World 10K Bengaluru', next(5, 25), 'Bengaluru',
          'India', '10K'),
    ]..sort((a, b) => a.raceDate.compareTo(b.raceDate));
  }

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
      // Explicit ascending — soonest race first. Without this the picker
      // showed the farthest-out races (2028/2029) at the top instead of
      // genuinely upcoming ones.
      final rows = await query.order('race_date', ascending: true).limit(limit);
      return (rows as List)
          .map((r) => RaceListing.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[RaceService] upcomingRaces error: $e');
      return [];
    }
  }
}
