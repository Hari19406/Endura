/// The onboarding plan reveal — the screen that has to make the plan feel
/// earned before the athlete commits to it.
///
/// Three parts: a whole-plan volume curve they can scrub, a colour-coded
/// "typical week" strip, and the "How we built your plan" receipt, whose rows
/// each jump back to the question that produced them.
///
/// Lives outside onboarding_pages.dart, which is already ~5,000 lines.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engines/config/workout_template_library.dart' show WorkoutIntent;
import '../engines/plan/week_resolver.dart' show DaySlot;
import '../services/analytics_service.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';
import 'onboarding_screen.dart' show EC, ET;
import 'plan_reveal_data.dart';

// ============================================================================
// RECEIPT ROW MODEL
// ============================================================================

/// One line of "How we built your plan".
///
/// Modelled as data rather than hand-written widgets so the two rows we can't
/// back yet — race terrain (no column on the `races` table) and long-run
/// workouts (no engine flag) — drop in later without restructuring.
class PlanReceiptRow {
  final IconData icon;
  final String label;
  final String value;

  /// Null for derived facts the athlete never answered directly.
  final PlanEditTarget? editTarget;

  const PlanReceiptRow({
    required this.icon,
    required this.label,
    required this.value,
    this.editTarget,
  });
}

// ============================================================================
// PAGE
// ============================================================================

class OPagePlanReveal extends StatefulWidget {
  final OnboardingAnswers answers;

  /// Null while the projection is still being computed, or if the plan builder
  /// threw. Either way the receipt still renders — onboarding never dead-ends.
  final PlanProjection? projection;

  final void Function(PlanEditTarget target) onEdit;
  final VoidCallback onGenerate;

  const OPagePlanReveal({
    super.key,
    required this.answers,
    required this.projection,
    required this.onEdit,
    required this.onGenerate,
  });

  @override
  State<OPagePlanReveal> createState() => _OPagePlanRevealState();
}

class _OPagePlanRevealState extends State<OPagePlanReveal> {
  int? _scrub;
  bool _scrubTracked = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: UnitUtils.useMilesNotifier,
      builder: (context, useMiles, _) {
        final p = widget.projection;
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: ET.pagePad,
                children: [
                  const SizedBox(height: 24),
                  _RevealHeader(
                    answers: widget.answers,
                    projection: p,
                    useMiles: useMiles,
                  ),
                  const SizedBox(height: 22),
                  if (p == null)
                    const _RevealSkeleton()
                  else ...[
                    _TypicalWeekStrip(
                      days: p.typicalWeek,
                      weekNumber: p.typicalWeekNumber,
                      useMiles: useMiles,
                    ),
                    const SizedBox(height: 14),
                    _VolumeCurveCard(
                      projection: p,
                      useMiles: useMiles,
                      scrubIndex: _scrub,
                      onScrub: _onScrub,
                    ),
                  ],
                  const SizedBox(height: 14),
                  _ReceiptCard(
                    rows: buildReceiptRows(
                      widget.answers,
                      p,
                      useMiles: useMiles,
                    ),
                    onEdit: _onEditTapped,
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
            _CtaBar(onGenerate: widget.onGenerate),
          ],
        );
      },
    );
  }

  void _onEditTapped(PlanEditTarget target) {
    HapticFeedback.lightImpact();
    Analytics.planRevealEditTapped(target.name);
    widget.onEdit(target);
  }

  void _onScrub(int? index) {
    if (index == _scrub) return; // touchCallback fires on every pointer move
    if (index != null) {
      HapticFeedback.selectionClick();
      if (!_scrubTracked) {
        _scrubTracked = true;
        Analytics.planRevealCurveScrubbed();
      }
    }
    setState(() => _scrub = index);
  }
}

// ============================================================================
// HEADER
// ============================================================================

class _RevealHeader extends StatelessWidget {
  final OnboardingAnswers answers;
  final PlanProjection? projection;
  final bool useMiles;

  const _RevealHeader({
    required this.answers,
    required this.projection,
    required this.useMiles,
  });

