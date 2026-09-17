import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/coach_message_builder.dart' as message;
import '../engines/config/workout_template_library.dart';
import '../engines/daily/weather_scaler.dart';
import '../engines/plan/plan_store.dart';
import '../services/analytics_service.dart' show Analytics;
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';
import '../widgets/workout_step_timeline.dart' show StepPaceBand;
import '../models/scheduled_workout_context.dart';
import 'run_screen.dart';
import '../utils/unit_utils.dart';

enum BlockState { pending, done }

// ── Dynamic ambient palette ─────────────────────────────────────────────────

/// The two-stop wash used for a workout's ambient header glow and its step
/// card accents — chosen by training intent, not by phase/week (those were
/// stripped from this screen).
@immutable
class _WorkoutGlow {
  final Color primary;
  final Color dark;
  const _WorkoutGlow(this.primary, this.dark);
}

_WorkoutGlow _glowForIntent(WorkoutIntent intent) {
  switch (intent) {
    case WorkoutIntent.aerobicBase:
    case WorkoutIntent.endurance:
      return const _WorkoutGlow(Color(0xFF1E50FF), Color(0xFF0D2040));
    case WorkoutIntent.vo2max:
    case WorkoutIntent.speed:
      return const _WorkoutGlow(Color(0xFFFF5500), Color(0xFF4A1500));
    case WorkoutIntent.threshold:
    case WorkoutIntent.raceSpecific:
      return const _WorkoutGlow(Color(0xFFFFC107), Color(0xFF4A3500));
  }
}

const _kCardBg = Color(0xFF12161F);
const _kCardBorder = Color(0xFF1E2535);
const _kStepBodyBg = Color(0xFF141923);
const _kPrimaryBlue = Color(0xFF007AFF);
const _kDangerRed = Color(0xFFFF3B30);
const _kWarmupBlue = Color(0xFF1E50FF);

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

  const PreRunBriefingScreen({
    super.key,
    required this.coachMessage,
    required this.onGoToRun,
    this.returnOnStart = false,
    this.scheduledContext,
    this.onPlanChanged,
  });

  @override
  State<PreRunBriefingScreen> createState() => _PreRunBriefingScreenState();
}

class _PreRunBriefingScreenState extends State<PreRunBriefingScreen>
    with SingleTickerProviderStateMixin {
  bool _useMiles = UnitUtils.useMilesNotifier.value;

  /// Drives the rotating cloud icon shown while the weather card is loading.
  late final AnimationController _cloudSpinController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
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
    _cloudSpinController.dispose();
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
    if (widget.returnOnStart) {
      Navigator.pop(context, true);
      return;
    }
    final weather = _weather;
    final effectiveMessage = (_weatherPacingEnabled && weather != null)
        ? _withWorkout(widget.coachMessage, _displayedWorkout)
        : widget.coachMessage;

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

  (int, String, Color) _impactTier(int delta, AppColors c) {
    if (delta <= 0) return (1, 'No Impact', c.success);
    if (delta < 15) return (2, 'Low Impact', c.success);
    if (delta < 30) return (3, 'Moderate Impact', c.premiumGold);
    return (4, 'Significant Impact', c.danger);
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
          color: _kCardBg,
          border: Border.all(color: _kCardBorder, width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            RotationTransition(
              turns: _cloudSpinController,
              child: Icon(
                Icons.cloud_queue_rounded,
                size: 28,
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
    final delta = _weatherScaler.deltaSecondsPerKm(weather);
    final (tier, tierLabel, tierColor) = _impactTier(delta, c);
    final markerFraction = (delta.clamp(0, 40) / 40).toDouble();
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
          color: _kCardBg,
          border: Border.all(color: _kCardBorder, width: 1),
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
                        delta > 0
                            ? '+${delta}s/km · Tier $tier: $tierLabel'
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
                  onChanged: delta > 0
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

  Widget _buildAmbientGlow(_WorkoutGlow glow) {
    return IgnorePointer(
      child: Container(
        height: 300,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.1,
            colors: [
              glow.primary.withValues(alpha: 0.32),
              glow.dark.withValues(alpha: 0.18),
              Colors.transparent,
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workout = _displayedWorkout;
    final c = context.colors;
    final glow = _glowForIntent(widget.coachMessage.workoutIntent);

    return Scaffold(
      backgroundColor: c.background,
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
          Positioned(top: 0, left: 0, right: 0, child: _buildAmbientGlow(glow)),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(
              top: 4,
              bottom: 24,
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
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Weather-adjusted pacing card ─────────────────────────
                _buildWeatherCard(),

                // ── Step breakdown cards ──────────────────────────────────
                _buildStepCards(workout),

                const SizedBox(height: 24),

                // ── Actions ────────────────────────────────────────────────
                if (_canLinkOrSkip) ...[
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
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _startWorkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimaryBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kPrimaryBlue.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      widget.coachMessage.hasWarmupCooldown
                          ? 'Start Workout'
                          : 'Start Run',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
                if (_canLinkOrSkip) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : _confirmSkip,
                      style: TextButton.styleFrom(foregroundColor: _kDangerRed),
                      child: const Text(
                        'Skip Workout',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
    final band = StepPaceBand.forBlock(block, intent, useMiles: useMiles);
    final headerColor = _headerColor();

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
            decoration: const BoxDecoration(
              color: _kStepBodyBg,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
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
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF4F4F5),
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
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF8A8A8F),
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

  Color _headerColor() {
    if (block.type != BlockType.main) return _kWarmupBlue;
    return _glowForIntent(intent).primary;
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
