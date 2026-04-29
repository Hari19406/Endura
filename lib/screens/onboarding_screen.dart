import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/training_days_service.dart';
import '../engines/planner/race_plan_builder.dart';
import '../engines/memory/engine_memory_service.dart';
import '../engines/memory/engine_memory.dart';
import '../engines/core/vdot_calculator.dart';
import '../services/profile_service.dart';

class EnduraColors {
  static const mint50 = Color(0xFFE6FAF7);
  static const mint200 = Color(0xFF99E8DC);
  static const mint500 = Color(0xFF00C2A8);
  static const mint600 = Color(0xFF00A08A);
  static const mint800 = Color(0xFF006B5E);
  static const white = Color(0xFFFFFFFF);
  static const bg = Color(0xFFFAFAFA);
  static const surface = Color(0xFFF2F2F0);
  static const border = Color(0xFFE5E5E3);
  static const muted = Color(0xFF999999);
  static const textSecondary = Color(0xFF666666);
  static const textPrimary = Color(0xFF1C1C1C);
  static const black = Color(0xFF0A0A0A);
  static const violet50 = Color(0xFFE8DEFF);
  static const violet500 = Color(0xFF7C6EF0);
  static const orange50 = Color(0xFFFFF0E5);
  static const orange500 = Color(0xFFFF7A3D);
  static const red50 = Color(0xFFFFEAEA);
  static const red500 = Color(0xFFE84040);
  static const amber50 = Color(0xFFFFF6DB);
  static const amber500 = Color(0xFFF0A800);
}