  @override
  Widget build(BuildContext context) {
    final weeks = projection?.weeks.length ?? answers.planWeeks;
    final title = answers.raceName == null
        ? '$weeks-week plan'
        : '$weeks-week ${answers.raceName}';

    final p = projection;
    final subtitle = p == null
        ? '${answers.runsPerWeek} runs/week'
        : 'Peaking at ${_km(p.peakWeeklyKm, useMiles)} '
              '${UnitUtils.unitLabel(useMiles)}/week · '
              '${answers.runsPerWeek} runs/week';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: EC.textPrimary,
            height: 1.2,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 14, color: EC.textSecondary),
        ),
      ],
    );
  }
}

// ============================================================================
// TYPICAL WEEK STRIP
// ============================================================================

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String intentLabel(WorkoutIntent? intent) => switch (intent) {
  WorkoutIntent.aerobicBase => 'Easy',
  WorkoutIntent.endurance => 'Long',
  WorkoutIntent.threshold => 'Tempo',
  WorkoutIntent.vo2max => 'Intervals',
  WorkoutIntent.speed => 'Speed',
  WorkoutIntent.raceSpecific => 'Race',
  null => 'Rest',
};

class _TypicalWeekStrip extends StatelessWidget {
  final List<DaySlot> days;
  final int weekNumber;
  final bool useMiles;

