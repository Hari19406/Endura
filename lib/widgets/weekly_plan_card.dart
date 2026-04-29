// ─────────────────────────────────────────────────────────────────────────────
// lib/widgets/weekly_plan_card.dart
//
// Replaces _buildBottomCarousel() in home_screen.dart.
// Shows: plan arc → week stats → day cards with block breakdowns.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../engines/plan/week_projection_service.dart';
import '../engines/config/workout_template_library.dart';
import '../models/training_phase.dart';

// ─────────────────────────────────────────────────────────────────────────────
// INTENT → COLOR MAPPING
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  static const easy      = Color(0xFF4ECCA3);
  static const tempo     = Color(0xFFF5A623);
  static const interval  = Color(0xFFE85D75);
  static const long      = Color(0xFF6C9FFF);
  static const recovery  = Color(0xFF8B7FD4);
  static const rest      = Color(0xFF555555);
  static const mint      = Color(0xFF00C2A8);
  static const card      = Color(0xFF252525);
  static const bg        = Color(0xFF1C1C1C);
  static const border    = Color(0x14FFFFFF);
  static const textSec   = Color(0xFF999999);
  static const textDim   = Color(0xFF666666);

  static Color forIntent(WorkoutIntent? intent) => switch (intent) {
    WorkoutIntent.aerobicBase  => easy,
    WorkoutIntent.endurance    => long,
    WorkoutIntent.threshold    => tempo,
    WorkoutIntent.vo2max       => interval,
    WorkoutIntent.speed        => interval,
    WorkoutIntent.raceSpecific => tempo,
    WorkoutIntent.recovery     => recovery,
    null                       => rest,
  };

  static Color forBlockType(BlockType type) => switch (type) {
    BlockType.warmup   => easy,
    BlockType.main     => interval,
    BlockType.recovery => recovery,
    BlockType.cooldown => easy,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAN ARC
// ─────────────────────────────────────────────────────────────────────────────

class _PlanArc extends StatelessWidget {
  final int totalWeeks;
  final int currentWeek;
  final TrainingPhase currentPhase;
  final String raceLabel;
  final ValueChanged<int>? onWeekTapped;

  const _PlanArc({
    required this.totalWeeks,
    required this.currentWeek,
    required this.currentPhase,
    required this.raceLabel,
    this.onWeekTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$raceLabel plan',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _C.mint.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_phaseDisplayName(currentPhase),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _C.mint)),
            ),
            const Spacer(),
            Text('Week $currentWeek of $totalWeeks',
              style: const TextStyle(fontSize: 12, color: _C.textSec)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(totalWeeks, (i) {
            final wn = i + 1;
            final done = wn < currentWeek;
            final cur = wn == currentWeek;
            return Expanded(
              child: GestureDetector(
                onTap: () => onWeekTapped?.call(wn),
                child: Padding(
                  padding: EdgeInsets.only(right: i < totalWeeks - 1 ? 2 : 0),
                  child: Column(children: [
                    Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: done || cur ? _C.mint : Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    if (cur)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 4, height: 4,
                        decoration: const BoxDecoration(color: _C.mint, shape: BoxShape.circle),
                      )
                    else
                      const SizedBox(height: 7),
                  ]),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 2),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Base',  style: TextStyle(fontSize: 10, color: _C.textDim)),
            Text('Build', style: TextStyle(fontSize: 10, color: _C.textDim)),
            Text('Peak',  style: TextStyle(fontSize: 10, color: _C.textDim)),
            Text('Taper', style: TextStyle(fontSize: 10, color: _C.textDim)),
          ],
        ),
      ],
    );
  }

  String _phaseDisplayName(TrainingPhase phase) => switch (phase) {
    TrainingPhase.base  => 'Base',
    TrainingPhase.build => 'Build',
    TrainingPhase.peak  => 'Peak',
    TrainingPhase.taper => 'Taper',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// WEEK STATS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _WeekStatsRow extends StatelessWidget {
  final double totalKm;
  final int sessions;
  final int quality;
  const _WeekStatsRow({required this.totalKm, required this.sessions, required this.quality});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _StatPill(value: '${totalKm.round()}', unit: 'km', label: 'Volume'),
      const SizedBox(width: 6),
      _StatPill(value: '$sessions', unit: 'runs', label: 'Sessions'),
      const SizedBox(width: 6),
      _StatPill(value: '$quality', unit: 'quality', label: 'Hard days'),
    ]);
  }
}

