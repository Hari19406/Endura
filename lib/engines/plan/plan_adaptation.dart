/// PlanAdaptation — the closed-loop mutation engine.
///
/// Pure: [reconcile] takes the persisted [MaterializedPlan], the athlete's run
/// history, their [PlanConfigState] and "now", and returns a possibly-mutated
/// plan plus a receipt of what changed. No I/O. The caller
/// ([AdaptationCoordinator]) does the loading and saving.
///
/// INVARIANTS
///   • Completed weeks (frozen, or whose calendar week ends on/before `asOfDate`,
///     or every training day already logged) are returned **by reference** —
///     never rebuilt, never touched.
///   • Forward-only: only the current week's not-yet-past days and whole future
///     weeks are eligible for mutation.
///   • The 3:1 cutback cadence and hard/easy separation are preserved — a shift
///     that would put two hard days back to back is rejected.
///   • Bounded: at most ONE structural mutation (a missed-session shift / carry /
///     drop) per call, plus at most one volume action and one pace recalibration.
library;

import '../config/workout_template_library.dart'
    show ResolvedBlock, ResolvedWorkout, WorkoutIntent;
import '../core/vdot_calculator.dart' show pacesFor;
import '../../models/plan_config_state.dart';
import '../../models/training_phase.dart';
import '../../utils/plan_calendar.dart';
import 'materialized_plan.dart';

/// A logged run, reduced to what adaptation needs. The caller builds these from
/// run history.
class RunSession {
  final DateTime date;
  final double distanceKm;

  /// Best-effort classification; null for an unlabelled / free run.
  final WorkoutIntent? intent;
  final int? paceSecPerKm;
  final int? rpe;

  const RunSession({
    required this.date,
    required this.distanceKm,
    this.intent,
    this.paceSecPerKm,
    this.rpe,
  });
}

class AdaptationResult {
  /// The plan after reconciliation. Identical instance to the input when
  /// [applied] is empty.
  final MaterializedPlan plan;
  final List<AdaptationLogEntry> applied;

  const AdaptationResult({required this.plan, required this.applied});

  bool get changed => applied.isNotEmpty;
}

class _Partition {
  final List<MaterializedWeek> frozen;
  final MaterializedWeek? current;
  final List<MaterializedWeek> future;
  final int currentWeekNo;
  final int todayIdx;

  const _Partition({
    required this.frozen,
    required this.current,
    required this.future,
    required this.currentWeekNo,
    required this.todayIdx,
  });
}

class PlanAdaptation {
  const PlanAdaptation._();

  /// Volume-drift thresholds.
  static const _shortfallRatio = 0.80;
  static const _overshootRatio = 1.15;
  static const _shortfallScale = 0.88; // within the spec's 0.85–0.90 band

