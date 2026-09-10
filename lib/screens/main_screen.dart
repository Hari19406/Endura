// lib/screens/main_screen.dart
//
// The persistent app shell — a 4-tab BottomNavigationBar over an IndexedStack
// (so each tab keeps its scroll position and state while backgrounded):
//
//   0  Feed   — social activity stream & runner discovery
//   1  Coach  — today's workout execution, weather, race countdown
//   2  Record — dedicated live GPS workout tracker
//   3  You    — athlete identity, career stats, history, shoe locker

import 'package:flutter/material.dart';

import '../services/coach_message_builder.dart' as message;
import '../models/scheduled_workout_context.dart';
import '../theme/app_colors.dart';
import '../utils/refreshable.dart';
import 'feed_screen.dart';
import 'home_screen.dart';
import 'run_screen.dart';
import 'you_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Tab indices (Feed is 0 — the IndexedStack child order below matches).
  static const _coachTab = 1;
  static const _recordTab = 2;
  static const _youTab = 3;

  int _currentIndex = _coachTab;
  message.CoachMessage? _activeCoachMessage;
  ScheduledWorkoutContext? _scheduledContext;

  /// Bumped to ask the Record tab to start an unguided Free Run immediately
  /// (from the Coach tab's Quick Start button).
  final ValueNotifier<int> _freeRunSignal = ValueNotifier<int>(0);

  final GlobalKey<_HomeScreenWrapperState> _homeKey = GlobalKey();
  final GlobalKey<_YouScreenWrapperState> _youKey = GlobalKey();

  @override
  void dispose() {
    _freeRunSignal.dispose();
    super.dispose();
  }

  void _onRunCompleted() {
    debugPrint('[MainScreen] Run completed — refreshing data');
    _homeKey.currentState?._refreshData();
    _youKey.currentState?._refreshData();
    if (_currentIndex == _recordTab) {
      setState(() => _currentIndex = _coachTab);
    }
  }

  void _navigateToYou() => setState(() => _currentIndex = _youTab);
  void _navigateToRun() => setState(() => _currentIndex = _recordTab);

  /// Coach tab → "Free Run": switch to Record and, once that frame is built and
  /// RunScreen is mounted in the ready state, fire the signal it listens for.
  void _startFreeRun() {
    setState(() => _currentIndex = _recordTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _freeRunSignal.value++;
    });
  }

  void _onCoachMessageReady(message.CoachMessage? msg) {
    if (_activeCoachMessage != msg) {
      setState(() => _activeCoachMessage = msg);
    }
  }

  void _onScheduledContextReady(ScheduledWorkoutContext? ctx) {
    if (!identical(_scheduledContext, ctx)) {
      setState(() => _scheduledContext = ctx);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const FeedScreen(),
          HomeScreenWrapper(
            key: _homeKey,
            onNavigateToYou: _navigateToYou,
            onNavigateToRun: _navigateToRun,
            onCoachMessageReady: _onCoachMessageReady,
            onScheduledContextReady: _onScheduledContextReady,
            onQuickStartFreeRun: _startFreeRun,
          ),
          RunScreenWrapper(
            onRunCompleted: _onRunCompleted,
            activeCoachMessage: _activeCoachMessage,
            scheduledContext: _scheduledContext,
            freeRunSignal: _freeRunSignal,
          ),
          YouScreenWrapper(key: _youKey),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: context.colors.divider, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: context.colors.surface,
          selectedItemColor: context.colors.accent,
          unselectedItemColor: context.colors.textTertiary,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Feed',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.fitness_center_outlined),
              activeIcon: Icon(Icons.fitness_center),
              label: 'Coach',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.radio_button_checked),
              activeIcon: Icon(Icons.radio_button_checked),
              label: 'Record',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_circle_outlined),
              activeIcon: Icon(Icons.account_circle),
              label: 'You',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab wrappers — own the GlobalKey → child-state plumbing used to refresh a
// tab's data after a run completes on another tab.
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreenWrapper extends StatefulWidget {
  final VoidCallback onNavigateToYou;
  final VoidCallback onNavigateToRun;
  final VoidCallback onQuickStartFreeRun;
  final void Function(message.CoachMessage?) onCoachMessageReady;
  final void Function(ScheduledWorkoutContext?) onScheduledContextReady;

  const HomeScreenWrapper({
    super.key,
    required this.onNavigateToYou,
    required this.onNavigateToRun,
    required this.onQuickStartFreeRun,
    required this.onCoachMessageReady,
    required this.onScheduledContextReady,
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
      onScheduledContextReady: widget.onScheduledContextReady,
      onQuickStartFreeRun: widget.onQuickStartFreeRun,
    );
  }
}

class RunScreenWrapper extends StatelessWidget {
  final VoidCallback onRunCompleted;
  final message.CoachMessage? activeCoachMessage;
  final ScheduledWorkoutContext? scheduledContext;
  final ValueNotifier<int> freeRunSignal;

  const RunScreenWrapper({
    super.key,
    required this.onRunCompleted,
    required this.freeRunSignal,
    this.activeCoachMessage,
    this.scheduledContext,
  });

  @override
  Widget build(BuildContext context) {
    return RunScreen(
      onWorkoutCompleted: onRunCompleted,
      activeCoachMessage: activeCoachMessage,
      scheduledContext: scheduledContext,
      freeRunSignal: freeRunSignal,
    );
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
