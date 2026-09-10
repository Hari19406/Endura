import 'package:flutter/material.dart';

import '../engines/config/workout_template_library.dart';
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';

/// The pace prescription for a single workout step, derived from the (already
/// VDOT-baked) pace band on a [ResolvedBlock] plus its structural role and the
/// parent workout's intent.
///
/// The numbers are *not* recomputed here — `ResolvedBlock.paceMin/MaxSecondsPerKm`
/// are set from the athlete's training paces at plan-materialisation time. This
/// class only decides how to label and format them (T / I / R / Easy / effort).
@immutable
class StepPaceBand {
  /// Short training-zone label, e.g. "Threshold", "VO2 / Interval", "Easy".
  final String zone;

  /// The actionable value shown on the badge — a pace window
  /// ("4:35 – 4:45 /km"), an easy ceiling ("≤ 6:15 /km"), or an effort cue
  /// ("Fast & relaxed") when [effortOnly] is true.
  final String value;

  /// True when [value] is a feel/effort cue rather than a numeric pace — RPE-only
  /// blocks, recovery jogs, and first-time / completion plans.
  final bool effortOnly;

  const StepPaceBand({
    required this.zone,
    required this.value,
    required this.effortOnly,
  });

  static const _easyIntents = {
    WorkoutIntent.aerobicBase,
    WorkoutIntent.endurance,
  };

  /// Build the band for [block] inside a workout of [intent].
  ///
  /// [effortBased] forces every step onto conversational / RPE cues — used for
  /// first-time and "just complete it" plans where rigid high-speed targets do
  /// more harm than good.
  factory StepPaceBand.forBlock(
    ResolvedBlock block,
    WorkoutIntent intent, {
    bool effortBased = false,
    bool useMiles = false,
  }) {
    // Recovery jogs between reps are always by feel.
    if (block.type == BlockType.recovery) {
      return const StepPaceBand(
        zone: 'Recovery',
        value: 'Easy jog — let it settle',
        effortOnly: true,
      );
    }

    // Warm-up / cool-down carry easy-pace bands; show a ceiling, never pressure.
    if (block.type == BlockType.warmup || block.type == BlockType.cooldown) {
      if (effortBased || block.isRpeOnly) {
        return const StepPaceBand(
          zone: 'Easy',
          value: 'Relaxed, conversational',
          effortOnly: true,
        );
      }
      return StepPaceBand(
        zone: 'Easy',
        value: _ceiling(block.paceMinSecondsPerKm, useMiles),
        effortOnly: false,
      );
    }

    // Main work.
    if (effortBased) {
      return StepPaceBand(
        zone: _zoneFor(intent),
        value: _effortCue(intent),
        effortOnly: true,
      );
    }

    if (block.isRpeOnly) {
      // Strides / hill sprints — fast but unmeasured.
      return StepPaceBand(
        zone: intent == WorkoutIntent.speed ? 'Strides' : _zoneFor(intent),
        value: intent == WorkoutIntent.speed
            ? 'Fast & relaxed strides'
            : 'By feel — strong, controlled',
        effortOnly: true,
      );
    }

    final easy = _easyIntents.contains(intent) &&
        (block.paceMaxSecondsPerKm - block.paceMinSecondsPerKm) >= 30;
    if (easy) {
      return StepPaceBand(
        zone: _zoneFor(intent),
        value: _ceiling(block.paceMinSecondsPerKm, useMiles),
        effortOnly: false,
      );
    }

    return StepPaceBand(
      zone: _zoneFor(intent),
      value: _window(
        block.paceMinSecondsPerKm,
        block.paceMaxSecondsPerKm,
        useMiles,
      ),
      effortOnly: false,
    );
  }

