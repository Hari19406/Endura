class RaceListing {
  final String id;
  final String source;
  final String name;
  final DateTime raceDate;
  final DateTime? raceEndDate;
  final String? locationRaw;
  final String? city;
  final String? country;
  final String? distanceLabel;
  final String? registrationUrl;
  final String? organizer;

  const RaceListing({
    required this.id,
    required this.source,
    required this.name,
    required this.raceDate,
    this.raceEndDate,
    this.locationRaw,
    this.city,
    this.country,
    this.distanceLabel,
    this.registrationUrl,
    this.organizer,
  });

  factory RaceListing.fromJson(Map<String, dynamic> j) => RaceListing(
    id: j['id'] as String,
    source: j['source'] as String? ?? 'aims',
    name: j['name'] as String,
    raceDate: DateTime.parse(j['race_date'] as String),
    raceEndDate: j['race_end_date'] != null
        ? DateTime.parse(j['race_end_date'] as String)
        : null,
    locationRaw: j['location_raw'] as String?,
    city: j['city'] as String?,
    country: j['country'] as String?,
    distanceLabel: j['distance_label'] as String?,
    registrationUrl: j['registration_url'] as String?,
    organizer: j['organizer'] as String?,
  );
}
