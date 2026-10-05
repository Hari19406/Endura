/// Master switch for the "How do you feel?" pre-run check-in and every pace/
/// volume adjustment driven by readiness (feeling, sleep, pain). When false the
/// check sheet is never shown and workouts resolve at their standard prescribed
/// paces. Flip to true to restore the feature.
const bool enableReadinessPaceAdjustment = false;

/// When true, [WorkoutComplianceCoordinator.sync] scans logged runs and
/// auto-completes any plan day within ±1 day that clears the distance
/// threshold — so a free run can tick off a workout. When false (default, like
/// Runna / Garmin Coach) only runs started from the plan workout, or linked
/// by hand via "Link Activity", count; free runs stay free.
const bool enableAutoRunMatching = false;