  static String _zoneFor(WorkoutIntent intent) => switch (intent) {
        WorkoutIntent.aerobicBase => 'Easy',
        WorkoutIntent.endurance => 'Endurance',
        WorkoutIntent.threshold => 'Threshold',
        WorkoutIntent.vo2max => 'VO2 / Interval',
        WorkoutIntent.speed => 'Repetition',
        WorkoutIntent.raceSpecific => 'Race pace',
      };

  static String _effortCue(WorkoutIntent intent) => switch (intent) {
        WorkoutIntent.aerobicBase ||
        WorkoutIntent.endurance =>
          'Conversational — you could chat the whole way',
        WorkoutIntent.threshold => 'Comfortably hard, sustainable',
        WorkoutIntent.vo2max => 'Hard but controlled — strong breathing',
        WorkoutIntent.speed => 'Fast & relaxed, full recovery',
        WorkoutIntent.raceSpecific => 'Goal race effort',
      };

  static String _ceiling(int paceMinSecondsPerKm, bool useMiles) {
    final rounded = (paceMinSecondsPerKm / 5).round() * 5;
    return '≤ ${_fmt(rounded, useMiles)} ${UnitUtils.perUnitLabel(useMiles)}';
  }

  static String _window(int minSecPerKm, int maxSecPerKm, bool useMiles) {
    final lo = (minSecPerKm / 5).round() * 5;
    final hi = (maxSecPerKm / 5).round() * 5;
    final unit = UnitUtils.perUnitLabel(useMiles);
    return lo == hi
        ? '${_fmt(lo, useMiles)} $unit'
        : '${_fmt(lo, useMiles)} – ${_fmt(hi, useMiles)} $unit';
  }

  static String _fmt(int secondsPerKm, bool useMiles) {
    final display =
        UnitUtils.displayPaceSeconds(secondsPerKm.toDouble(), useMiles).round();
    return UnitUtils.formatSeconds(display);
  }
}

/// A clean, scannable vertical timeline of a structured workout: one row per
/// [ResolvedBlock], each with its phase, quantity, a VDOT-derived pace-range
/// badge and a short coaching cue.
class WorkoutStepTimeline extends StatelessWidget {
  final ResolvedWorkout workout;
  final bool useMiles;

  /// Force conversational / RPE cues on every step (first-time & completion
  /// plans). Individual RPE-only blocks always show effort cues regardless.
  final bool effortBased;