class EnduraTheme {
  static const radius = 14.0;
  static const iconRadius = 10.0;
  static const borderWidth = 0.5;
  static const pagePadding = EdgeInsets.symmetric(horizontal: 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// FLOW (new order for narrative continuity):
//   1. Intro          — Meet Max
//   2. Goal           — What are you training for?
//   3. Goal Intent    — What do you want from it?
//   4. Race Date      — When is the race?
//   5. Running Profile— How long have you been running + consistency
//   6. Recent Run     — What does a recent run look like?
//   7. Best Time      — What's your best time?
//   8. Training Days  — How many days can you train?
//   9. About You      — DOB + gender (personal, least intrusive, last)
//  10. Build Plan     — Plan summary + Start training button
// ─────────────────────────────────────────────────────────────────────────────

enum _PageType {
  intro,
  goal,
  goalIntent,
  raceDate,
  runningProfile,
  experience,
  recentRun,
  bestTime,
  trainingDays,
  aboutYou,
  buildPlan,
}

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Goal
  String? _selectedGoal;
  String? _goalIntent;

  // Race date — now just a single DateTime
  DateTime? _raceDate;

  // Running profile
  double _weeklyMileage = 20;
  double _longestRun = 10;
  bool _weeklyMileageTouched = false;
  bool _longestRunTouched = false;
  String? _experienceLevel;

  // Recent run
  double? _recentRunKm;
  int? _recentRunMinutes;
  int? _recentRunSeconds;

  // Best time
  bool _knowsPace = true;
  String _paceDistance = '5k';
  int? _paceMinutes;
  int? _paceSeconds;
  bool _paceRecent = true;

  // Training days
  int _runsPerWeek = 3;
  List<int> _selectedDayIndices = TrainingDaysService.defaultsFor(3);

  // About you — DOB + gender only
  DateTime? _dob;
  String? _gender;

  // Computed vDOT — derived from PR or easy pace
  int _computedVdot = 40;
  bool _vdotIsProvisional = true;

  late AnimationController _loopCtrl;

  @override
  void initState() {
    super.initState();
    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  List<_PageType> get _pageSequence => [
        _PageType.intro,
        _PageType.goal,
        _PageType.goalIntent,
        _PageType.raceDate,
        _PageType.runningProfile,
        _PageType.experience,
        _PageType.recentRun,
        _PageType.bestTime,
        _PageType.trainingDays,
        _PageType.aboutYou,
        _PageType.buildPlan,
      ];

  int get _totalPages => _pageSequence.length;

  _PageType get _currentPageType {
    if (_currentPage >= _pageSequence.length) return _pageSequence.last;
    return _pageSequence[_currentPage];
  }

  double get _progress =>
      0.08 + (_currentPage / max(1, _totalPages - 1)) * 0.92;

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    HapticFeedback.selectionClick();
  }

  bool get _canContinue {
    switch (_currentPageType) {
      case _PageType.intro:
        return true;
      case _PageType.goal:
        return _selectedGoal != null;
      case _PageType.goalIntent:
        return _goalIntent != null;
      case _PageType.raceDate:
        return _raceDate != null;
      case _PageType.runningProfile:
        return _weeklyMileageTouched && _longestRunTouched;
      case _PageType.experience:
        return _experienceLevel != null;
      case _PageType.recentRun:
        return true;
      case _PageType.bestTime:
        return true;
      case _PageType.trainingDays:
        return _selectedDayIndices.length == _runsPerWeek;
      case _PageType.aboutYou:
        return _gender != null && _dob != null;
      case _PageType.buildPlan:
        return false;
    }
  }

  double _resolveWeeklyKm() => _weeklyMileage;

  /// Derives vDOT from whatever the user provided.
  /// Returns (vdot, isProvisional).
  (int, bool) _computeVdotFromInputs() {
    // Best path: user entered a PR time
    if (_knowsPace && _paceMinutes != null) {
      final prSeconds = _paceMinutes! * 60 + (_paceSeconds ?? 0);
      final distKm = switch (_paceDistance) {
        '5k'   => 5.0,
        '10k'  => 10.0,
        'half' => 21.0975,
        _      => 5.0,
      };
      final confidence = _paceRecent ? PrConfidence.high : PrConfidence.low;
      final vdot = vdotFromPr(
        prTimeSeconds: prSeconds,
        prDistanceKm: distKm,
        confidence: confidence,
      );
      return (vdot, !_paceRecent);
    }

    // Fallback: derive from recent run easy pace
    if (_recentRunKm != null &&
        _recentRunKm! > 0 &&
        _recentRunMinutes != null) {
      final totalSec = _recentRunMinutes! * 60 + (_recentRunSeconds ?? 0);
      if (totalSec > 0) {
        final easyPace = totalSec / _recentRunKm!;
        return (vdotFromEasyPace(easyPace), true);
      }
    }

    return (40, true);
  }

  Future<void> _saveProfileAndComplete() async {
    final (vdot, isProvisional) = _computeVdotFromInputs();
    setState(() {
      _computedVdot = vdot;
      _vdotIsProvisional = isProvisional;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final experience = _experienceLevel ?? 'intermediate';

      await prefs.setString('goal_race', _selectedGoal ?? '5k');
      await prefs.setString('experience_level', experience);
      await prefs.setInt('runs_per_week', _runsPerWeek);
      await TrainingDaysService.save(_selectedDayIndices);

      if (_raceDate != null) {
        await prefs.setString('race_date', _raceDate!.toIso8601String());
      }

      if (_goalIntent != null) {
        await prefs.setString('goal_intent', _goalIntent!);
      }

      if (_gender != null) await prefs.setString('gender', _gender!);
      if (_dob != null) {
        await prefs.setString('dob', _dob!.toIso8601String());
      }

      if (_recentRunKm != null) {
        await prefs.setDouble('recent_run_km', _recentRunKm!);
      }
      if (_recentRunMinutes != null) {
        await prefs.setInt('recent_run_minutes', _recentRunMinutes!);
      }
      if (_recentRunSeconds != null) {
        await prefs.setInt('recent_run_seconds', _recentRunSeconds ?? 0);
      }

      await prefs.setDouble('weekly_mileage_km', _weeklyMileage);
      await prefs.setDouble('longest_run_km', _longestRun);

      if (_knowsPace && _paceMinutes != null) {
        await prefs.setString('pace_distance', _paceDistance);
        await prefs.setInt('pace_minutes', _paceMinutes!);
        await prefs.setInt('pace_seconds', _paceSeconds ?? 0);
        await prefs.setBool('pace_recent', _paceRecent);
      }

      // ── vDOT ─────────────────────────────────────────────────────────
      await prefs.setInt('vdot_score', _computedVdot);
      await prefs.setBool('vdot_is_provisional', _vdotIsProvisional);

      // Persist into EngineMemory so the coach engine picks it up immediately.
      final memService = EngineMemoryService();
      final currentMemory = await memService.load();
      await memService.save(currentMemory.copyWith(
        vdotScore: _computedVdot,
        vdotIsProvisional: _vdotIsProvisional,
      ));

      // ── Build and save race plan ──────────────────────────────────────
      if (_raceDate != null) {
        try {
          final racePlan = RacePlanBuilder.build(
            currentWeeklyKm: _resolveWeeklyKm(),
            goalRace: _selectedGoal ?? '5k',
            raceDate: _raceDate!,
            experienceLevel: experience,
          );
          await EngineMemoryService().saveRacePlan(racePlan);
          debugPrint('[Onboarding] Race plan saved: '
              '${racePlan.weeks.length} weeks');
        } catch (e) {
          debugPrint('[Onboarding] Race plan build failed: $e');
        }
      }

      // ── Save profile to Supabase ──────────────────────────────────────
      await ProfileService.instance.saveProfile(UserProfile(
        gender:       _gender,
        dob:          _dob,
        goal:         _selectedGoal,
        runsPerWeek:  _runsPerWeek,
        trainingDays: _selectedDayIndices,
        paceDistance: _knowsPace ? _paceDistance : null,
        paceMinutes:  _knowsPace ? _paceMinutes : null,
        paceSeconds:  _knowsPace ? _paceSeconds : null,
        raceDate:     _raceDate,
        useMetric:    true,
      ));

      debugPrint('[Onboarding] Profile saved: goal=$_selectedGoal, '
          'exp=$experience, days=$_runsPerWeek, intent=$_goalIntent');
    } catch (e) {
      debugPrint('[Onboarding] Error saving profile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBuildPage = _currentPageType == _PageType.buildPlan;
    final isIntro = _currentPageType == _PageType.intro;

    return Scaffold(
      backgroundColor: EnduraColors.white,
      body: SafeArea(
        child: Column(
          children: [
            if (!isIntro && !isBuildPage)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(0, 0, 12, 0),
                          child: Icon(Icons.chevron_left_rounded,
                              size: 24, color: EnduraColors.textSecondary),
                        ),
                      )
                    else
                      const SizedBox(width: 36),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 4,
                          backgroundColor: EnduraColors.surface,
                          valueColor: const AlwaysStoppedAnimation(
                              EnduraColors.mint500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: const NeverScrollableScrollPhysics(),
                children: _buildPages(),
              ),
            ),
            _buildBottom(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPages() {
    return _pageSequence.map((type) {
      switch (type) {
        case _PageType.intro:
          return _PageIntro(loopCtrl: _loopCtrl);

        case _PageType.goal:
          return _PageGoal(
            selected: _selectedGoal,
            loopCtrl: _loopCtrl,
            onSelect: (g) => setState(() => _selectedGoal = g),
          );

        case _PageType.goalIntent:
          return _PageGoalIntent(
            selected: _goalIntent,
            onSelect: (v) => setState(() => _goalIntent = v),
          );

        case _PageType.raceDate:
          if (_selectedGoal == null) return const SizedBox.shrink();
          return _PageRaceDate(
            selectedGoal: _selectedGoal!,
            raceDate: _raceDate,
            onDatePicked: (d) => setState(() => _raceDate = d),
          );

        case _PageType.runningProfile:
          return _PageRunningProfile(
            weeklyMileage: _weeklyMileage,
            longestRun: _longestRun,
            onMileageChanged: (v) => setState(() {
              _weeklyMileage = v;
              _weeklyMileageTouched = true;
            }),
            onLongestRunChanged: (v) => setState(() {
              _longestRun = v;
              _longestRunTouched = true;
            }),
          );

        case _PageType.experience:
          return _PageExperience(
            selected: _experienceLevel,
            onSelect: (v) => setState(() => _experienceLevel = v),
          );

        case _PageType.recentRun:
          return _PageRecentRun(
            km: _recentRunKm,
            minutes: _recentRunMinutes,
            seconds: _recentRunSeconds,
            onKmChanged: (v) => setState(() => _recentRunKm = v),
            onMinutesChanged: (v) => setState(() => _recentRunMinutes = v),
            onSecondsChanged: (v) => setState(() => _recentRunSeconds = v),
          );

        case _PageType.bestTime:
          return _PageBestTime(
            knowsPace: _knowsPace,
            distance: _paceDistance,
            minutes: _paceMinutes,
            seconds: _paceSeconds,
            isRecent: _paceRecent,
            onToggleKnows: (k) => setState(() => _knowsPace = k),
            onDistanceChanged: (d) => setState(() => _paceDistance = d),
            onMinutesChanged: (m) => setState(() => _paceMinutes = m),
            onSecondsChanged: (s) => setState(() => _paceSeconds = s),
            onRecencyChanged: (r) => setState(() => _paceRecent = r),
          );

        case _PageType.trainingDays:
          return _PageTrainingDays(
            runsPerWeek: _runsPerWeek,
            selectedDays: _selectedDayIndices,
            onFrequencyChanged: (n) => setState(() {
              _runsPerWeek = n;
              _selectedDayIndices = TrainingDaysService.defaultsFor(n);
            }),
            onDaysChanged: (days) =>
                setState(() => _selectedDayIndices = days),
          );

        case _PageType.aboutYou:
          return _PageAboutYou(
            gender: _gender,
            dob: _dob,
            onGenderChanged: (g) => setState(() => _gender = g),
            onDobChanged: (d) => setState(() => _dob = d),
          );

        case _PageType.buildPlan:
          if (_selectedGoal == null) return const SizedBox.shrink();
          final previewVdot = _computeVdotFromInputs();
          return _PageBuildPlan(
            goal: _selectedGoal!,
            raceDate: _raceDate,
            runsPerWeek: _runsPerWeek,
            selectedDayIndices: _selectedDayIndices,
            goalIntent: _goalIntent,
            vdotScore: previewVdot.$1,
            vdotIsProvisional: previewVdot.$2,
            onStartTraining: () async {
              await _saveProfileAndComplete();
              if (mounted) widget.onComplete();
            },
          );
      }
    }).toList();
  }

  Widget _buildBottom() {
    final isBuildPage = _currentPageType == _PageType.buildPlan;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        children: [
          if (!isBuildPage)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _totalPages,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 5,
                    width: i == _currentPage ? 20 : 5,
                    decoration: BoxDecoration(
                      color: i == _currentPage
                          ? EnduraColors.textPrimary
                          : EnduraColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          if (!isBuildPage)
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _canContinue ? () => _nextPage() : null, 
                style: ElevatedButton.styleFrom(
                  backgroundColor: EnduraColors.textPrimary,
                  foregroundColor: EnduraColors.white,
                  disabledBackgroundColor: EnduraColors.surface,
                  disabledForegroundColor: EnduraColors.muted,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(EnduraTheme.radius),
                  ),
                ),
                child: Text(
                  _currentPageType == _PageType.intro ? "Let's go" : 'Continue',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MicroLabel extends StatelessWidget {
  final String text;
  const _MicroLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: EnduraColors.mint600,
            letterSpacing: 0.4),
      );
}

class _PageTitle extends StatelessWidget {
  final String text;
  const _PageTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      textAlign: TextAlign.center,
      style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: EnduraColors.textPrimary,
          height: 1.3));
}

class _PageSubtitle extends StatelessWidget {
  final String text;
  const _PageSubtitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      textAlign: TextAlign.center,
      style: const TextStyle(
          fontSize: 13, color: EnduraColors.textSecondary, height: 1.5));
}

class _SelectionCard extends StatelessWidget {
  final Widget icon;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _SelectionCard(
      {required this.icon,
      required this.label,
      this.subtitle,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color:
                    selected ? EnduraColors.textPrimary : EnduraColors.white,
                borderRadius: BorderRadius.circular(EnduraTheme.radius),
                border: Border.all(
                    color: selected
                        ? EnduraColors.textPrimary
                        : EnduraColors.border,
                    width: EnduraTheme.borderWidth)),
            child: Row(children: [
              icon,
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? EnduraColors.white
                                : EnduraColors.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: selected
                                  ? EnduraColors.muted
                                  : EnduraColors.textSecondary))
                    ],
                  ])),
              AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? EnduraColors.mint500
                          : Colors.transparent,
                      border: Border.all(
                          color: selected
                              ? EnduraColors.mint500
                              : EnduraColors.border,
                          width: 1.5)),
                  child: selected
                      ? const Icon(Icons.check,
                          size: 12, color: EnduraColors.white)
                      : null),
            ])));
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
                color:
                    selected ? EnduraColors.textPrimary : EnduraColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected
                        ? EnduraColors.textPrimary
                        : EnduraColors.border,
                    width: EnduraTheme.borderWidth)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? EnduraColors.white
                        : EnduraColors.textSecondary))));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 1: Intro
