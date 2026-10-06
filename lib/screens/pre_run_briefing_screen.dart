import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/coach_message_builder.dart' as message;
import '../engines/config/workout_template_library.dart';
import '../engines/daily/weather_scaler.dart';
import '../engines/plan/materialized_plan.dart' show DayCompletion;
import '../engines/plan/plan_store.dart';
import '../models/activity_telemetry.dart' show ActivityDetail;
import '../services/analytics_service.dart' show Analytics;
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';
import '../utils/workout_type_style.dart' show dayColorForIntent;
import '../widgets/ambient_scaffold.dart';
import '../widgets/workout_step_timeline.dart' show StepPaceBand;
import '../models/scheduled_workout_context.dart';
import 'activity_detail_screen.dart';
import 'calendar_day_status.dart';
import 'run_screen.dart';
import '../services/athlete_pace_zones.dart';
import '../services/athlete_physiology.dart';
import '../utils/unit_utils.dart';

enum BlockState { pending, done }

/// Exact blue of the primary Start Workout/Start Run CTA — Warmup and
/// Cooldown step cards match it precisely so those two "bookend" steps read
/// as one visual family with the action that starts the whole session.
// Kept: brand blue of the Start CTA; no matching semantic token.
const _kStartBlue = Color(0xFF007AFF);

// ── Chasing-dash cloud loader ────────────────────────────────────────────────

/// An upright cloud outline whose contour is drawn as a dashed stroke that
/// continuously marches around the perimeter ("chasing dash" / marching
/// ants) — the cloud silhouette itself never moves or rotates.
class _ChasingDashCloud extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _ChasingDashCloud({required this.animation, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => CustomPaint(
        painter: _ChasingDashCloudPainter(
          progress: animation.value,
          color: color,
        ),
      ),
    );
  }
}

class _ChasingDashCloudPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _ChasingDashCloudPainter({required this.progress, required this.color});

  static const _dashLength = 5.0;
  static const _gapLength = 4.5;

  @override
  void paint(Canvas canvas, Size size) {
    final cloudPath = _buildCloudPath(size);
    // One full dash+gap pattern length of travel per animation loop —
    // `progress` runs 0→1 on repeat, so the phase at 1.0 lands exactly back
    // on the phase at 0.0 (mod pattern length), giving a seamless loop with
    // no visible jump/reset.
    final patternLength = _dashLength + _gapLength;
    final phase = progress * patternLength * 2;
    final dashed = _dashedPath(cloudPath, _dashLength, _gapLength, phase);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _ChasingDashCloudPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// A simple rounded cloud silhouette: a pill-shaped base with three
/// overlapping circular bumps unioned on top, built with `Path.combine` so
/// the result is a single clean outline rather than overlapping strokes.
Path _buildCloudPath(Size size) {
  final w = size.width;
  final h = size.height;

  final base = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, h * 0.46, w * 0.88, h * 0.46),
        Radius.circular(h * 0.23),
      ),
    );

  final bumps = <Offset, double>{
    Offset(w * 0.27, h * 0.46): h * 0.30,
    Offset(w * 0.50, h * 0.34): h * 0.36,
    Offset(w * 0.72, h * 0.46): h * 0.30,
  };

  var path = base;
  for (final entry in bumps.entries) {
    final bump = Path()
      ..addOval(Rect.fromCircle(center: entry.key, radius: entry.value));
    path = Path.combine(PathOperation.union, path, bump);
  }
  return path;
}

/// Walks every contour of [source] and rebuilds it as alternating dash/gap
/// segments offset by [phase], so animating [phase] over time produces a
/// continuous "marching ants" effect along the outline.
Path _dashedPath(
  Path source,
  double dashLength,
  double gapLength,
  double phase,
) {
  final dashPath = Path();
  final patternLength = dashLength + gapLength;

  for (final metric in source.computeMetrics()) {
    final total = metric.length;
    var distance = phase % patternLength;
    if (distance < 0) distance += patternLength;

    var start = -distance;
    while (start < total) {
      final end = start + dashLength;
      final clampedStart = start.clamp(0.0, total);
      final clampedEnd = end.clamp(0.0, total);
      if (clampedEnd > clampedStart) {
        dashPath.addPath(
          metric.extractPath(clampedStart, clampedEnd),
          Offset.zero,
        );
      }
      start += patternLength;
    }
  }
  return dashPath;
}

