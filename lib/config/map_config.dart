/// Single source for the MapTiler tile endpoint.
///
/// The key is injected at build time via
/// `--dart-define-from-file=dart_defines.env` (same mechanism as the Supabase /
/// PostHog / RevenueCat keys). Never hardcode the key in a widget — and restrict
/// it by app bundle id in the MapTiler dashboard, since client keys are visible
/// in network traffic.
library;

const String mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

/// Streets raster tile template for `flutter_map`'s `TileLayer.urlTemplate`.
const String mapTilerStreetsUrlTemplate =
    'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=$mapTilerKey';
