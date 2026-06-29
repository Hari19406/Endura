# Endura Run App — Claude Instructions

## After every feature or fix

After completing any code change (feature, bug fix, refactor, cleanup), always:

1. **Save a memory entry** summarizing what was done — what changed, why, and any key decisions made. Keep it short (3–5 lines max). Use type `project` for ongoing work or `feedback` if a pattern emerged about how to approach this codebase.

2. **Git commit** is handled automatically by the Stop hook — no need to do it manually unless asked.

## Project context

- Flutter app for running coaching (iOS/Android)
- Coach is called "Max"
- Dark theme throughout (EC color tokens, not ThemeData)
- Analytics via `AnalyticsService` (PostHog)
- Onboarding lives in `lib/onboarding/` (not `lib/screens/`)