class PreRunBriefingScreen extends StatefulWidget {
  final message.CoachMessage coachMessage;
  final VoidCallback onGoToRun;
  final bool returnOnStart;

  /// The plan slot this briefing is for — known for any previewed plan day
  /// (not just today), which is what "Link Activity" / "Skip Workout" act
  /// on. [RunScreen] only actually auto-links the *new* run against it when
  /// the day being previewed is genuinely today (see [_startWorkout]) — you
  /// can't retroactively or pre-emptively complete a different day by
  /// running now. Null when the run is fully ad-hoc (no plan day to attach
  /// to), which also hides the Link/Skip actions.
  final ScheduledWorkoutContext? scheduledContext;

  /// Called after "Link Activity" or "Skip Workout" successfully mutates the
  /// stored plan, so the screen that pushed this one can reload its state.
  final VoidCallback? onPlanChanged;

  /// How this plan day currently reads on the calendar — completed, skipped,
  /// missed, or upcoming (see [calendarDayStatus]). Null means "not a plan
  /// day at all" (an ad-hoc/free-run briefing), which renders identically to
  /// [CalendarDayStatus.upcoming]. Drives which action buttons and header
  /// badge this screen shows; callers already compute this for their day
  /// strips, so it's threaded straight through rather than re-derived here.
  final CalendarDayStatus? dayStatus;

  /// The logged-run stats for this day, present only when [dayStatus] is
  /// [CalendarDayStatus.completed] — backs the "✓ Completed · X km logged"
  /// header chip and the "View Activity" action.
  final DayCompletion? completion;

  const PreRunBriefingScreen({
    super.key,
    required this.coachMessage,
    required this.onGoToRun,
    this.returnOnStart = false,
    this.scheduledContext,
    this.onPlanChanged,
    this.dayStatus,
    this.completion,
  });

  @override
  State<PreRunBriefingScreen> createState() => _PreRunBriefingScreenState();
}