// ─────────────────────────────────────────────────────────────────────────────

class _PageIntro extends StatelessWidget {
  final AnimationController loopCtrl;
  const _PageIntro({required this.loopCtrl});
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EnduraTheme.pagePadding,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                  color: EnduraColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: EnduraColors.border)),
              child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_run_rounded,
                        size: 56, color: EnduraColors.mint500),
                    SizedBox(height: 4),
                    Text('MAX',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: EnduraColors.mint600,
                            letterSpacing: 1)),
                  ])),
          const SizedBox(height: 24),
          const Text('Endura',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  color: EnduraColors.textPrimary,
                  letterSpacing: -0.5)),
          const SizedBox(height: 28),
          RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                  style: TextStyle(
                      fontSize: 16,
                      color: EnduraColors.textSecondary,
                      height: 1.6),
                  children: [
                    TextSpan(text: "Hey, I'm "),
                    TextSpan(
                        text: 'Max',
                        style: TextStyle(
                            color: EnduraColors.mint500,
                            fontWeight: FontWeight.w500)),
                    TextSpan(
                        text:
                            " — your running coach.\n\nLet's build something great together."),
                  ])),
          const SizedBox(height: 16),
          const Text('Takes less than a minute',
              style: TextStyle(fontSize: 12, color: EnduraColors.muted)),
        ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 2: Goal
// ─────────────────────────────────────────────────────────────────────────────

class _PageGoal extends StatelessWidget {
  final String? selected;
  final AnimationController loopCtrl;
  final ValueChanged<String> onSelect;
  const _PageGoal(
      {required this.selected,
      required this.loopCtrl,
      required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EnduraTheme.pagePadding,
        child: Column(children: [
          const SizedBox(height: 40),
          SizedBox(
              height: 64,
              child: AnimatedBuilder(
                  animation: loopCtrl,
                  builder: (_, __) => CustomPaint(
                      size: const Size(100, 64),
                      painter: _FlagPainter(loopCtrl.value)))),
          const SizedBox(height: 12),
          const _MicroLabel('We wants to know'),
          const SizedBox(height: 4),
          const _PageTitle('What are you training for?'),
          const SizedBox(height: 6),
          const _PageSubtitle(
              'Pick your distance. We will build the right plan.'),
          const SizedBox(height: 20),
          Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [
            _g('5k', '5K', 'The perfect starting race', EnduraColors.mint50,
                EnduraColors.mint500),
            const SizedBox(height: 10),
            _g('10k', '10K', 'Step up the distance', EnduraColors.violet50,
                EnduraColors.violet500),
            const SizedBox(height: 10),
            _g('half_marathon', 'Half marathon', "The runner's milestone",
                EnduraColors.orange50, EnduraColors.orange500),
            const SizedBox(height: 10),
            _g('marathon', 'Marathon', 'The ultimate challenge',
                EnduraColors.red50, EnduraColors.red500),
            const SizedBox(height: 10),
          ])),
        ]));
  }

  Widget _g(String key, String label, String sub, Color bg, Color fg) =>
      _SelectionCard(
          icon: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: bg,
                  borderRadius:
                      BorderRadius.circular(EnduraTheme.iconRadius)),
              child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: fg)))),
          label: label,
          subtitle: sub,
          selected: selected == key,
          onTap: () => onSelect(key));
}

