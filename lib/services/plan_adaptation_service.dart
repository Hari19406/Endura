/// PlanAdaptationService — mid-plan return-to-training recalibration.
///
/// Given the persisted [MaterializedPlan], "now", and the calendar dates the
/// athlete missed, this classifies the layoff into a [MissedWindow] and returns
/// a recalibrated clone of the plan plus a coach explanation of the change.
///
/// The physiology follows Jack Daniels' return-to-training guidance (*Daniels'
/// Running Formula*, 3rd ed., "Returning after a layoff"):
///   • &lt; 48 h  — negligible loss; resume as written, never cram.
///   • ~1 week   — VO2/plasma retained, connective-tissue stiffness drops;
///                 short volume dip + one fewer hard session.
///   • 2 weeks+  — measurable loss of plasma volume and running economy;
///                 re-anchor volume down, run strict aerobic base for ~2 weeks,
///                 then rebuild at a capped weekly rate.
///
/// Pure: no I/O. The caller loads the plan, runs [evaluateAndRecalibrate], and
/// (if it chooses to act on the result) persists [PlanRecalibration.updatedPlan].
/// Nothing in the app wires this automatically — it is an opt-in utility.
library;

import 'dart:math' as math;

import '../engines/core/vdot_calculator.dart' show pacesFor;
import '../engines/config/workout_template_library.dart'
    show BlockType, ResolvedBlock, ResolvedWorkout, WorkoutIntent;
import '../engines/plan/materialized_plan.dart';
import '../models/training_phase.dart';
import '../utils/plan_calendar.dart';

/// How long the athlete was away, in consecutive missed calendar days.
enum MissedWindow {
  /// No missed sessions — the plan is returned untouched.
  none,

  /// 1–2 consecutive days. Aerobic loss is negligible; resume as scheduled.
  brief,

  /// 3–7 consecutive days (~1 week). Brief volume deload + drop one hard day.
  moderate,

  /// 8–21+ consecutive days (2–3+ weeks). Re-anchor volume, enforce an aerobic
  /// base block, then rebuild to race day at a capped weekly rate.
  extended,
}

/// Result of [PlanAdaptationService.evaluateAndRecalibrate].
class PlanRecalibration {
  /// A clone of the input plan with adjusted weekly volume and modified workout
  /// slots. For [MissedWindow.none] / [MissedWindow.brief] this is structurally
  /// identical to the input (only an adaptation-log line is added for `brief`).
  final MaterializedPlan updatedPlan;

  /// The detected layoff window.
  final MissedWindow missedWindow;

  /// A human-readable explanation from Max: what happened physiologically and
  /// why the plan changed (or deliberately did not).
  final String coachExplanation;

  const PlanRecalibration({
    required this.updatedPlan,
    required this.missedWindow,
    required this.coachExplanation,
  });

  /// True when [updatedPlan] carries volume / slot changes vs. the input.
  bool get changedPlan =>
      missedWindow == MissedWindow.moderate ||
      missedWindow == MissedWindow.extended;
}

class PlanAdaptationService {
  const PlanAdaptationService();

  // ── Tunables ──────────────────────────────────────────────────────────────

  /// Return-week volume multiplier for a ~1-week layoff (15–20% deload).
  static const double moderateDeloadScale = 0.82;

  /// Volume re-anchor multiplier for a 2-week+ layoff (25–35% cut).
  static const double extendedReanchorScale = 0.70;

  /// Maximum week-over-week volume growth while rebuilding (≈ +9%/week, inside
  /// the 8–10% safe-progression band).
  static const double weeklyProgressionCeiling = 1.09;

  /// Length of the strict aerobic-base block after an extended layoff.
  static const int aerobicBaseWindowDays = 14;

  /// Intents that count as "speedwork" and are stripped during the aerobic
  /// base block / hard-day downgrade.
  static const Set<WorkoutIntent> _speedIntents = {
    WorkoutIntent.threshold,
    WorkoutIntent.vo2max,
    WorkoutIntent.speed,
    WorkoutIntent.raceSpecific,
  };

  // ── Public API ────────────────────────────────────────────────────────────

