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

/// Theme-aware variant: the dark MapTiler style in dark mode, the standard
/// streets style otherwise. Pass `Theme.of(context).brightness == dark`.
String mapTilerStreetsUrl({required bool isDark}) {
  final tileStyle = isDark ? 'streets-v2-dark' : 'streets-v2';
  return 'https://api.maptiler.com/maps/$tileStyle/{z}/{x}/{y}.png?key=$mapTilerKey';
}