class _PreRunBriefingScreenState extends State<PreRunBriefingScreen>
    with SingleTickerProviderStateMixin {
  bool _useMiles = UnitUtils.useMilesNotifier.value;

  /// Drives the chasing-dash outline animation on the cloud icon shown while
  /// the weather card is loading — the cloud body stays upright; only the
  /// dashes marching around its contour move.
  late final AnimationController _cloudDashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  // ── Weather-adjusted pacing ────────────────────────────────────────────
  WeatherSnapshot? _weather;
  bool _weatherLoading = true;
  bool _weatherPacingEnabled = false;
  static const _weatherScaler = WeatherScaler();

  /// Reverse-geocoded "City, Region" — null (never blocks the weather card
  /// itself) while resolving or on any failure, in which case the card shows
  /// a generic "Current Location" label instead.
  String? _locationLabel;

  // ── Link / Skip busy state ───────────────────────────────────────────────
  bool _busy = false;

  bool get _canLinkOrSkip => widget.scheduledContext != null;

  bool get _isCompleted => widget.dayStatus == CalendarDayStatus.completed;
  bool get _isSkipped => widget.dayStatus == CalendarDayStatus.skipped;

  /// The workout actually shown below — weather-eased when the toggle is on
  /// and a snapshot is available, otherwise the plan's own resolved workout.
  ResolvedWorkout get _displayedWorkout {
    final weather = _weather;
    if (!_weatherPacingEnabled || weather == null) {
      return widget.coachMessage.resolvedWorkout;
    }
    return _weatherScaler.scale(widget.coachMessage.resolvedWorkout, weather).workout;
  }

  @override
  void initState() {
    super.initState();
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
    _loadWeather();
    // Fire-and-forget, independent of the weather fetch — geocoding is
    // purely decorative and must never hold up the weather card (or the
    // first frame) while it resolves.
    _loadLocationLabel();
  }

  Future<void> _loadWeather() async {
    final weather = await WeatherService.getCurrentWeather();
    if (!mounted) return;
    setState(() {
      _weather = weather;
      _weatherLoading = false;
      // Default the easing on when it's meaningful (≥2%); the user can
      // still switch it off.
      if (weather != null && _weatherScaler.slowdownPercent(weather) >= 2) {
        _weatherPacingEnabled = true;
      }
    });
  }

  Future<void> _loadLocationLabel() async {
    final label = await LocationService.getCurrentLocationLabel();
    if (!mounted || label == null) return;
    setState(() => _locationLabel = label);
  }

  void _onUnitPrefChanged() {
    if (mounted) setState(() => _useMiles = UnitUtils.useMilesNotifier.value);
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    _cloudDashController.dispose();
    super.dispose();
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// A copy of [m] with [workout] swapped in — used to carry the
  /// weather-eased paces into the live run when the toggle is on. Mirrors the
  /// same rebuild pre_run_check.dart already does for its own weather step.
  message.CoachMessage _withWorkout(
    message.CoachMessage m,
    ResolvedWorkout workout,
  ) => message.CoachMessage(
    reflectionText: m.reflectionText,
    acknowledgementText: m.acknowledgementText,
    workoutTitle: m.workoutTitle,
    workoutSteps: m.workoutSteps,
    resolvedWorkout: workout,
    workoutIntent: m.workoutIntent,
    goalText: m.goalText,
    feelText: m.feelText,
    phaseLabel: m.phaseLabel,
    weekNumber: m.weekNumber,
    movedFromDay: m.movedFromDay,
    nextPlannedIntent: m.nextPlannedIntent,
    nextPlannedLabel: m.nextPlannedLabel,
  );

  void _startWorkout() {
    final weather = _weather;
    final effectiveMessage = (_weatherPacingEnabled && weather != null)
        ? _withWorkout(widget.coachMessage, _displayedWorkout)
        : widget.coachMessage;

    if (widget.returnOnStart) {
      // Hand back the (possibly weather-eased) message so the caller starts
      // the run with the paces the user actually saw.
      Navigator.pop(context, effectiveMessage);
      return;
    }

    // Only forward the scheduled-day link when this briefing is genuinely
    // for today — previewing a different day and starting a run now must
    // not silently complete that other day.
    final sched = widget.scheduledContext;
    final isScheduledToday =
        sched != null && _isSameDate(sched.scheduledDate, DateTime.now());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunScreen(
          activeCoachMessage: effectiveMessage,
          onWorkoutCompleted: widget.onGoToRun,
          scheduledContext: isScheduledToday ? sched : null,
        ),
      ),
    );
  }

  /// The primary button's label — only reached for the non-completed
  /// (upcoming/skipped/missed) branch of [_buildFloatingActions], since a
  /// completed day swaps the whole button for an outlined "Run Again".
  String get _primaryLabel {
    if (_isSkipped) return 'Run Anyway';
    return widget.coachMessage.hasWarmupCooldown ? 'Start Workout' : 'Start Run';
  }

  // ── Link Activity ─────────────────────────────────────────────────────

  int? _parsePaceSeconds(String pace) {
    final parts = pace.split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m == null || s == null) return null;
    return m * 60 + s;
  }

  Future<void> _openLinkActivitySheet() async {
    final sched = widget.scheduledContext;
    if (sched == null || _busy) return;

    final runs = await DatabaseService.instance.getUnlinkedRuns();
    if (!mounted) return;

    final picked = await showModalBottomSheet<RunRecord>(
      context: context,
      backgroundColor: context.colors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _LinkActivitySheet(runs: runs, useMiles: _useMiles),
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    final ok = await PlanStore.instance.markDayCompleted(
      weekNumber: sched.weekNumber,
      weekday: sched.weekday,
      actualKm: picked.distanceKm,
      actualPaceSecPerKm: _parsePaceSeconds(picked.averagePace),
      rpe: picked.rpe?.toDouble(),
      runId: picked.id?.toString(),
      completedAt: picked.date,
    );
    if (ok && picked.id != null) {
      await DatabaseService.instance.updateRunScheduledDayId(
        picked.id!,
        sched.dayId,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Analytics.capture(
        'activity_linked_to_workout',
        properties: {'week': sched.weekNumber, 'weekday': sched.weekday},
      );
      widget.onPlanChanged?.call();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not link — this day is already completed.'),
        ),
      );
    }
  }

  // ── View Activity (completed + linked to a run) ───────────────────────

  Future<void> _openLinkedActivity() async {
    final runId = int.tryParse(widget.completion?.runId ?? '');
    if (runId == null || _busy) return;

    final record = await DatabaseService.instance.getRunById(runId);
    if (!mounted || record == null) return;
    final maxHr = await AthletePhysiology.instance.resolveMaxHr();
    final paceZones = await AthletePaceZones.instance.resolve();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityDetailScreen(
          activity: ActivityDetail.fromRunRecord(
            record,
            runnerName: 'You',
            maxHr: maxHr,
            paceZoneConfig: paceZones,
          ),
        ),
      ),
    );
  }

  // ── Skip Workout ─────────────────────────────────────────────────────

  Future<void> _confirmSkip() async {
    final sched = widget.scheduledContext;
    if (sched == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Skip this workout?',
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'This will mark today\'s session as skipped.',
            style: TextStyle(color: c.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Skip',
                style: TextStyle(color: c.danger, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await PlanStore.instance.markDaySkipped(
      weekNumber: sched.weekNumber,
      weekday: sched.weekday,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Analytics.capture(
        'workout_skipped',
        properties: {'week': sched.weekNumber, 'weekday': sched.weekday},
      );
      widget.onPlanChanged?.call();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not skip — already completed or skipped.'),
        ),
      );
    }
  }

  // ── Weather card ─────────────────────────────────────────────────────

  // Tiers follow the temp + dew point table bands: ≤2% low, ≤4.5% moderate.
  (int, String, Color) _impactTier(double percent, AppColors c) {
    if (percent < 0.5) return (1, 'No Impact', c.success);
    if (percent <= 2) return (2, 'Low Impact', c.success);
    if (percent <= 4.5) return (3, 'Moderate Impact', c.premiumGold);
    return (4, 'Significant Impact', c.danger);
  }

  /// Seconds (per km or per mile, matching the unit toggle) the slowdown adds
  /// to the first main block's pace *as the step list displays it* — pace
  /// rounded to 5s in km, then converted — so the card and the steps always
  /// show the same change. Null when the workout has no pace target.
  int? _weatherDeltaSeconds(WeatherSnapshot weather) {
    final original = widget.coachMessage.resolvedWorkout;
    final adjusted = _weatherScaler.scale(original, weather).workout;
    for (var i = 0; i < original.blocks.length; i++) {
      final b = original.blocks[i];
      if (b.type != BlockType.main || b.isRpeOnly) continue;
      int shown(int secPerKm) => UnitUtils.displayPaceSeconds(
        ((secPerKm / 5).round() * 5).toDouble(),
        _useMiles,
      ).round();
      return shown(adjusted.blocks[i].paceMinSecondsPerKm) -
          shown(b.paceMinSecondsPerKm);
    }
    return null;
  }

  Widget _buildWeatherCard() {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _weatherLoading
          ? _buildWeatherLoadingCard(c)
          : (_weather == null
                ? const SizedBox.shrink(key: ValueKey('weather-hidden'))
                : _buildWeatherContentCard(c, textTheme, _weather!)),
    );
  }

  /// Shown the instant the screen mounts, before GPS/network resolve — a
  /// spinning cloud so the card never appears to "pop in" late.
  Widget _buildWeatherLoadingCard(AppColors c) {
    return Padding(
      key: const ValueKey('weather-loading'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border, width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 26,
              child: _ChasingDashCloud(
                animation: _cloudDashController,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Checking conditions…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherContentCard(
    AppColors c,
    TextTheme textTheme,
    WeatherSnapshot weather,
  ) {
    final percent = _weatherScaler.slowdownPercent(weather);
    final deltaSec = _weatherDeltaSeconds(weather);
    final (tier, tierLabel, tierColor) = _impactTier(percent, c);
    final markerFraction = (percent.clamp(0, 10) / 10).toDouble();
    final icon = switch (weather.condition) {
      WeatherCondition.clear => Icons.wb_sunny_outlined,
      WeatherCondition.cloudy => Icons.cloud_outlined,
      WeatherCondition.rain => Icons.water_drop_outlined,
      WeatherCondition.snow => Icons.ac_unit,
      WeatherCondition.fog => Icons.foggy,
    };
    final conditionLabel = switch (weather.condition) {
      WeatherCondition.clear => 'Clear',
      WeatherCondition.cloudy => 'Partly cloudy',
      WeatherCondition.rain => 'Rainy',
      WeatherCondition.snow => 'Snowy',
      WeatherCondition.fog => 'Foggy',
    };

    return Padding(
      key: const ValueKey('weather-content'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border, width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: c.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${weather.tempC.round()}°',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            conditionLabel,
                            style: textTheme.bodySmall?.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Feels like ${weather.apparentTempC.round()}° · ${_locationLabel ?? 'Current Location'}',
                        style: textTheme.bodySmall?.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 14,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.success, c.premiumGold, c.danger],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(-1 + 2 * markerFraction, 0),
                    child: Container(
                      width: 2,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enable Weather Adjusted Pacing',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        percent >= 0.5
                            ? '+${percent.toStringAsFixed(1)}%${deltaSec != null ? ' (+${deltaSec}s${UnitUtils.perUnitLabel(_useMiles)})' : ''} · Tier $tier: $tierLabel'
                            : 'No adjustment needed · Tier $tier: $tierLabel',
                        style: textTheme.bodySmall?.copyWith(
                          color: tierColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _weatherPacingEnabled,
                  onChanged: percent >= 0.5
                      ? (v) => setState(() => _weatherPacingEnabled = v)
                      : null,
                  activeThumbColor: c.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  String _subtitle() {
    final date = widget.scheduledContext?.scheduledDate ?? DateTime.now();
    final dateStr = DateFormat('MMMM d, yyyy').format(date);
    final dist = UnitUtils.displayDistance(_displayedWorkout.totalDistanceKm, _useMiles);
    final unit = _useMiles ? 'miles' : 'kilometers';
    return '$dateStr · ${dist.toStringAsFixed(1)} $unit total';
  }

  /// The green "✓ Completed" / muted "Skipped" pill shown under the subtitle.
  /// Only called when [_isCompleted] or [_isSkipped] is true.
  Widget _buildStatusChip(AppColors c) {
    if (_isCompleted) {
      final km = widget.completion?.actualKm;
      final loggedText = (km != null && km > 0)
          ? ' · ${UnitUtils.displayDistance(km, _useMiles).toStringAsFixed(2)} ${UnitUtils.unitLabel(_useMiles)} logged'
          : '';
      return _StatusChip(
        icon: Icons.check_circle_rounded,
        label: 'Completed$loggedText',
        color: c.success,
        background: c.success.withValues(alpha: 0.12),
        border: c.success.withValues(alpha: 0.4),
      );
    }
    return _StatusChip(
      icon: Icons.skip_next_rounded,
      label: 'Skipped',
      color: c.textTertiary,
    );
  }

  /// A soft top-of-screen wash tinted by the workout's training intent,
  /// layered above [AmbientScaffold]'s own shared background nodes — resolves
  /// through [dayColorForIntent] so it tracks the same tokens as every other
  /// intent/interval accent on this screen instead of a one-off hex value.
  Widget _buildAmbientGlow(Color intentColor) {
    return IgnorePointer(
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.1,
            colors: [
              intentColor.withValues(alpha: 0.30),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  /// The Link/View → Start/Run Again → Skip action stack — deliberately laid
  /// out as the last thing in the scrollable content (not a floating/sticky
  /// bar) so reaching a CTA means having scrolled past the full workout
  /// prescription first.
  Widget _buildActionButtons(AppColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Secondary slot: Link Activity (upcoming/skipped) or View
        // Activity (completed + actually linked to a run) ──────────────────
        if (_isCompleted) ...[
          if (widget.completion?.runId != null) ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: _busy ? null : _openLinkedActivity,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'View Activity',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ] else if (_canLinkOrSkip) ...[
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: _busy ? null : _openLinkActivitySheet,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textPrimary,
                side: BorderSide(color: c.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Link Activity',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Primary slot: outlined "Run Again" once completed, otherwise
        // the solid Start/Run Anyway pill ───────────────────────────────────
        if (_isCompleted)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _busy ? null : _startWorkout,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textPrimary,
                side: BorderSide(color: c.accent, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Run Again',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          )
        else
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _busy ? 0.5 : 1,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _startWorkout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kStartBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kStartBlue.withValues(alpha: 0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  _primaryLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          ),

        // Skip Workout only makes sense for a day that hasn't already been
        // resolved one way or the other.
        if (_canLinkOrSkip && !_isSkipped && !_isCompleted) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : _confirmSkip,
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text(
              'Skip Workout',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final workout = _displayedWorkout;
    final c = context.colors;
    final intentColor = dayColorForIntent(context, widget.coachMessage.workoutIntent);

    return AmbientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildAmbientGlow(intentColor),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(
              top: 4,
              bottom: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: title + subtitle (centered) ───────────────────
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        widget.coachMessage.workoutTitle.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitle(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.textSecondary,
                        ),
                      ),
                      if (_isCompleted || _isSkipped) ...[
                        const SizedBox(height: 10),
                        _buildStatusChip(c),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Weather-adjusted pacing card ─────────────────────────
                // Hidden once the run is done — the pacing toggle has
                // nothing left to adjust after the fact.
                if (!_isCompleted) _buildWeatherCard(),

                // ── Step breakdown cards ──────────────────────────────────
                _buildStepCards(workout),

                // Deliberate scroll-to-reach gap — the CTAs sit at the very
                // end of the content stream, not pinned/floating, so getting
                // to "Start" means scrolling past the whole prescription.
                const SizedBox(height: 48),
                _buildActionButtons(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCards(ResolvedWorkout workout) {
    final blocks = workout.blocks;
    if (blocks.isEmpty) {
      return Text(
        'Full rest day — nothing scheduled.',
        style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
      );
    }
    return Column(
      children: [
        for (final block in blocks)
          _StepCard(
            block: block,
            intent: workout.intent,
            useMiles: _useMiles,
          ),
      ],
    );
  }
}

// ── Status chip ──────────────────────────────────────────────────────────────

/// The small pill under the header subtitle for a completed or skipped day.
/// [background]/[border] default to a soft tint of [color] (the skipped
/// chip's plain style); pass them explicitly for a chip that needs its own
/// fixed palette regardless of [color] (the completed chip's muted emerald).
class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? background;
  final Color? border;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.background,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.14),
        border: border != null ? Border.all(color: border!, width: 1) : null,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step breakdown card ──────────────────────────────────────────────────────

/// A single workout step rendered as a two-part card: a solid accent header
/// band (step name + total distance/duration) over a dark body with the
/// per-rep pace/effort prescription and any between-rep recovery cue.
class _StepCard extends StatelessWidget {
  final ResolvedBlock block;
  final WorkoutIntent intent;
  final bool useMiles;

  const _StepCard({
    required this.block,
    required this.intent,
    required this.useMiles,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final band = StepPaceBand.forBlock(block, intent, useMiles: useMiles);
    final headerColor = _headerColor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _title(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  _headerQuantity(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(
                left: BorderSide(color: c.border, width: 1),
                right: BorderSide(color: c.border, width: 1),
                bottom: BorderSide(color: c.border, width: 1),
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: headerColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.directions_run_rounded,
                        size: 14,
                        color: headerColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _primaryLine(band),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_recoveryLine() != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: Text(
                      _recoveryLine()!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Derived text ──────────────────────────────────────────────────────────

  /// Warmup and Cooldown always read as [_kStartBlue] — the same exact blue
  /// as the primary Start button, so those two bookend steps visually pair
  /// with the action that kicks the session off. Recovery keeps the muted
  /// "easy" token; main-set blocks resolve dynamically through
  /// [dayColorForIntent] so they stay in lockstep with every other
  /// intent/interval accent in the app.
  Color _headerColor(BuildContext context) {
    final c = context.colors;
    switch (block.type) {
      case BlockType.warmup:
      case BlockType.cooldown:
        return _kStartBlue;
      case BlockType.recovery:
        return c.workoutEasy;
      case BlockType.main:
        return dayColorForIntent(context, intent);
    }
  }

  String _title() {
    switch (block.type) {
      case BlockType.warmup:
        return 'Warmup';
      case BlockType.cooldown:
        return 'Cooldown';
      case BlockType.recovery:
        return 'Recovery';
      case BlockType.main:
        if (block.isRpeOnly && intent == WorkoutIntent.speed) return 'Strides';
        if ((block.reps ?? 1) > 1) {
          return intent == WorkoutIntent.threshold
              ? 'Cruise Interval'
              : 'Interval';
        }
        return switch (intent) {
          WorkoutIntent.threshold => 'Tempo',
          WorkoutIntent.vo2max => 'Interval',
          WorkoutIntent.speed => 'Reps',
          WorkoutIntent.raceSpecific => 'Race Pace',
          WorkoutIntent.endurance => 'Long Run',
          WorkoutIntent.aerobicBase => 'Easy Run',
        };
    }
  }

  String _headerQuantity() {
    if (block.durationSeconds != null) {
      final total = block.durationSeconds! * (block.reps ?? 1);
      return total >= 60 && total % 60 == 0
          ? '${total ~/ 60} min'
          : '${total}s';
    }
    return _fmtDistance(block.totalDistanceKm);
  }

  String _eachQuantity() {
    if (block.durationSeconds != null) {
      final s = block.durationSeconds!;
      return s >= 60 && s % 60 == 0 ? '${s ~/ 60} min' : '${s}s';
    }
    return _fmtDistance(block.distanceKm);
  }

  String _fmtDistance(double km) {
    if (km < 1.0) return '${(km * 1000).round()} m';
    final d = UnitUtils.displayDistance(km, useMiles);
    return '${d.toStringAsFixed(d >= 10 ? 0 : 1)} ${UnitUtils.unitLabel(useMiles)}';
  }

  String _primaryLine(StepPaceBand band) {
    final reps = block.reps ?? 1;
    final each = _eachQuantity();
    final qty = reps > 1 ? '$reps × $each' : each;
    return band.effortOnly ? '$qty — ${band.value}' : '$qty at ${band.value}';
  }

  String? _recoveryLine() {
    if ((block.reps ?? 1) <= 1) return null;
    if (block.recoverySeconds != null) {
      final s = block.recoverySeconds!;
      final txt = s >= 60
          ? '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} min'
          : '${s}s';
      return '$txt jog between reps';
    }
    if (block.recoveryMeters != null) {
      return '${_fmtDistance(block.recoveryMeters! / 1000)} jog between reps';
    }
    return null;
  }
}

// ── Link Activity sheet ─────────────────────────────────────────────────────

/// Lists recent runs with no plan day attached yet — tapping one hands it
/// back to the caller, which links it via [PlanStore.markDayCompleted] +
/// [DatabaseService.updateRunScheduledDayId].
class _LinkActivitySheet extends StatelessWidget {
  final List<RunRecord> runs;
  final bool useMiles;

  const _LinkActivitySheet({required this.runs, required this.useMiles});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Link an activity',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a recent run to count toward this workout.',
              style: textTheme.bodySmall?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: 16),
            if (runs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No recent unlinked runs found.',
                  style: textTheme.bodyMedium?.copyWith(color: c.textTertiary),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: runs.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: c.divider),
                  itemBuilder: (_, i) {
                    final run = runs[i];
                    final dist = UnitUtils.displayDistance(
                      run.distanceKm,
                      useMiles,
                    );
                    final unit = UnitUtils.unitLabel(useMiles);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${dist.toStringAsFixed(1)} $unit',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        DateFormat('EEE, MMM d · h:mm a').format(run.date),
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: c.textTertiary,
                      ),
                      onTap: () => Navigator.of(context).pop(run),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
