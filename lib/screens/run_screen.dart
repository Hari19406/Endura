import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'foreground_task_handler.dart';
import 'dart:math' show sin, cos, atan2;
import 'dart:ui' as ui;
import '../utils/database_service.dart';
import '../screens/run_screen_summary.dart';
import '../services/audio_cue_service.dart';
import 'dart:convert';
import '../services/cloud_sync_service.dart';
import '../services/coach_message_builder.dart' as message;
import '../widgets/target_pace_indicator.dart';
import '../engines/pace_engine.dart';
import '../engines/config/workout_template_library.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

enum RunMode { warmup, mainSet, cooldown }

enum RunState { ready, running, paused }

enum PermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
  checking,
}

class RunScreen extends StatefulWidget {
  final message.CoachMessage? activeCoachMessage;
  final VoidCallback? onWorkoutCompleted;

  const RunScreen({
    super.key,
    this.activeCoachMessage,
    this.onWorkoutCompleted,
  });

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> with WidgetsBindingObserver {
  RunState _runState = RunState.ready;
  PermissionStatus _permissionStatus = PermissionStatus.checking;

  int _seconds = 0;
  double _distance = 0.0;
  double _pendingDistance = 0.0;
  Timer? _timer;
  StreamSubscription<Position>? _positionStream;
  Position? _lastPosition;

  StreamSubscription<Position>? _warmupStream;

  final PaceEngine _paceEngine = PaceEngine();
  PaceSnapshot _paceSnapshot = PaceSnapshot(
    currentPaceSecondsPerKm: 0,
    smoothedPaceSecondsPerKm: 0,
    averagePaceSecondsPerKm: 0,
    isStale: false,
    isGpsSpeed: false,
    timestamp: DateTime.now(),
  );

  final MapController _mapController = MapController();
  final List<LatLng> _routePoints = [];
  LatLng? _currentLocation;
  double _currentBearing = 0.0;
  double _smoothedBearing = 0.0;
  LatLng? _lastCameraCenter;
  final double _cameraMovementThreshold = 50.0;
  bool _userHasPannedMap = false;
  final _kalmanLat = _KalmanFilter();
  final _kalmanLng = _KalmanFilter();

  bool _voiceCoachingEnabled = false;
  int _lastAnnouncedKm = 0;

  double _deviceHeading = 0.0;

  DateTime? _lastGPSUpdate;
  Timer? _gpsMonitorTimer;
  bool _isGPSSignalLost = false;

  // ignore: unused_field
  DateTime? _backgroundTime;
  // ignore: unused_field
  bool _wasRunningBeforeBackground = false;
  DateTime? _runStartTime;

  String _distanceUnit = 'km';

  bool _isFirstRun = true;

  // ── Phase management ────────────────────────────────────────────────────────
  RunMode _currentPhase = RunMode.warmup;
  int _mainPhaseStartSeconds = 0;
  double _mainPhaseStartDistanceM = 0.0;
  int _cooldownPhaseStartSeconds = 0;
  double _cooldownPhaseStartDistanceM = 0.0;
  bool _phaseMilestoneReached = false;

  double _capturedMainDistanceM = 0.0;
  int _capturedMainSeconds = 0;
  String _capturedMainPace = '--:--';
  List<LatLng> _capturedMainRoute = [];

  static const int _warmupCooldownDurationSeconds = 600; // 10 min

  // ── Resolved workout helpers ──────────────────────────────────────────────
  ResolvedWorkout? get _workout => widget.activeCoachMessage?.resolvedWorkout;

bool get _hasWarmup =>
    (widget.activeCoachMessage?.hasWarmupCooldown ?? false) &&
    (_workout?.blocks.any((b) => b.type == BlockType.warmup) ?? false);

bool get _hasCooldown =>
    (widget.activeCoachMessage?.hasWarmupCooldown ?? false) &&
    (_workout?.blocks.any((b) => b.type == BlockType.cooldown) ?? false);

  bool get _isLastPhase =>
      _currentPhase == RunMode.cooldown ||
      (_currentPhase == RunMode.mainSet && !_hasCooldown);

  int get _phaseElapsedSeconds {
    switch (_currentPhase) {
      case RunMode.warmup:   return _seconds;
      case RunMode.mainSet:  return _seconds - _mainPhaseStartSeconds;
      case RunMode.cooldown: return _seconds - _cooldownPhaseStartSeconds;
    }
  }

  double get _phaseDistanceM {
    switch (_currentPhase) {
      case RunMode.warmup:   return _distance;
      case RunMode.mainSet:  return _distance - _mainPhaseStartDistanceM;
      case RunMode.cooldown: return _distance - _cooldownPhaseStartDistanceM;
    }
  }

  int get _phaseCountdownSeconds {
    if (_currentPhase == RunMode.mainSet) return 0;
    return (_warmupCooldownDurationSeconds - _phaseElapsedSeconds)
        .clamp(0, _warmupCooldownDurationSeconds);
  }

  /// Total distance of work blocks in meters (the main set target).
  double? get _mainTargetDistanceM {
  final workBlocks = _workout?.blocks.where((b) => b.type == BlockType.main);
  if (workBlocks == null) return null;
    double total = 0;
    for (final b in workBlocks) {
      total += b.totalDistanceKm * 1000;
    }
    return total > 0 ? total : null;
  }

  /// Target pace range for the main set — extracted from work blocks.
  /// Used by TargetPaceIndicator widget.
  message.PaceRange? get _targetPaceRange {
  if (_currentPhase != RunMode.mainSet) return null;
  final workBlocks = _workout?.blocks.where((b) => b.type == BlockType.main);
  if (workBlocks == null) return null;
    final nonRpe = workBlocks.where((b) => !b.isRpeOnly);
    if (nonRpe.isEmpty) return null;
    final fastest = nonRpe.map((b) => b.paceMinSecondsPerKm).reduce((a, b) => a < b ? a : b);
    final slowest = nonRpe.map((b) => b.paceMaxSecondsPerKm).reduce((a, b) => a > b ? a : b);
    return message.PaceRange(
      minSecondsPerKm: fastest,
      maxSecondsPerKm: slowest,
    );
  }

  String get _phaseName {
    switch (_currentPhase) {
      case RunMode.warmup:   return 'WARMUP';
      case RunMode.mainSet:  return 'MAIN SET';
      case RunMode.cooldown: return 'COOLDOWN';
    }
  }

  Color get _phaseColor {
    switch (_currentPhase) {
      case RunMode.warmup:   return const Color(0xFF388E3C);
      case RunMode.mainSet:  return const Color(0xFF0A0A0A);
      case RunMode.cooldown: return const Color(0xFF1565C0);
    }
  }

  String get _milestoneHint {
    switch (_currentPhase) {
      case RunMode.warmup:
        return 'Warmup done — tap Next for Main Set';
      case RunMode.mainSet:
        return _isLastPhase
            ? 'Run done — tap Finish'
            : 'Main set done — tap Next for Cooldown';
      case RunMode.cooldown:
        return 'Cooldown done — tap Finish';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentPhase = _hasWarmup ? RunMode.warmup : RunMode.mainSet;
    _loadSettings();
    _checkPermissions();
    _startCompassTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _handleAppBackground();
        break;
      case AppLifecycleState.resumed:
        _handleAppForeground();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _handleAppBackground() {
    debugPrint('App going to background');
    _wasRunningBeforeBackground = _runState == RunState.running;
    _backgroundTime = DateTime.now();
    if (_runState == RunState.running) {
      _timer?.cancel();
      _timer = null;
      _gpsMonitorTimer?.cancel();
      _gpsMonitorTimer = null;
    }
  }

  void _handleAppForeground() async {
    debugPrint('App returning to foreground');
    if (!mounted) return;
    if (_runStartTime != null && _runState == RunState.running) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final backgroundElapsed = prefs.getInt('background_elapsed_seconds');
        if (backgroundElapsed != null && backgroundElapsed > 0) {
          setState(() => _seconds = backgroundElapsed);
        } else {
          final actualElapsed = DateTime.now().difference(_runStartTime!).inSeconds;
          if (actualElapsed > _seconds && actualElapsed < 86400) {
            setState(() => _seconds = actualElapsed);
          }
        }
      } catch (e) {
        debugPrint('Error syncing background time: $e');
      }
      _resumeTimersAfterBackground();
    }
    _backgroundTime = null;
    _wasRunningBeforeBackground = false;
    if (_permissionStatus == PermissionStatus.granted && _currentLocation == null) {
      _getCurrentLocation();
    }
  }

  void _resumeTimersAfterBackground() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _runState == RunState.running) {
        setState(() {
          _seconds++;
          _paceSnapshot = _paceEngine.tick(_seconds);
        });
        _checkPhaseMilestone();
      }
    });
    _startGPSMonitoring();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historyJson = prefs.getString('run_history');
      final settingsJson = prefs.getString('app_settings');
      if (settingsJson != null) {
        final decoded = jsonDecode(settingsJson);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          _voiceCoachingEnabled = map['voiceCoaching'] as bool? ?? false;
        }
      }
      await AudioCueService.instance.initialize(enabled: _voiceCoachingEnabled);
      if (mounted) {
        setState(() {
          _distanceUnit = prefs.getString('distance_unit') ?? 'km';
          _isFirstRun = (historyJson == null || historyJson.isEmpty);
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  void _startCompassTracking() {}

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'run_tracker_channel',
        channelName: 'Run Tracking',
        channelDescription: 'Notification for active run tracking',
        onlyAlertOnce: true,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> _startForegroundTask() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Run in progress',
      notificationText: 'tracking distance and pace',
      callback: startCallback,
    );
  }

  Future<void> _stopForegroundTask() async {
    await FlutterForegroundTask.stopService();
  }

  double _convertDistance(double meters) {
    double km = meters / 1000;
    if (_distanceUnit == 'miles') return km * 0.621371;
    return km;
  }

  String _getDistanceLabel() => _distanceUnit == 'miles' ? 'mi' : 'km';

  Future<void> _checkPermissions() async {
    if (!mounted) return;
    setState(() => _permissionStatus = PermissionStatus.checking);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _permissionStatus = PermissionStatus.serviceDisabled);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _permissionStatus = PermissionStatus.denied);
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _permissionStatus = PermissionStatus.deniedForever);
        return;
      }
      if (mounted) {
        setState(() => _permissionStatus = PermissionStatus.granted);
        _getCurrentLocation();
      }
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      if (mounted) setState(() => _permissionStatus = PermissionStatus.denied);
    }
  }

  Future<void> _requestPermission() async {
    if (_permissionStatus == PermissionStatus.deniedForever) {
      bool opened = await Geolocator.openAppSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Can\'t open settings. Please turn on location yourself.'), backgroundColor: Color(0xFFF57C00)),
        );
      }
      return;
    }
    if (_permissionStatus == PermissionStatus.serviceDisabled) {
      bool opened = await Geolocator.openLocationSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Can\'t open settings. Please turn on location yourself.'), backgroundColor: Color(0xFFF57C00)),
        );
      }
      await Future.delayed(const Duration(seconds: 1));
      _checkPermissions();
      return;
    }
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _permissionStatus = PermissionStatus.denied);
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _permissionStatus = PermissionStatus.deniedForever);
        return;
      }
      if (mounted) {
        setState(() => _permissionStatus = PermissionStatus.granted);
        _getCurrentLocation();
      }
    } catch (e) {
      debugPrint('Error requesting permission: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    if (_permissionStatus != PermissionStatus.granted) return;
    _startGpsWarmup();
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  void _startGpsWarmup() {
    if (_warmupStream != null) return;
    _warmupStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
    ).listen(
      (Position position) {
        if (mounted && _runState == RunState.ready) {
          setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
        }
      },
      onError: (e) => debugPrint('Warmup GPS error: $e'),
      cancelOnError: false,
    );
  }

  void _stopGpsWarmup() {
    _warmupStream?.cancel();
    _warmupStream = null;
  }

  Future<void> _startTracking() async {
    if (_runState != RunState.ready) return;
    if (_permissionStatus != PermissionStatus.granted) { _requestPermission(); return; }

    _runStartTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('run_start_time', _runStartTime!.millisecondsSinceEpoch);
      await prefs.setInt('background_elapsed_seconds', 0);
    } catch (e) { debugPrint('Error saving start time: $e'); }

    await _initForegroundTask();
    await _startForegroundTask();
    _stopGpsWarmup();

    if (mounted) {
      setState(() {
        _runState = RunState.running;
        _seconds = 0;
        _distance = 0.0;
        _pendingDistance = 0.0;
        _lastPosition = null;
        _kalmanLat.reset();
        _kalmanLng.reset();
        _paceEngine.reset();
        _paceSnapshot = PaceSnapshot(
          currentPaceSecondsPerKm: 0, smoothedPaceSecondsPerKm: 0,
          averagePaceSecondsPerKm: 0, isStale: false, isGpsSpeed: false,
          timestamp: DateTime.now(),
        );
        _routePoints.clear();
        _isGPSSignalLost = false;
        _lastGPSUpdate = DateTime.now();
        _currentBearing = 0.0;
        _smoothedBearing = 0.0;
        _lastCameraCenter = null;
        _userHasPannedMap = false;
        _currentPhase = _hasWarmup ? RunMode.warmup : RunMode.mainSet;
        _mainPhaseStartSeconds = 0;
        _mainPhaseStartDistanceM = 0.0;
        _cooldownPhaseStartSeconds = 0;
        _cooldownPhaseStartDistanceM = 0.0;
        _phaseMilestoneReached = false;
        _capturedMainDistanceM = 0.0;
        _capturedMainSeconds = 0;
        _capturedMainPace = '--:--';
        _capturedMainRoute = [];
      });
    }

    AudioCueService.instance.announceRunStart();
    await Posthog().capture(
      eventName: 'workout_started',
      properties: {
        'workout_type': widget.activeCoachMessage != null
            ? _resolveWorkoutType(widget.activeCoachMessage!.workoutIntent)
            : 'free',
      },
    );
    _startGPSMonitoring();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _runState == RunState.running) {
        setState(() {
          _seconds++;
          _paceSnapshot = _paceEngine.tick(_seconds);
        });
        _checkPhaseMilestone();
      }
    });

    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
      ).listen(
        (Position position) {
          if (_runState != RunState.running) return;
          _lastGPSUpdate = DateTime.now();
          if (_isGPSSignalLost && mounted) setState(() => _isGPSSignalLost = false);
          if (position.accuracy > 60) return;

          if (_lastPosition != null) {
            final timeDelta = position.timestamp.difference(_lastPosition!.timestamp).inSeconds;
            if (timeDelta > 0) {
              final quickDistance = Geolocator.distanceBetween(_lastPosition!.latitude, _lastPosition!.longitude, position.latitude, position.longitude);
              if (quickDistance / timeDelta > 12.0) return;
            }
          }

          final smoothedLat = _kalmanLat.filter(position.latitude);
          final smoothedLng = _kalmanLng.filter(position.longitude);
          LatLng newPoint = LatLng(smoothedLat, smoothedLng);

          if (_lastPosition != null) {
            double distanceInMeters = Geolocator.distanceBetween(_lastPosition!.latitude, _lastPosition!.longitude, position.latitude, position.longitude);
            if (distanceInMeters >= 1) {
              double newBearing = _calculateBearing(_lastPosition!.latitude, _lastPosition!.longitude, position.latitude, position.longitude);
              if (mounted) setState(() => _deviceHeading = newBearing);
              double bearingChange = newBearing - _smoothedBearing;
              if (bearingChange > 180) bearingChange -= 360;
              if (bearingChange < -180) bearingChange += 360;
              bool sharpTurn = _isSharpTurnDetected(distanceInMeters, bearingChange);
              if (!sharpTurn || distanceInMeters >= 10) _currentBearing = _smoothBearing(newBearing, _smoothedBearing);
            }

            if (mounted && _runState == RunState.running && !_isGPSSignalLost) {
              _pendingDistance += distanceInMeters;
              if (_pendingDistance >= 1) {
                final validDistance = _pendingDistance;
                _pendingDistance = 0;
                setState(() {
                  _distance += validDistance;
                  _paceSnapshot = _paceEngine.addPoint(
                    GpsPoint(lat: position.latitude, lng: position.longitude, accuracy: position.accuracy, speed: position.speed, timestamp: position.timestamp),
                    _distance, _seconds,
                  );
                  _routePoints.add(newPoint);
                  _currentLocation = newPoint;
                  _smoothedBearing = _currentBearing;
                  if (_shouldUpdateCamera(newPoint)) _smoothMoveCamera(newPoint);
                });
                final kmCompleted = (_distance / 1000).floor();
                if (kmCompleted > _lastAnnouncedKm && kmCompleted > 0) {
                  _lastAnnouncedKm = kmCompleted;
                  AudioCueService.instance.announceKilometre(kmCompleted: kmCompleted, paceString: _paceSnapshot.formattedAverage, elapsedSeconds: _seconds);
                }
                _checkPhaseMilestone();
              } else {
                setState(() {
                  _currentLocation = newPoint;
                  _smoothedBearing = _currentBearing;
                  if (_shouldUpdateCamera(newPoint)) _smoothMoveCamera(newPoint);
                });
              }
            }
          } else {
            if (mounted) {
              setState(() {
                _routePoints.add(newPoint);
                _currentLocation = newPoint;
                _mapController.move(newPoint, 16.0);
                _lastCameraCenter = newPoint;
              });
            }
          }
          _lastPosition = position;
        },
        onError: (error) {
          debugPrint('GPS error: ${error.toString()}');
          if (mounted && !_isGPSSignalLost) setState(() => _isGPSSignalLost = true);
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('Error starting position stream: $e');
    }
  }

  void _startGPSMonitoring() {
    _gpsMonitorTimer?.cancel();
    _gpsMonitorTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_runState != RunState.running) { timer.cancel(); return; }
      if (_lastGPSUpdate != null) {
        final secondsSinceLastUpdate = DateTime.now().difference(_lastGPSUpdate!).inSeconds;
        if (secondsSinceLastUpdate > 10 && !_isGPSSignalLost && mounted) setState(() => _isGPSSignalLost = true);
      }
    });
  }

  void _pauseTracking() {
    if (_runState != RunState.running) return;
    _timer?.cancel(); _timer = null;
    _gpsMonitorTimer?.cancel(); _gpsMonitorTimer = null;
    if (mounted) setState(() { _runState = RunState.paused; _isGPSSignalLost = false; _wasRunningBeforeBackground = false; _backgroundTime = null; });
  }

  void _resumeTracking() {
    if (_runState != RunState.paused) return;
    if (mounted) setState(() { _runState = RunState.running; _lastGPSUpdate = DateTime.now(); _isGPSSignalLost = false; _wasRunningBeforeBackground = false; _backgroundTime = null; });
    _startGPSMonitoring();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _runState == RunState.running) {
        setState(() { _seconds++; _paceSnapshot = _paceEngine.tick(_seconds); });
        _checkPhaseMilestone();
      }
    });
  }

  double _calculateBearing(double startLat, double startLng, double endLat, double endLng) {
    double startLatRad = startLat * (3.14159265359 / 180.0);
    double endLatRad = endLat * (3.14159265359 / 180.0);
    double endLngRad = endLng * (3.14159265359 / 180.0);
    double startLngRad = startLng * (3.14159265359 / 180.0);
    double dLng = endLngRad - startLngRad;
    double y = sin(dLng) * cos(endLatRad);
    double x = cos(startLatRad) * sin(endLatRad) - sin(startLatRad) * cos(endLatRad) * cos(dLng);
    double bearing = atan2(y, x);
    bearing = bearing * (180.0 / 3.14159265359);
    bearing = (bearing + 360) % 360;
    return bearing;
  }

  double _smoothBearing(double newBearing, double oldBearing) {
    double diff = newBearing - oldBearing;
    if (diff > 180) diff -= 360;
    else if (diff < -180) diff += 360;
    return ((oldBearing + (diff * 0.3)) + 360) % 360;
  }

  bool _isSharpTurnDetected(double distanceInMeters, double bearingChange) {
    if (distanceInMeters < 10 && bearingChange.abs() > 45) return true;
    if (distanceInMeters >= 10 && distanceInMeters < 30 && bearingChange.abs() > 60) return true;
    return false;
  }

  double _getDistanceFromCamera(LatLng point) {
    if (_lastCameraCenter == null) return double.infinity;
    return Geolocator.distanceBetween(_lastCameraCenter!.latitude, _lastCameraCenter!.longitude, point.latitude, point.longitude);
  }

  bool _shouldUpdateCamera(LatLng newLocation) {
    if (_lastCameraCenter == null) return true;
    if (_userHasPannedMap) {
      if (_getDistanceFromCamera(newLocation) > 100) { _userHasPannedMap = false; return true; }
      return false;
    }
    return _getDistanceFromCamera(newLocation) > _cameraMovementThreshold;
  }

  void _smoothMoveCamera(LatLng target) {
    _mapController.move(target, _mapController.camera.zoom);
    _lastCameraCenter = target;
  }

  Future<void> _finishRun() async {
    if (_runState != RunState.paused) return;

    _timer?.cancel(); _timer = null;
    _positionStream?.cancel(); _positionStream = null;
    _gpsMonitorTimer?.cancel(); _gpsMonitorTimer = null;
    await _stopForegroundTask();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('run_start_time');
      await prefs.remove('background_elapsed_seconds');
    } catch (e) { debugPrint('Error clearing tracking preferences: $e'); }

    if (_currentPhase == RunMode.mainSet) {
      _capturedMainDistanceM = _distance - _mainPhaseStartDistanceM;
      _capturedMainSeconds = _seconds - _mainPhaseStartSeconds;
      _capturedMainPace = _calcPhasePace(_capturedMainDistanceM, _capturedMainSeconds);
      _capturedMainRoute = List<LatLng>.from(_routePoints);
    }

    final warmupSeconds = _hasWarmup ? _mainPhaseStartSeconds : 0;
    final cooldownSeconds = _currentPhase == RunMode.cooldown ? _seconds - _cooldownPhaseStartSeconds : 0;
    final runDate = DateTime.now();
    final capturedWorkoutType = widget.activeCoachMessage != null
    ? _resolveWorkoutType(widget.activeCoachMessage!.workoutIntent)
    : 'free';
    if (_capturedMainDistanceM >= 100) {
      await AudioCueService.instance.announceRunComplete(
        distanceKm: _capturedMainDistanceM / 1000,
        averagePace: _capturedMainPace,
        elapsedSeconds: _capturedMainSeconds,
      );

      try {
        final polyline = encodeRouteToPolyline(
          _capturedMainRoute.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        );
        final newRun = RunRecord(
          distanceKm: _capturedMainDistanceM / 1000,
          averagePace: _capturedMainPace,
          durationSeconds: _capturedMainSeconds,
          date: runDate,
          routePolyline: polyline,
          workoutType: capturedWorkoutType,
        );
        await DatabaseService.instance.insertRun(newRun);
        CloudSyncService.instance.syncPendingRuns().then((r) => debugPrint('Sync: $r'));
        await Posthog().capture(
          eventName: 'workout_completed',
          properties: {
            'duration': _capturedMainSeconds,
            'distance': double.parse(
                (_capturedMainDistanceM / 1000).toStringAsFixed(2)),
          },
        );
        await _showCSCalibrationPromptIfNeeded();
      } catch (e) {
        debugPrint('Error saving run: $e');
      }
    }

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => RunSummaryScreen(
          distanceKm: _capturedMainDistanceM / 1000,
          durationSeconds: _capturedMainSeconds,
          averagePace: _capturedMainPace,
          routePoints: _capturedMainRoute,
          runDate: runDate,
          warmupDurationSeconds: warmupSeconds,
          cooldownDurationSeconds: cooldownSeconds,
          onDone: () => Navigator.popUntil(context, (route) => route.isFirst),
          activeCoachMessage: widget.activeCoachMessage,
        ),
      ));
    }
  }

  /// Map WorkoutIntent to the string stored in RunRecord.
  String _resolveWorkoutType(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.threshold    => 'tempo',
      WorkoutIntent.vo2max       => 'interval',
      WorkoutIntent.speed        => 'interval',
      WorkoutIntent.raceSpecific => 'tempo',
      WorkoutIntent.endurance    => 'long',
      WorkoutIntent.recovery     => 'recovery',
      WorkoutIntent.aerobicBase  => 'easy',
    };
  }

  // ── Phase management ────────────────────────────────────────────────────────

  void _advancePhase() {
    if (_currentPhase == RunMode.warmup) {
      setState(() {
        _mainPhaseStartSeconds = _seconds;
        _mainPhaseStartDistanceM = _distance;
        _currentPhase = RunMode.mainSet;
        _phaseMilestoneReached = false;
      });
    } else if (_currentPhase == RunMode.mainSet) {
      _capturedMainDistanceM = _distance - _mainPhaseStartDistanceM;
      _capturedMainSeconds = _seconds - _mainPhaseStartSeconds;
      _capturedMainPace = _calcPhasePace(_capturedMainDistanceM, _capturedMainSeconds);
      _capturedMainRoute = List<LatLng>.from(_routePoints);
      setState(() {
        _cooldownPhaseStartSeconds = _seconds;
        _cooldownPhaseStartDistanceM = _distance;
        _currentPhase = RunMode.cooldown;
        _phaseMilestoneReached = false;
      });
    }
  }

  void _tapNext() {
    _advancePhase();
    if (_runState == RunState.paused) _resumeTracking();
  }

  void _checkPhaseMilestone() {
    if (_phaseMilestoneReached) return;
    bool hit = false;
    if (_currentPhase == RunMode.warmup || _currentPhase == RunMode.cooldown) {
      hit = _phaseCountdownSeconds <= 0;
    } else if (_currentPhase == RunMode.mainSet) {
      final target = _mainTargetDistanceM;
      if (target != null) hit = _phaseDistanceM >= target;
    }
    if (hit) {
      setState(() => _phaseMilestoneReached = true);
      HapticFeedback.heavyImpact();
    }
  }

  String _calcPhasePace(double distanceM, int seconds) {
    if (distanceM < 1 || seconds <= 0) return '--:--';
    final secsPerKm = (seconds / (distanceM / 1000)).round();
    final mins = secsPerKm ~/ 60;
    final secs = secsPerKm % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _buildDistanceText() {
    final phaseKm = _convertDistance(_phaseDistanceM);
    if (_currentPhase == RunMode.mainSet) {
      final target = _mainTargetDistanceM;
      if (target != null) {
        final targetConverted = _convertDistance(target);
        return '${phaseKm.toStringAsFixed(2)}/${targetConverted.toStringAsFixed(1)} ${_getDistanceLabel()}';
      }
    }
    return '${phaseKm.toStringAsFixed(2)} ${_getDistanceLabel()}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _positionStream?.cancel();
    _warmupStream?.cancel();
    _gpsMonitorTimer?.cancel();
    _stopForegroundTask();
    AudioCueService.instance.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    int secs = seconds % 60;
    if (hours > 0) return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // ── Build methods (ALL UI UNCHANGED from original) ──────────────────────────

  Widget _buildCompassIcon() {
    return GestureDetector(
      onTap: () {
        if (_currentLocation != null && mounted) {
          setState(() { _deviceHeading = 0.0; _smoothedBearing = 0.0; _currentBearing = 0.0; });
          _mapController.move(_currentLocation!, _mapController.camera.zoom);
        }
      },
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.white, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Transform.rotate(
          angle: -_deviceHeading * (3.14159265359 / 180.0),
          child: Center(child: Text('N', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800,
            color: _deviceHeading < 10 || _deviceHeading > 350 ? const Color(0xFFD32F2F) : const Color(0xFF0A0A0A),
            letterSpacing: -0.3,
          ))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionStatus != PermissionStatus.granted && _runState == RunState.ready) {
      return Scaffold(body: _buildPermissionError());
    }
    return Scaffold(
      body: Stack(
        children: [
          _currentLocation == null
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF000000)))
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: _currentLocation!, initialZoom: 17.5, minZoom: 10.0, maxZoom: 18.0, interactionOptions: const InteractionOptions(flags: InteractiveFlag.all)),
                  children: [
                    TileLayer(urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=3Iy00qmbWys8hyAY1PIe', userAgentPackageName: 'com.example.runtracker', maxZoom: 19, subdomains: const ['a', 'b', 'c'], tileProvider: NetworkTileProvider()),
                    PolylineLayer(polylines: [Polyline(points: _routePoints, strokeWidth: 4.0, color: const Color(0xFF000000), borderStrokeWidth: 2.0, borderColor: Colors.white)]),
                    if (_currentLocation != null)
                      MarkerLayer(markers: [
                        Marker(point: _currentLocation!, width: 40, height: 40, child: Transform.rotate(
                          angle: _smoothedBearing * (3.14159265359 / 180.0),
                          child: Container(
                            decoration: BoxDecoration(color: const Color(0xFF000000), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, spreadRadius: 2)]),
                            child: const Icon(Icons.navigation, color: Colors.white, size: 20),
                          ),
                        )),
                      ]),
                  ],
                ),
          if (_isFirstRun && _runState == RunState.ready) _buildWelcomeCard()
          else Positioned(top: 60, left: 20, right: 20, child: _buildStatsCard()),
          if (_currentLocation != null) Positioned(bottom: _runState == RunState.paused ? 140 : 110, right: 20, child: _buildCompassIcon()),
          Positioned(bottom: 40, left: 20, right: 20, child: _buildActionButtons()),
          if (_runState == RunState.running) _buildGPSLostBanner(),
        ],
      ),
    );
  }

  Widget _buildPermissionError() {
    IconData icon; String title; String bodyMessage; String buttonText;
    switch (_permissionStatus) {
      case PermissionStatus.checking: return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF000000))));
      case PermissionStatus.serviceDisabled: icon = Icons.location_off; title = 'Location is off'; bodyMessage = 'Turn on location to track your runs.'; buttonText = 'Turn on location';
      case PermissionStatus.denied: icon = Icons.location_disabled; title = 'Location needed'; bodyMessage = 'We need location to track your runs and show your route.'; buttonText = 'Allow location';
      case PermissionStatus.deniedForever: icon = Icons.settings_outlined; title = 'Location blocked'; bodyMessage = 'You permanently blocked location access. To fix this:\n\n1. Tap "Open settings" below\n2. Tap "Permissions"\n3. Tap "Location"\n4. Select "While using the app"'; buttonText = 'Open settings';
      default: return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF000000))));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(title: const Text('Endura', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF000000), fontSize: 16, letterSpacing: -0.3)), centerTitle: true, elevation: 0, backgroundColor: const Color(0xFFFFFFFF)),
      body: Center(child: Padding(padding: const EdgeInsets.all(40.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 48, color: const Color(0xFF999999)),
        const SizedBox(height: 24),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF000000))),
        const SizedBox(height: 12),
        Text(bodyMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.6)),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _requestPermission, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF000000), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: Text(buttonText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)))),
        const SizedBox(height: 12),
        if (_permissionStatus == PermissionStatus.deniedForever)
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _checkPermissions, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Color(0xFFE8E8E8)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('I\'ve updated settings, check again', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF666666)))))
        else TextButton(onPressed: _checkPermissions, style: TextButton.styleFrom(foregroundColor: const Color(0xFF666666)), child: const Text('Check again')),
      ]))),
    );
  }

  Widget _buildWelcomeCard() {
    return Positioned(top: 60, left: 20, right: 20, child: Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ready to run?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF000000), letterSpacing: -0.3)),
        const SizedBox(height: 16),
        _buildWelcomeTip('Tap Start to begin'),
        const SizedBox(height: 8),
        _buildWelcomeTip('We\'ll track your route'),
        const SizedBox(height: 8),
        _buildWelcomeTip('Pause anytime you need'),
        if (_targetPaceRange != null) ...[
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFF0F0F0)),
          const SizedBox(height: 16),
          _buildWelcomeTip('Today\'s target: ${PaceComparator.formatRange(_targetPaceRange!)}'),
        ],
      ]),
    ));
  }

  Widget _buildWelcomeTip(String text) {
    return Row(children: [
      Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF000000), shape: BoxShape.circle)),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF666666), height: 1.4))),
    ]);
  }

  Widget _buildStatsCard() {
    final isActive = _runState != RunState.ready;
    final isWarmupOrCooldown = _currentPhase != RunMode.mainSet;
    final showPaceIndicator = _currentPhase == RunMode.mainSet && isActive;

    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        if (_runState == RunState.paused) Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(border: Border.all(color: const Color(0xFF0A0A0A)), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF0A0A0A), shape: BoxShape.circle)), const SizedBox(width: 8), const Text('PAUSED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0A0A0A), letterSpacing: 1))])),
        if (_runState == RunState.running && _isGPSSignalLost) Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD32F2F)), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle)), const SizedBox(width: 8), const Text('GPS LOST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD32F2F), letterSpacing: 1))])),
        if (isActive) ...[
          Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _phaseColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: _phaseColor.withOpacity(0.25))), child: Text(_phaseName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _phaseColor, letterSpacing: 1.1)))]),
          const SizedBox(height: 14),
        ],
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isWarmupOrCooldown ? 'COUNTDOWN' : 'TIME', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF999999), letterSpacing: 0.8)), const SizedBox(height: 6), Text(isWarmupOrCooldown && isActive ? _formatTime(_phaseCountdownSeconds) : _formatTime(_seconds), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: isWarmupOrCooldown && isActive && _phaseCountdownSeconds == 0 ? const Color(0xFF388E3C) : const Color(0xFF000000), letterSpacing: -0.3, fontFeatures: const [FontFeature.tabularFigures()]))])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('DISTANCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF999999), letterSpacing: 0.8)), const SizedBox(height: 6), Text(isActive ? _buildDistanceText() : '0.00 ${_getDistanceLabel()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF000000), letterSpacing: -0.3, fontFeatures: [FontFeature.tabularFigures()]))])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isWarmupOrCooldown ? 'FREE PACE' : 'PACE', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF999999), letterSpacing: 0.8)), const SizedBox(height: 6), Text('${_paceSnapshot.formattedCurrent}/km', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _paceSnapshot.isStale ? const Color(0xFF999999) : const Color(0xFF000000), letterSpacing: -0.3, fontFeatures: const [FontFeature.tabularFigures()]))])),
        ]),
        if (showPaceIndicator) ...[const SizedBox(height: 14), Container(height: 1, color: const Color(0xFFF0F0F0)), const SizedBox(height: 14), TargetPaceIndicator(currentPaceSecondsPerKm: _paceSnapshot.smoothedPaceSecondsPerKm, targetRange: _targetPaceRange)],
        if (_phaseMilestoneReached && isActive) ...[const SizedBox(height: 14), Container(height: 1, color: const Color(0xFFF0F0F0)), const SizedBox(height: 14), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: const Color(0xFF388E3C).withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF388E3C).withOpacity(0.25))), child: Row(children: [const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF388E3C)), const SizedBox(width: 8), Text(_milestoneHint, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF388E3C)))]))],
      ]),
    );
  }

  Widget _buildActionButtons() {
    switch (_runState) {
      case RunState.ready:
        return SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _permissionStatus == PermissionStatus.granted ? _startTracking : null, style: ElevatedButton.styleFrom(backgroundColor: _permissionStatus == PermissionStatus.granted ? const Color(0xFF000000) : const Color(0xFFCCCCCC), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Start', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5))));
      case RunState.running:
        return SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _pauseTracking, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A0A0A), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Pause', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5))));
      case RunState.paused:
        return Row(children: [
          Expanded(child: ElevatedButton(onPressed: _resumeTracking, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A0A0A), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Resume', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)))),
          const SizedBox(width: 12),
          Expanded(child: _isLastPhase
            ? ElevatedButton(onPressed: _finishRun, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Finish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)))
            : ElevatedButton(onPressed: _tapNext, style: ElevatedButton.styleFrom(backgroundColor: _phaseColor, foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Next →', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)))),
        ]);
    }
  }

  Widget _buildGPSLostBanner() {
    return Positioned(top: 0, left: 0, right: 0, child: AnimatedSlide(offset: _isGPSSignalLost ? Offset.zero : const Offset(0, -1), duration: const Duration(milliseconds: 300), curve: Curves.easeOut, child: AnimatedOpacity(opacity: _isGPSSignalLost ? 1.0 : 0.0, duration: const Duration(milliseconds: 300), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), color: const Color(0xFFF57C00), child: SafeArea(bottom: false, child: Row(children: [
      TweenAnimationBuilder<double>(tween: Tween(begin: 0.4, end: 1.0), duration: const Duration(milliseconds: 800), builder: (context, value, child) => Opacity(opacity: value, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)))),
      const SizedBox(width: 10),
      const Expanded(child: Text('GPS signal lost — distance paused', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
      const Icon(Icons.gps_off, color: Colors.white, size: 16),
    ]))))));
  }

  Future<void> _showCSCalibrationPromptIfNeeded() async {
    // No-op: pace zones are derived from the PR entered at onboarding
    // and nudged automatically. No calibration prompt needed.
  }
}

class CompassPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final northPaint = Paint()..color = const Color(0xFFD32F2F)..style = PaintingStyle.fill;
    final northPath = ui.Path()..moveTo(centerX, centerY - 8)..lineTo(centerX - 5, centerY + 4)..lineTo(centerX + 5, centerY + 4)..close();
    canvas.drawPath(northPath, northPaint);
    final southPaint = Paint()..color = const Color(0xFF666666)..style = PaintingStyle.fill;
    final southPath = ui.Path()..moveTo(centerX, centerY + 8)..lineTo(centerX - 5, centerY - 4)..lineTo(centerX + 5, centerY - 4)..close();
    canvas.drawPath(southPath, southPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _KalmanFilter {
  final double _q = 3.0;
  final double _r = 10.0;
  double _p = 1.0;
  double _value = 0.0;
  bool _initialized = false;
  double filter(double measurement) {
    if (!_initialized) { _value = measurement; _initialized = true; return measurement; }
    _p = _p + _q;
    final k = _p / (_p + _r);
    _value = _value + k * (measurement - _value);
    _p = (1 - k) * _p;
    return _value;
  }
  void reset() { _initialized = false; _p = 1.0; }
}