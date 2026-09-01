# Endura Run App — Claude Instructions

## After every feature or fix

After completing any code change (feature, bug fix, refactor, cleanup), always:

1. **Save a memory entry** summarizing what was done — what changed, why, and any key decisions made. Keep it short (3–5 lines max). Use type `project` for ongoing work or `feedback` if a pattern emerged about how to approach this codebase.

2. **Git commit** is handled automatically by the Stop hook — no need to do it manually unless asked.

## Visual verification

- Do NOT run browser tools, headless web previews, or take screenshots to inspect the UI.
- Do NOT start `flutter run -d web-server` or any preview server to "see" a change.
- All visual verification is done by the developer via hot reload on their connected
  device/emulator. Make the code change, run `flutter analyze`, and hand it back for the
  developer to eyeball.
- To preview a single screen in isolation, the developer uses the Dev Launcher
  (`lib/main_dev.dart`, VS Code launch config "Dev Launcher").

## Project context

- Flutter app for running coaching (iOS/Android)
- Coach is called "Max"
- Dark theme throughout (EC color tokens, not ThemeData)
- Analytics via `AnalyticsService` (PostHog)
- Onboarding lives in `lib/onboarding/` (not `lib/screens/`)
