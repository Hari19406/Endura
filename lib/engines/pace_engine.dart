import 'dart:collection';
import 'dart:math';

class GpsPoint {
  final double lat;
  final double lng;
  final double accuracy;
  final double speed; // m/s from GPS chipset (Doppler-derived)
  final DateTime timestamp;

  const GpsPoint({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.speed,
    required this.timestamp,
  });
}

class PaceSnapshot {
  final double currentPaceSecondsPerKm;
  final double smoothedPaceSecondsPerKm;
  final double averagePaceSecondsPerKm;
  final bool isStale;
  final bool isGpsSpeed; // true = using chipset speed, not yet rolling window
  final DateTime timestamp;

  const PaceSnapshot({
    required this.currentPaceSecondsPerKm,
    required this.smoothedPaceSecondsPerKm,
    required this.averagePaceSecondsPerKm,
    required this.isStale,
    required this.isGpsSpeed,
    required this.timestamp,
  });

  String get formattedCurrent => _format(currentPaceSecondsPerKm);
  String get formattedSmoothed => _format(smoothedPaceSecondsPerKm);
  String get formattedAverage => _format(averagePaceSecondsPerKm);

  static String _format(double paceSecondsPerKm) {
    if (paceSecondsPerKm <= 0 ||
        paceSecondsPerKm.isInfinite ||
        paceSecondsPerKm.isNaN) return '--:--';
    if (paceSecondsPerKm > 5999) return '99:59';
    int minutes = paceSecondsPerKm ~/ 60;
    int seconds = (paceSecondsPerKm % 60).round();
    if (seconds == 60) {
      minutes++;
      seconds = 0;
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class PaceEngine {
  static const int _ringBufferCapacity = 30;
  static const double _rollingWindowSeconds = 8.0;
  static const double _rollingWindowMeters = 40.0;
  static const int _smoothingBufferSize = 5;
  static const double _maxSpeedMs = 12.0;
  static const double _maxAccuracyMeters = 60.0;
  static const double _minMovementMeters = 1.0;
  static const double _stoppedSpeedThreshold = 0.3;
  static const double _stalePaceTimeoutSeconds = 15.0;
  static const double _maxPaceSecondsPerKm = 1800.0;
  static const double _minPaceSecondsPerKm = 90.0;

  // GPS speed bootstrapping: instant pace before rolling window kicks in
  static const double _minGpsSpeedMs = 0.5; // below this, user isn't running
  static const int _gpsSpeedSmoothingSize = 3;

  final _ringBuffer = Queue<GpsPoint>();
  final List<double> _paceSmoothing = [];
  final List<double> _gpsSpeedBuffer = [];
  double _lastValidPace = 0.0;
  double _smoothedPace = 0.0;
  double _totalDistance = 0.0;
  int _totalSeconds = 0;
  GpsPoint? _lastAcceptedPoint;
  DateTime? _lastGpsTimestamp;
  bool _isStale = false;
  bool _rollingWindowActive = false; // true once we have enough buffer data

  double get lastValidPace => _lastValidPace;
  double get smoothedPace => _smoothedPace;

  void reset() {
    _ringBuffer.clear();
    _paceSmoothing.clear();
    _gpsSpeedBuffer.clear();
    _lastValidPace = 0.0;
    _smoothedPace = 0.0;
    _totalDistance = 0.0;
    _totalSeconds = 0;
    _lastAcceptedPoint = null;
    _lastGpsTimestamp = null;
    _isStale = false;
    _rollingWindowActive = false;
  }

  PaceSnapshot addPoint(GpsPoint point, double currentTotalDistance, int currentTotalSeconds) {
    _totalDistance = currentTotalDistance;
    _totalSeconds = currentTotalSeconds;
    _lastGpsTimestamp = point.timestamp;

    if (point.accuracy > _maxAccuracyMeters) {
      return _buildSnapshot();
    }

    // ── Phase 1: GPS speed bootstrapping ─────────────────────────────────
    // Use chipset-reported speed for instant pace from the very first fix.
    // This runs in PARALLEL with the ring buffer — it doesn't gate it.
    if (point.speed >= 0 && point.speed < _maxSpeedMs) {
      _updateGpsSpeedPace(point.speed);
    }

    // ── Impossible speed check ───────────────────────────────────────────
    if (_lastAcceptedPoint != null) {
      final dt = point.timestamp.difference(_lastAcceptedPoint!.timestamp).inMilliseconds / 1000.0;
      if (dt > 0) {
        final dist = _haversineMeters(
          _lastAcceptedPoint!.lat, _lastAcceptedPoint!.lng,
          point.lat, point.lng,
        );
        if (dist / dt > _maxSpeedMs) {
          return _buildSnapshot();
        }
        if (dist < _minMovementMeters) {
          _checkStale(point.timestamp);
          return _buildSnapshot();
        }
      }
    }

    // ── Accept into ring buffer ──────────────────────────────────────────
    _ringBuffer.addLast(point);
    if (_ringBuffer.length > _ringBufferCapacity) {
      _ringBuffer.removeFirst();
    }
    _lastAcceptedPoint = point;
    _isStale = false;

    // ── Phase 2: Rolling window pace ─────────────────────────────────────
    _computeRollingPace();

    return _buildSnapshot();
  }

  PaceSnapshot tick(int currentTotalSeconds) {
    _totalSeconds = currentTotalSeconds;
    if (_lastGpsTimestamp != null) {
      _checkStale(DateTime.now());
    }
    return _buildSnapshot();
  }

  // ── GPS speed → instant pace (Phase 1) ─────────────────────────────────

  void _updateGpsSpeedPace(double speedMs) {
    if (speedMs < _minGpsSpeedMs) return; // not running yet

    // Convert m/s to seconds/km
    double paceFromSpeed = 1000.0 / speedMs;
    paceFromSpeed = paceFromSpeed.clamp(_minPaceSecondsPerKm, _maxPaceSecondsPerKm);

    _gpsSpeedBuffer.add(paceFromSpeed);
    if (_gpsSpeedBuffer.length > _gpsSpeedSmoothingSize) {
      _gpsSpeedBuffer.removeAt(0);
    }

    // Median of last 3 readings — smooths out chipset noise
    final sorted = List<double>.from(_gpsSpeedBuffer)..sort();
    final median = sorted[sorted.length ~/ 2];

    // Only use GPS speed if rolling window hasn't taken over yet
    if (!_rollingWindowActive) {
      if (_smoothedPace <= 0) {
        _smoothedPace = median;
      } else {
        const alpha = 0.4; // slightly more responsive for bootstrap phase
        _smoothedPace = alpha * median + (1 - alpha) * _smoothedPace;
      }
      _lastValidPace = _smoothedPace;
    }
  }

  // ── Rolling window pace (Phase 2) ──────────────────────────────────────

  void _computeRollingPace() {
    if (_ringBuffer.length < 2) return;

    double windowDistance = 0.0;
    double windowTime = 0.0;

    final points = _ringBuffer.toList().reversed.toList();

    for (int i = 1; i < points.length; i++) {
      final segDist = _haversineMeters(
        points[i - 1].lat, points[i - 1].lng,
        points[i].lat, points[i].lng,
      );
      final segTime = points[i - 1].timestamp.difference(points[i].timestamp).inMilliseconds / 1000.0;

      windowDistance += segDist;
      windowTime += segTime;

      if (windowTime >= _rollingWindowSeconds && windowDistance >= _rollingWindowMeters) {
        break;
      }
    }

    if (windowDistance < 5.0 || windowTime < 2.0) {
      if (_ringBuffer.length >= 3) {
        final recentSpeed = _estimateRecentSpeed();
        if (recentSpeed < _stoppedSpeedThreshold && _lastValidPace > 0) {
          return;
        }
      }
      return;
    }

    // Rolling window has enough data — take over from GPS speed
    _rollingWindowActive = true;

    double rawPace = (windowTime / windowDistance) * 1000.0;
    rawPace = rawPace.clamp(_minPaceSecondsPerKm, _maxPaceSecondsPerKm);

    _paceSmoothing.add(rawPace);
    if (_paceSmoothing.length > _smoothingBufferSize) {
      _paceSmoothing.removeAt(0);
    }

    final sorted = List<double>.from(_paceSmoothing)..sort();
    final median = sorted[sorted.length ~/ 2];

    if (_smoothedPace <= 0) {
      _smoothedPace = median;
    } else {
      const alpha = 0.3;
      _smoothedPace = alpha * median + (1 - alpha) * _smoothedPace;
    }

    _lastValidPace = _smoothedPace;
  }

  double _estimateRecentSpeed() {
    if (_ringBuffer.length < 2) return 0.0;
    final points = _ringBuffer.toList();
    final last = points.last;
    final prev = points[points.length - 2];
    final dist = _haversineMeters(prev.lat, prev.lng, last.lat, last.lng);
    final dt = last.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    if (dt <= 0) return 0.0;
    return dist / dt;
  }

  void _checkStale(DateTime now) {
    if (_lastGpsTimestamp == null) return;
    final gap = now.difference(_lastGpsTimestamp!).inSeconds;
    _isStale = gap > _stalePaceTimeoutSeconds;
  }

  PaceSnapshot _buildSnapshot() {
    double avgPace = 0.0;
    if (_totalDistance > 0) {
      avgPace = _totalSeconds / (_totalDistance / 1000.0);
    }

    final displayPace = _lastValidPace > 0 ? _lastValidPace : 0.0;
    final displaySmoothed = _smoothedPace > 0 ? _smoothedPace : displayPace;

    return PaceSnapshot(
      currentPaceSecondsPerKm: displayPace,
      smoothedPaceSecondsPerKm: displaySmoothed,
      averagePaceSecondsPerKm: avgPace,
      isStale: _isStale,
      isGpsSpeed: !_rollingWindowActive && _lastValidPace > 0,
      timestamp: DateTime.now(),
    );
  }

  static double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180.0;
}