  /// Classify a set of missed calendar dates by the longest run of consecutive
  /// missed days.
  MissedWindow classifyWindow(List<DateTime> missedWorkoutDates) {
    final span = _longestConsecutiveSpan(missedWorkoutDates);
    if (span <= 0) return MissedWindow.none;
    if (span <= 2) return MissedWindow.brief;
    if (span <= 7) return MissedWindow.moderate;
    return MissedWindow.extended;
  }

  /// Evaluate a layoff and return a recalibrated plan.
  ///
  /// [activePlan]              the persisted materialised plan.
  /// [currentDate]            "today" — the day the athlete resumes.
  /// [missedWorkoutDates]      calendar dates of skipped sessions.
  /// [remainingWeeksToRace]    weeks from [currentDate] to race day; used to
  ///                           bound the rebuild wave and detect that the
  ///                           athlete is already inside the taper.
  PlanRecalibration evaluateAndRecalibrate({
    required MaterializedPlan activePlan,
    required DateTime currentDate,
    required List<DateTime> missedWorkoutDates,
    required int remainingWeeksToRace,
  }) {
    final window = classifyWindow(missedWorkoutDates);
    final spanDays = _longestConsecutiveSpan(missedWorkoutDates);

    if (activePlan.weeks.isEmpty || window == MissedWindow.none) {
      return PlanRecalibration(
        updatedPlan: activePlan,
        missedWindow: MissedWindow.none,
        coachExplanation:
            'No missed sessions detected — your plan is unchanged.',
      );
    }

    final week1Start = activePlan.week1Monday;
    final today = _dateOnly(currentDate);
    final total = activePlan.totalWeeks;
    final currentWeekNo =
        (PlanCalendar.daysBetween(week1Start, today) ~/ 7 + 1).clamp(1, total);
    final todayIdx = currentDate.weekday - 1; // 0 = Monday

    // The last two week numbers are the race taper and are never volume-scaled
    // or stripped of intensity, regardless of the layoff length.
    final taperStartNo = total - 1;
    bool isTaper(MaterializedWeek w) =>
        w.phase == TrainingPhase.taper || w.weekNumber >= taperStartNo;

    final ePace = pacesFor(activePlan.builtFromVdot).ePaceSecPerKm;

    // ── brief ───────────────────────────────────────────────────────────────
    if (window == MissedWindow.brief) {
      return PlanRecalibration(
        updatedPlan: _clone(activePlan, List.of(activePlan.weeks), [
          AdaptationLogEntry(
            at: currentDate,
            reason: 'missed_window_brief',
            weekNumber: currentWeekNo,
            summary: '$spanDays day(s) missed — no plan change; '
                'resumed today as scheduled.',
          ),
        ]),
        missedWindow: MissedWindow.brief,
        coachExplanation: _briefExplanation(spanDays),
      );
    }

    // If the athlete is already inside the taper, protect it entirely — no
    // volume change, no intensity change — whatever the window.
    final inTaper = currentWeekNo >= taperStartNo ||
        activePlan.weekByNumber(currentWeekNo)?.phase == TrainingPhase.taper ||
        remainingWeeksToRace <= 2;
    if (inTaper) {
      return PlanRecalibration(
        updatedPlan: _clone(activePlan, List.of(activePlan.weeks), [
          AdaptationLogEntry(
            at: currentDate,
            reason: 'missed_window_${window.name}_taper_protected',
            weekNumber: currentWeekNo,
            summary: 'Missed block landed in the taper — plan left intact to '
                'preserve race-week freshness.',
          ),
        ]),
        missedWindow: window,
        coachExplanation: _taperProtectedExplanation(window, spanDays),
      );
    }

    // ── moderate ────────────────────────────────────────────────────────────
    if (window == MissedWindow.moderate) {
      final log = <AdaptationLogEntry>[];
      final weeks = <MaterializedWeek>[];
      var downgraded = false;
      double? oldTarget;
      double? newTarget;

      for (final w in activePlan.weeks) {
        if (w.weekNumber < currentWeekNo || isTaper(w)) {
          weeks.add(w); // past or taper — by reference
          continue;
        }
        if (w.weekNumber == currentWeekNo) {
          oldTarget = w.targetKm;
          var mw = _scaleWeekVolume(w, moderateDeloadScale, fromIdx: todayIdx);
          newTarget = mw.targetKm;
          final (down, applied) =
              _downgradeFirstQuality(mw, fromIdx: todayIdx, ePace: ePace);
          if (applied) downgraded = true;
          weeks.add(down);
        } else if (!downgraded) {
          // No quality left in the return week — take the first one from the
          // earliest following non-taper week instead.
          final (down, applied) =
              _downgradeFirstQuality(w, fromIdx: 0, ePace: ePace);
          if (applied) downgraded = true;
          weeks.add(down);
        } else {
          weeks.add(w); // normal progression resumes
        }
      }

      log.add(AdaptationLogEntry(
        at: currentDate,
        reason: 'missed_window_moderate_deload',
        weekNumber: currentWeekNo,
        summary: 'Return week volume eased '
            '${_pctDrop(moderateDeloadScale)}% '
            '(${_km(oldTarget)} → ${_km(newTarget)} km) after $spanDays days off.',
      ));
      if (downgraded) {
        log.add(AdaptationLogEntry(
          at: currentDate,
          reason: 'missed_window_moderate_quality_downgraded',
          weekNumber: currentWeekNo,
          summary: 'First hard session after the break converted to an easy '
              'aerobic run to protect tendons.',
        ));
      }

      return PlanRecalibration(
        updatedPlan: _clone(activePlan, weeks, log),
        missedWindow: MissedWindow.moderate,
        coachExplanation:
            _moderateExplanation(spanDays, oldTarget, newTarget, downgraded),
      );
    }

    // ── extended ────────────────────────────────────────────────────────────
    final nonTaper = activePlan.weeks
        .where((w) => w.weekNumber >= currentWeekNo && !isTaper(w))
        .toList()
      ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));

    // Re-anchor the current week down, then ramp back toward each week's
    // original target at no more than `weeklyProgressionCeiling` per week.
    final newTargets = <int, double>{};
    double? prev;
    for (final w in nonTaper) {
      final t = prev == null
          ? w.targetKm * extendedReanchorScale
          : math.min(w.targetKm, prev * weeklyProgressionCeiling);
      newTargets[w.weekNumber] = _round1(t);
      prev = t;
    }

    final windowEnd = today.add(const Duration(days: aerobicBaseWindowDays));
    final weeks = <MaterializedWeek>[];
    for (final w in activePlan.weeks) {
      if (w.weekNumber < currentWeekNo || isTaper(w)) {
        weeks.add(w); // past or taper — by reference
        continue;
      }
      final fromIdx = w.weekNumber == currentWeekNo ? todayIdx : 0;

      // 1. Strip speedwork inside the 14-day aerobic-base block.
      final converted = <MaterializedDay>[
        for (final d in w.days)
          _maybeAerobicConvert(
            d,
            weekNumber: w.weekNumber,
            week1Start: week1Start,
            windowStart: today,
            windowEnd: windowEnd,
            fromIdx: fromIdx,
            ePace: ePace,
          ),
      ];
      var mw = w.copyWith(days: converted);

      // 2. Re-anchor / ramp weekly volume.
      final nt = newTargets[w.weekNumber];
      if (nt != null) mw = _reanchorWeekVolume(mw, nt, fromIdx: fromIdx);

      weeks.add(mw);
    }

    final anchorOld = nonTaper.isNotEmpty ? nonTaper.first.targetKm : null;
    final anchorNew =
        nonTaper.isNotEmpty ? newTargets[nonTaper.first.weekNumber] : null;
    final log = <AdaptationLogEntry>[
      AdaptationLogEntry(
        at: currentDate,
        reason: 'missed_window_extended_reanchor',
        weekNumber: currentWeekNo,
        summary: 'Weekly volume re-anchored '
            '${_pctDrop(extendedReanchorScale)}% '
            '(${_km(anchorOld)} → ${_km(anchorNew)} km) and rebuilt to race day '
            'at ≤ ${((weeklyProgressionCeiling - 1) * 100).round()}%/week '
            'after $spanDays days off.',
      ),
      AdaptationLogEntry(
        at: currentDate,
        reason: 'missed_window_extended_aerobic_base',
        weekNumber: currentWeekNo,
        summary: 'Next $aerobicBaseWindowDays days set to strict easy / long '
            'aerobic — all speed and threshold work removed.',
      ),
    ];

    return PlanRecalibration(
      updatedPlan: _clone(activePlan, weeks, log),
      missedWindow: MissedWindow.extended,
      coachExplanation:
          _extendedExplanation(spanDays, anchorOld, anchorNew),
    );
  }

  // ── Volume helpers ────────────────────────────────────────────────────────

  /// Multiply a week's target + every not-yet-done workout (weekday ≥ [fromIdx])
  /// by [factor].
  MaterializedWeek _scaleWeekVolume(
    MaterializedWeek w,
    double factor, {
    int fromIdx = 0,
  }) {
    final days = [
      for (final d in w.days)
        (d.weekday >= fromIdx &&
                d.completion == null &&
                d.workout != null &&
                !d.slot.isRest)
            ? d.copyWith(workout: _scaleDistance(d.workout!, factor))
            : d,
    ];
    return w.copyWith(targetKm: _round1(w.targetKm * factor), days: days);
  }

  /// Set a week's target to [newTarget] and scale its not-yet-done workouts
  /// (weekday ≥ [fromIdx]) by the same ratio.
  MaterializedWeek _reanchorWeekVolume(
    MaterializedWeek w,
    double newTarget, {
    int fromIdx = 0,
  }) {
    final base = w.plannedKm > 0 ? w.plannedKm : w.targetKm;
    final f = base > 0 ? newTarget / base : 1.0;
    final days = [
      for (final d in w.days)
        (d.weekday >= fromIdx &&
                d.completion == null &&
                d.workout != null &&
                !d.slot.isRest)
            ? d.copyWith(workout: _scaleDistance(d.workout!, f))
            : d,
    ];
    return w.copyWith(targetKm: _round1(newTarget), days: days);
  }

  ResolvedWorkout _scaleDistance(ResolvedWorkout wk, double f) => ResolvedWorkout(
        templateId: wk.templateId,
        name: wk.name,
        intent: wk.intent,
        phase: wk.phase,
        coachNote: wk.coachNote,
        blocks: [
          for (final b in wk.blocks)
            ResolvedBlock(
              type: b.type,
              distanceKm: _round1(b.distanceKm * f),
              paceMinSecondsPerKm: b.paceMinSecondsPerKm,
              paceMaxSecondsPerKm: b.paceMaxSecondsPerKm,
              durationSeconds: b.durationSeconds,
              isRpeOnly: b.isRpeOnly,
              reps: b.reps,
              recoverySeconds: b.recoverySeconds,
              recoveryMeters: b.recoveryMeters,
              label: b.label,
            ),
        ],
      );

  // ── Slot helpers ──────────────────────────────────────────────────────────

  /// Convert the earliest not-yet-done quality day at/after [fromIdx] into an
  /// easy aerobic run. Returns `(week, wasApplied)`.
  (MaterializedWeek, bool) _downgradeFirstQuality(
    MaterializedWeek w, {
    required int fromIdx,
    required (int, int) ePace,
  }) {
    for (var i = 0; i < w.days.length; i++) {
      final d = w.days[i];
      if (d.weekday < fromIdx || d.completion != null || !d.slot.isQuality) {
        continue;
      }
      final days = List<MaterializedDay>.of(w.days);
      days[i] = _toEasyAerobic(d, ePace);
      return (w.copyWith(days: days), true);
    }
    return (w, false);
  }

  /// Inside the aerobic-base window, turn any not-done quality day or speed-
  /// intent day into an easy aerobic run. Long runs (endurance intent) are
  /// kept — they *are* aerobic base.
  MaterializedDay _maybeAerobicConvert(
    MaterializedDay d, {
    required int weekNumber,
    required DateTime week1Start,
    required DateTime windowStart,
    required DateTime windowEnd,
    required int fromIdx,
    required (int, int) ePace,
  }) {
    if (d.weekday < fromIdx || d.completion != null || d.isRest) return d;
    final dayDate = PlanCalendar.dateFor(week1Start, weekNumber, d.weekday);
    if (dayDate.isBefore(windowStart) || dayDate.isAfter(windowEnd)) return d;

    final isHard = d.slot.isQuality ||
        (d.intent != null && _speedIntents.contains(d.intent));
    if (!isHard) return d;
    return _toEasyAerobic(d, ePace);
  }

  MaterializedDay _toEasyAerobic(MaterializedDay d, (int, int) ePace) {
    final km = d.workout?.totalDistanceKm ?? 6.0;
    return MaterializedDay(
      weekday: d.weekday,
      slot: MaterializedSlot.easy,
      intent: WorkoutIntent.aerobicBase,
      templateId: 'easy_aerobic_return',
      progressionStep: 0,
      completion: d.completion,
      workout: ResolvedWorkout(
        templateId: 'easy_aerobic_return',
        name: 'Easy aerobic run',
        intent: WorkoutIntent.aerobicBase,
        phase: d.workout?.phase ?? TrainingPhase.base,
        coachNote: 'Converted from a hard session while you rebuild — keep this '
            'conversational.',
        blocks: [
          ResolvedBlock(
            type: BlockType.main,
            distanceKm: _round1(km),
            paceMinSecondsPerKm: ePace.$1,
            paceMaxSecondsPerKm: ePace.$2,
          ),
        ],
      ),
    );
  }

  // ── Plan assembly ─────────────────────────────────────────────────────────

  MaterializedPlan _clone(
    MaterializedPlan p,
    List<MaterializedWeek> weeks,
    List<AdaptationLogEntry> newLog,
  ) =>
      p.copyWith(
        weeks: weeks,
        adaptationLog: [...p.adaptationLog, ...newLog],
      );

  // ── Window detection ──────────────────────────────────────────────────────

  int _longestConsecutiveSpan(List<DateTime> dates) {
    if (dates.isEmpty) return 0;
    final days = dates.map(_dateOnly).toSet().toList()..sort();
    var best = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i].difference(days[i - 1]).inDays == 1) {
        run++;
        best = math.max(best, run);
      } else {
        run = 1;
      }
    }
    return best;
  }

  // ── Coach copy ────────────────────────────────────────────────────────────

  String _briefExplanation(int days) =>
      "You missed ${_days(days)}. That's nothing to worry about — your aerobic "
      'fitness barely moves over 48 hours, so there is no lost ground to make '
      'up. Pick up today with the run already on your schedule, exactly as '
      "written. I'm deliberately not stacking the missed mileage back on: "
      'cramming it in is how a quiet week turns into a strained calf or a '
      'cranky Achilles. Straight back to normal.';

  String _moderateExplanation(
    int days,
    double? oldKm,
    double? newKm,
    bool downgraded,
  ) =>
      'You were out for ${_days(days)} — roughly a week. Your engine (heart, '
      'lungs, blood volume) is still in good shape, but tendons and the small '
      'stabilising muscles lose their springiness quickly when you stop. So for '
      'this return week I have trimmed planned volume by '
      '${_pctDrop(moderateDeloadScale)}% (about ${_km(oldKm)} → ${_km(newKm)} '
      'km)${downgraded ? ' and turned your next hard session into an easy '
          'aerobic run' : ''}. That protects your Achilles and knees while the '
      'connective tissue re-adapts. From next week you are back on the normal '
      'progression.';

  String _extendedExplanation(int days, double? oldKm, double? newKm) =>
      'You have been out for ${_days(days)}, so we rebuild rather than resume. '
      'Over a break this long, plasma volume drops and running economy fades — '
      'holding the old paces now invites overtraining and bone-stress injury. '
      'The plan: weekly volume is re-anchored '
      '${_pctDrop(extendedReanchorScale)}% lower (about ${_km(oldKm)} → '
      '${_km(newKm)} km this week), the next $aerobicBaseWindowDays days are '
      'strictly easy / long aerobic with every speed and threshold session '
      'converted, and from there volume climbs back toward race day at no more '
      'than ${((weeklyProgressionCeiling - 1) * 100).round()}% per week. Your '
      'final two taper weeks are untouched, so you will still arrive fresh.';

  String _taperProtectedExplanation(MissedWindow window, int days) =>
      'You missed ${_days(days)}, but you are already in the race taper. The '
      'taper exists to bank freshness, and there is no time left to safely '
      'rebuild volume before race day — so the plan stays exactly as it is. '
      'Run what is scheduled, keep it relaxed, and trust the work already in '
      'the bank.';

  // ── Formatting ────────────────────────────────────────────────────────────

  static String _days(int n) => n == 1 ? '1 day' : '$n days';
  static String _km(double? v) => v == null ? '—' : v.toStringAsFixed(0);
  static int _pctDrop(double scale) => ((1 - scale) * 100).round();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static double _round1(double v) => (v * 10).round() / 10;
}
