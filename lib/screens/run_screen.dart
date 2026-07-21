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
import '../screens/pre_run_briefing_screen.dart';
import '../screens/pre_run_check.dart';
import '../screens/paywall_screen.dart';
import '../services/revenue_cat_service.dart';
import '../services/audio_cue_service.dart';
import 'dart:convert';
import '../services/cloud_sync_service.dart';
import '../services/coach_message_builder.dart' as message;
import '../widgets/target_pace_indicator.dart';
import '../engines/pace_engine.dart';
import '../engines/config/workout_template_library.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../config/map_config.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../utils/unit_utils.dart';

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

class _RunScreenState extends State<RunScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
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
  final double _cameraMovementThreshold = 15.0;
  bool _userHasPannedMap = false;

  late final AnimationController _cameraAnimController;
  Animation<double>? _cameraLatAnim;
  Animation<double>? _cameraLngAnim;
  final _kalmanLat = _KalmanFilter();
  final _kalmanLng = _KalmanFilter();

  bool _voiceCoachingEnabled = false;
  int _lastAnnouncedKm = 0;

  // ── Elevation + splits (main-set phase only, matches saved distance/duration) ──
  double _elevationGainM = 0.0;
  double? _lastAltitudeForGain;
  final List<Map<String, dynamic>> _splits = [];
  int _lastSplitKm = 0;

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
  bool _showRunTypeChoice = false;
  bool _isFreeRun = false;
  bool _workoutReadyToStart = false;
  message.CoachMessage? _activeCoachMessage;

  // ── Start countdown ─────────────────────────────────────────────────────────
  bool _showCountdown = false;
  int _countdownIndex = 0;
  Timer? _countdownTimer;
  Completer<void>? _countdownCompleter;
  static const List<String> _countdownSteps = ['3', '2', '1', 'GO!'];

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
  ResolvedWorkout? get _workout => _isFreeRun ? null : _activeCoachMessage?.resolvedWorkout;

bool get _hasWarmup =>
    (_activeCoachMessage?.hasWarmupCooldown ?? false) &&
    (_workout?.blocks.any((b) => b.type == BlockType.warmup) ?? false);

