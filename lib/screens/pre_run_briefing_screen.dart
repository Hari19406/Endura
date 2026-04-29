import 'package:flutter/material.dart';
import '../services/coach_message_builder.dart' as message;
import '../engines/config/workout_template_library.dart';
import 'run_screen.dart';

// ── Block completion state ────────────────────────────────────────────────────

enum BlockState { pending, done }

// ── Screen ────────────────────────────────────────────────────────────────────

class PreRunBriefingScreen extends StatefulWidget {
  final message.CoachMessage coachMessage;
  final VoidCallback onGoToRun;

  const PreRunBriefingScreen({
    super.key,
    required this.coachMessage,
    required this.onGoToRun,
  });

  @override
  State<PreRunBriefingScreen> createState() => _PreRunBriefingScreenState();
}

class _PreRunBriefingScreenState extends State<PreRunBriefingScreen> {
  void _startWorkout() {
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

  List<ResolvedBlock> get _warmupBlocks =>
      widget.coachMessage.resolvedWorkout.blocks
          .where((b) => b.type == BlockType.warmup)
          .toList();

  List<ResolvedBlock> get _workBlocks =>
      widget.coachMessage.resolvedWorkout.blocks
          .where((b) => b.type == BlockType.main || b.type == BlockType.recovery)
          .toList();

  List<ResolvedBlock> get _cooldownBlocks =>
      widget.coachMessage.resolvedWorkout.blocks
          .where((b) => b.type == BlockType.cooldown)
          .toList();

  bool get _hasWarmup =>
      widget.coachMessage.hasWarmupCooldown && _warmupBlocks.isNotEmpty;

  bool get _hasCooldown =>
      widget.coachMessage.hasWarmupCooldown && _cooldownBlocks.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final workout = widget.coachMessage.resolvedWorkout;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'Workout Plan',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A0A0A),
            fontSize: 16,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0A0A0A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            if (widget.coachMessage.phaseWeekLabel.isNotEmpty) ...[
              _PhaseWeekBanner(label: widget.coachMessage.phaseWeekLabel),
              const SizedBox(height: 16),
            ],

            Text(
              widget.coachMessage.workoutTitle,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0A0A0A),
                letterSpacing: -0.8,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 5),

            Text(
              widget.coachMessage.hasWarmupCooldown
                  ? 'Warmup and cooldown included — hard efforts need your muscles ready'
                  : 'No warmup needed — this run is at an easy effort',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF999999),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            _buildHeroStats(workout),
            const SizedBox(height: 28),

            const Text(
              'FROM YOUR COACH',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF999999),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.coachMessage.reflectionText,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF444444),
                height: 1.6,
              ),
            ),
            if (widget.coachMessage.acknowledgementText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.coachMessage.acknowledgementText,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF888888),
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                ),
              ),
            ],

            if (widget.coachMessage.goalText.isNotEmpty ||
                widget.coachMessage.feelText.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.coachMessage.goalText.isNotEmpty)
                    Expanded(
                      child: _CoachingInsightCard(
                        icon: Icons.flag_outlined,
                        label: 'GOAL',
                        text: widget.coachMessage.goalText,
                        iconColor: const Color(0xFF1565C0),
                      ),
                    ),
                  if (widget.coachMessage.goalText.isNotEmpty &&
                      widget.coachMessage.feelText.isNotEmpty)
                    const SizedBox(width: 10),
                  if (widget.coachMessage.feelText.isNotEmpty)
                    Expanded(
                      child: _CoachingInsightCard(
                        icon: Icons.favorite_border,
                        label: 'FEEL',
                        text: widget.coachMessage.feelText,
                        iconColor: const Color(0xFFE53935),
                      ),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 32),

            const Text(
              'WORKOUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF999999),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            if (_hasWarmup) ...[
              _WorkoutBlockCard(
                stepNumber: 1,
                label: 'WARMUP',
                blocks: _warmupBlocks,
                accentColor: const Color(0xFF388E3C),
                state: BlockState.pending,
                isWarmupCooldown: true,
                workoutIntent: widget.coachMessage.workoutIntent,
              ),
              const SizedBox(height: 10),
            ],

              _WorkoutBlockCard(
                stepNumber: _hasWarmup ? 2 : 1,
                label: 'MAIN SET',
                blocks: _workBlocks,
                accentColor: const Color(0xFF0A0A0A),
                state: BlockState.pending,
                isMain: true,
                workoutIntent: widget.coachMessage.workoutIntent,
              ),

              if (_hasCooldown) ...[
                const SizedBox(height: 10),
                _WorkoutBlockCard(
                  stepNumber: _hasWarmup ? 3 : 2,
                  label: 'COOLDOWN',
                  blocks: _cooldownBlocks,
                  accentColor: const Color(0xFF1565C0),
                  state: BlockState.pending,
                  isWarmupCooldown: true,
                  workoutIntent: widget.coachMessage.workoutIntent,
                ),
              ],

            const SizedBox(height: 24),

            if (widget.coachMessage.movedFromDay != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8E8E8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF999999)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.coachMessage.workoutTitle} moved from '
                        '${widget.coachMessage.movedFromDay}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── CTA — always enabled ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _startWorkout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A0A0A),
                  foregroundColor: Colors.white,
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
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStats(ResolvedWorkout workout) {
    final labels = <String>[];
    final values = <String>[];

    final totalDist = workout.totalDistanceKm;
    if (totalDist > 0) {
      values.add('${totalDist.toStringAsFixed(1)} km');
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
        final fastest = nonRpe.map((b) => b.paceMinSecondsPerKm).reduce((a, b) => a < b ? a : b);
        final slowest = nonRpe.map((b) => b.paceMaxSecondsPerKm).reduce((a, b) => a > b ? a : b);
        final intent = widget.coachMessage.workoutIntent;
        if ((intent == WorkoutIntent.aerobicBase ||
            intent == WorkoutIntent.recovery ||
            intent == WorkoutIntent.endurance) &&
            (slowest - fastest) >= 30) {
          final ceiling = (fastest / 5).round() * 5;
          values.add('≤ ${_fmt(ceiling)} /km');
        } else {
          final lo = (fastest / 5).round() * 5;
          final hi = (slowest / 5).round() * 5;
          values.add(lo == hi
              ? '${_fmt(lo)} /km'
              : '${_fmt(lo)}–${_fmt(hi)} /km');
        }
        labels.add('PACE');
      }
    }

    if (labels.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 36, color: const Color(0xFFEEEEEE)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    values[i],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0A0A0A),
                      letterSpacing: -0.3,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF999999),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(int secondsPerKm) {
    final mins = secondsPerKm ~/ 60;
    final secs = secondsPerKm % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}

