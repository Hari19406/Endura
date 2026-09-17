/// LocationService — resolves the device's current coordinates into a short
/// "City, Region" label for display only (the pre-run weather card). Never
/// required by any core flow: every failure mode (no permission, location
/// services off, no network, geocoder returns nothing, timeout) resolves to
/// null so the caller falls back to a generic placeholder instead of
/// blocking or crashing.
library;

import 'package:geocoding/geocoding.dart' as geocoding;

import 'weather_service.dart';

class LocationService {
  const LocationService._();

  static Future<String?> getCurrentLocationLabel({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final position = await WeatherService.getLocation();
      if (position == null) return null;

      final placemarks = await geocoding
          .placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(timeout);
      if (placemarks.isEmpty) return null;

      final place = placemarks.first;
      final city = place.locality?.trim();
      final region = (place.administrativeArea ?? place.subAdministrativeArea)
          ?.trim();

      if (city != null && city.isNotEmpty && region != null && region.isNotEmpty) {
        return '$city, $region';
      }
      if (city != null && city.isNotEmpty) return city;
      if (region != null && region.isNotEmpty) return region;
      return null;
    } catch (_) {
      return null;
    }
  }
}
