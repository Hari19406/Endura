// lib/main_dev.dart
//
// Isolated Dev Launcher Menu.
//
// Runs the app straight into a plain list of every screen/flow/component that
// can be instantiated in isolation — no auth gate, no onboarding gate, no
// bottom-nav wiring. Every destination is pushed as its own route so the
// hardware / on-screen back button (plus the floating back button this host
// overlays) returns you to the launcher without restarting the app.
//
//   flutter run -t lib/main_dev.dart --dart-define-from-file=dart_defines.env
//
// The dart-defines are optional: without them, screens that read live Supabase
// data simply render empty instead of crashing.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'services/theme_service.dart';
import 'utils/unit_utils.dart';

import 'engines/config/archetype_table.dart' show ExperienceLevel;
import 'models/activity_telemetry.dart';
import 'models/plan_config_state.dart';
import 'onboarding/onboarding_screen.dart';
import 'onboarding/plan_reveal_data.dart';
import 'onboarding/plan_reveal_page.dart';
import 'screens/activity_detail_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/run_screen.dart';
import 'screens/you_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/manage_plan_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/milestones_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/device_pairing_screen.dart';

import 'widgets/rpe_input_widget.dart';
import 'widgets/target_pace_indicator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Best-effort: wire Supabase so live-data screens behave like the real app.
  // Missing credentials is fine here — those screens just render empty.
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } catch (e) {
      debugPrint('[DevLauncher] Supabase init failed: $e');
    }
  } else {
    debugPrint(
      '[DevLauncher] No SUPABASE_* dart-defines — live-data screens will be '
      'empty. Pass --dart-define-from-file=dart_defines.env if you need them.',
    );
  }

  // These back the singletons that many screens touch on first build.
  try {
    await ThemeController.instance.load();
  } catch (e) {
    debugPrint('[DevLauncher] ThemeController.load failed: $e');
  }
  try {
    await UnitUtils.init();
  } catch (e) {
    debugPrint('[DevLauncher] UnitUtils.init failed: $e');
  }

  runApp(const DevLauncherApp());
}

class DevLauncherApp extends StatelessWidget {
  const DevLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Endura — Dev Launcher',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const DevLauncherScreen(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu model
// ─────────────────────────────────────────────────────────────────────────────

class _DevEntry {
  final String title;
  final String? subtitle;
  final WidgetBuilder builder;

  const _DevEntry(this.title, this.builder, {this.subtitle});
}

class _DevSection {
  final String header;
  final List<_DevEntry> entries;

  const _DevSection(this.header, this.entries);
}

final List<_DevSection> _menu = [
  _DevSection('Flows', [
    _DevEntry(
      'Onboarding',
      (_) => OnboardingScreen(onComplete: () {}),
      subtitle: 'Full race-first onboarding sequence (starts at the goal page)',
    ),
    _DevEntry(
      'Test Half Marathon Onboarding',
      (_) => OnboardingScreen(shortenedMode: true, onComplete: () {}),
      subtitle: 'Straight into the race path — pick "Half Marathon" at the '
          'picker, then every screen through to the Reveal',
    ),
    _DevEntry(
      'Preview Reveal Screen (Half Marathon 12-wk)',
      (_) => const _PlanRevealStage(),
      subtitle: '12-wk HM · 4 runs/wk · 25 km base · Sat long run — jumps '
          'straight to OPagePlanReveal for tuning',
    ),
    _DevEntry(
      'Preview Reveal Screen (5K 8-wk)',
      (_) => const _PlanRevealStage.fiveK(),
      subtitle: '8-wk 5K · 5 runs/wk · 22 km base · Sat long run — inspect the '
          '5K volume wave, long-run cap and VO2/threshold session mix',
    ),
    _DevEntry(
      'Preview Reveal Screen (10K 10-wk)',
      (_) => const _PlanRevealStage.tenK(),
      subtitle: '10-wk 10K · 5 runs/wk · 28 km base · Sun long run — inspect the '
          '10K volume wave, ≤16 km long-run cap and threshold-led session mix',
    ),
  ]),
  _DevSection('Screens', [
    _DevEntry('Auth', (_) => AuthScreen(onAuthenticated: () {})),
    _DevEntry('Home', (_) => const HomeScreen()),
    _DevEntry('Run', (_) => const RunScreen()),
    _DevEntry('You', (_) => const YouScreen()),
    _DevEntry(
      'Activity Detail (telemetry)',
      (_) => ActivityDetailScreen(activity: ActivityDetail.mock()),
      subtitle: '11.73 km progression run — summary grid, route, training '
          'impact, km splits, scrubbable pace/elevation/HR-zones/cadence charts',
    ),
    _DevEntry('Paywall', (_) => const PaywallScreen()),
    _DevEntry('Settings', (_) => const SettingsScreen()),
    _DevEntry('Notifications', (_) => const NotificationsScreen()),
    _DevEntry('Manage plan', (_) => const ManagePlanScreen()),
    _DevEntry('Feedback', (_) => const FeedbackScreen()),
    _DevEntry(
      'Milestones',
      (_) => const MilestonesScreen(achievements: []),
      subtitle: 'Rendered with an empty achievement list',
    ),
    _DevEntry('Reset password', (_) => const ResetPasswordScreen()),
    _DevEntry(
      'Device pairing — heart rate',
      (_) => const DevicePairingScreen(deviceType: DeviceType.heartRate),
    ),
    _DevEntry(
      'Device pairing — cadence',
      (_) => const DevicePairingScreen(deviceType: DeviceType.cadence),
    ),
  ]),
  _DevSection('Components', [
    _DevEntry(
      'RpeInputWidget',
      (_) => _ComponentStage(
        child: RpeInputWidget(onRpeSelected: (_) {}),
      ),
    ),
    _DevEntry(
      'TargetPaceIndicator',
      (_) => const _ComponentStage(
        child: TargetPaceIndicator(
          currentPaceSecondsPerKm: 300,
          targetRange: null,
        ),
      ),
    ),
  ]),
];

// ─────────────────────────────────────────────────────────────────────────────
// Launcher screen
// ─────────────────────────────────────────────────────────────────────────────

class DevLauncherScreen extends StatelessWidget {
  const DevLauncherScreen({super.key});