  const WorkoutStepTimeline({
    super.key,
    required this.workout,
    this.useMiles = false,
    this.effortBased = false,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = workout.blocks;
    if (blocks.isEmpty) {
      return Text(
        'Full rest day — nothing scheduled.',
        style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          _StepRow(
            block: blocks[i],
            intent: workout.intent,
            useMiles: useMiles,
            effortBased: effortBased,
            isLast: i == blocks.length - 1,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final ResolvedBlock block;
  final WorkoutIntent intent;
  final bool useMiles;
  final bool effortBased;
  final bool isLast;

  const _StepRow({
    required this.block,
    required this.intent,
    required this.useMiles,
    required this.effortBased,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final band = StepPaceBand.forBlock(
      block,
      intent,
      effortBased: effortBased,
      useMiles: useMiles,
    );
    final accent = _phaseColor(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline rail ────────────────────────────────────────────────
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: c.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // ── Step content ─────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _phaseLabel(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: accent,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _quantity(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Badge(
                        text: band.effortOnly
                            ? band.value
                            : '${band.zone} · ${band.value}',
                        icon: band.effortOnly
                            ? Icons.favorite_border_rounded
                            : Icons.speed_rounded,
                        color: accent,
                      ),
                      if (_recovery() != null)
                        _Badge(
                          text: _recovery()!,
                          icon: Icons.pause_circle_outline_rounded,
                          color: c.textTertiary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _cue(),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Derived text ──────────────────────────────────────────────────────────

  String _phaseLabel() {
    switch (block.type) {
      case BlockType.warmup:
        return 'WARMUP';
      case BlockType.cooldown:
        return 'COOLDOWN';
      case BlockType.recovery:
        return 'RECOVERY';
      case BlockType.main:
        if (block.isRpeOnly && intent == WorkoutIntent.speed) return 'STRIDES';
        if ((block.reps ?? 1) > 1) {
          return intent == WorkoutIntent.threshold ? 'CRUISE INTERVAL' : 'INTERVAL';
        }
        return switch (intent) {
          WorkoutIntent.threshold => 'TEMPO',
          WorkoutIntent.vo2max => 'INTERVAL',
          WorkoutIntent.speed => 'REPS',
          WorkoutIntent.raceSpecific => 'RACE PACE',
          WorkoutIntent.endurance => 'LONG RUN',
          WorkoutIntent.aerobicBase => 'EASY RUN',
        };
    }
  }

  String _quantity() {
    if (block.durationSeconds != null) {
      final s = block.durationSeconds!;
      return s >= 60 && s % 60 == 0 ? '${s ~/ 60} min' : '${s}s';
    }
    final each = _distance(block.distanceKm);
    return (block.reps ?? 1) > 1 ? '${block.reps} × $each' : each;
  }

  String _distance(double km) {
    if (km < 1.0) return '${(km * 1000).round()} m';
    final d = UnitUtils.displayDistance(km, useMiles);
    return '${d.toStringAsFixed(d >= 10 ? 0 : 1)} ${UnitUtils.unitLabel(useMiles)}';
  }

  String? _recovery() {
    if ((block.reps ?? 1) <= 1) return null;
    if (block.recoverySeconds != null) {
      final s = block.recoverySeconds!;
      final txt = s >= 60
          ? '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'
          : '${s}s';
      return '$txt recovery';
    }
    if (block.recoveryMeters != null) {
      return '${_distance(block.recoveryMeters! / 1000)} jog';
    }
    return null;
  }

  String _cue() {
    switch (block.type) {
      case BlockType.warmup:
        return 'Ease in — let your heart rate and legs wake up gradually.';
      case BlockType.cooldown:
        return 'Flush the legs. Loose and easy, no pace pressure.';
      case BlockType.recovery:
        return 'Keep jogging — breathing settles before the next rep.';
      case BlockType.main:
        if (effortBased) {
          return 'Run by feel today — smooth and sustainable, finish knowing '
              'you had more.';
        }
        return switch (intent) {
          WorkoutIntent.threshold =>
            'Comfortably hard and controlled. Rhythmic breathing, don\'t surge '
                'early.',
          WorkoutIntent.vo2max =>
            'Strong but smooth. Even splits — resist blasting the first rep.',
          WorkoutIntent.speed =>
            'Quick turnover, relaxed shoulders. Take the full recovery.',
          WorkoutIntent.raceSpecific =>
            'Lock into goal race effort — rehearse the pace you want on the day.',
          WorkoutIntent.endurance =>
            'Start slower than feels necessary. Conversational the whole way.',
          WorkoutIntent.aerobicBase =>
            'Truly easy. If you can\'t talk in full sentences, slow down.',
        };
    }
  }

  Color _phaseColor(BuildContext context) {
    final c = context.colors;
    switch (block.type) {
      case BlockType.warmup:
        return const Color(0xFF388E3C);
      case BlockType.cooldown:
        return const Color(0xFF1565C0);
      case BlockType.recovery:
        return c.textTertiary;
      case BlockType.main:
        return switch (intent) {
          WorkoutIntent.threshold => const Color(0xFFBF360C),
          WorkoutIntent.vo2max => const Color(0xFF0D47A1),
          WorkoutIntent.speed => const Color(0xFF6A1B9A),
          WorkoutIntent.raceSpecific => const Color(0xFFAD1457),
          WorkoutIntent.endurance => const Color(0xFF1B5E20),
          WorkoutIntent.aerobicBase => const Color(0xFF00695C),
        };
    }
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const _Badge({required this.text, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
