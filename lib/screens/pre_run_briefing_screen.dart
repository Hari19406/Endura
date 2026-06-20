import 'package:flutter/material.dart';
import '../services/coach_message_builder.dart' as message;
import '../engines/config/workout_template_library.dart';
import 'run_screen.dart';

enum BlockState { pending, done }

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
    final hasCoachContent = widget.coachMessage.reflectionText.isNotEmpty ||
        widget.coachMessage.goalText.isNotEmpty ||
        widget.coachMessage.feelText.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text(
          'Today\'s Workout',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A0A0A),
            fontSize: 16,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFFF2F2F2),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0A0A0A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
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
                    const SizedBox(height: 12),
                  ],
                  Text(
                    widget.coachMessage.workoutTitle,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0A0A0A),
                      letterSpacing: -0.8,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.coachMessage.hasWarmupCooldown
                        ? 'Warmup & cooldown included'
                        : 'Easy effort — no warmup needed',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFAAAAAA),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildHeroStats(workout),
                ],
              ),
            ),

            const SizedBox(height: 10),

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
                          decoration: const BoxDecoration(
                            color: Color(0xFF0A0A0A),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'M',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Max',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0A0A0A),
                          ),
                        ),
                      ],
                    ),
                    if (widget.coachMessage.reflectionText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.coachMessage.reflectionText,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF333333),
                          height: 1.6,
                        ),
                      ),
                    ],
                    if (widget.coachMessage.acknowledgementText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.coachMessage.acknowledgementText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF888888),
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (widget.coachMessage.goalText.isNotEmpty ||
                        widget.coachMessage.feelText.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                      const SizedBox(height: 16),
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

            if (hasCoachContent) const SizedBox(height: 10),

            // ── Workout card ─────────────────────────────────────────────────
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WORKOUT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF999999),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_hasWarmup) ...[
                    _WorkoutSection(
                      stepNumber: 1,
                      label: 'WARMUP',
                      blocks: _warmupBlocks,
                      accentColor: const Color(0xFF388E3C),
                      workoutIntent: widget.coachMessage.workoutIntent,
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                    const SizedBox(height: 16),
                  ],

                  _WorkoutSection(
                    stepNumber: _hasWarmup ? 2 : 1,
                    label: 'MAIN SET',
                    blocks: _workBlocks,
                    accentColor: const Color(0xFF0A0A0A),
                    workoutIntent: widget.coachMessage.workoutIntent,
                  ),

                  if (_hasCooldown) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
                    const SizedBox(height: 16),
                    _WorkoutSection(
                      stepNumber: _hasWarmup ? 3 : 2,
                      label: 'COOLDOWN',
                      blocks: _cooldownBlocks,
                      accentColor: const Color(0xFF1565C0),
                      workoutIntent: widget.coachMessage.workoutIntent,
                    ),
                  ],
                ],
              ),
            ),

            if (widget.coachMessage.movedFromDay != null) ...[
              const SizedBox(height: 10),
              _Card(
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
            ],

            const SizedBox(height: 24),

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
        final fastest = nonRpe
            .map((b) => b.paceMinSecondsPerKm)
            .reduce((a, b) => a < b ? a : b);
        final slowest = nonRpe
            .map((b) => b.paceMaxSecondsPerKm)
            .reduce((a, b) => a > b ? a : b);
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

    return Row(
      children: [
        for (int i = 0; i < labels.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 32, color: const Color(0xFFE8E8E8)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  values[i],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0A0A0A),
                    letterSpacing: -0.3,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  labels[i],
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFAAAAAA),
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
    final mins = secondsPerKm ~/ 60;
    final secs = secondsPerKm % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

// ── Workout section (within the workout card) ─────────────────────────────────

class _WorkoutSection extends StatelessWidget {
  final int stepNumber;
  final String label;
  final List<ResolvedBlock> blocks;
  final Color accentColor;
  final WorkoutIntent workoutIntent;

  const _WorkoutSection({
    required this.stepNumber,
    required this.label,
    required this.blocks,
    required this.accentColor,
    required this.workoutIntent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '$stepNumber',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentColor,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildBlockRow(blocks[i]),
        ],
      ],
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

    final String quantity;
    if (block.reps != null && block.reps! > 1) {
      quantity = '${block.reps} × ${_smartDistance(block.distanceKm)}';
    } else {
      quantity = _smartDistance(block.distanceKm);
    }

    String? recovery;
    if (block.reps != null && block.reps! > 1) {
      if (block.recoverySeconds != null) {
        final m = block.recoverySeconds! ~/ 60;
        final s = block.recoverySeconds! % 60;
        recovery = m > 0
            ? '$m:${s.toString().padLeft(2, '0')} rest'
            : '${block.recoverySeconds}s rest';
      } else if (block.recoveryMeters != null) {
        recovery = '${_smartDistance(block.recoveryMeters! / 1000)} jog';
      }
    }

    final pace = block.formattedPaceForIntent(workoutIntent);

    final icon = block.type == BlockType.recovery
        ? Icons.pause_circle_outline
        : block.type == BlockType.warmup || block.type == BlockType.cooldown
            ? Icons.timer_outlined
            : block.reps != null && block.reps! > 1
                ? Icons.repeat
                : Icons.straighten;

    final detail = StringBuffer(quantity);
    detail.write(' · $pace');
    if (recovery != null) detail.write(' · $recovery');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(icon, size: 14, color: const Color(0xFFCCCCCC)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                blockLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0A0A0A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail.toString(),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF777777),
                  height: 1.4,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
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
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF444444),
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