class _FlagPainter extends CustomPainter {
  final double t;
  _FlagPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final rp = Paint()
      ..color = EnduraColors.mint500
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final off = (t * 20) % 10;
    for (double x = -off; x < size.width; x += 10) {
      canvas.drawLine(Offset(x.clamp(0, size.width), cy + 16),
          Offset((x + 5).clamp(0, size.width), cy + 16), rp);
    }
    canvas.drawCircle(Offset(cx - 30, cy + 16), 4,
        Paint()..color = EnduraColors.surface);
    canvas.drawCircle(
        Offset(cx - 30, cy + 16),
        4,
        Paint()
          ..color = EnduraColors.mint500
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.save();
    canvas.translate(cx + 20, cy + 16);
    canvas.rotate(sin(t * 2 * pi) * 0.05);
    canvas.drawLine(
        Offset.zero,
        const Offset(0, -36),
        Paint()
          ..color = EnduraColors.textPrimary
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
    canvas.drawPath(
        Path()
          ..moveTo(0, -36)
          ..lineTo(16, -28)
          ..lineTo(0, -20)
          ..close(),
        Paint()..color = EnduraColors.mint500);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlagPainter o) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 3: Goal Intent
// ─────────────────────────────────────────────────────────────────────────────

class _PageGoalIntent extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _PageGoalIntent({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EnduraTheme.pagePadding,
        child: Column(children: [
          const SizedBox(height: 40),
          Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: EnduraColors.mint50, shape: BoxShape.circle),
              child: const Icon(Icons.flag_rounded,
                  size: 32, color: EnduraColors.mint500)),
          const SizedBox(height: 16),
          const _MicroLabel('Perfect. Now tell me'),
          const SizedBox(height: 4),
          const _PageTitle("What do you want from it?"),
          const SizedBox(height: 6),
          const _PageSubtitle(
              'This shapes how We pushes you — or holds you back.'),
          const SizedBox(height: 32),
          _SelectionCard(
              icon: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: EnduraColors.mint50,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.sentiment_satisfied_rounded,
                      size: 24, color: EnduraColors.mint500)),
              label: 'Finish comfortably',
              subtitle: 'Cross the line feeling strong',
              selected: selected == 'finish',
              onTap: () => onSelect('finish')),
          const SizedBox(height: 12),
          _SelectionCard(
              icon: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: EnduraColors.violet50,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.trending_up_rounded,
                      size: 24, color: EnduraColors.violet500)),
              label: 'Improve steadily',
              subtitle: 'Get faster week over week',
              selected: selected == 'improve',
              onTap: () => onSelect('improve')),
          const SizedBox(height: 12),
          _SelectionCard(
              icon: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: EnduraColors.orange50,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.bolt_rounded,
                      size: 24, color: EnduraColors.orange500)),
              label: 'Peak performance',
              subtitle: 'Push limits and hit a PR',
              selected: selected == 'peak',
              onTap: () => onSelect('peak')),
        ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 4: Race Date — single date input + calendar picker
// ─────────────────────────────────────────────────────────────────────────────

class _PageRaceDate extends StatefulWidget {
  final String selectedGoal;
  final DateTime? raceDate;
  final ValueChanged<DateTime> onDatePicked;
  const _PageRaceDate(
      {required this.selectedGoal,
      required this.raceDate,
      required this.onDatePicked});
  @override
  State<_PageRaceDate> createState() => _PageRaceDateState();
}

