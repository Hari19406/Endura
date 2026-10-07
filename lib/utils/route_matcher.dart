// lib/utils/route_matcher.dart
//
// Pure-Dart "have I run this route before?" matcher for Matched Runs V1.
//
// Two stages, nothing stored — everything is computed on demand:
//   1. Cheap candidate filter: distance within ±10% and a parseable polyline
//      that is long enough and whose bounding box overlaps the current run's.
//   2. Shape check: both routes are resampled to [sampleCount] points by
//      cumulative distance and compared with a symmetric nearest-point
//      distance (mean ≤ 35 m and ≥ 90% of points within 75 m). Starting point
//      is irrelevant, so a loop joined at a different spot still matches.
//      Direction is then checked and reversed routes are rejected.
//
// Deliberately not handled in V1: partial routes, reversed-route matching,
// segments, map matching, DTW / Fréchet.
library;

import 'dart:math' as math;

/// A stored run that may share the current run's route.
class RouteCandidate {
  final int id;
  final double distanceKm;

  /// The app's `"lat,lng;lat,lng"` polyline string; parsed only if the cheap
  /// filter passes.
  final String polyline;

  const RouteCandidate({
    required this.id,
    required this.distanceKm,
    required this.polyline,
  });
}

class RouteMatch {
  final int id;

  /// Mean symmetric nearest-point distance in metres (lower = tighter match).
  final double meanDistanceM;

  const RouteMatch({required this.id, required this.meanDistanceM});
}

class RouteMatcher {
  RouteMatcher._();

  static const int sampleCount = 50;
  static const double maxDistanceDiffFraction = 0.10;
  static const double maxMeanDistanceM = 35;
  static const double nearDistanceM = 75;
  static const double minNearFraction = 0.90;
  static const int minPoints = 10;
  static const double minRouteLengthM = 200;

  /// A route whose ends are closer than this fraction of its length is treated
  /// as a loop (start point may be rotated when checking direction).
  static const double _loopGapFraction = 0.15;

  /// A reversed traversal must beat the forward one by this factor to reject.
  static const double _reversedRatio = 0.7;

  /// Candidates (in input order) that share [current]'s route.
  static List<RouteMatch> findMatches({
    required List<Map<String, double>> current,
    required double currentDistanceKm,
    required List<RouteCandidate> candidates,
  }) {
    if (currentDistanceKm <= 0 || !_usable(current)) return const [];
    final origin = _Projection(current.first['lat']!);
    final cur = _project(current, origin);
    final curLen = _length(cur);
    if (curLen < minRouteLengthM) return const [];
    final curBox = _Box.of(cur);
    final curSample = _resample(cur, sampleCount);

    final out = <RouteMatch>[];
    for (final cand in candidates) {
      // ── Stage 1: cheap filters, before any parsing ──
      if (cand.polyline.isEmpty || cand.distanceKm <= 0) continue;
      final diff = (cand.distanceKm - currentDistanceKm).abs();
      if (diff / currentDistanceKm > maxDistanceDiffFraction) continue;

      final points = parsePolyline(cand.polyline);
      if (!_usable(points)) continue;
      final other = _project(points, origin);
      if (_length(other) < minRouteLengthM) continue;
      if (!curBox.overlaps(_Box.of(other), nearDistanceM)) continue;

      // ── Stage 2: shape ──
      final otherSample = _resample(other, sampleCount);
      final a2b = _nearestDistances(curSample, other);
      final b2a = _nearestDistances(otherSample, cur);
      final all = [...a2b, ...b2a];
      final mean = all.reduce((a, b) => a + b) / all.length;
      if (mean > maxMeanDistanceM) continue;
      final near = all.where((d) => d <= nearDistanceM).length / all.length;
      if (near < minNearFraction) continue;

      if (_isReversed(curSample, otherSample)) continue;
      out.add(RouteMatch(id: cand.id, meanDistanceM: mean));
    }
    return out;
  }

  /// Parses `"lat,lng;lat,lng"`. Malformed input yields an empty list.
  static List<Map<String, double>> parsePolyline(String polyline) {
    if (polyline.isEmpty) return const [];
    try {
      return [
        for (final pair in polyline.split(';'))
          if (pair.isNotEmpty)
            {
              'lat': double.parse(pair.split(',')[0]),
              'lng': double.parse(pair.split(',')[1]),
            },
      ];
    } catch (_) {
      return const [];
    }
  }