  void _open(BuildContext context, _DevEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _DevHost(title: entry.title, child: entry.builder(ctx)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (final section in _menu) {
      rows.add(_SectionHeader(section.header));
      for (final entry in section.entries) {
        rows.add(
          ListTile(
            title: Text(
              entry.title,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: entry.subtitle == null
                ? null
                : Text(
                    entry.subtitle!,
                    style: TextStyle(color: c.textTertiary, fontSize: 12),
                  ),
            trailing: Icon(Icons.chevron_right, color: c.textTertiary),
            onTap: () => _open(context, entry),
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Dev Launcher')),
      body: ListView(children: rows),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c.accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Wraps every pushed destination so there is always a way back to the
/// launcher, even for screens that render no AppBar of their own.
class _DevHost extends StatelessWidget {
  final String title;
  final Widget child;

  const _DevHost({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 8,
            bottom: 8,
            child: SafeArea(
              child: FloatingActionButton.small(
                heroTag: 'dev-back',
                tooltip: 'Back to Dev Launcher ($title)',
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Icon(Icons.arrow_back),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RevealVariant { halfMarathon12, fiveK8, tenK10 }

/// Jumps straight to [OPagePlanReveal] with a pre-populated config so the
/// fine-tune sliders + week-2 preview can be inspected without tapping through
/// onboarding. Variants:
///   • [_RevealVariant.halfMarathon12] — 12-wk HM · 4 runs/wk · 25 km base
///   • [_RevealVariant.fiveK8]         — 8-wk 5K · 5 runs/wk · 22 km base
///   • [_RevealVariant.tenK10]         — 10-wk 10K · 5 runs/wk · 28 km base
class _PlanRevealStage extends StatefulWidget {
  final _RevealVariant variant;
  const _PlanRevealStage() : variant = _RevealVariant.halfMarathon12;

  const _PlanRevealStage.fiveK() : variant = _RevealVariant.fiveK8;

  const _PlanRevealStage.tenK() : variant = _RevealVariant.tenK10;

  @override
  State<_PlanRevealStage> createState() => _PlanRevealStageState();
}

class _PlanRevealStageState extends State<_PlanRevealStage> {
  late final OnboardingAnswers _answers = switch (widget.variant) {
    _RevealVariant.fiveK8 => OnboardingAnswers(
        goal: '5k',
        raceName: 'Dev 5K',
        raceDate: DateTime.now().add(const Duration(days: 8 * 7)),
        experienceRaw: 'regular',
        experienceBridged: 'intermediate',
        raceGoalRaw: 'target_time',
        targetFinishSec: 22 * 60, // 22:00
        baselineWeeklyKm: 22,
        runsPerWeek: 5,
        selectedDays: const [0, 1, 3, 4, 5], // Mon/Tue/Thu/Fri/Sat
        longRunDayIndex: 5, // Saturday
        paceDistance: '5k',
        paceDistanceKm: 5.0,
        currentTimeSec: 24 * 60, // 24:00 now → 22:00 goal
        startDate: DateTime.now(),
        planWeeks: 8,
        vdot: 46,
        vdotProvisional: false,
      ),
    _RevealVariant.tenK10 => OnboardingAnswers(
        goal: '10k',
        raceName: 'Dev 10K',
        raceDate: DateTime.now().add(const Duration(days: 10 * 7)),
        experienceRaw: 'regular',
        experienceBridged: 'intermediate',
        raceGoalRaw: 'target_time',
        targetFinishSec: 46 * 60, // 46:00
        baselineWeeklyKm: 28,
        runsPerWeek: 5,
        selectedDays: const [0, 2, 3, 5, 6], // Mon/Wed/Thu/Sat/Sun
        longRunDayIndex: 6, // Sunday
        paceDistance: '10k',
        paceDistanceKm: 10.0,
        currentTimeSec: 50 * 60, // 50:00 now → 46:00 goal
        startDate: DateTime.now(),
        planWeeks: 10,
        vdot: 45,
        vdotProvisional: false,
      ),
    _RevealVariant.halfMarathon12 => OnboardingAnswers(
        goal: 'half_marathon',
        raceName: 'Dev Half',
        raceDate: DateTime.now().add(const Duration(days: 12 * 7)),
        experienceRaw: 'regular',
        experienceBridged: 'intermediate',
        raceGoalRaw: 'finish',
        baselineWeeklyKm: 25,
        runsPerWeek: 4,
        selectedDays: const [0, 2, 4, 5], // Mon / Wed / Fri / Sat
        longRunDayIndex: 5, // Saturday
        paceDistance: 'half',
        paceDistanceKm: 21.0975,
        currentTimeSec: 6600, // 1:50:00
        startDate: DateTime.now(),
        planWeeks: 12,
        vdot: 44,
        vdotProvisional: false,
      ),
  };

  late final PlanConfigState _config = switch (widget.variant) {
    _RevealVariant.fiveK8 => PlanConfigState.fromInputs(
        goalType: PlanGoalType.fiveK,
        experience: ExperienceLevel.intermediate,
        vDOT: 46,
        runsPerWeek: 5,
        longRunDay: 6, // Saturday (1 = Mon … 7 = Sun)
        availableDays: const {1, 2, 4, 5, 6},
        durationWeeks: 8,
        currentWeeklyKm: 22,
      ),
    _RevealVariant.tenK10 => PlanConfigState.fromInputs(
        goalType: PlanGoalType.tenK,
        experience: ExperienceLevel.intermediate,
        vDOT: 45,
        runsPerWeek: 5,
        longRunDay: 7, // Sunday
        availableDays: const {1, 3, 4, 6, 7},
        durationWeeks: 10,
        currentWeeklyKm: 28,
      ),
    _RevealVariant.halfMarathon12 => PlanConfigState.fromInputs(
        goalType: PlanGoalType.half,
        experience: ExperienceLevel.intermediate,
        vDOT: 44,
        runsPerWeek: 4,
        longRunDay: 6, // Saturday (1 = Mon … 7 = Sun)
        availableDays: const {1, 3, 5, 6},
        durationWeeks: 12,
        currentWeeklyKm: 25,
      ),
  };

  late final PlanProjection? _projection = _safeBuild();

  PlanProjection? _safeBuild() {
    try {
      return PlanProjection.build(_answers);
    } catch (_) {
      return null; // exercise the receipt-only + standalone-sliders path
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: OPagePlanReveal(
          answers: _answers,
          projection: _projection,
          initialConfig: _config,
          onEdit: (t) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('onEdit: ${t.name}')),
          ),
          onGenerate: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('onGenerate — would materialise here')),
          ),
          onConfigChanged: (c) => debugPrint('[DevLauncher] tuned: $c'),
        ),
      ),
    );
  }
}

/// Neutral backdrop for previewing a single component in isolation.
class _ComponentStage extends StatelessWidget {
  final Widget child;
  const _ComponentStage({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );
  }
}
