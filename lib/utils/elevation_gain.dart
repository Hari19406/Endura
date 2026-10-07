// lib/utils/elevation_gain.dart
//
// Total ascent for a run, from its captured track samples.
//
// Raw GPS altitude is noisy, and summing positive fix-to-fix deltas while
// discarding the negative ones turns that noise into phantom climbing. Here
// the samples go through the same cleaning the elevation chart and GAP use
// (ElevationProfile: drop null/0.0, reject spikes, resample onto the 20 m
// distance grid, smooth), and only the positive steps of that cleaned profile
// are summed. No external elevation source is involved.
library;

import 'gap_calculator.dart' show ElevationProfile, GapSample;

class ElevationGain {
  ElevationGain._();

  /// Total ascent in metres (rounded to 0.1 m) from `{d, alt, ...}` track
  /// samples, or null when fewer than two usable altitude readings remain -
  /// "unknown", never 0.
  static double? fromTrackSamples(List<Map<String, dynamic>> samples) {
    final ascent = ElevationProfile.totalAscent([
      for (final m in samples)
        if ((m['d'] as num?) != null)
          GapSample(
            distanceM: (m['d'] as num).toDouble(),
            altitudeM: (m['alt'] as num?)?.toDouble(),
          ),
    ]);
    if (ascent == null) return null;
    return double.parse(ascent.toStringAsFixed(1));
  }
}
