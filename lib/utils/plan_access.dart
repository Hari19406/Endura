/// Free-tier plan access: the first two plan weeks (the first 14 calendar days
/// of a Monday-aligned plan) are fully unlocked; week 3 onward is paywalled for
/// anyone without an active premium entitlement (the RevenueCat entitlement
/// already covers the free trial).
///
/// Locked weeks stay *visible* in the schedule — only their session detail is
/// gated — and tapping one opens the subscription flow.
const int kFreePlanWeeks = 2;

bool isPlanWeekLocked({required int weekNumber, required bool isPro}) =>
    !isPro && weekNumber > kFreePlanWeeks;
