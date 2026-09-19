/// VdotAdaptationGuard — safety rails on the weekly vDOT nudge.
///
/// Pure: given the nudge the pace evidence proposes and the athlete's plan
/// context, decides what may actually be applied. Upward shifts (faster paces)
/// are rationed; downward shifts (easing paces after high RPE / fatigue) always
/// pass, so an athlete who is struggling is never held to stale paces.
///
///   • Proportional cap — the shorter the plan, the less fitness we bank:
///       ≤ 4 weeks : no upward shift at all
///       ≤ 8 weeks : +1 total, 14-day consolidation between rises
///       ≥ 9 weeks : +2 total (+3 for a beginner), 28-day consolidation
///     "Total" is measured against the vDOT the plan started from.
///   • Taper lock — no upward shift while tapering; a race-week pace change
///     only adds risk.
///   • Consolidation lockout — after an upward shift, no further upward shift
///     until the interval has elapsed.
library;

import '../../models/race_plan.dart';
import '../../models/training_phase.dart';

/// The caps that apply to a plan of a given length / athlete level.
class VdotAdaptationLimits {
  /// Maximum cumulative upward gain over the plan's starting vDOT.
  final int maxUpwardGain;

  /// Days that must pass after an upward shift before the next one.
  final int consolidationDays;

  const VdotAdaptationLimits({
    required this.maxUpwardGain,
    required this.consolidationDays,
  });
}

/// Why an upward nudge was (not) applied — surfaced in logs and tests.
enum VdotShiftReason {
  /// Nothing proposed.
  none,

  /// Applied as proposed.
  applied,

  /// Downward shift: always allowed, bypasses every upward guard.
  downwardBypass,

  /// Plan is too short to bank any fitness.
  planTooShort,

  /// Athlete is in the plan's taper.
  taperLock,

  /// Within the consolidation interval of the last upward shift.
  consolidationLockout,

  /// Already at the plan's maximum upward gain.
  gainCapReached,
}

class VdotShiftDecision {
  /// The nudge to apply (may be smaller than proposed, or 0).
  final int applied;
  final VdotShiftReason reason;

  const VdotShiftDecision(this.applied, this.reason);

  bool get isUpward => applied > 0;

  @override
  String toString() => 'VdotShiftDecision($applied, ${reason.name})';
}

class VdotAdaptationGuard {
  const VdotAdaptationGuard._();

  /// Limits for a plan spanning [planWeeks]. A null length (no race plan) uses
  /// the long-plan tier — there is no short deadline to protect.
  static VdotAdaptationLimits limitsFor({
    required int? planWeeks,
    required bool isBeginner,
  }) {
    if (planWeeks != null && planWeeks <= 4) {
      return const VdotAdaptationLimits(maxUpwardGain: 0, consolidationDays: 0);
    }
    if (planWeeks != null && planWeeks <= 8) {
      return const VdotAdaptationLimits(
        maxUpwardGain: 1,
        consolidationDays: 14,
      );
    }
    return VdotAdaptationLimits(
      maxUpwardGain: isBeginner ? 3 : 2,
      consolidationDays: 28,
    );
  }

  /// Weeks at the end of the plan that count as taper: the final week for
  /// plans up to 8 weeks, otherwise 3 for a marathon, 2 for a half, 1 else.
  static int taperWeeks({required int planWeeks, required String goalRace}) {
    if (planWeeks <= 8) return 1;
    return switch (goalRace) {
      'marathon' => 3,
      'half_marathon' => 2,
      _ => 1,
    };
  }

  /// True when [today] falls in the plan's taper — either the plan itself
  /// labels the week as taper, or it is inside the final [taperWeeks].
  static bool isInTaper({required RacePlan plan, required DateTime today}) {
    if (plan.weeks.isEmpty) return false;
    if (plan.currentWeek(today)?.phase == TrainingPhase.taper) return true;
    final total = plan.totalWeeks;
    final weekNo = plan.currentWeekNumber(today);
    final remainingInclusive = total - weekNo + 1;
    return remainingInclusive <=
        taperWeeks(planWeeks: total, goalRace: plan.goalRace);
  }

  /// Decide what part of [proposed] may be applied.
  ///
  /// [currentVdot] and [anchorVdot] (vDOT at plan start) bound the cumulative
  /// gain. [plan] is null when the athlete has no race plan.
  static VdotShiftDecision resolve({
    required int proposed,
    required int currentVdot,
    required int anchorVdot,
    required RacePlan? plan,
    required DateTime? lastUpwardShift,
    required DateTime today,
  }) {
    if (proposed == 0) return const VdotShiftDecision(0, VdotShiftReason.none);
    if (proposed < 0) {
      return VdotShiftDecision(proposed, VdotShiftReason.downwardBypass);
    }

    final limits = limitsFor(
      planWeeks: plan?.totalWeeks,
      isBeginner: plan?.experienceLevel == 'beginner',
    );
    if (limits.maxUpwardGain == 0) {
      return const VdotShiftDecision(0, VdotShiftReason.planTooShort);
    }
    if (plan != null && isInTaper(plan: plan, today: today)) {
      return const VdotShiftDecision(0, VdotShiftReason.taperLock);
    }
    if (lastUpwardShift != null &&
        today.difference(lastUpwardShift).inDays < limits.consolidationDays) {
      return const VdotShiftDecision(0, VdotShiftReason.consolidationLockout);
    }

    final headroom = anchorVdot + limits.maxUpwardGain - currentVdot;
    if (headroom <= 0) {
      return const VdotShiftDecision(0, VdotShiftReason.gainCapReached);
    }
    final applied = proposed < headroom ? proposed : headroom;
    return VdotShiftDecision(applied, VdotShiftReason.applied);
  }
}
