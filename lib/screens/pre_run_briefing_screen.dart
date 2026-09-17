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
import '../widgets/workout_step_timeline.dart';
import '../models/scheduled_workout_context.dart';
import 'run_screen.dart';
import '../utils/unit_utils.dart';

enum BlockState { pending, done }

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

class _PreRunBriefingScreenState extends State<PreRunBriefingScreen> {
  bool _useMiles = UnitUtils.useMilesNotifier.value;

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

  (String, Color) _impactTier(int delta, AppColors c) {
    if (delta <= 0) return ('No Impact', c.success);
    if (delta < 15) return ('Low Impact', c.success);
    if (delta < 30) return ('Moderate Impact', c.premiumGold);
    return ('Significant Impact', c.danger);
  }

  Widget _buildWeatherCard() {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;
    if (_weatherLoading) return const SizedBox.shrink();

    final weather = _weather;
    if (weather == null) return const SizedBox.shrink();

    final delta = _weatherScaler.deltaSecondsPerKm(weather);
    final (tierLabel, tierColor) = _impactTier(delta, c);
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
      padding: const EdgeInsets.only(bottom: 8),
      child: _Card(
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
              ],
            ),
            const SizedBox(height: 12),
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
                            ? '+${delta}s/km · $tierLabel'
                            : 'No adjustment needed · $tierLabel',
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

  @override
  Widget build(BuildContext context) {
    final workout = _displayedWorkout;
    final hasCoachContent =
        widget.coachMessage.reflectionText.isNotEmpty ||
        widget.coachMessage.goalText.isNotEmpty ||
        widget.coachMessage.feelText.isNotEmpty;

    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(
          'Today\'s Workout',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
            fontSize: 16,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header card ──────────────────────────────────────────────────
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.coachMessage.phaseWeekLabel.isNotEmpty) ...[
                    _PhaseWeekBanner(label: widget.coachMessage.phaseWeekLabel),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    widget.coachMessage.workoutTitle,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.coachMessage.hasWarmupCooldown
                        ? 'Warmup & cooldown included'
                        : 'Easy effort — no warmup needed',
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                  const SizedBox(height: 14),
                  _buildHeroStats(workout),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Coach card ───────────────────────────────────────────────────
            if (hasCoachContent)
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              'M',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: c.onAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Max',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if (widget.coachMessage.reflectionText.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.coachMessage.reflectionText,
                        style: TextStyle(
                          fontSize: 13,
                          color: c.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (widget.coachMessage.acknowledgementText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.coachMessage.acknowledgementText,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textTertiary,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (widget.coachMessage.goalText.isNotEmpty ||
                        widget.coachMessage.feelText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Divider(height: 1, thickness: 1, color: c.divider),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.coachMessage.goalText.isNotEmpty)
                            Expanded(
                              child: _InsightItem(
                                icon: Icons.flag_outlined,
                                label: 'GOAL',
                                text: widget.coachMessage.goalText,
                                iconColor: const Color(0xFF1565C0),
                              ),
                            ),
                          if (widget.coachMessage.goalText.isNotEmpty &&
                              widget.coachMessage.feelText.isNotEmpty)
                            const SizedBox(width: 16),
                          if (widget.coachMessage.feelText.isNotEmpty)
                            Expanded(
                              child: _InsightItem(
                                icon: Icons.favorite_border,
                                label: 'FEEL',
                                text: widget.coachMessage.feelText,
                                iconColor: const Color(0xFFE53935),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

            if (hasCoachContent) const SizedBox(height: 8),

            // ── Weather-adjusted pacing card ─────────────────────────────────
            _buildWeatherCard(),

            // ── Workout card ─────────────────────────────────────────────────
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WORKOUT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  WorkoutStepTimeline(workout: workout, useMiles: _useMiles),
                ],
              ),
            ),

            if (widget.coachMessage.movedFromDay != null) ...[
              const SizedBox(height: 8),
              _Card(
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 14, color: c.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.coachMessage.workoutTitle} moved from '
                        '${widget.coachMessage.movedFromDay}',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: c.background,
            border: Border(top: BorderSide(color: c.divider, width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                        borderRadius: BorderRadius.circular(14),
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
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    disabledBackgroundColor: c.accent.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStats(ResolvedWorkout workout) {
    final c = context.colors;
    final labels = <String>[];
    final values = <String>[];

    final totalDist = workout.totalDistanceKm;
    if (totalDist > 0) {
      values.add(
        '${UnitUtils.displayDistance(totalDist, _useMiles).toStringAsFixed(1)} ${UnitUtils.unitLabel(_useMiles)}',
      );
      labels.add('DISTANCE');
    }

    final dur = workout.estimatedDuration;
    if (dur.inMinutes > 0) {
      values.add('~${dur.inMinutes} min');
      labels.add('DURATION');
    }

    final workBlocks = workout.blocks.where((b) => b.type == BlockType.main);
    if (workBlocks.isNotEmpty) {
      final nonRpe = workBlocks.where((b) => !b.isRpeOnly);
      if (nonRpe.isNotEmpty) {
        final fastest = nonRpe
            .map((b) => b.paceMinSecondsPerKm)
            .reduce((a, b) => a < b ? a : b);
        final slowest = nonRpe
            .map((b) => b.paceMaxSecondsPerKm)
            .reduce((a, b) => a > b ? a : b);
        final intent = widget.coachMessage.workoutIntent;
        if ((intent == WorkoutIntent.aerobicBase ||
                intent == WorkoutIntent.endurance) &&
            (slowest - fastest) >= 30) {
          final ceiling = (fastest / 5).round() * 5;
          values.add('≤ ${_fmt(ceiling)} ${UnitUtils.perUnitLabel(_useMiles)}');
        } else {
          final lo = (fastest / 5).round() * 5;
          final hi = (slowest / 5).round() * 5;
          values.add(
            lo == hi
                ? '${_fmt(lo)} ${UnitUtils.perUnitLabel(_useMiles)}'
                : '${_fmt(lo)}–${_fmt(hi)} ${UnitUtils.perUnitLabel(_useMiles)}',
          );
        }
        labels.add('PACE');
      }
    }

    if (labels.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (int i = 0; i < labels.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 32, color: c.divider),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  values[i],
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    letterSpacing: -0.3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: c.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _fmt(int secondsPerKm) {
    final displaySeconds = UnitUtils.displayPaceSeconds(
      secondsPerKm.toDouble(),
      _useMiles,
    );
    return UnitUtils.formatSeconds(displaySeconds.round());
  }
}

// ── Shared card wrapper ───────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

// ── Coaching insight item ─────────────────────────────────────────────────────

class _InsightItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color iconColor;

  const _InsightItem({
    required this.icon,
    required this.label,
    required this.text,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: iconColor,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: context.colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

// ── Phase + week banner ───────────────────────────────────────────────────────

class _PhaseWeekBanner extends StatelessWidget {
  final String label;
  const _PhaseWeekBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1565C0),
        ),
      ),
    );
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
