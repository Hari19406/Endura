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

import 'onboarding/onboarding_screen.dart';
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
      subtitle: 'Full race-first onboarding sequence',
    ),
  ]),
  _DevSection('Screens', [
    _DevEntry('Auth', (_) => AuthScreen(onAuthenticated: () {})),
    _DevEntry('Home', (_) => const HomeScreen()),
    _DevEntry('Run', (_) => const RunScreen()),
    _DevEntry('You', (_) => const YouScreen()),
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