class _PageRaceDateState extends State<_PageRaceDate> {
  final _dayCtrl = TextEditingController();
  final _monthCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.raceDate != null) {
      _dayCtrl.text = widget.raceDate!.day.toString().padLeft(2, '0');
      _monthCtrl.text = widget.raceDate!.month.toString().padLeft(2, '0');
      _yearCtrl.text = widget.raceDate!.year.toString();
    }
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _tryParse() {
    final day = int.tryParse(_dayCtrl.text);
    final month = int.tryParse(_monthCtrl.text);
    final year = int.tryParse(_yearCtrl.text);
    if (day != null && month != null && year != null && year > 2000) {
      try {
        final date = DateTime(year, month, day);
        if (date.isAfter(DateTime.now())) {
          widget.onDatePicked(date);
        }
      } catch (_) {}
    }
  }

  Future<void> _openCalendar() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
        context: context,
        initialDate: widget.raceDate ?? now.add(const Duration(days: 84)),
        firstDate: now.add(const Duration(days: 14)),
        lastDate: now.add(const Duration(days: 730)),
        builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.light(
                    primary: EnduraColors.textPrimary,
                    onPrimary: EnduraColors.white,
                    surface: EnduraColors.white,
                    onSurface: EnduraColors.textPrimary)),
            child: child!));
    if (picked != null) {
      widget.onDatePicked(picked);
      _dayCtrl.text = picked.day.toString().padLeft(2, '0');
      _monthCtrl.text = picked.month.toString().padLeft(2, '0');
      _yearCtrl.text = picked.year.toString();
      setState(() {});
    }
  }

  String get _goalLabel => switch (widget.selectedGoal) {
        '5k' => '5K',
        '10k' => '10K',
        'half_marathon' => 'Half marathon',
        'marathon' => 'Marathon',
        _ => ''
      };

  String? get _weekHint {
    final d = widget.raceDate;
    if (d == null) return null;
    final weeks = d.difference(DateTime.now()).inDays ~/ 7;
    if (weeks < 4) return '$weeks weeks away — very tight, plan will be compressed';
    if (weeks < 8) return '$weeks weeks away — just enough time to build well';
    if (weeks <= 16) return '$weeks weeks away — ideal window for a solid plan';
    if (weeks <= 24) return '$weeks weeks away — plenty of time, We\'ll build gradually';
    return '$weeks weeks away — long runway, we\'ll build smart and steady';
  }

  Color get _hintColor {
    final d = widget.raceDate;
    if (d == null) return EnduraColors.mint500;
    final weeks = d.difference(DateTime.now()).inDays ~/ 7;
    if (weeks < 4) return EnduraColors.red500;
    if (weeks < 8) return EnduraColors.amber500;
    return EnduraColors.mint500;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EnduraTheme.pagePadding,
        child: Column(children: [
          const SizedBox(height: 40),
          const Icon(Icons.calendar_month_rounded,
              size: 48, color: EnduraColors.mint500),
          const SizedBox(height: 12),
          _MicroLabel('$_goalLabel — let\'s plan backwards'),
          const SizedBox(height: 4),
          const _PageTitle("When's race day?"),
          const SizedBox(height: 6),
          const _PageSubtitle(
              'We counts backwards from your race date\nto build every training week.'),
          const SizedBox(height: 40),

          // ── Date input row ───────────────────────────────────────────
          Row(children: [
            _dateField('DD', _dayCtrl, 2),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('/',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: EnduraColors.muted))),
            _dateField('MM', _monthCtrl, 2),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('/',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: EnduraColors.muted))),
            _dateField('YYYY', _yearCtrl, 4),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _openCalendar,
              child: Container(
                width: 48,
                height: 56,
                decoration: BoxDecoration(
                    color: EnduraColors.textPrimary,
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.calendar_today_rounded,
                    size: 20, color: EnduraColors.white),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Week hint ────────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _weekHint != null
                ? Container(
                    key: ValueKey(_weekHint),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                        color: _hintColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _hintColor.withOpacity(0.25))),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: _hintColor),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_weekHint!,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _hintColor,
                                  height: 1.4))),
                    ]),
                  )
                : const SizedBox(key: ValueKey('empty'), height: 0),
          ),

          const Spacer(),
          Text(
              widget.raceDate != null
                  ? 'Date set — tap Continue'
                  : 'Type a date or tap the calendar icon',
              style: const TextStyle(
                  fontSize: 12, color: EnduraColors.muted)),
          const SizedBox(height: 8),
        ]));
  }

  Widget _dateField(
      String hint, TextEditingController ctrl, int maxLen) {
    return Expanded(
      child: Container(
        height: 56,
        decoration: BoxDecoration(
            color: EnduraColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: widget.raceDate != null
                    ? EnduraColors.mint500
                    : EnduraColors.border,
                width: widget.raceDate != null ? 1.5 : 0.5)),
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: EnduraColors.textPrimary),
          decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                  fontSize: 14,
                  color: EnduraColors.muted,
                  fontWeight: FontWeight.w400),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(maxLen),
          ],
          onChanged: (_) => _tryParse(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 5: Running Profile — Weekly mileage → Longest run
// ─────────────────────────────────────────────────────────────────────────────

class _PageRunningProfile extends StatelessWidget {
  final double weeklyMileage;
  final double longestRun;
  final ValueChanged<double> onMileageChanged;
  final ValueChanged<double> onLongestRunChanged;

  const _PageRunningProfile({
    required this.weeklyMileage,
    required this.longestRun,
    required this.onMileageChanged,
    required this.onLongestRunChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EnduraTheme.pagePadding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 32),
        const Center(child: _MicroLabel('Your running background')),
        const SizedBox(height: 4),
        const Center(child: _PageTitle('Tell us about your running')),
        const SizedBox(height: 6),
        const Center(child: _PageSubtitle(
            'We use this to set the right starting point\nand protect you from doing too much too soon.')),
        const SizedBox(height: 36),

        _sectionLabel('WEEKLY KILOMETRES'),
        const SizedBox(height: 4),
        _valueDisplay('${weeklyMileage.round()} km / week'),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: EnduraColors.textPrimary,
            inactiveTrackColor: EnduraColors.border,
            thumbColor: EnduraColors.textPrimary,
            overlayColor: EnduraColors.textPrimary.withOpacity(0.1),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: weeklyMileage,
            min: 5,
            max: 90,
            divisions: 17,
            onChanged: onMileageChanged,
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('5 km', style: TextStyle(fontSize: 11, color: EnduraColors.muted)),
          const Text('90 km', style: TextStyle(fontSize: 11, color: EnduraColors.muted)),
        ]),
        const SizedBox(height: 6),
        Text(_mileageHint(weeklyMileage),
            style: const TextStyle(fontSize: 11, color: EnduraColors.textSecondary)),
        const SizedBox(height: 36),

        _sectionLabel('LONGEST RUN (LAST 30 DAYS)'),
        const SizedBox(height: 4),
        _valueDisplay('${longestRun.round()} km'),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: EnduraColors.textPrimary,
            inactiveTrackColor: EnduraColors.border,
            thumbColor: EnduraColors.textPrimary,
            overlayColor: EnduraColors.textPrimary.withOpacity(0.1),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: longestRun,
            min: 5,
            max: 80,
            divisions: 15,
            onChanged: onLongestRunChanged,
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('5 km', style: TextStyle(fontSize: 11, color: EnduraColors.muted)),
          const Text('80 km', style: TextStyle(fontSize: 11, color: EnduraColors.muted)),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w600,
          color: EnduraColors.muted, letterSpacing: 1.1));

  Widget _valueDisplay(String text) => Text(text,
      style: const TextStyle(
          fontSize: 28, fontWeight: FontWeight.w600,
          color: EnduraColors.textPrimary, letterSpacing: -0.5));

  String _mileageHint(double km) {
    if (km <= 10) return 'Just getting started — Max will keep things light';
    if (km <= 20) return 'Building a base — good foundation to work from';
    if (km <= 40) return 'Solid volume — Max can push with structure';
    return 'High mileage — Max will train you seriously';
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Page 6: Experience Level
// ─────────────────────────────────────────────────────────────────────────────

class _PageExperience extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _PageExperience({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EnduraTheme.pagePadding,
      child: Column(children: [
        const SizedBox(height: 40),
        Container(
          width: 64, height: 64,
          decoration: const BoxDecoration(
            color: EnduraColors.mint50, shape: BoxShape.circle),
          child: const Icon(Icons.speed_rounded,
              size: 32, color: EnduraColors.mint500)),
        const SizedBox(height: 16),
        const _MicroLabel('One more thing'),
        const SizedBox(height: 4),
        const _PageTitle('How would you describe yourself?'),
        const SizedBox(height: 6),
        const _PageSubtitle(
            'We use this to set the right intensity\nfrom day one.'),
        const SizedBox(height: 32),
        _SelectionCard(
          icon: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: EnduraColors.mint50,
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.directions_walk_rounded,
                size: 24, color: EnduraColors.mint500)),
          label: 'Beginner',
          subtitle: "I'm new to running or just getting consistent",
          selected: selected == 'beginner',
          onTap: () => onSelect('beginner')),
        const SizedBox(height: 12),
        _SelectionCard(
          icon: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: EnduraColors.violet50,
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.directions_run_rounded,
                size: 24, color: EnduraColors.violet500)),
          label: 'Intermediate',
          subtitle: 'I run regularly and have done a race or two',
          selected: selected == 'intermediate',
          onTap: () => onSelect('intermediate')),
        const SizedBox(height: 12),
        _SelectionCard(
          icon: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: EnduraColors.orange50,
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.flash_on_rounded,
                size: 24, color: EnduraColors.orange500)),
          label: 'Advanced',
          subtitle: 'I train seriously and know my paces well',
          selected: selected == 'advanced',
          onTap: () => onSelect('advanced')),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 7: Recent Run
// ─────────────────────────────────────────────────────────────────────────────