bool get _hasCooldown =>
    (_activeCoachMessage?.hasWarmupCooldown ?? false) &&
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

    final intent = _activeCoachMessage?.workoutIntent;
    if ((intent == WorkoutIntent.aerobicBase ||
            intent == WorkoutIntent.recovery ||
            intent == WorkoutIntent.endurance) &&
        (slowest - fastest) >= 30) {
      final ceiling = (fastest / 5).round() * 5;
      return message.PaceRange(
        minSecondsPerKm: ceiling,
        maxSecondsPerKm: slowest,
      );
    }

    return message.PaceRange(
      minSecondsPerKm: fastest,
      maxSecondsPerKm: slowest,
    );
  }

  String get _phaseName {
    if (_isFreeRun) return 'FREE RUN';
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
  void didUpdateWidget(RunScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeCoachMessage != oldWidget.activeCoachMessage &&
        _runState == RunState.ready) {
      setState(() => _activeCoachMessage = widget.activeCoachMessage);
    }
  }

  @override
  void initState() {
    super.initState();
    _activeCoachMessage = widget.activeCoachMessage;
    WidgetsBinding.instance.addObserver(this);
    _currentPhase = _hasWarmup ? RunMode.warmup : RunMode.mainSet;
    _distanceUnit = UnitUtils.useMilesNotifier.value ? 'miles' : 'km';
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
    _loadSettings();
    _checkPermissions();
    _startCompassTracking();
    _cameraAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _cameraAnimController.addListener(_onCameraAnimation);
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
      _voiceCoachingEnabled = prefs.getBool('voice_coaching') ?? false;
      await AudioCueService.instance.initialize(enabled: _voiceCoachingEnabled);
      if (mounted) {
        setState(() {
          _isFirstRun = (historyJson == null || historyJson.isEmpty);
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  void _onUnitPrefChanged() {
    if (mounted) {
      setState(() => _distanceUnit = UnitUtils.useMilesNotifier.value ? 'miles' : 'km');
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

  String _displayPace(double paceSecondsPerKm) {
    if (paceSecondsPerKm <= 0 || paceSecondsPerKm.isInfinite || paceSecondsPerKm.isNaN) {
      return '--:--';
    }
    final displaySeconds = UnitUtils.displayPaceSeconds(paceSecondsPerKm, _distanceUnit == 'miles');
    if (displaySeconds > 5999) return '99:59';
    return UnitUtils.formatSeconds(displaySeconds.round());
  }

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
          final newLoc = LatLng(position.latitude, position.longitude);
          setState(() => _currentLocation = newLoc);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _runState == RunState.ready) {
              try {
                final zoom = _mapController.camera.zoom;
                _mapController.move(newLoc, zoom > 0 ? zoom : 17.5);
              } catch (_) {}
            }
          });
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

    await _runCountdown();
    if (!mounted || _runState != RunState.ready) return;
    await _executeStartTracking();
  }

  Future<void> _runCountdown() {
    _countdownCompleter = Completer<void>();
    setState(() {
      _showCountdown = true;
      _countdownIndex = 0;
    });
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (_countdownIndex >= _countdownSteps.length - 1) {
        _completeCountdown();
      } else if (mounted) {
        setState(() => _countdownIndex++);
      }
    });
    return _countdownCompleter!.future;
  }

  void _completeCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) setState(() => _showCountdown = false);
    if (_countdownCompleter != null && !_countdownCompleter!.isCompleted) {
      _countdownCompleter!.complete();
    }
  }

  void _skipCountdown() => _completeCountdown();

  Future<void> _executeStartTracking() async {
    _runStartTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('run_start_time', _runStartTime!.millisecondsSinceEpoch);
      await prefs.setInt('background_elapsed_seconds', 0);
      await prefs.setDouble('run_distance_meters', 0.0);
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
        _elevationGainM = 0.0;
        _lastAltitudeForGain = null;
        _splits.clear();
        _lastSplitKm = 0;
      });
    }

    AudioCueService.instance.announceRunStart();
    await Analytics.workoutStarted(
      _activeCoachMessage != null
          ? _resolveWorkoutType(_activeCoachMessage!.workoutIntent)
          : 'free',
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
          final LatLng newPoint = LatLng(smoothedLat, smoothedLng);

          if (_currentPhase == RunMode.mainSet) {
            if (_lastAltitudeForGain != null) {
              final altDelta = position.altitude - _lastAltitudeForGain!;
              // Ignore sub-noise deltas and improbable spikes from GPS jitter.
              if (altDelta > 0.5 && altDelta < 15) _elevationGainM += altDelta;
            }
            _lastAltitudeForGain = position.altitude;
          }

          if (_lastPosition != null) {
            final double distanceInMeters = Geolocator.distanceBetween(_lastPosition!.latitude, _lastPosition!.longitude, position.latitude, position.longitude);

            // Update bearing every GPS tick — use GPS course when valid, fall back to position delta
            if (position.heading >= 0) {
              double bearingDiff = position.heading - _smoothedBearing;
              if (bearingDiff > 180) bearingDiff -= 360;
              if (bearingDiff < -180) bearingDiff += 360;
              _currentBearing = (_smoothedBearing + bearingDiff * 0.4 + 360) % 360;
              _deviceHeading = position.heading;
            } else if (distanceInMeters >= 1) {
              final double newBearing = _calculateBearing(_lastPosition!.latitude, _lastPosition!.longitude, position.latitude, position.longitude);
              double bearingChange = newBearing - _smoothedBearing;
              if (bearingChange > 180) bearingChange -= 360;
              if (bearingChange < -180) bearingChange += 360;
              final bool sharpTurn = _isSharpTurnDetected(distanceInMeters, bearingChange);
              if (!sharpTurn || distanceInMeters >= 10) _currentBearing = _smoothBearing(newBearing, _smoothedBearing);
              _deviceHeading = newBearing;
            }

            if (mounted && _runState == RunState.running && !_isGPSSignalLost) {
              _pendingDistance += distanceInMeters;
              if (_pendingDistance >= 1) {
                final validDistance = _pendingDistance;
                _pendingDistance = 0;
                final shouldMoveCamera = _shouldUpdateCamera(newPoint);
                setState(() {
                  _distance += validDistance;
                  _paceSnapshot = _paceEngine.addPoint(
                    GpsPoint(lat: position.latitude, lng: position.longitude, accuracy: position.accuracy, speed: position.speed, timestamp: position.timestamp),
                    _distance, _seconds,
                  );
                  _routePoints.add(newPoint);
                  _currentLocation = newPoint;
                  _smoothedBearing = _currentBearing;
                });
                SharedPreferences.getInstance().then(
                  (prefs) => prefs.setDouble('run_distance_meters', _distance),
                );
                if (shouldMoveCamera) _smoothMoveCamera(newPoint);
                final kmCompleted = (_distance / 1000).floor();
                if (kmCompleted > _lastAnnouncedKm && kmCompleted > 0) {
                  _lastAnnouncedKm = kmCompleted;
                  AudioCueService.instance.announceKilometre(kmCompleted: kmCompleted, paceString: _paceSnapshot.formattedAverage, elapsedSeconds: _seconds);
                }
                if (_currentPhase == RunMode.mainSet) {
                  final phaseKm = (_phaseDistanceM / 1000).floor();
                  if (phaseKm > _lastSplitKm) {
                    _lastSplitKm = phaseKm;
                    _splits.add({'km': phaseKm, 'seconds': _phaseElapsedSeconds});
                  }
                }
                _checkPhaseMilestone();
              } else {
                final shouldMoveCamera = _shouldUpdateCamera(newPoint);
                setState(() {
                  _currentLocation = newPoint;
                  _smoothedBearing = _currentBearing;
                });
                if (shouldMoveCamera) _smoothMoveCamera(newPoint);
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
    Analytics.workoutPaused();
  }

  void _resumeTracking() {
    if (_runState != RunState.paused) return;
    if (mounted) setState(() { _runState = RunState.running; _lastGPSUpdate = DateTime.now(); _isGPSSignalLost = false; _wasRunningBeforeBackground = false; _backgroundTime = null; });
    Analytics.workoutResumed();
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

  void _onCameraAnimation() {
    if (mounted && _cameraLatAnim != null && _cameraLngAnim != null) {
      try {
        _mapController.move(
          LatLng(_cameraLatAnim!.value, _cameraLngAnim!.value),
          _mapController.camera.zoom,
        );
      } catch (_) {}
    }
  }

  void _smoothMoveCamera(LatLng target) {
    try {
      final currentCenter = _mapController.camera.center;
      _cameraAnimController.stop();
      _cameraLatAnim = Tween<double>(begin: currentCenter.latitude, end: target.latitude)
          .animate(CurvedAnimation(parent: _cameraAnimController, curve: Curves.easeOutCubic));
      _cameraLngAnim = Tween<double>(begin: currentCenter.longitude, end: target.longitude)
          .animate(CurvedAnimation(parent: _cameraAnimController, curve: Curves.easeOutCubic));
      _cameraAnimController.forward(from: 0);
    } catch (_) {}
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
    final capturedWorkoutType = (!_isFreeRun && _activeCoachMessage != null)
    ? _resolveWorkoutType(_activeCoachMessage!.workoutIntent)
    : 'free';
    if (_capturedMainDistanceM >= 80) {
      await AudioCueService.instance.announceRunComplete(
        distanceKm: _capturedMainDistanceM / 1000,
        averagePace: _capturedMainPace,
        elapsedSeconds: _capturedMainSeconds,
      );

      FirebaseCrashlytics.instance.setCustomKey('run_distance_km', (_capturedMainDistanceM / 1000).toStringAsFixed(2));
      FirebaseCrashlytics.instance.setCustomKey('run_duration_s', _capturedMainSeconds.toString());
      FirebaseCrashlytics.instance.setCustomKey('run_workout_type', capturedWorkoutType);
      FirebaseCrashlytics.instance.setCustomKey('run_is_free', _isFreeRun.toString());

      try {
        final polyline = encodeRouteToPolyline(
          _capturedMainRoute.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        );
        // Convert cumulative km markers into per-split durations for storage.
        final capturedSplits = <Map<String, dynamic>>[];
        int prevSplitSeconds = 0;
        for (final s in _splits) {
          final cumSeconds = s['seconds'] as int;
          capturedSplits.add({'km': s['km'], 'seconds': cumSeconds - prevSplitSeconds});
          prevSplitSeconds = cumSeconds;
        }
        final newRun = RunRecord(
          distanceKm: _capturedMainDistanceM / 1000,
          averagePace: _capturedMainPace,
          durationSeconds: _capturedMainSeconds,
          date: runDate,
          routePolyline: polyline,
          workoutType: capturedWorkoutType,
          elevationGain: _elevationGainM,
          splits: capturedSplits,
        );
        await DatabaseService.instance.insertRun(newRun);
        CloudSyncService.instance.syncPendingRuns().then((r) => debugPrint('Sync: $r'));
        await Analytics.workoutCompleted(
          durationSeconds: _capturedMainSeconds,
          distanceKm: double.parse(
              (_capturedMainDistanceM / 1000).toStringAsFixed(2)),
          workoutType: capturedWorkoutType,
          isFreeRun: _isFreeRun,
          averagePace: _capturedMainPace,
        );
        await _showCSCalibrationPromptIfNeeded();
      } catch (e, stack) {
        debugPrint('Error saving run: $e');
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'run_save_failed', fatal: false);
        Analytics.runSaveFailed(e.toString());
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
          onDone: () async {
            widget.onWorkoutCompleted?.call();
            Navigator.popUntil(context, (route) => route.isFirst);
            await _resetToReady();
          },
          onDiscard: () async {
            Navigator.pop(context);
            await Analytics.workoutDiscarded();
            await _resetToReady();
          },
          activeCoachMessage: _isFreeRun ? null : _activeCoachMessage,
          isFreeRun: _isFreeRun,
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

  /// Average of the main set pace range formatted for TTS, e.g. "5 minutes 30 seconds".
  String? get _mainSetTargetPaceForSpeech {
    final workBlocks = _workout?.blocks.where((b) => b.type == BlockType.main);
    if (workBlocks == null || workBlocks.isEmpty) return null;
    final nonRpe = workBlocks.where((b) => !b.isRpeOnly).toList();
    if (nonRpe.isEmpty) return null;
    final fastest = nonRpe.map((b) => b.paceMinSecondsPerKm).reduce((a, b) => a < b ? a : b);
    final slowest = nonRpe.map((b) => b.paceMaxSecondsPerKm).reduce((a, b) => a > b ? a : b);
    final avg = ((fastest + slowest) / 2).round();
    final mins = avg ~/ 60;
    final secs = avg % 60;
    if (secs == 0) return '$mins minutes';
    return '$mins minutes $secs seconds';
  }

  void _advancePhase() {
    if (_currentPhase == RunMode.warmup) {
      final paceStr = _mainSetTargetPaceForSpeech;
      setState(() {
        _mainPhaseStartSeconds = _seconds;
        _mainPhaseStartDistanceM = _distance;
        _currentPhase = RunMode.mainSet;
        _phaseMilestoneReached = false;
        _elevationGainM = 0.0;
        _lastAltitudeForGain = null;
        _splits.clear();
        _lastSplitKm = 0;
      });
      AudioCueService.instance.announceMainSetStart(targetPace: paceStr);
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
      AudioCueService.instance.announceCooldownStart();
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
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    _timer?.cancel();
    _positionStream?.cancel();
    _warmupStream?.cancel();
    _gpsMonitorTimer?.cancel();
    _countdownTimer?.cancel();
    _cameraAnimController.dispose();
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
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: _currentLocation!, initialZoom: 17.5, minZoom: 10.0, maxZoom: 18.0, interactionOptions: const InteractionOptions(flags: InteractiveFlag.all)),
                  children: [
                    TileLayer(
                      urlTemplate: mapTilerStreetsUrlTemplate,
                      userAgentPackageName: 'com.example.runtracker',
                      maxZoom: 19,
                      subdomains: const ['a', 'b', 'c'],
                      tileProvider: NetworkTileProvider(),
                      errorTileCallback: (tile, error, stack) {
                        FirebaseCrashlytics.instance.recordError(error, stack, reason: 'maptiler_tile_load_failed', fatal: false);
                      },
                    ),
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
          if (_showCountdown) _buildCountdownOverlay(),
        ],
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    final step = _countdownSteps[_countdownIndex];
    final isGo = step == 'GO!';
    return Positioned.fill(
      child: GestureDetector(
        onTap: _skipCountdown,
        child: Container(
          color: Colors.black.withOpacity(0.78),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Text(
                  step,
                  key: ValueKey(_countdownIndex),
                  style: TextStyle(
                    fontSize: isGo ? 72 : 96,
                    fontWeight: FontWeight.w800,
                    color: isGo ? context.colors.accent : Colors.white,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Tap to skip',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionError() {
    IconData icon; String title; String bodyMessage; String buttonText;
    switch (_permissionStatus) {
      case PermissionStatus.checking: return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case PermissionStatus.serviceDisabled: icon = Icons.location_off; title = 'Location is off'; bodyMessage = 'Turn on location to track your runs.'; buttonText = 'Turn on location';
      case PermissionStatus.denied: icon = Icons.location_disabled; title = 'Location needed'; bodyMessage = 'We need location to track your runs and show your route.'; buttonText = 'Allow location';
      case PermissionStatus.deniedForever: icon = Icons.settings_outlined; title = 'Location blocked'; bodyMessage = 'You permanently blocked location access. To fix this:\n\n1. Tap "Open settings" below\n2. Tap "Permissions"\n3. Tap "Location"\n4. Select "While using the app"'; buttonText = 'Open settings';
      default: return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text('Endura', style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary, fontSize: 16, letterSpacing: -0.3)), centerTitle: true, elevation: 0, backgroundColor: c.surface),
      body: Center(child: Padding(padding: const EdgeInsets.all(40.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 48, color: c.textTertiary),
        const SizedBox(height: 24),
        Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary)),
        const SizedBox(height: 12),
        Text(bodyMessage, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.6)),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _requestPermission, style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: Text(buttonText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)))),
        const SizedBox(height: 12),
        if (_permissionStatus == PermissionStatus.deniedForever)
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _checkPermissions, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: c.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text('I\'ve updated settings, check again', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.textSecondary))))
        else TextButton(onPressed: _checkPermissions, style: TextButton.styleFrom(foregroundColor: c.textSecondary), child: const Text('Check again')),
      ]))),
    );
  }

  Widget _buildWelcomeCard() {
    final c = context.colors;
    return Positioned(top: 60, left: 20, right: 20, child: Container(
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ready to run?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.textPrimary, letterSpacing: -0.3)),
        const SizedBox(height: 16),
        _buildWelcomeTip('Tap Start to begin'),
        const SizedBox(height: 8),
        _buildWelcomeTip('We\'ll track your route'),
        const SizedBox(height: 8),
        _buildWelcomeTip('Pause anytime you need'),
        if (_targetPaceRange != null && RevenueCatService.isProNotifier.value) ...[
          const SizedBox(height: 16),
          Container(height: 1, color: c.divider),
          const SizedBox(height: 16),
          _buildWelcomeTip('Today\'s target: ${PaceComparator.formatRange(_targetPaceRange!)}'),
        ],
      ]),
    ));
  }

  Widget _buildWelcomeTip(String text) {
    final c = context.colors;
    return Row(children: [
      Container(width: 4, height: 4, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4))),
    ]);
  }

  Widget _buildStatsCard() {
    final isActive = _runState != RunState.ready;
    final isWarmupOrCooldown = _currentPhase != RunMode.mainSet;
    final showPaceIndicator = _currentPhase == RunMode.mainSet && isActive;

    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        if (_runState == RunState.paused) Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(border: Border.all(color: c.textPrimary), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: BoxDecoration(color: c.textPrimary, shape: BoxShape.circle)), const SizedBox(width: 8), Text('PAUSED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textPrimary, letterSpacing: 1))])),
        if (_runState == RunState.running && _isGPSSignalLost) Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD32F2F)), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle)), const SizedBox(width: 8), const Text('GPS LOST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD32F2F), letterSpacing: 1))])),
        if (isActive) ...[
          Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _phaseColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: _phaseColor.withOpacity(0.25))), child: Text(_phaseName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _phaseColor, letterSpacing: 1.1)))]),
          const SizedBox(height: 14),
        ],
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isWarmupOrCooldown ? 'COUNTDOWN' : 'TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.textTertiary, letterSpacing: 0.8)), const SizedBox(height: 6), Text(isWarmupOrCooldown && isActive ? _formatTime(_phaseCountdownSeconds) : _formatTime(_seconds), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: isWarmupOrCooldown && isActive && _phaseCountdownSeconds == 0 ? const Color(0xFF388E3C) : c.textPrimary, letterSpacing: -0.3, fontFeatures: const [FontFeature.tabularFigures()]))])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('DISTANCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.textTertiary, letterSpacing: 0.8)), const SizedBox(height: 6), Text(isActive ? _buildDistanceText() : '0.00 ${_getDistanceLabel()}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary, letterSpacing: -0.3, fontFeatures: const [FontFeature.tabularFigures()]))])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isWarmupOrCooldown ? 'FREE PACE' : 'PACE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.textTertiary, letterSpacing: 0.8)), const SizedBox(height: 6), Text('${_displayPace(_paceSnapshot.currentPaceSecondsPerKm)}${UnitUtils.perUnitLabel(_distanceUnit == 'miles')}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _paceSnapshot.isStale ? c.textTertiary : c.textPrimary, letterSpacing: -0.3, fontFeatures: const [FontFeature.tabularFigures()]))])),
        ]),
        if (showPaceIndicator) ...[const SizedBox(height: 14), Container(height: 1, color: c.divider), const SizedBox(height: 14), TargetPaceIndicator(currentPaceSecondsPerKm: _paceSnapshot.smoothedPaceSecondsPerKm, targetRange: _targetPaceRange)],
        if (_phaseMilestoneReached && isActive) ...[const SizedBox(height: 14), Container(height: 1, color: c.divider), const SizedBox(height: 14), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: const Color(0xFF388E3C).withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF388E3C).withOpacity(0.25))), child: Row(children: [const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF388E3C)), const SizedBox(width: 8), Text(_milestoneHint, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF388E3C)))]))],
      ]),
    );
  }

  Future<void> _onWorkoutChosen() async {
    setState(() => _showRunTypeChoice = false);

    if (!RevenueCatService.isProNotifier.value) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      return;
    }

    if (_activeCoachMessage == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No workout today — check back tomorrow.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showPreRunCheck(
      context: context,
      coachMessage: _activeCoachMessage!,
      onProceed: (scaled) async {
        if (!mounted) return;
        final shouldStart = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PreRunBriefingScreen(
              coachMessage: scaled,
              onGoToRun: () {},
              returnOnStart: true,
            ),
          ),
        );
        if (shouldStart == true && mounted) {
          setState(() {
            _activeCoachMessage = scaled;
            _isFreeRun = false;
            _workoutReadyToStart = true;
          });
        }
      },
      onSkip: () {},
    );
  }

  void _onFreeRunChosen() {
    setState(() {
      _isFreeRun = true;
      _showRunTypeChoice = false;
    });
    _startTracking();
  }

  Future<void> _resetToReady() async {
    _timer?.cancel(); _timer = null;
    _positionStream?.cancel(); _positionStream = null;
    _gpsMonitorTimer?.cancel(); _gpsMonitorTimer = null;
    _stopGpsWarmup();
    await _stopForegroundTask();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('run_start_time');
      await prefs.remove('background_elapsed_seconds');
      await prefs.remove('run_distance_meters');
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _runState = RunState.ready;
      _seconds = 0;
      _distance = 0.0;
      _pendingDistance = 0.0;
      _routePoints.clear();
      _currentPhase = RunMode.warmup;
      _mainPhaseStartSeconds = 0;
      _mainPhaseStartDistanceM = 0.0;
      _cooldownPhaseStartSeconds = 0;
      _cooldownPhaseStartDistanceM = 0.0;
      _phaseMilestoneReached = false;
      _capturedMainDistanceM = 0.0;
      _capturedMainSeconds = 0;
      _capturedMainPace = '--:--';
      _capturedMainRoute = [];
      _elevationGainM = 0.0;
      _lastAltitudeForGain = null;
      _splits.clear();
      _lastSplitKm = 0;
      _isFreeRun = false;
      _showRunTypeChoice = false;
      _workoutReadyToStart = false;
      _lastAnnouncedKm = 0;
      _isGPSSignalLost = false;
      _activeCoachMessage = widget.activeCoachMessage;
    });

    _startGpsWarmup();
  }

  Future<void> _onFinishTapped() async {
    final mainDistanceM = _currentPhase == RunMode.mainSet
        ? _distance - _mainPhaseStartDistanceM
        : _capturedMainDistanceM;

    if (mainDistanceM < 80) {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Run too short', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Text('You need at least 80m to save a run.', style: TextStyle(fontSize: 14, color: context.colors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'resume'),
              child: Text('Keep running', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      if (result == 'resume' && mounted) {
        _resumeTracking();
      } else if (result == 'discard' && mounted) {
        await Analytics.workoutDiscarded();
        await _resetToReady();
      }
      return;
    }

    await _finishRun();
  }

  Widget _buildRunTypeButton(String label, VoidCallback onPressed, {bool outlined = false}) {
    return SizedBox(
      width: 140,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: outlined ? context.colors.surface : context.colors.accent,
          foregroundColor: outlined ? context.colors.textPrimary : context.colors.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: outlined ? BorderSide(color: context.colors.border) : BorderSide.none,
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ),
    );
  }

  Widget _buildActionButtons() {
    switch (_runState) {
      case RunState.ready:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: _showRunTypeChoice
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildRunTypeButton('Workout', _onWorkoutChosen),
                          const SizedBox(height: 8),
                          _buildRunTypeButton('Free Run', _onFreeRunChosen, outlined: true),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _permissionStatus == PermissionStatus.granted
                    ? () {
                        if (_workoutReadyToStart) {
                          _startTracking();
                        } else {
                          setState(() => _showRunTypeChoice = !_showRunTypeChoice);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _permissionStatus == PermissionStatus.granted ? context.colors.accent : context.colors.textFaint,
                  foregroundColor: context.colors.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Start', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ),
            ),
          ],
        );
      case RunState.running:
        return SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _pauseTracking, style: ElevatedButton.styleFrom(backgroundColor: context.colors.accent, foregroundColor: context.colors.onAccent, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Pause', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5))));
      case RunState.paused:
        return Row(children: [
          Expanded(child: ElevatedButton(onPressed: _resumeTracking, style: ElevatedButton.styleFrom(backgroundColor: context.colors.accent, foregroundColor: context.colors.onAccent, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Resume', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)))),
          const SizedBox(width: 12),
          Expanded(child: _isLastPhase
            ? ElevatedButton(onPressed: _onFinishTapped, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Finish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)))
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