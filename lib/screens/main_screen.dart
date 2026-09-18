// lib/screens/main_screen.dart
//
// The persistent app shell — a 4-tab BottomNavigationBar over a swipeable
// PageView (each tab keeps its scroll position and state while off-screen,
// since AutomaticKeepAliveClientMixin below pins every tab's element tree
// alive rather than letting PageView dispose it):
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

  /// True whenever the Record tab has a run actually in progress (not just
  /// "ready to start") — disables the PageView's swipe gesture so a drag
  /// meant for the live map/HUD doesn't get eaten as a tab switch, and so an
  /// active run can't be swiped away from by accident. Bottom-nav taps still
  /// work regardless, since [PageController.animateToPage] ignores physics.
  bool _isRunTrackingActive = false;

  late final PageController _pageController = PageController(
    initialPage: _coachTab,
  );

  /// Bumped to ask the Record tab to start an unguided Free Run immediately
  /// (from the Coach tab's Quick Start button).
  final ValueNotifier<int> _freeRunSignal = ValueNotifier<int>(0);

  final GlobalKey<_HomeScreenWrapperState> _homeKey = GlobalKey();
  final GlobalKey<_YouScreenWrapperState> _youKey = GlobalKey();

  @override
  void dispose() {
    _freeRunSignal.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _onTrackingActiveChanged(bool active) {
    if (_isRunTrackingActive != active) {
      setState(() => _isRunTrackingActive = active);
    }
  }

  void _onRunCompleted() {
    debugPrint('[MainScreen] Run completed — refreshing data');
    _homeKey.currentState?._refreshData();
    _youKey.currentState?._refreshData();
    if (_currentIndex == _recordTab) {
      _goToTab(_coachTab);
    }
  }

  void _navigateToYou() => _goToTab(_youTab);
  void _navigateToRun() => _goToTab(_recordTab);

  /// Coach tab → "Free Run": switch to Record and, once that frame is built and
  /// RunScreen is mounted in the ready state, fire the signal it listens for.
  void _startFreeRun() {
    _goToTab(_recordTab);
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
      body: PageView(
        controller: _pageController,
        // A run in progress must not be swiped away from by accident, and a
        // horizontal drag over the live map should pan the map rather than
        // flip tabs. Bottom-nav taps still work — animateToPage ignores
        // physics — so the Record tab stays reachable either way.
        physics: _isRunTrackingActive
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: (index) => setState(() => _currentIndex = index),
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
            onTrackingActiveChanged: _onTrackingActiveChanged,
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
          onTap: _goToTab,
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
  final ValueChanged<bool>? onTrackingActiveChanged;

  const RunScreenWrapper({
    super.key,
    required this.onRunCompleted,
    required this.freeRunSignal,
    this.activeCoachMessage,
    this.scheduledContext,
    this.onTrackingActiveChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RunScreen(
      onWorkoutCompleted: onRunCompleted,
      activeCoachMessage: activeCoachMessage,
      scheduledContext: scheduledContext,
      freeRunSignal: freeRunSignal,
      onTrackingActiveChanged: onTrackingActiveChanged,
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