// ── Workout block card ────────────────────────────────────────────────────────

class _WorkoutBlockCard extends StatelessWidget {
  final int stepNumber;
  final String label;
  final List<ResolvedBlock> blocks;
  final Color accentColor;
  final BlockState state;
  final bool isMain;
  final bool isWarmupCooldown;
  final WorkoutIntent workoutIntent;

  const _WorkoutBlockCard({
    required this.stepNumber,
    required this.label,
    required this.blocks,
    required this.accentColor,
    required this.state,
    required this.workoutIntent,
    this.isMain = false,
    this.isWarmupCooldown = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = state == BlockState.done;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(
            color: isDone ? const Color(0xFF4CAF50) : accentColor,
            width: 3,
          ),
          top: const BorderSide(color: Color(0xFFE8E8E8)),
          right: const BorderSide(color: Color(0xFFE8E8E8)),
          bottom: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDone ? const Color(0xFF4CAF50) : accentColor,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: isDone ? const Color(0xFF4CAF50) : accentColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '$stepNumber',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final block in blocks) ...[
            _buildBlockRow(block),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildBlockRow(ResolvedBlock block) {
    final blockLabel = block.label ??
        (block.type == BlockType.recovery
            ? 'Recovery'
            : block.type == BlockType.warmup
                ? 'Warmup'
                : block.type == BlockType.cooldown
                    ? 'Cooldown'
                    : 'Run');
    final buf = StringBuffer(blockLabel);
    final distStr = _smartDistance(block.distanceKm);

    if (block.reps != null && block.reps! > 1) {
      buf.write(': ${block.reps} × $distStr');
    } else {
      buf.write(': $distStr');
    }
    buf.write(' @ ${block.formattedPaceForIntent(workoutIntent)}');
    if (block.recovery != null && block.reps != null && block.reps! > 1) {
      buf.write(' (${_smartDistance(block.recovery!.distanceKm)} jog)');
    }

    final icon = block.type == BlockType.recovery
        ? Icons.pause_circle_outline
        : block.type == BlockType.warmup || block.type == BlockType.cooldown
            ? Icons.timer_outlined
            : block.reps != null && block.reps! > 1
                ? Icons.repeat
                : Icons.straighten;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: const Color(0xFF999999)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            buf.toString(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF0A0A0A),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  String _smartDistance(double km) {
    if (km < 1.0) return '${(km * 1000).round()}m';
    return '${km.toStringAsFixed(1)} km';
  }
}

// ── Coaching insight card ─────────────────────────────────────────────────────

class _CoachingInsightCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color iconColor;

  const _CoachingInsightCard({
    required this.icon,
    required this.label,
    required this.text,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 5),
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
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF333333),
              height: 1.5,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1565C0),
            ),
          ),
        ],
      ),
    );
  }
}