  static bool _usable(List<Map<String, double>> pts) {
    if (pts.length < minPoints) return false;
    for (final p in pts) {
      final lat = p['lat'];
      final lng = p['lng'];
      if (lat == null || lng == null) return false;
      if (!lat.isFinite || !lng.isFinite) return false;
    }
    return true;
  }

  // ── Geometry (local equirectangular projection, metres) ─────────────────

  static List<_P> _project(List<Map<String, double>> pts, _Projection o) => [
    for (final p in pts) o.toXY(p['lat']!, p['lng']!),
  ];

  static double _length(List<_P> pts) {
    var len = 0.0;
    for (var i = 1; i < pts.length; i++) {
      len += pts[i].dist(pts[i - 1]);
    }
    return len;
  }

  /// [n] points evenly spaced by cumulative distance (first and last included).
  static List<_P> _resample(List<_P> pts, int n) {
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + pts[i].dist(pts[i - 1]));
    }
    final total = cum.last;
    final out = <_P>[];
    var seg = 1;
    for (var k = 0; k < n; k++) {
      final target = total * k / (n - 1);
      while (seg < pts.length - 1 && cum[seg] < target) {
        seg++;
      }
      final span = cum[seg] - cum[seg - 1];
      final t = span <= 0 ? 0.0 : ((target - cum[seg - 1]) / span).clamp(0, 1);
      final a = pts[seg - 1];
      final b = pts[seg];
      out.add(_P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
    }
    return out;
  }

  /// Distance from each of [samples] to the nearest point on [path].
  static List<double> _nearestDistances(List<_P> samples, List<_P> path) => [
    for (final s in samples)
      () {
        var best = double.infinity;
        for (var i = 1; i < path.length; i++) {
          final d = _pointToSegment(s, path[i - 1], path[i]);
          if (d < best) best = d;
        }
        return best;
      }(),
  ];

  static double _pointToSegment(_P p, _P a, _P b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return p.dist(a);
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
    return p.dist(_P(a.x + dx * t, a.y + dy * t));
  }

  // ── Direction ───────────────────────────────────────────────────────────

  /// True when [b] traces the same shape as [a] but in the opposite direction.
  /// Loops may start anywhere, so for them every rotation is tried; other
  /// routes are compared start-to-start.
  static bool _isReversed(List<_P> a, List<_P> b) {
    final n = a.length;
    final rotatable = _isLoop(a) && _isLoop(b);

    double cost(int s, bool reverse) {
      var sum = 0.0;
      for (var i = 0; i < n; i++) {
        final int j;
        if (rotatable) {
          j = reverse ? ((s - i) % n + n) % n : (i + s) % n;
        } else {
          j = reverse ? n - 1 - i : i;
        }
        sum += a[i].dist(b[j]);
      }
      return sum / n;
    }

    var fwd = double.infinity;
    var rev = double.infinity;
    for (var s = 0; s < (rotatable ? n : 1); s++) {
      fwd = math.min(fwd, cost(s, false));
      rev = math.min(rev, cost(s, true));
    }
    return rev < fwd * _reversedRatio;
  }

  static bool _isLoop(List<_P> sample) {
    final gap = sample.first.dist(sample.last);
    return gap <= _loopGapFraction * _length(sample);
  }
}

class _P {
  final double x;
  final double y;
  const _P(this.x, this.y);
  double dist(_P o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
}

class _Projection {
  static const double _mPerDegLat = 111320.0;
  final double _mPerDegLng;
  _Projection(double refLat)
    : _mPerDegLng = _mPerDegLat * math.cos(refLat * math.pi / 180);
  _P toXY(double lat, double lng) => _P(lng * _mPerDegLng, lat * _mPerDegLat);
}

class _Box {
  final double minX, maxX, minY, maxY;
  const _Box(this.minX, this.maxX, this.minY, this.maxY);

  factory _Box.of(List<_P> pts) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    return _Box(minX, maxX, minY, maxY);
  }

  bool overlaps(_Box o, double margin) =>
      minX <= o.maxX + margin &&
      maxX >= o.minX - margin &&
      minY <= o.maxY + margin &&
      maxY >= o.minY - margin;
}