class _PageRecentRun extends StatelessWidget {
  final double? km;
  final int? minutes;
  final int? seconds;
  final ValueChanged<double> onKmChanged;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onSecondsChanged;
  const _PageRecentRun(
      {required this.km,
      required this.minutes,
      required this.seconds,
      required this.onKmChanged,
      required this.onMinutesChanged,
      required this.onSecondsChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EnduraTheme.pagePadding,
        child: Column(children: [
          const SizedBox(height: 40),
          Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: EnduraColors.mint50, shape: BoxShape.circle),
              child: const Icon(Icons.route_rounded,
                  size: 32, color: EnduraColors.mint500)),
          const SizedBox(height: 16),
          const _MicroLabel('A quick snapshot'),
          const SizedBox(height: 4),
          const _PageTitle('Tell us about a recent run'),
          const SizedBox(height: 6),
          const _PageSubtitle(
              'Any run from the last couple of weeks.\nThis helps Us dial in your zones faster.'),
          const SizedBox(height: 32),
          _lbl('Distance'),
          const SizedBox(height: 8),
          Container(
              decoration: BoxDecoration(
                  color: EnduraColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: EnduraColors.border,
                      width: EnduraTheme.borderWidth)),
              child: TextField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: EnduraColors.textPrimary),
                  decoration: const InputDecoration(
                      hintText: '0.0',
                      hintStyle: TextStyle(color: EnduraColors.muted),
                      suffixText: 'km',
                      suffixStyle: TextStyle(
                          fontSize: 16, color: EnduraColors.textSecondary),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14)),
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (n != null) onKmChanged(n);
                  })),
          const SizedBox(height: 20),
          _lbl('How long did it take?'),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _ti('min', minutes, onMinutesChanged),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: EnduraColors.muted))),
            _ti('sec', seconds, onSecondsChanged),
          ]),
          const Spacer(),
          const Text("No recent run? Skip — We will figure it out",
              style: TextStyle(fontSize: 12, color: EnduraColors.muted)),
          const SizedBox(height: 8),
        ]));
  }

  Widget _lbl(String t) => Align(
      alignment: Alignment.centerLeft,
      child: Text(t,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: EnduraColors.textSecondary)));

  Widget _ti(String l, int? v, ValueChanged<int> cb) => Column(children: [
        Container(
            width: 72,
            decoration: BoxDecoration(
                color: EnduraColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: EnduraColors.border,
                    width: EnduraTheme.borderWidth)),
            child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: EnduraColors.textPrimary),
                decoration: const InputDecoration(
                    hintText: '00',
                    hintStyle: TextStyle(color: EnduraColors.muted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14)),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2)
                ],
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) cb(n);
                })),
        const SizedBox(height: 4),
        Text(l,
            style: const TextStyle(
                fontSize: 11, color: EnduraColors.textSecondary)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 8: Best Time
// ─────────────────────────────────────────────────────────────────────────────

class _PageBestTime extends StatelessWidget {
  final bool knowsPace;
  final String distance;
  final int? minutes;
  final int? seconds;
  final bool isRecent;
  final ValueChanged<bool> onToggleKnows;
  final ValueChanged<String> onDistanceChanged;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onSecondsChanged;
  final ValueChanged<bool> onRecencyChanged;
  const _PageBestTime(
      {required this.knowsPace,
      required this.distance,
      required this.minutes,
      required this.seconds,
      required this.isRecent,
      required this.onToggleKnows,
      required this.onDistanceChanged,
      required this.onMinutesChanged,
      required this.onSecondsChanged,
      required this.onRecencyChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EnduraTheme.pagePadding,
        child: Column(children: [
          const SizedBox(height: 40),
          Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: EnduraColors.mint50, shape: BoxShape.circle),
              child: const Icon(Icons.timer_outlined,
                  size: 32, color: EnduraColors.mint500)),
          const SizedBox(height: 16),
          const _MicroLabel('Sharpen the zones'),
          const SizedBox(height: 4),
          const _PageTitle("What's your best race time?"),
          const SizedBox(height: 6),
          const _PageSubtitle(
              'Gives Us accurate training paces from day one.\nNo guessing, no generic zones.'),
          const SizedBox(height: 20),
          Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: EnduraColors.border,
                      width: EnduraTheme.borderWidth)),
              child: Row(children: [
                _tab('I know my time', knowsPace, () => onToggleKnows(true)),
                _tab("I'm not sure", !knowsPace, () => onToggleKnows(false)),
              ])),
          const SizedBox(height: 24),
          Expanded(child: knowsPace ? _ks() : _us()),
        ]));
  }

  Widget _tab(String l, bool s, VoidCallback f) => Expanded(
      child: GestureDetector(
          onTap: f,
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color:
                      s ? EnduraColors.textPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9)),
              child: Text(l,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: s
                          ? EnduraColors.white
                          : EnduraColors.textSecondary)))));

  Widget _ks() => Column(children: [
        Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['5k', '10k', 'half']
                .map((d) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                        onTap: () => onDistanceChanged(d),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                                color: distance == d
                                    ? EnduraColors.textPrimary
                                    : EnduraColors.surface,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(
                                d == 'half' ? 'Half' : d.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: distance == d
                                        ? EnduraColors.white
                                        : EnduraColors.textSecondary))))))
                .toList()),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ti('min', minutes, onMinutesChanged),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(':',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: EnduraColors.muted))),
          _ti('sec', seconds, onSecondsChanged),
        ]),
        const SizedBox(height: 24),
        Container(
            decoration: BoxDecoration(
                color: EnduraColors.surface,
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              _recTab('Recent', 'Last 6 weeks', true),
              _recTab('Older', '6+ weeks ago', false),
            ])),
        const SizedBox(height: 8),
        Text(
            isRecent
                ? 'We will use this as your current fitness baseline'
                : 'We will apply a small adjustment — fitness may have shifted',
            style: const TextStyle(
                fontSize: 11, color: EnduraColors.textSecondary)),
      ]);

  Widget _recTab(String label, String sub, bool val) => Expanded(
      child: GestureDetector(
          onTap: () => onRecencyChanged(val),
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: isRecent == val
                      ? EnduraColors.textPrimary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9)),
              child: Column(children: [
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isRecent == val
                            ? EnduraColors.white
                            : EnduraColors.textSecondary)),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10, color: EnduraColors.muted)),
              ]))));

  Widget _ti(String l, int? v, ValueChanged<int> cb) => Column(children: [
        Container(
            width: 64,
            decoration: BoxDecoration(
                color: EnduraColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: EnduraColors.border,
                    width: EnduraTheme.borderWidth)),
            child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: EnduraColors.textPrimary),
                decoration: const InputDecoration(
                    hintText: '00',
                    hintStyle: TextStyle(color: EnduraColors.muted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14)),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2)
                ],
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) cb(n);
                })),
        const SizedBox(height: 4),
        Text(l,
            style: const TextStyle(
                fontSize: 11, color: EnduraColors.textSecondary)),
      ]);

  Widget _us() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: EnduraColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: EnduraColors.border)),
            child: const Center(
                child: Text('?',
                    style: TextStyle(
                        fontSize: 24,
                        color: EnduraColors.textPrimary,
                        fontWeight: FontWeight.w500)))),
        const SizedBox(height: 20),
        RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
                style: TextStyle(
                    fontSize: 14,
                    color: EnduraColors.textSecondary,
                    height: 1.6),
                children: [
                  TextSpan(text: "No worries. "),
                  TextSpan(
                      text: 'Max',
                      style: TextStyle(
                          color: EnduraColors.mint500,
                          fontWeight: FontWeight.w500)),
                  TextSpan(
                      text:
                          " will calibrate your zones from your first few runs.\n\nJust run how you normally would."),
                ])),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 9: Training Days
