import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/route_matcher.dart';

const _lat0 = 12.97;
const _lng0 = 77.59;
final _mPerLng = 111320.0 * math.cos(_lat0 * math.pi / 180);

typedef _XY = ({double x, double y});

String _poly(List<_XY> pts) => pts
    .map((p) => '${_lat0 + p.y / 111320.0},${_lng0 + p.x / _mPerLng}')
    .join(';');

double _len(List<_XY> pts) {
  var l = 0.0;
  for (var i = 1; i < pts.length; i++) {
    l += math.sqrt(
      math.pow(pts[i].x - pts[i - 1].x, 2) +
          math.pow(pts[i].y - pts[i - 1].y, 2),
    );
  }
  return l;
}

/// Asymmetric closed loop (~3.3 km), first point == last point.
List<_XY> _loop({double scale = 1}) => [
  for (var i = 0; i <= 800; i++)
    () {
      final t = 2 * math.pi * i / 800;
      return (
        x: scale * (600 * math.cos(t) + 120 * math.cos(3 * t)),
        y: scale * (400 * math.sin(t) + 150 * math.sin(2 * t)),
      );
    }(),
];

/// The same loop joined at a different point (start rotated by [k] points).
List<_XY> _rotated(List<_XY> loop, int k) {
  final body = loop.sublist(0, loop.length - 1);
  final r = [...body.sublist(k), ...body.sublist(0, k)];
  return [...r, r.first];
}

/// Deterministic jitter of up to ±[m] metres on each axis.
List<_XY> _noisy(List<_XY> pts, double m) {
  var seed = 12345;
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return (seed / 0x7fffffff) * 2 - 1;
  }

  return [for (final p in pts) (x: p.x + next() * m, y: p.y + next() * m)];
}

/// Straight 1.5 km out and back along the x axis.
List<_XY> _outAndBack() => [
  for (var i = 0; i <= 300; i++) (x: i * 5.0, y: 0.0),
  for (var i = 299; i >= 0; i--) (x: i * 5.0, y: 0.0),
];

/// Rectangle (2:1) whose perimeter is [target] metres.
List<_XY> _rectangle(double target) {
  final w = target / 6 * 2;
  final h = target / 6;
  final pts = <_XY>[];
  for (var x = 0.0; x < w; x += 5) {
    pts.add((x: x, y: 0));
  }
  for (var y = 0.0; y < h; y += 5) {
    pts.add((x: w, y: y));
  }
  for (var x = w; x > 0; x -= 5) {
    pts.add((x: x, y: h));
  }
  for (var y = h; y >= 0; y -= 5) {
    pts.add((x: 0, y: y));
  }
  return pts;
}

List<Map<String, double>> _asPoints(List<_XY> pts) =>
    RouteMatcher.parsePolyline(_poly(pts));

List<RouteMatch> _match(
  List<_XY> current,
  List<RouteCandidate> candidates, {
  double? distanceKm,
}) => RouteMatcher.findMatches(
  current: _asPoints(current),
  currentDistanceKm: distanceKm ?? _len(current) / 1000,
  candidates: candidates,
);

RouteCandidate _cand(int id, List<_XY> pts, {double? distanceKm}) =>
    RouteCandidate(
      id: id,
      distanceKm: distanceKm ?? _len(pts) / 1000,
      polyline: _poly(pts),
    );

void main() {
  final loop = _loop();

  test('identical route matches', () {
    expect(_match(loop, [_cand(1, loop)]).map((m) => m.id), [1]);
  });

  test('+-10 m GPS noise still matches', () {
    final today = _noisy(loop, 10);
    final earlier = _noisy(_loop(), 10);
    expect(_match(today, [_cand(7, earlier)]).map((m) => m.id), [7]);
  });

  test('different route is rejected', () {
    final other = _rectangle(_len(loop));
    expect(_match(loop, [_cand(1, other)]), isEmpty);
  });

  test('same loop joined at a different starting point matches', () {
    for (final k in [100, 313, 555]) {
      expect(
        _match(loop, [_cand(2, _rotated(loop, k))]).map((m) => m.id),
        [2],
        reason: 'rotation $k',
      );
    }
  });

  test('a different route with a similar distance is rejected', () {
    final sameLength = _rectangle(_len(loop));
    expect((_len(sameLength) - _len(loop)).abs() / _len(loop), lessThan(0.05));
    expect(_match(loop, [_cand(3, sameLength)]), isEmpty);
  });

  test('distance more than 10% different is rejected, 9% is allowed', () {
    final d = _len(loop) / 1000;
    expect(_match(loop, [_cand(1, loop, distanceKm: d * 1.11)]), isEmpty);
    expect(_match(loop, [_cand(1, loop, distanceKm: d * 0.89)]), isEmpty);
    expect(_match(loop, [_cand(1, loop, distanceKm: d * 1.09)]), isNotEmpty);
  });

  test('empty, malformed and too-short polylines are rejected', () {
    final d = _len(loop) / 1000;
    for (final bad in [
      '',
      'garbage',
      'a,b;c,d',
      '12.97,77.59',
      _poly(loop.take(5).toList()),
    ]) {
      expect(
        _match(loop, [RouteCandidate(id: 1, distanceKm: d, polyline: bad)]),
        isEmpty,
        reason: 'candidate "$bad"',
      );
    }
    expect(
      RouteMatcher.findMatches(
        current: const [],
        currentDistanceKm: d,
        candidates: [_cand(1, loop)],
      ),
      isEmpty,
    );
    expect(
      RouteMatcher.findMatches(
        current: _asPoints(loop.take(5).toList()),
        currentDistanceKm: d,
        candidates: [_cand(1, loop)],
      ),
      isEmpty,
    );
  });

  test('the same loop run in the opposite direction is rejected', () {
    final reversed = loop.reversed.toList();
    expect(_match(loop, [_cand(1, reversed)]), isEmpty);
    // ...including when it also starts somewhere else on the loop.
    expect(_match(loop, [_cand(1, _rotated(reversed, 250))]), isEmpty);
  });

  test('an out-and-back is not matched to an unrelated loop', () {
    final oab = _outAndBack();
    final unrelated = _loop(scale: _len(oab) / _len(loop));
    expect(_match(oab, [_cand(1, unrelated)]), isEmpty);
    expect(_match(unrelated, [_cand(1, oab)]), isEmpty);
  });

  test('an out-and-back still matches itself', () {
    final oab = _outAndBack();
    expect(_match(oab, [_cand(1, _noisy(oab, 8))]).map((m) => m.id), [1]);
  });

  test('only the matching candidates are returned, in input order', () {
    final res = _match(loop, [
      _cand(1, _rectangle(_len(loop))),
      _cand(2, _rotated(loop, 40)),
      _cand(3, loop.reversed.toList()),
      _cand(4, loop),
    ]);
    expect(res.map((m) => m.id), [2, 4]);
  });
}