  const _TypicalWeekStrip({
    required this.days,
    required this.weekNumber,
    required this.useMiles,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('A TYPICAL WEEK'),
          const SizedBox(height: 14),
          Row(
            children: List.generate(7, (i) {
              final slot = i < days.length ? days[i] : null;
              return Expanded(
                child: _DayCell(
                  slot: slot,
                  letter: _dayLetters[i],
                  useMiles: useMiles,
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            'Week $weekNumber — your biggest build week',
            style: const TextStyle(fontSize: 11, color: EC.muted),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DaySlot? slot;
  final String letter;
  final bool useMiles;

  const _DayCell({
    required this.slot,
    required this.letter,
    required this.useMiles,
  });

  @override
  Widget build(BuildContext context) {
    final isRest = slot == null || slot!.isRest;
    // dayColorForIntent maps rest to white, which was designed for a light
    // surface and reads as a bright blob on EC.bg. Ring it instead.
    final fill = isRest ? Colors.transparent : dayColorForIntent(slot!.intent);
    final km = slot?.distanceKm;

    return Column(
      children: [
        Text(
          letter,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: EC.muted,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: isRest ? Border.all(color: EC.border, width: 1.2) : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isRest ? 'Rest' : intentLabel(slot!.intent),
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: EC.textSecondary,
            letterSpacing: 0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
        const SizedBox(height: 2),
        Text(
          isRest ? '—' : (km == null ? '—' : _km(km, useMiles)),
          style: const TextStyle(fontSize: 9, color: EC.muted),
        ),
      ],
    );
  }
}

// ============================================================================
// VOLUME CURVE
// ============================================================================

class _VolumeCurveCard extends StatelessWidget {
  final PlanProjection projection;
  final bool useMiles;
  final int? scrubIndex;
  final ValueChanged<int?> onScrub;

  const _VolumeCurveCard({
    required this.projection,
    required this.useMiles,
    required this.scrubIndex,
    required this.onScrub,
  });

  @override
  Widget build(BuildContext context) {
    final points = projection.weeks;
    final unit = UnitUtils.unitLabel(useMiles);
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(
          i.toDouble(),
          UnitUtils.displayDistance(points[i].effectiveKm, useMiles),
        ),
    ];
    final peakDisplay = UnitUtils.displayDistance(
      projection.peakWeeklyKm,
      useMiles,
    );

    final scrubbed = scrubIndex != null && scrubIndex! < points.length
        ? points[scrubIndex!]
        : null;

    // Fixed-height caption so the layout never jumps as the value changes.
    final caption = scrubbed == null
        ? 'Peaks at ${_km(projection.peakWeeklyKm, useMiles)} $unit '
              'in week ${projection.peakWeekNumber}'
        : 'Week ${scrubbed.week} · ${_km(scrubbed.effectiveKm, useMiles)} $unit'
              '${scrubbed.isCutback ? ' · recovery week' : ''}';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('WEEKLY VOLUME'),
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: Text(
              caption,
              style: TextStyle(
                fontSize: 12,
                color: scrubbed == null ? EC.textSecondary : EC.teal,
                fontWeight: scrubbed == null
                    ? FontWeight.w400
                    : FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: peakDisplay <= 0 ? 10 : peakDisplay * 1.22,
                minX: 0,
                maxX: (points.length - 1).toDouble(),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        final step = points.length <= 8 ? 2 : 4;
                        if (i != 0 && (i + 1) % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'W${i + 1}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: EC.muted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    preventCurveOverShooting: true,
                    color: EC.teal,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    showingIndicators: scrubIndex == null
                        ? const []
                        : [scrubIndex!],
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          EC.teal.withOpacity(0.26),
                          EC.teal.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  getTouchedSpotIndicator: (bar, indexes) => indexes
                      .map(
                        (_) => TouchedSpotIndicatorData(
                          FlLine(
                            color: EC.teal.withOpacity(0.45),
                            strokeWidth: 1.5,
                          ),
                          FlDotData(
                            getDotPainter: (s, pct, b, i) => FlDotCirclePainter(
                              radius: 4,
                              color: EC.surface,
                              strokeWidth: 2.5,
                              strokeColor: EC.teal,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  // The built-in tooltip is suppressed; the caption above the
                  // chart carries the value so nothing overlaps the curve.
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.transparent,
                    tooltipPadding: EdgeInsets.zero,
                    tooltipMargin: 0,
                    getTooltipItems: (spots) => spots.map((_) => null).toList(),
                  ),
                  // Scrub only while a finger is actually down. Allow-listing
                  // the active events (rather than blocking the end ones) also
                  // clears the crosshair after a wheel scroll over the chart,
                  // which emits no pan-end event and would otherwise leave the
                  // indicator stuck on whatever week it passed over.
                  touchCallback: (event, response) {
                    final active =
                        event is FlTapDownEvent ||
                        event is FlPanDownEvent ||
                        event is FlPanStartEvent ||
                        event is FlPanUpdateEvent ||
                        event is FlLongPressStart ||
                        event is FlLongPressMoveUpdate;
                    if (!active) {
                      onScrub(null);
                      return;
                    }
                    final spots = response?.lineBarSpots;
                    onScrub(
                      spots == null || spots.isEmpty
                          ? null
                          : spots.first.spotIndex,
                    );
                  },
                ),
              ),
              duration: Duration.zero,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RECEIPT
// ============================================================================

/// Builds the receipt. Public so the widget test can assert on it directly.
///
/// Race terrain and long-run workouts are deliberately absent rather than shown
/// as placeholders — we have no data for either yet.
List<PlanReceiptRow> buildReceiptRows(
  OnboardingAnswers a,
  PlanProjection? p, {
  required bool useMiles,
}) {
  final unit = UnitUtils.unitLabel(useMiles);
  final rows = <PlanReceiptRow>[
    PlanReceiptRow(
      icon: Icons.flag_outlined,
      label: 'Goal',
      value: goalLabel(a.raceGoalRaw),
      editTarget: PlanEditTarget.goal,
    ),
    PlanReceiptRow(
      icon: Icons.directions_run_rounded,
      label: 'Runs per week',
      value: '${a.runsPerWeek}',
      editTarget: PlanEditTarget.runsPerWeek,
    ),
  ];

  if (p != null) {
    rows.add(
      PlanReceiptRow(
        icon: Icons.show_chart_rounded,
        label: 'Weekly volume',
        value:
            '${_km(p.minWeeklyKm, useMiles)}–${_km(p.peakWeeklyKm, useMiles)} $unit',
        editTarget: PlanEditTarget.runsPerWeek,
      ),
    );
    rows.add(
      PlanReceiptRow(
        icon: Icons.bolt_rounded,
        label: 'Speed workouts',
        value: p.minQuality == p.maxQuality
            ? '${p.maxQuality} per week'
            : '${p.minQuality}–${p.maxQuality} per week',
      ),
    );
  }

  rows.add(
    PlanReceiptRow(
      icon: Icons.calendar_today_rounded,
      label: 'Available days',
      value: dayListLabel(a.selectedDays),
      editTarget: PlanEditTarget.trainingDays,
    ),
  );
  rows.add(
    PlanReceiptRow(
      icon: Icons.event_repeat_rounded,
      label: 'Long run day',
      value: a.longRunDayIndex == null
          ? 'Not set'
          : fullDayName(a.longRunDayIndex!),
      editTarget: PlanEditTarget.longRunDay,
    ),
  );

  if (p != null) {
    rows.add(
      PlanReceiptRow(
        icon: Icons.timeline_rounded,
        label: 'Long runs',
        value:
            '${_km(p.minLongRunKm, useMiles)}–${_km(p.maxLongRunKm, useMiles)} $unit',
      ),
    );
  }

  rows.add(
    PlanReceiptRow(
      icon: Icons.speed_rounded,
      label: 'Current fitness',
      value: fitnessLabel(a),
      editTarget: PlanEditTarget.currentTime,
    ),
  );

  return rows;
}

/// Reads the raw race goal, not the bridged intent. The bridge collapses five
/// answers into two, which is what made the old summary label fall through to
/// "Finish comfortably" for anyone who picked "enjoy" or "finish".
String goalLabel(String? raceGoal) => switch (raceGoal) {
  'pr' => 'Beat my PR',
  'target_time' => 'Hit my target time',
  'finish' => 'Finish strong',
  'enjoy' => 'Enjoy the race',
  'undecided' => 'Still deciding',
  _ => 'Finish strong',
};

const _fullDayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _shortDayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String fullDayName(int index) =>
    index >= 0 && index < 7 ? _fullDayNames[index] : 'Not set';

String dayListLabel(List<int> days) {
  if (days.isEmpty) return 'Not set';
  final sorted = [...days]..sort();
  return sorted.map((d) => _shortDayNames[d.clamp(0, 6)]).join(' · ');
}

/// "vDOT 44 · 1:50:00 half" — real provenance, not "your last 2 activities".
String fitnessLabel(OnboardingAnswers a) {
  final distance = switch (a.paceDistance) {
    '10k' => '10K',
    'half' => 'half',
    'marathon' => 'marathon',
    _ => '5K',
  };
  if (a.currentTimeSec <= 0) return 'vDOT ${a.vdot}';
  return 'vDOT ${a.vdot} · ${_hms(a.currentTimeSec)} $distance';
}

class _ReceiptCard extends StatelessWidget {
  final List<PlanReceiptRow> rows;
  final void Function(PlanEditTarget) onEdit;

  const _ReceiptCard({required this.rows, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How we built your plan',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: EC.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap any row to adjust. You can change these anytime — even after '
            'you start training.',
            style: TextStyle(
              fontSize: 12,
              color: EC.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          for (final row in rows) _ReceiptRowTile(row: row, onEdit: onEdit),
        ],
      ),
    );
  }
}

class _ReceiptRowTile extends StatelessWidget {
  final PlanReceiptRow row;
  final void Function(PlanEditTarget) onEdit;

  const _ReceiptRowTile({required this.row, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final editable = row.editTarget != null;

    return Semantics(
      button: editable,
      label: editable ? 'Edit ${row.label}' : null,
      child: InkWell(
        onTap: editable ? () => onEdit(row.editTarget!) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 17, color: EC.teal),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: EC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      row.value,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: EC.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (editable) ...[
                const Text(
                  'Edit',
                  style: TextStyle(fontSize: 12.5, color: EC.muted),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: EC.muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CHROME
// ============================================================================

class _CtaBar extends StatelessWidget {
  final VoidCallback onGenerate;

  const _CtaBar({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () {
            HapticFeedback.mediumImpact();
            onGenerate();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: EC.teal,
            foregroundColor: EC.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ET.radius),
            ),
          ),
          child: const Text(
            'Start training',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _RevealSkeleton extends StatelessWidget {
  const _RevealSkeleton();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: SizedBox(
        height: 150,
        child: Center(
          child: Text(
            'Shaping your weeks…',
            style: TextStyle(fontSize: 13, color: EC.muted),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EC.surface,
        borderRadius: BorderRadius.circular(ET.cardRadius),
        border: Border.all(color: EC.border, width: ET.borderWidth),
      ),
      child: child,
    );
  }
}

class _CardLabel extends StatelessWidget {
  final String text;

  const _CardLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: EC.muted,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ============================================================================
// FORMATTING
// ============================================================================

/// Whole numbers throughout. These are projected weekly targets that the daily
/// scaler adjusts anyway, so a decimal would be false precision — and seven
/// strip cells across a phone have no room for one.
String _km(double km, bool useMiles) =>
    UnitUtils.displayDistance(km, useMiles).round().toString();

String _hms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}