// ─────────────────────────────────────────────────────────────────────────────

class _PageTrainingDays extends StatelessWidget {
  final int runsPerWeek;
  final List<int> selectedDays;
  final ValueChanged<int> onFrequencyChanged;
  final ValueChanged<List<int>> onDaysChanged;

  const _PageTrainingDays({
    required this.runsPerWeek,
    required this.selectedDays,
    required this.onFrequencyChanged,
    required this.onDaysChanged,
  });

  static const _fullDayLabels = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _hints = {
    3: 'Perfect for beginners and busy schedules',
    4: 'Great balance of training and recovery',
    5: 'For committed runners building volume',
    6: 'Serious training with one full rest day',
  };

  void _toggleDay(int idx) {
    final updated = List<int>.from(selectedDays);
    if (updated.contains(idx)) {
      if (updated.length <= 1) return;
      updated.remove(idx);
    } else {
      updated.add(idx);
    }
    updated.sort();
    onDaysChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final countMatchesFreq = selectedDays.length == runsPerWeek;
    return Padding(
      padding: EnduraTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Center(child: _MicroLabel('Almost done')),
          const SizedBox(height: 4),
          const Center(child: _PageTitle('How many days can you train?')),
          const SizedBox(height: 6),
          const Center(child: _PageSubtitle(
              'Then pick which days suit you best.\nWe will fit your workouts around your life.')),
          const SizedBox(height: 28),

          // ── Frequency selector ──────────────────────────────────────
          Row(
            children: [3, 4, 5, 6].map((n) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: n < 6 ? 8 : 0),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onFrequencyChanged(n);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: runsPerWeek == n
                          ? EnduraColors.mint50
                          : EnduraColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: runsPerWeek == n
                            ? EnduraColors.mint500
                            : EnduraColors.border,
                        width: EnduraTheme.borderWidth,
                      ),
                    ),
                    child: Column(children: [
                      Text('$n',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: runsPerWeek == n
                                  ? EnduraColors.mint800
                                  : EnduraColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('days',
                          style: TextStyle(
                              fontSize: 11,
                              color: runsPerWeek == n
                                  ? EnduraColors.mint600
                                  : EnduraColors.textSecondary)),
                    ]),
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _hints[runsPerWeek] ?? '',
              key: ValueKey(runsPerWeek),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  color: EnduraColors.textSecondary,
                  height: 1.5),
            ),
          ),
          const SizedBox(height: 28),

          const Text('PICK YOUR DAYS',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: EnduraColors.muted,
                  letterSpacing: 1.1)),
          const SizedBox(height: 10),

          // ── Day picker — vertical full names ────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: List.generate(7, (i) {
                  final isSelected = selectedDays.contains(i);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _toggleDay(i);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? EnduraColors.textPrimary
                              : EnduraColors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? EnduraColors.textPrimary
                                : EnduraColors.border,
                            width: EnduraTheme.borderWidth,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fullDayLabels[i],
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? EnduraColors.white
                                    : EnduraColors.textPrimary,
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check,
                                  size: 16, color: EnduraColors.mint500),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: countMatchesFreq
                ? const SizedBox(height: 18)
                : Text(
                    key: const ValueKey('validation'),
                    selectedDays.length < runsPerWeek
                        ? 'Select ${runsPerWeek - selectedDays.length} more day${runsPerWeek - selectedDays.length == 1 ? '' : 's'}'
                        : 'Deselect ${selectedDays.length - runsPerWeek} day${selectedDays.length - runsPerWeek == 1 ? '' : 's'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12,
                        color: EnduraColors.orange500,
                        height: 1.5),
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 10: About You — DOB + gender only
// ─────────────────────────────────────────────────────────────────────────────

class _PageAboutYou extends StatefulWidget {
  final String? gender;
  final DateTime? dob;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<DateTime> onDobChanged;
  const _PageAboutYou(
      {required this.gender,
      required this.dob,
      required this.onGenderChanged,
      required this.onDobChanged});
  @override
  State<_PageAboutYou> createState() => _PageAboutYouState();
}

