import 'package:flutter/material.dart';
import 'screens/main_screen.dart';
import 'services/first_run_service.dart';
import 'onboarding/onboarding_screen.dart';
import 'utils/database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'screens/reset_password_screen.dart';
import 'dart:async';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'services/analytics_service.dart';
import 'services/revenue_cat_service.dart';
import 'services/profile_service.dart';
import 'services/hydration_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'utils/unit_utils.dart';

Future<T?> safeSupabaseCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (e) {
    debugPrint('[Supabase] Safe call caught: $e');
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  debugPrint('[Startup] SUPABASE_URL="$supabaseUrl"');
  debugPrint('[Startup] SUPABASE_ANON_KEY length=${supabaseAnonKey.length}');

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    const debugMessage =
        'Supabase credentials missing.\n\n'
        'Run with: flutter build/run --dart-define-from-file=dart_defines.env';
    await FirebaseCrashlytics.instance.recordError(
      Exception(debugMessage),
      null,
      fatal: true,
    );
    runApp(_StartupErrorApp(debugMessage: debugMessage));
    return;
  }

  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    debugPrint('[Startup] Supabase initialized successfully');
  } catch (e) {
    debugPrint('[Startup] Supabase.initialize() failed: $e');
    await FirebaseCrashlytics.instance.recordError(e, null, fatal: true);
    runApp(_StartupErrorApp(debugMessage: 'Supabase init failed:\n$e'));
    return;
  }

  const posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
  const posthogHost = String.fromEnvironment('POSTHOG_HOST');

  if (posthogApiKey.isNotEmpty && posthogHost.isNotEmpty) {
    await Posthog().setup(
      PostHogConfig(posthogApiKey)
        ..host = posthogHost
        ..debug = false
        ..captureApplicationLifecycleEvents = true,
    );
    debugPrint('[Startup] PostHog initialized');

    // If a user is already logged in at cold start, tie events to them
    // immediately (the auth listener's initialSession event also covers this,
    // but doing it here avoids a race for the very first app_opened event).
    final existingUser = Supabase.instance.client.auth.currentUser;
    if (existingUser != null) {
      await Analytics.identify(
        existingUser.id,
        properties: {'email': existingUser.email ?? ''},
      );
    }
    await Analytics.appOpened();
  } else {
    debugPrint('[Startup] PostHog skipped — missing credentials');
  }

  // Load the saved theme preference before first frame to avoid a flash.
  await ThemeController.instance.load();
  await UnitUtils.init();

  runApp(const MyApp());
}

class _StartupErrorApp extends StatelessWidget {
  final String debugMessage;
  const _StartupErrorApp({required this.debugMessage});

  @override
  Widget build(BuildContext context) {
    final displayMessage = kDebugMode
        ? debugMessage
        : "We couldn't start Endura. Please try again later.";
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  displayMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Endura',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const AppInitializer(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  FirstRunService? _firstRunService;
  bool _initDone = false;
  bool _initError = false;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    _initialize();
    _listenAuthEvents();
    _listenPushMessages();
  }

  void _listenPushMessages() {
    // Foreground messages — app is open
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground message: ${message.notification?.title}');
    });
    // User tapped a notification while app was in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] Notification tapped: ${message.notification?.title}');
    });
  }

  Future<void> _savePushToken() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: false,
      badge: false,
      sound: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    final token = await messaging.getToken();
    if (token != null) {
      await ProfileService.instance.updateField('push_token', token);
      debugPrint('[Startup] push token saved');
    }
  }

  Future<void> _initialize() async {
    try {
      final service = await FirstRunService.create();
      await DatabaseService.instance.migrateFromSharedPreferences();

      // RevenueCat init — only if user is already logged in at startup
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await RevenueCatService.init(user.id);
        debugPrint('[Startup] RevenueCat initialized');
        // Sync plan state: backfill Supabase for existing users, restore for new devices
        ProfileService.instance.syncPlanState().catchError(
          (e) => debugPrint('[Startup] syncPlanState error: $e'),
        );
        // Save FCM push token to Supabase for future notifications
        _savePushToken().catchError(
          (e) => debugPrint('[Startup] savePushToken error: $e'),
        );
      }
      if (mounted) {
        setState(() {
          _firstRunService = service;
          _initDone = true;
        });
      }
    } catch (e, stack) {
      debugPrint('[AppInitializer] Init error: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'app_init_failed',
        fatal: true,
      );
      if (mounted) setState(() => _initError = true);
    }
  }

  void _listenAuthEvents() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      final event = data.event;
      debugPrint('[Auth] Event: $event');

      if (event == AuthChangeEvent.passwordRecovery) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          );
        }
        return;
      }

      // AFTER
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          await RevenueCatService.init(user.id);
          await Analytics.identify(
            user.id,
            properties: {'email': user.email ?? ''},
          );
          FirebaseCrashlytics.instance.setUserIdentifier(user.id);
          // Pull the account's saved theme preference (new-device restore).
          final profile = await ProfileService.instance.fetchProfile();
          await ThemeController.instance.applyFromRemote(profile?.themeMode);
          _savePushToken().catchError(
            (e) => debugPrint('[Auth] savePushToken error: $e'),
          );
          // Offline-first: hydrate local state on a fresh device + flush any
          // queued shoe edits.
          HydrationService.instance.hydrateOnLogin().catchError(
            (e) => debugPrint('[Auth] hydrateOnLogin error: $e'),
          );
        }
      }

      if (event == AuthChangeEvent.signedOut) {
        await Analytics.reset();
      }
      if (mounted) setState(() {});
    }, onError: (e) => debugPrint('[Auth] Stream error: $e'));
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Still initializing
    if (!_initDone && !_initError) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Init failed
    if (_initError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: context.colors.danger),
              const SizedBox(height: 16),
              Text(
                'Failed to initialize app',
                style: TextStyle(
                  fontSize: 16,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _initError = false;
                    _initDone = false;
                  });
                  _initialize();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // ── STEP 1: Must have a session ──
    final session = Supabase.instance.client.auth.currentSession;
    debugPrint(
      '[AppInitializer] session=${session != null ? "active" : "null"}',
    );

    if (session == null) {
      return AuthScreen(
        onAuthenticated: () {
          if (mounted) setState(() {});
        },
      );
    }

    // ── STEP 2: Must complete onboarding ──
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return AuthScreen(
        onAuthenticated: () {
          if (mounted) setState(() {});
        },
      );
    }
    final onboardingDone = _firstRunService?.isOnboardingCompleted() ?? false;
    debugPrint('[AppInitializer] onboardingDone=$onboardingDone');

    if (!onboardingDone) {
      return OnboardingScreen(
        onComplete: () async {
          await _firstRunService?.markOnboardingCompleted();
          if (mounted) setState(() {});
        },
      );
    }

    // ── STEP 3: All good ──
    return const MainScreen();
  }
}
