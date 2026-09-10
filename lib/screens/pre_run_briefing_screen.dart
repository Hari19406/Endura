import 'package:flutter/material.dart';
import '../services/coach_message_builder.dart' as message;
import '../engines/config/workout_template_library.dart';
import '../theme/app_colors.dart';
import '../widgets/workout_step_timeline.dart';
import 'run_screen.dart';
import '../utils/unit_utils.dart';

enum BlockState { pending, done }

class PreRunBriefingScreen extends StatefulWidget {
  final message.CoachMessage coachMessage;
  final VoidCallback onGoToRun;
  final bool returnOnStart;

  const PreRunBriefingScreen({
    super.key,
    required this.coachMessage,
    required this.onGoToRun,
    this.returnOnStart = false,
  });

  @override
  State<PreRunBriefingScreen> createState() => _PreRunBriefingScreenState();
}

class _PreRunBriefingScreenState extends State<PreRunBriefingScreen> {
  bool _useMiles = UnitUtils.useMilesNotifier.value;

  @override
  void initState() {
    super.initState();
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
  }

  void _onUnitPrefChanged() {
    if (mounted) setState(() => _useMiles = UnitUtils.useMilesNotifier.value);
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    super.dispose();
  }

  void _startWorkout() {
    if (widget.returnOnStart) {
      Navigator.pop(context, true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunScreen(
          activeCoachMessage: widget.coachMessage,
          onWorkoutCompleted: widget.onGoToRun,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workout = widget.coachMessage.resolvedWorkout;
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

                  WorkoutStepTimeline(
                    workout: widget.coachMessage.resolvedWorkout,
                    useMiles: _useMiles,
                  ),
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
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _startWorkout,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
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