class _PageAboutYouState extends State<_PageAboutYou> {
  final _dayCtrl = TextEditingController();
  final _monthCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.dob != null) {
      _dayCtrl.text = widget.dob!.day.toString().padLeft(2, '0');
      _monthCtrl.text = widget.dob!.month.toString().padLeft(2, '0');
      _yearCtrl.text = widget.dob!.year.toString();
    }
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _tryParseDob() {
    final day = int.tryParse(_dayCtrl.text);
    final month = int.tryParse(_monthCtrl.text);
    final year = int.tryParse(_yearCtrl.text);
    if (day != null && month != null && year != null && year > 1900 && year < DateTime.now().year) {
      try {
        final dob = DateTime(year, month, day);
        widget.onDobChanged(dob);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
        padding: EnduraTheme.pagePadding,
        child: Column(children: [
          const SizedBox(height: 32),
          Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: EnduraColors.mint50, shape: BoxShape.circle),
              child: const Icon(Icons.person_outline_rounded,
                  size: 36, color: EnduraColors.mint500)),
          const SizedBox(height: 16),
          const _MicroLabel('Last thing'),
          const SizedBox(height: 4),
          const _PageTitle('A little about you'),
          const SizedBox(height: 6),
          const _PageSubtitle(
              'We use age to personalise recovery and load.\nNothing else.'),
          const SizedBox(height: 32),

          // ── DOB ──────────────────────────────────────────────────────
          _lbl('DATE OF BIRTH'),
          const SizedBox(height: 10),
          Row(children: [
            _dobField('DD', _dayCtrl, 2),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('/',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: EnduraColors.muted))),
            _dobField('MM', _monthCtrl, 2),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('/',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: EnduraColors.muted))),
            _dobField('YYYY', _yearCtrl, 4),
          ]),

          const SizedBox(height: 32),

          // ── Gender ───────────────────────────────────────────────────
          _lbl('GENDER'),
          const SizedBox(height: 10),
          Row(
              children: ['Male', 'Female', 'Other']
                  .map((g) => Expanded(
                      child: Padding(
                          padding:
                              EdgeInsets.only(right: g != 'Other' ? 8 : 0),
                          child: _Chip(
                              label: g,
                              selected: widget.gender == g.toLowerCase(),
                              onTap: () =>
                                  widget.onGenderChanged(g.toLowerCase())))))
                  .toList()),
          const SizedBox(height: 24),
        ]));
  }

  Widget _lbl(String t) => Align(
      alignment: Alignment.centerLeft,
      child: Text(t,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: EnduraColors.muted,
              letterSpacing: 1.1)));

  Widget _dobField(String hint, TextEditingController ctrl, int maxLen) {
    return Expanded(
      child: Container(
        height: 56,
        decoration: BoxDecoration(
            color: EnduraColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: widget.dob != null
                    ? EnduraColors.mint500
                    : EnduraColors.border,
                width: widget.dob != null ? 1.5 : 0.5)),
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: EnduraColors.textPrimary),
          decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                  fontSize: 14,
                  color: EnduraColors.muted,
                  fontWeight: FontWeight.w400),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(maxLen),
          ],
          onChanged: (_) => _tryParseDob(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page 11: Build Plan
// ─────────────────────────────────────────────────────────────────────────────


class _PageBuildPlan extends StatefulWidget {
  final String goal;
  final DateTime? raceDate;
  final int runsPerWeek;
  final List<int> selectedDayIndices;
  final String? goalIntent;
  final int vdotScore;
  final bool vdotIsProvisional;
  final VoidCallback onStartTraining;
  const _PageBuildPlan({
      required this.goal,
      required this.raceDate,
      required this.runsPerWeek,
      required this.selectedDayIndices,
      required this.goalIntent,
      required this.vdotScore,
      required this.vdotIsProvisional,
      required this.onStartTraining});
  @override
  State<_PageBuildPlan> createState() => _PageBuildPlanState();
}

class _PageBuildPlanState extends State<_PageBuildPlan>
    with TickerProviderStateMixin {
  late AnimationController _ring;
  int _stg = 0;
  bool _card = false;

  static const _txt = [
    'Analyzing your profile...',
    'Calculating your zones...',
    'Building your training plan...',
  ];

  @override
  void initState() {
    super.initState();
    // Ring runs to 100% in 3.2s, then holds
    _ring = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3200))
      ..forward();

    Future.delayed(const Duration(milliseconds: 800),
        () { if (mounted) setState(() => _stg = 1); });
    Future.delayed(const Duration(milliseconds: 1800),
        () { if (mounted) setState(() => _stg = 2); });
    Future.delayed(const Duration(milliseconds: 2800),
        () { if (mounted) setState(() => _stg = 3); });
    // Hold at 100% for ~1.5s before showing card
    Future.delayed(const Duration(milliseconds: 4700),
        () { if (mounted) setState(() => _card = true); });
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  String get _gl => switch (widget.goal) {
        '5k' => '5K',
        '10k' => '10K',
        'half_marathon' => 'Half marathon',
        'marathon' => 'Marathon',
        _ => '5K'
      };

  String get _intentLabel => switch (widget.goalIntent) {
        'finish' => 'Finish comfortably',
        'improve' => 'Improve steadily',
        'peak'   => 'Peak performance',
        _        => ''
      };

  String get _raceDateLabel {
    final d = widget.raceDate;
    if (d == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  int get _weeksOut {
    if (widget.raceDate == null) return 12;
    return widget.raceDate!.difference(DateTime.now()).inDays ~/ 7;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EnduraTheme.pagePadding,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // ── Ring ────────────────────────────────────────────────────
          SizedBox(
              width: 90,
              height: 90,
              child: AnimatedBuilder(
                  animation: _ring,
                  builder: (_, __) => Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                                size: const Size(90, 90),
                                painter: _RPaint(_ring.value)),
                            Text(
                                '${(_ring.value * 100).round()}%',
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w500,
                                    color: EnduraColors.textPrimary)),
                          ]))),
          const SizedBox(height: 28),

          // ── Steps ────────────────────────────────────────────────────
          ...List.generate(
              3,
              (i) => AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _stg >= i ? 1.0 : 0.3,
                  child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _stg > i
                                    ? EnduraColors.mint50
                                    : EnduraColors.surface),
                            child: _stg > i
                                ? const Icon(Icons.check,
                                    size: 12, color: EnduraColors.mint500)
                                : null),
                        const SizedBox(width: 10),
                        Text(_txt[i],
                            style: TextStyle(
                                fontSize: 13,
                                color: _stg > i
                                    ? EnduraColors.textPrimary
                                    : EnduraColors.muted)),
                      ])))),

          const SizedBox(height: 16),

          // ── Plan card ────────────────────────────────────────────────
          AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: _card ? 1.0 : 0.0,
              child: AnimatedSlide(
                  duration: const Duration(milliseconds: 500),
                  offset: _card ? Offset.zero : const Offset(0, 0.1),
                  child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                          color: EnduraColors.surface,
                          borderRadius:
                              BorderRadius.circular(EnduraTheme.radius)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('YOUR PLAN IS READY',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: EnduraColors.mint500,
                                    letterSpacing: 0.3)),
                            const SizedBox(height: 10),
                            Text(
                                _raceDateLabel.isNotEmpty
                                    ? '$_gl — $_raceDateLabel'
                                    : _gl,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    color: EnduraColors.textPrimary)),
                            if (_intentLabel.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(_intentLabel,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: EnduraColors.textSecondary)),
                            ],
                            const SizedBox(height: 4),
                            Text(
                                'Phase 1: Base building · $_weeksOut weeks total',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: EnduraColors.textSecondary)),
                            const SizedBox(height: 14),
                            Row(
                                children: List.generate(7, (i) {
                              final isActive = widget.selectedDayIndices.contains(i);
                              return Padding(
                                  padding:
                                      const EdgeInsets.only(right: 6),
                                  child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isActive
                                              ? EnduraColors.textPrimary
                                              : EnduraColors.border),
                                      child: Center(
                                          child: Text(
                                              TrainingDaysService
                                                  .dayLabels[i],
                                              style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight:
                                                      FontWeight.w500,
                                                  color: isActive
                                                      ? EnduraColors.white
                                                      : EnduraColors
                                                          .muted)))));
                            })),
                            const SizedBox(height: 14),
                            Container(
                                padding:
                                    const EdgeInsets.only(top: 12),
                                decoration: const BoxDecoration(
                                    border: Border(
                                        top: BorderSide(
                                            color: EnduraColors.border,
                                            width: 0.5))),
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _s('${widget.runsPerWeek}',
                                          'runs/week'),
                                      _s('$_weeksOut', 'weeks total'),
                                      _s('vDOT ${widget.vdotScore}',
                                          widget.vdotIsProvisional ? 'estimated' : 'from PR'),
                                    ])),
                          ])))),

          // ── Start button — only shows after card ─────────────────────
          if (_card) ...[
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                    onPressed: widget.onStartTraining,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: EnduraColors.textPrimary,
                        foregroundColor: EnduraColors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                EnduraTheme.radius))),
                    child: const Text('Start training',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500)))),
          ],
        ]));
  }

  Widget _s(String v, String l) => Column(children: [
        Text(v,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: EnduraColors.textPrimary)),
        Text(l,
            style: const TextStyle(
                fontSize: 10, color: EnduraColors.textSecondary)),
      ]);
}

class _RPaint extends CustomPainter {
  final double p;
  _RPaint(this.p);
  @override
  void paint(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    c.drawCircle(
        ctr,
        40,
        Paint()
          ..color = EnduraColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    c.drawArc(
        Rect.fromCircle(center: ctr, radius: 40),
        -pi / 2,
        2 * pi * p,
        false,
        Paint()
          ..color = EnduraColors.mint500
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RPaint o) => o.p != p;
}