class _StatPill extends StatelessWidget {
  final String value, unit, label;
  const _StatPill({required this.value, required this.unit, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.border),
        ),
        child: Column(children: [
          RichText(text: TextSpan(children: [
            TextSpan(text: value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            TextSpan(text: ' $unit',
              style: const TextStyle(fontSize: 11, color: _C.textSec)),
          ])),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 9, color: _C.textDim, letterSpacing: 0.3)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DAY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final ProjectedDay day;
  final VoidCallback? onTap;
  const _DayCard({required this.day, this.onTap});

  String get _workoutName {
    if (day.status == DayStatus.rest) return 'Rest day';
    if (day.status == DayStatus.missed) return 'Missed';
    if (day.templateName != null) return day.templateName!;
    return switch (day.intent) {
      WorkoutIntent.aerobicBase  => 'Easy run',
      WorkoutIntent.endurance    => 'Long run',
      WorkoutIntent.threshold    => 'Threshold session',
      WorkoutIntent.vo2max       => 'VO₂ intervals',
      WorkoutIntent.speed        => 'Speed work',
      WorkoutIntent.raceSpecific => 'Race pace',
      WorkoutIntent.recovery     => 'Recovery jog',
      null                       => 'Rest day',
    };
  }

  String get _detailText {
    if (day.status == DayStatus.completed) {
      final dist = day.completedDistanceKm?.toStringAsFixed(1) ?? '0.0';
      final pace = day.completedPace ?? '--:--';
      return '$dist km · $pace/km';
    }
    if (day.workout != null) {
      final dist = day.workout!.totalDistanceKm.toStringAsFixed(1);
      final mainBlocks = day.workout!.blocks.where((b) => b.type == BlockType.main).toList();
      if (mainBlocks.isNotEmpty) {
        return '$dist km · ${mainBlocks.first.formattedPace}';
      }
      return '$dist km';
    }
    if (day.status == DayStatus.rest) return 'Recovery & adaptation';
    if (day.status == DayStatus.missed) return 'No run logged';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final color = _C.forIntent(day.intent);
    final isToday = day.status == DayStatus.today;
    final isCompleted = day.status == DayStatus.completed;
    final isProjected = day.status == DayStatus.projected;
    final dimmed = day.status == DayStatus.rest || day.status == DayStatus.missed;
    final dateStr = DateFormat('MMM d').format(day.date);

    return GestureDetector(
      onTap: day.hasWorkout ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isToday ? _C.mint : _C.border,
            width: isToday ? 1.5 : 0.5,
          ),
        ),
        child: Opacity(
          opacity: dimmed ? 0.5 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(day.dayLabel,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                if (isToday) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: _C.mint, borderRadius: BorderRadius.circular(8)),
                    child: const Text('TODAY',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
                        color: _C.bg, letterSpacing: 0.3)),
                  ),
                ],
                const Spacer(),
                Text(dateStr, style: const TextStyle(fontSize: 10, color: _C.textDim)),
              ]),
              const SizedBox(height: 8),

              Row(children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_workoutName,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                      overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(_detailText,
                      style: const TextStyle(fontSize: 11, color: _C.textSec)),
                  ],
                )),
                if (isCompleted)
                  Container(
                    width: 18, height: 18,
                    decoration: const BoxDecoration(color: _C.mint, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 11, color: _C.bg),
                  )
                else if (day.hasWorkout)
                  Text('${day.distanceKm.round()} km',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),

              if (day.workout != null && day.workout!.blocks.length > 1) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFF333333), width: 0.5)),
                  ),
                  child: Wrap(
                    spacing: 4, runSpacing: 4,
                    children: day.workout!.blocks.map((block) {
                      final bc = _C.forBlockType(block.type);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: bc.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _blockChipLabel(block),
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: bc),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              if (isProjected && day.hasWorkout)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('projected',
                      style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic,
                        color: Colors.white.withOpacity(0.25))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _blockChipLabel(ResolvedBlock block) {
    if (block.isRpeOnly) {
      if (block.reps != null && block.reps! > 1) {
        return '${block.reps}×${block.formattedDistance} RPE 9';
      }
      return '${block.formattedDistance} RPE 9';
    }
    if (block.reps != null && block.reps! > 1) {
      return '${block.reps}×${block.formattedDistance} @ ${block.formattedPace}';
    }
    if (block.type == BlockType.main) {
      return '${block.formattedDistance} @ ${block.formattedPace}';
    }
    return '${block.formattedDistance} ${block.label ?? block.type.name}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class WeeklyPlanCard extends StatelessWidget {
  final WeekProjection projection;
  final int totalPlanWeeks;
  final int currentPlanWeek;
  final String raceLabel;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;
  final ValueChanged<int>? onWeekTapped;
  final ValueChanged<ProjectedDay>? onDayTapped;

  const WeeklyPlanCard({
    super.key,
    required this.projection,
    required this.totalPlanWeeks,
    required this.currentPlanWeek,
    required this.raceLabel,
    this.onPreviousWeek,
    this.onNextWeek,
    this.onWeekTapped,
    this.onDayTapped,
  });

  String get _weekTitle =>
      projection.weekNumber == currentPlanWeek ? 'This week' : 'Week ${projection.weekNumber}';

  String get _dateRange {
    final s = projection.weekStart;
    final e = s.add(const Duration(days: 6));
    final f = DateFormat('MMM d');
    return '${f.format(s)} – ${f.format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlanArc(
          totalWeeks: totalPlanWeeks,
          currentWeek: currentPlanWeek,
          currentPhase: projection.phase,
          raceLabel: raceLabel,
          onWeekTapped: onWeekTapped,
        ),
        const SizedBox(height: 20),

        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_weekTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Colors.white, letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text(_dateRange, style: const TextStyle(fontSize: 11, color: _C.textSec)),
          ]),
          const Spacer(),
          Row(children: [
            _NavBtn(icon: Icons.chevron_left, onTap: onPreviousWeek),
            const SizedBox(width: 6),
            _NavBtn(icon: Icons.chevron_right, onTap: onNextWeek),
          ]),
        ]),
        const SizedBox(height: 12),

        _WeekStatsRow(
          totalKm: projection.totalVolumeKm,
          sessions: projection.sessionCount,
          quality: projection.qualityCount,
        ),
        const SizedBox(height: 12),

        ...projection.days.map((day) => _DayCard(
          day: day,
          onTap: day.hasWorkout ? () => onDayTapped?.call(day) : null,
        )),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NavBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: _C.border),
        ),
        child: Icon(icon, size: 16, color: _C.textSec),
      ),
    );
  }
}