  static AdaptationResult reconcile({
    required MaterializedPlan plan,
    required List<RunSession> history,
    required PlanConfigState config,
    required DateTime asOfDate,
  }) {
    if (plan.weeks.isEmpty) {
      return AdaptationResult(plan: plan, applied: const []);
    }

    final week1Start = plan.week1Monday;

    // Week 1 can be a partial week (the plan starts mid-week). Slots before
    // the start date are pre-plan: never the athlete's, so never "missed",
    // never counted toward "all done", never part of the planned volume.
    int firstActive(MaterializedWeek w) => plan.firstActiveWeekday(w.weekNumber);

    final parts = _partition(plan, asOfDate);
    final currentWeekNo = parts.currentWeekNo;
    final todayIdx = parts.todayIdx;
    final frozen = parts.frozen;
    final current = parts.current;
    final future = parts.future;

    final log = <AdaptationLogEntry>[];
    var mutatedCurrent = current;
    var mutatedFuture = List<MaterializedWeek>.of(future);

    // ── Rule 1: missed key session (ONE structural mutation) ───────────────
    final structural = _applyMissedKeySession(
      current: mutatedCurrent,
      future: mutatedFuture,
      previousWeek: _weekByNumber(plan, currentWeekNo - 1),
      week1Start: week1Start,
      firstActive: firstActive,
      asOfDate: asOfDate,
      todayIdx: todayIdx,
      currentWeekNo: currentWeekNo,
      log: log,
    );
    mutatedCurrent = structural.$1;
    mutatedFuture = structural.$2;

    // ── Rule 2: volume drift over the last two completed weeks ─────────────
    _applyVolumeDrift(
      plan: plan,
      history: history,
      week1Start: week1Start,
      firstActive: firstActive,
      currentWeekNo: currentWeekNo,
      current: mutatedCurrent,
      future: mutatedFuture,
      todayIdx: todayIdx,
      asOfDate: asOfDate,
      onCurrent: (w) => mutatedCurrent = w,
      onFuture: (i, w) => mutatedFuture[i] = w,
      log: log,
    );

    // ── Rule 3: pace recalibration ────────────────────────────────────────
    final newVdot = config.vDOT.round();
    var builtFromVdot = plan.builtFromVdot;
    if ((newVdot - plan.builtFromVdot).abs() >= 1) {
      final factor = _paceScale(plan.builtFromVdot, newVdot);
      mutatedCurrent = mutatedCurrent == null
          ? null
          : _recalibrateWeekPaces(mutatedCurrent!, factor, fromIdx: todayIdx + 1);
      mutatedFuture = [
        for (final w in mutatedFuture) _recalibrateWeekPaces(w, factor)
      ];
      builtFromVdot = newVdot;
      log.add(AdaptationLogEntry(
        at: asOfDate,
        reason: 'pace_recalibrated',
        summary: 'Training paces updated for VDOT '
            '${plan.builtFromVdot} → $newVdot across all upcoming weeks.',
      ));
    }

    if (log.isEmpty) {
      return AdaptationResult(plan: plan, applied: const []);
    }

    // ── Reassemble (frozen by reference) ──────────────────────────────────
    final weeks = <MaterializedWeek>[
      ...frozen,
      if (mutatedCurrent != null) mutatedCurrent!,
      ...mutatedFuture,
    ]..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));

    return AdaptationResult(
      plan: plan.copyWith(
        weeks: weeks,
        builtFromVdot: builtFromVdot,
        adaptationLog: [...plan.adaptationLog, ...log],
      ),
      applied: log,
    );
  }

  /// Pace-only adaptation: re-price the remaining plan for [newVdot] and touch
  /// nothing else. Skips the missed-session and volume rules of [reconcile] —
  /// a change in fitness estimate must never move a workout to another day,
  /// change its distance, or swap its type.
  ///
  /// Same forward-only guarantees as [reconcile]: frozen/past weeks are returned
  /// by reference, days before tomorrow in the current week and any day with a
  /// completion keep their original paces. Identical instance when the VDOT
  /// differs from the plan's [MaterializedPlan.builtFromVdot] by less than 1.
  static AdaptationResult recalibratePaces({
    required MaterializedPlan plan,
    required int newVdot,
    required DateTime asOfDate,
  }) {
    if (plan.weeks.isEmpty || (newVdot - plan.builtFromVdot).abs() < 1) {
      return AdaptationResult(plan: plan, applied: const []);
    }

    final parts = _partition(plan, asOfDate);
    final factor = _paceScale(plan.builtFromVdot, newVdot);
    final current = parts.current == null
        ? null
        : _recalibrateWeekPaces(
            parts.current!,
            factor,
            fromIdx: parts.todayIdx + 1,
          );
    final future = [
      for (final w in parts.future) _recalibrateWeekPaces(w, factor),
    ];

    final entry = AdaptationLogEntry(
      at: asOfDate,
      reason: 'pace_recalibrated',
      summary: 'Training paces updated for VDOT '
          '${plan.builtFromVdot} → $newVdot across all upcoming weeks.',
    );
    final weeks = <MaterializedWeek>[
      ...parts.frozen,
      ?current,
      ...future,
    ]..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));

    return AdaptationResult(
      plan: plan.copyWith(
        weeks: weeks,
        builtFromVdot: newVdot,
        adaptationLog: [...plan.adaptationLog, entry],
      ),
      applied: [entry],
    );
  }

  /// Split the plan into past/frozen weeks, the current week, and future weeks
  /// as of [asOfDate]. Frozen weeks are kept by reference.
  static _Partition _partition(MaterializedPlan plan, DateTime asOfDate) {
    final week1Start = plan.week1Monday;
    final currentWeekNo = _weekNumberFor(asOfDate, week1Start, plan.totalWeeks);
    final frozen = <MaterializedWeek>[];
    MaterializedWeek? current;
    final future = <MaterializedWeek>[];

    for (final w in plan.weeks) {
      final wEnd = PlanCalendar.dateFor(week1Start, w.weekNumber + 1, 0);
      final isPast = w.isFrozen ||
          !wEnd.isAfter(asOfDate) ||
          _allTrainingDaysDone(w, fromIdx: plan.firstActiveWeekday(w.weekNumber));
      if (isPast) {
        frozen.add(w); // by reference — untouched
      } else if (w.weekNumber == currentWeekNo) {
        current = w;
      } else if (w.weekNumber > currentWeekNo) {
        future.add(w);
      } else {
        // A not-yet-past week numbered below "current" (clock skew) — leave it.
        frozen.add(w);
      }
    }
    future.sort((a, b) => a.weekNumber.compareTo(b.weekNumber));

    return _Partition(
      frozen: frozen,
      current: current,
      future: future,
      currentWeekNo: currentWeekNo,
      todayIdx: asOfDate.weekday - 1, // 0 = Monday
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RULE 1 — MISSED KEY SESSION
  // ══════════════════════════════════════════════════════════════════════════

  static (MaterializedWeek?, List<MaterializedWeek>) _applyMissedKeySession({
    required MaterializedWeek? current,
    required List<MaterializedWeek> future,
    required MaterializedWeek? previousWeek,
    required DateTime week1Start,
    required int Function(MaterializedWeek) firstActive,
    required DateTime asOfDate,
    required int todayIdx,
    required int currentWeekNo,
    required List<AdaptationLogEntry> log,
  }) {
    // 1a — a key day earlier THIS week was missed and days remain: shift it.
    if (current != null) {
      final missed = _firstMissedKeyDayIndex(
        current,
        todayIdx,
        fromIdx: firstActive(current),
      );
      if (missed != null) {
        final candidate = _shiftTargetIndex(current, missed, todayIdx);
        if (candidate != null) {
          final days = List<MaterializedDay>.of(current.days);
          final key = days[missed];
          final host = days[candidate];
          days[missed] = _withContent(key, from: host); // key day takes the easy
          days[candidate] = _withContent(host, from: key); // host takes the key
          log.add(AdaptationLogEntry(
            at: asOfDate,
            reason: 'missed_key_shifted',
            weekNumber: current.weekNumber,
            summary: 'Missed ${_slotName(key.slot)} moved from '
                '${_dayName(missed)} to ${_dayName(candidate)}; '
                '${_dayName(missed)} is now an easy run.',
          ));
          return (current.copyWith(days: days), future);
        }
      }
    }

    // 1b — last week ended with a missed key session: carry ONE forward,
    //      or drop it if we're tapering.
    if (previousWeek != null && current != null) {
      final missedIdx = _firstMissedKeyDayIndex(
        previousWeek,
        7,
        fromIdx: firstActive(previousWeek),
      );
      if (missedIdx != null) {
        final missedDay = previousWeek.days[missedIdx];
        final isLong = missedDay.slot == MaterializedSlot.longRun;
        final tapering = previousWeek.phase == TrainingPhase.taper ||
            current.phase == TrainingPhase.taper;

        if (isLong && tapering) {
          log.add(AdaptationLogEntry(
            at: asOfDate,
            reason: 'missed_long_dropped_taper',
            weekNumber: previousWeek.weekNumber,
            summary: 'Missed long run in the taper was dropped to protect '
                'race-week recovery.',
          ));
          return (current, future);
        }

        final carried = _carryInto(
          current,
          missedDay,
          fromIdx: firstActive(current),
        );
        if (carried != null) {
          log.add(AdaptationLogEntry(
            at: asOfDate,
            reason: 'missed_key_carried',
            weekNumber: current.weekNumber,
            summary: 'Missed ${_slotName(missedDay.slot)} from last week '
                'carried into ${_dayName(carried.$2)} this week.',
          ));
          return (carried.$1, future);
        }

        log.add(AdaptationLogEntry(
          at: asOfDate,
          reason: 'missed_key_not_carried',
          weekNumber: previousWeek.weekNumber,
          summary: 'Missed ${_slotName(missedDay.slot)} from last week could '
              'not be re-fit without stacking hard days — skipped.',
        ));
        return (current, future);
      }
    }

    return (current, future);
  }

  /// Index of the earliest quality/long day in `[fromIdx, beforeIdx)` that has
  /// no completion, or null. [fromIdx] skips a partial first week's pre-plan
  /// slots.
  static int? _firstMissedKeyDayIndex(
    MaterializedWeek w,
    int beforeIdx, {
    int fromIdx = 0,
  }) {
    for (var i = fromIdx; i < w.days.length && i < beforeIdx; i++) {
      final d = w.days[i];
      if (d.completion == null && _isKey(d.slot) && d.workout != null) return i;
    }
    return null;
  }

  /// A future day this week that can host the shifted key session without
  /// creating back-to-back hard days.
  static int? _shiftTargetIndex(MaterializedWeek w, int missedIdx, int todayIdx) {
    for (var j = todayIdx + 1; j < w.days.length; j++) {
      final d = w.days[j];
      if (d.completion != null) continue;
      if (d.slot != MaterializedSlot.easy &&
          d.slot != MaterializedSlot.mediumLong) {
        continue;
      }
      final trial = List<MaterializedDay>.of(w.days);
      final key = trial[missedIdx];
      trial[missedIdx] = _withContent(trial[missedIdx], from: d);
      trial[j] = _withContent(d, from: key);
      if (!_hasBackToBackHard(trial)) return j;
    }
    return null;
  }

  /// Put [missedDay]'s session onto an easy day of [week], respecting hard/easy
  /// separation and never creating a second long run or a third quality.
  static (MaterializedWeek, int)? _carryInto(
    MaterializedWeek week,
    MaterializedDay missedDay, {
    int fromIdx = 0,
  }) {
    final isLong = missedDay.slot == MaterializedSlot.longRun;
    if (isLong && week.hasLongRun) return null;
    if (!isLong && week.qualityCount >= 2) {
      // replace the lowest-priority quality (quality2) rather than add a third
      final q2 = week.days.indexWhere((d) => d.slot == MaterializedSlot.quality2);
      // A pre-plan slot can't host a session — it isn't the athlete's day.
      if (q2 < fromIdx) return null;
      final days = List<MaterializedDay>.of(week.days);
      days[q2] = _withContent(days[q2], from: missedDay);
      if (_hasBackToBackHard(days)) return null;
      return (week.copyWith(days: days), q2);
    }

    for (var j = fromIdx; j < week.days.length; j++) {
      final d = week.days[j];
      if (d.completion != null || d.slot != MaterializedSlot.easy) continue;
      final days = List<MaterializedDay>.of(week.days);
      days[j] = _withContent(d, from: missedDay);
      if (!_hasBackToBackHard(days)) return (week.copyWith(days: days), j);
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RULE 2 — VOLUME DRIFT
  // ══════════════════════════════════════════════════════════════════════════

  static void _applyVolumeDrift({
    required MaterializedPlan plan,
    required List<RunSession> history,
    required DateTime week1Start,
    required int Function(MaterializedWeek) firstActive,
    required int currentWeekNo,
    required MaterializedWeek? current,
    required List<MaterializedWeek> future,
    required int todayIdx,
    required DateTime asOfDate,
    required void Function(MaterializedWeek) onCurrent,
    required void Function(int, MaterializedWeek) onFuture,
    required List<AdaptationLogEntry> log,
  }) {
    final wA = _weekByNumber(plan, currentWeekNo - 1);
    final wB = _weekByNumber(plan, currentWeekNo - 2);
    if (wA == null || wB == null) return;

    double ratio(MaterializedWeek w) {
      // A partial first week is judged only on the days the athlete actually
      // had: planned km and the run window both start at the plan's first
      // active day, not Monday.
      final fromIdx = firstActive(w);
      final activePlanned = w.days
          .where((d) => d.weekday >= fromIdx)
          .fold<double>(0, (s, d) => s + d.plannedKm);
      final planned = activePlanned > 0
          ? activePlanned
          : (w.plannedKm > 0 ? w.plannedKm : w.targetKm);
      if (planned <= 0) return 1.0;
      final start = PlanCalendar.dateFor(week1Start, w.weekNumber, fromIdx);
      final end = PlanCalendar.dateFor(week1Start, w.weekNumber + 1, 0);
      final done = history
          .where((r) => !r.date.isBefore(start) && r.date.isBefore(end))
          .fold<double>(0, (s, r) => s + r.distanceKm);
      return done / planned;
    }

    final rA = ratio(wA);
    final rB = ratio(wB);

    // Shortfall: scale the current week's remaining days + the next future week.
    if (rA < _shortfallRatio && rB < _shortfallRatio) {
      if (current != null) {
        onCurrent(_scaleWeekVolume(current, _shortfallScale, fromIdx: todayIdx + 1));
      }
      if (future.isNotEmpty) {
        onFuture(0, _scaleWeekVolume(future.first, _shortfallScale));
      }
      log.add(AdaptationLogEntry(
        at: asOfDate,
        reason: 'volume_shortfall_scaled',
        weekNumber: current?.weekNumber ?? currentWeekNo,
        summary: 'Two low-volume weeks in a row — upcoming volume eased to '
            '${(_shortfallScale * 100).round()}% so you can rebuild safely.',
      ));
      return;
    }

    // Overshoot: don't raise anything, and bank a recovery day next week.
    if (rA > _overshootRatio && rB > _overshootRatio && future.isNotEmpty) {
      final w = future.first;
      final j = w.days.indexWhere((d) =>
          d.completion == null &&
          (d.slot == MaterializedSlot.easy ||
              d.slot == MaterializedSlot.mediumLong));
      if (j >= 0) {
        final days = List<MaterializedDay>.of(w.days);
        days[j] = _restDay(days[j].weekday);
        onFuture(0, w.copyWith(days: days));
        log.add(AdaptationLogEntry(
          at: asOfDate,
          reason: 'volume_overshoot_rest',
          weekNumber: w.weekNumber,
          summary: 'You have been running well over plan — next week keeps its '
              'original target and swaps one easy day for full rest.',
        ));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MUTATION HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  static bool _isKey(MaterializedSlot s) =>
      s == MaterializedSlot.quality1 ||
      s == MaterializedSlot.quality2 ||
      s == MaterializedSlot.longRun;

  static bool _isHard(MaterializedSlot s) => _isKey(s);

  static bool _hasBackToBackHard(List<MaterializedDay> days) {
    final sorted = [...days]..sort((a, b) => a.weekday.compareTo(b.weekday));
    for (var i = 0; i + 1 < sorted.length; i++) {
      if (sorted[i].weekday + 1 == sorted[i + 1].weekday &&
          _isHard(sorted[i].slot) &&
          _isHard(sorted[i + 1].slot)) {
        return true;
      }
    }
    return false;
  }

  static bool _allTrainingDaysDone(MaterializedWeek w, {int fromIdx = 0}) {
    final training = w.days.where((d) => !d.isRest && d.weekday >= fromIdx);
    return training.isNotEmpty && training.every((d) => d.completion != null);
  }

  /// A copy of [target] carrying [from]'s session content (slot/intent/template/
  /// workout/progression) but keeping [target]'s calendar weekday + completion.
  static MaterializedDay _withContent(
    MaterializedDay target, {
    required MaterializedDay from,
  }) =>
      MaterializedDay(
        weekday: target.weekday,
        slot: from.slot,
        intent: from.intent,
        templateId: from.templateId,
        progressionStep: from.progressionStep,
        workout: from.workout,
        completion: target.completion,
      );

  static MaterializedDay _restDay(int weekday) =>
      MaterializedDay(weekday: weekday, slot: MaterializedSlot.rest);

  // ── Volume scaling ──────────────────────────────────────────────────────

  static MaterializedWeek _scaleWeekVolume(
    MaterializedWeek w,
    double factor, {
    int fromIdx = 0,
  }) {
    final days = [
      for (final d in w.days)
        (d.weekday >= fromIdx && d.completion == null && d.workout != null)
            ? d.copyWith(workout: _scaleWorkoutDistance(d.workout!, factor))
            : d,
    ];
    return w.copyWith(targetKm: _round1(w.targetKm * factor), days: days);
  }

  static ResolvedWorkout _scaleWorkoutDistance(ResolvedWorkout wk, double f) =>
      _rebuild(wk, (b) => ResolvedBlock(
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
          ));

  // ── Pace recalibration ──────────────────────────────────────────────────

  static double _paceScale(int oldVdot, int newVdot) {
    double mid(int v) {
      final e = pacesFor(v).ePaceSecPerKm;
      return (e.$1 + e.$2) / 2.0;
    }

    final s = mid(newVdot) / mid(oldVdot);
    return s.clamp(0.85, 1.18);
  }

  static MaterializedWeek _recalibrateWeekPaces(
    MaterializedWeek w,
    double factor, {
    int fromIdx = 0,
  }) {
    final days = [
      for (final d in w.days)
        (d.weekday >= fromIdx && d.completion == null && d.workout != null)
            ? d.copyWith(workout: _scaleWorkoutPace(d.workout!, factor))
            : d,
    ];
    return w.copyWith(days: days);
  }

  static ResolvedWorkout _scaleWorkoutPace(ResolvedWorkout wk, double f) =>
      _rebuild(wk, (b) => ResolvedBlock(
            type: b.type,
            distanceKm: b.distanceKm,
            paceMinSecondsPerKm: (b.paceMinSecondsPerKm * f).round(),
            paceMaxSecondsPerKm: (b.paceMaxSecondsPerKm * f).round(),
            durationSeconds: b.durationSeconds,
            isRpeOnly: b.isRpeOnly,
            reps: b.reps,
            recoverySeconds: b.recoverySeconds,
            recoveryMeters: b.recoveryMeters,
            label: b.label,
          ));

  static ResolvedWorkout _rebuild(
    ResolvedWorkout wk,
    ResolvedBlock Function(ResolvedBlock) map,
  ) =>
      ResolvedWorkout(
        templateId: wk.templateId,
        name: wk.name,
        intent: wk.intent,
        phase: wk.phase,
        coachNote: wk.coachNote,
        blocks: wk.blocks.map(map).toList(),
      );

  // ── Date / lookup helpers ───────────────────────────────────────────────

  static int _weekNumberFor(DateTime asOf, DateTime week1Start, int total) {
    final elapsed = PlanCalendar.daysBetween(week1Start, asOf);
    return (elapsed ~/ 7 + 1).clamp(1, total);
  }

  static MaterializedWeek? _weekByNumber(MaterializedPlan p, int n) {
    for (final w in p.weeks) {
      if (w.weekNumber == n) return w;
    }
    return null;
  }

  static double _round1(double v) => (v * 10).round() / 10;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static String _dayName(int i) => _dayNames[i.clamp(0, 6)];

  static String _slotName(MaterializedSlot s) => switch (s) {
        MaterializedSlot.quality1 ||
        MaterializedSlot.quality2 =>
          'quality session',
        MaterializedSlot.longRun => 'long run',
        MaterializedSlot.mediumLong => 'medium-long run',
        MaterializedSlot.easy => 'easy run',
        MaterializedSlot.rest => 'rest day',
      };
}
