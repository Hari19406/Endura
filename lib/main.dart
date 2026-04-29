import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/run_screen.dart';
import 'screens/you_screen.dart';
import 'services/first_run_service.dart';
import 'screens/onboarding_screen.dart';
import 'utils/database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'screens/reset_password_screen.dart';
import 'dart:async';
import 'utils/refreshable.dart';
import 'services/coach_message_builder.dart' as message;

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
    runApp(const _StartupErrorApp(
      message: 'Supabase credentials missing.\n\n'
          'Run with: flutter run --dart-define-from-file=dart_defines.env',
    ));
    return;
  }

  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    debugPrint('[Startup] Supabase initialized successfully');
  } catch (e) {
    debugPrint('[Startup] Supabase.initialize() failed: $e');
    runApp(_StartupErrorApp(message: 'Supabase init failed:\n$e'));
    return;
  }

  runApp(const MyApp());
}

class _StartupErrorApp extends StatelessWidget {
  final String message;
  const _StartupErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
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
                  message,
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
    return MaterialApp(
      title: 'Endura',
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0A0A0A),
          secondary: Color(0xFF0A0A0A),
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF0A0A0A),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAFAFA),
          foregroundColor: Color(0xFF0A0A0A),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF0A0A0A),
          unselectedItemColor: Color(0xFF999999),
          elevation: 0,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? Colors.white
                  : const Color(0xFFFFFFFF)),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFF555555)
                  : const Color(0xFFDDDDDD)),
          trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFF555555)
                  : const Color(0xFFCCCCCC)),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF0A0A0A),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0A0A0A),
          ),
        ),
      ),
      home: const AppInitializer(),
      debugShowCheckedModeBanner: false,
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
  }

  Future<void> _initialize() async {
    try {
      final service = await FirstRunService.create();
      await DatabaseService.instance.migrateFromSharedPreferences();
      if (mounted) {
        setState(() {
          _firstRunService = service;
          _initDone = true;
        });
      }
    } catch (e) {
      debugPrint('[AppInitializer] Init error: $e');
      if (mounted) setState(() => _initError = true);
    }
  }

  void _listenAuthEvents() {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
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

        if (mounted) setState(() {});
      },
      onError: (e) => debugPrint('[Auth] Stream error: $e'),
    );
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
      return const Scaffold(
        backgroundColor: Color(0xFFFAFAFA),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0A0A0A)),
        ),
      );
    }

    // Init failed
    if (_initError) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to initialize app',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() { _initError = false; _initDone = false; });
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
    debugPrint('[AppInitializer] session=${session != null ? "active" : "null"}');

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
    return const MainNavigation();
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  message.CoachMessage? _activeCoachMessage;

  final GlobalKey<_HomeScreenWrapperState> _homeKey = GlobalKey();
  final GlobalKey<_YouScreenWrapperState> _youKey = GlobalKey();

  void _onRunCompleted() {
    debugPrint('[MainNavigation] Run completed — refreshing data');
    _homeKey.currentState?._refreshData();
    _youKey.currentState?._refreshData();
    if (_currentIndex == 1) {
      setState(() => _currentIndex = 0);
    }
  }

  void _navigateToYou() => setState(() => _currentIndex = 2);
  void _navigateToRun() => setState(() => _currentIndex = 1);

  void _onCoachMessageReady(message.CoachMessage? msg) {
    if (_activeCoachMessage != msg) {
      setState(() => _activeCoachMessage = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreenWrapper(
            key: _homeKey,
            onNavigateToYou: _navigateToYou,
            onNavigateToRun: _navigateToRun,
            onCoachMessageReady: _onCoachMessageReady,
          ),
          RunScreenWrapper(onRunCompleted: _onRunCompleted),
          YouScreenWrapper(key: _youKey),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: Colors.grey.shade200, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF0A0A0A),
          unselectedItemColor: const Color(0xFF999999),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_run_outlined),
              activeIcon: Icon(Icons.directions_run),
              label: 'Run',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'You',
            ),  
          ],
        ),
      ),
    );
  }
}

class HomeScreenWrapper extends StatefulWidget {
  final VoidCallback onNavigateToYou;
  final VoidCallback onNavigateToRun;
  final void Function(message.CoachMessage?) onCoachMessageReady;

  const HomeScreenWrapper({
    super.key,
    required this.onNavigateToYou,
    required this.onNavigateToRun,
    required this.onCoachMessageReady,
  });

  @override
  State<HomeScreenWrapper> createState() => _HomeScreenWrapperState();
}

class _HomeScreenWrapperState extends State<HomeScreenWrapper> {
  final GlobalKey<State> _childKey = GlobalKey();

  void _refreshData() {
    debugPrint('[HomeScreenWrapper] Refreshing data');
    final childState = _childKey.currentState;
    if (childState is Refreshable) {
      (childState as Refreshable).loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      key: _childKey,
      onNavigateToYou: widget.onNavigateToYou,
      onNavigateToRun: widget.onNavigateToRun,
      onCoachMessageReady: widget.onCoachMessageReady,
    );
  }
}

class RunScreenWrapper extends StatelessWidget {
  final VoidCallback onRunCompleted;

  const RunScreenWrapper({super.key, required this.onRunCompleted,});

  @override
  Widget build(BuildContext context) {
    return RunScreen(onWorkoutCompleted: onRunCompleted);
  }
}

class YouScreenWrapper extends StatefulWidget {
  const YouScreenWrapper({super.key});

  @override
  State<YouScreenWrapper> createState() => _YouScreenWrapperState();
}

class _YouScreenWrapperState extends State<YouScreenWrapper> {
  final GlobalKey<State> _childKey = GlobalKey();

  void _refreshData() {
    debugPrint('[YouScreenWrapper] Refreshing data');
    final childState = _childKey.currentState;
    if (childState is Refreshable) {
      (childState as Refreshable).loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return YouScreen(key: _childKey);
  }
}