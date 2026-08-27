import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/training_days_service.dart';
import '../../engines/planner/race_plan_builder.dart';
import '../../engines/memory/engine_memory_service.dart';
import '../../engines/core/vdot_calculator.dart';
import '../../services/profile_service.dart';
import '../../services/analytics_service.dart';
import 'onboarding_pages.dart';
import '../../models/training_phase.dart';

class EC {
  static const bg = Color(0xFF0D0D0D);
  static const surface = Color(0xFF1A1A1A);
  static const surface2 = Color(0xFF242424);
  static const border = Color(0xFF2E2E2E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9A9A9A);
  static const muted = Color(0xFF555555);
  static const teal = Color(0xFF00C2A8);
  static const tealDim = Color(0xFF00856F);
  static const red = Color(0xFFE84040);
  static const amber = Color(0xFFF0A800);
  static const violet = Color(0xFF7C6EF0);
  static const orange = Color(0xFFFF7A3D);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
}

class ET {
  static const radius = 14.0;
  static const cardRadius = 16.0;
  static const borderWidth = 0.75;
  static const pagePad = EdgeInsets.symmetric(horizontal: 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE ENUM — race-first onboarding
// ─────────────────────────────────────────────────────────────────────────────

enum OPage {
  goal, // "What are you training for?" — only Upcoming race is live
  racePicker, // pick a real race (or add one manually)
  experience, // race-type experience (this flow's own 5-level vocab)
  pastMonth, // km run in the past month
  raceGoal, // what's the goal for this race (this flow's own vocab)
  targetTime, // shown only for pr / target_time goals
  runsPerWeek, // slider + live plan preview
  dayPicker, // which days are free
  longRunDay, // long run day
  currentTime, // current race time -> vDOT
  planStart, // start today vs start next week
  review, // final plan overview
  buildPlan, // building animation
  welcome,
}

// ─────────────────────────────────────────────────────────────────────────────
// ENGINE BRIDGE
// The onboarding flow speaks its own vocabulary. The plan engine still speaks
// the legacy one (beginner/intermediate/advanced, structured/steady). These two
// helpers are the ONLY place the two vocabularies meet. Remove them when the
// engine is rebuilt to speak the new vocab natively.
// ─────────────────────────────────────────────────────────────────────────────

String _bridgeExperience(String? raceExperience) => switch (raceExperience) {
  'just_starting' => 'beginner',
  'early' => 'beginner',
  'regular' => 'intermediate',
  'seasoned' => 'advanced',
  'competitive' => 'advanced',
  _ => 'intermediate',
};

String _bridgeGoalIntent(String? raceGoal) => switch (raceGoal) {
  'pr' => 'structured',
  'target_time' => 'structured',
  'undecided' => 'structured',
  'finish' => 'steady',
  'enjoy' => 'steady',
  _ => 'structured',
};

// ─────────────────────────────────────────────────────────────────────────────
// SHELL
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  /// When true, skips the goal page (drops straight into the race picker) and
  /// carries over experience / fitness data from the existing profile.
  /// Used for post-plan re-onboarding.
  final bool shortenedMode;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.shortenedMode = false,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _ctrl = PageController();
  int _current = 0;
  bool _prefilledFromMemory = false;

  // ── Collected data ───────────────────────────────────────────────────────

  // Race (from racePicker)
  String? _raceId;
  String? _raceName;
  String? _raceCity;
  DateTime? _raceDate;

  // Goal distance key: '5k' | '10k' | 'half_marathon' | 'marathon'
  String? _goal;

  // Race-type experience — this flow's own vocab
  String? _experience;

  // Past-month volume
  String? _pastMonthBucket;
  double _pastMonthKm = 0;

  // Race goal — this flow's own vocab
  String? _raceGoal;
  int? _timeToBeatSec; // for 'pr'
  int? _targetFinishSec; // for 'target_time'

  // Training days
  int _runsPerWeek = 4;
  List<int> _selectedDays = TrainingDaysService.defaultsFor(4);
  int? _longRunDayIndex;

  // Current race time (vDOT inputs) — OPageBestTime uses 'half' not 'half_marathon'
  String _paceDistance = '5k';
  int _paceHours = 0;
  int _paceMinutes = 25;
  int _paceSeconds = 0;

  // Plan start
  DateTime _startDate = DateTime.now();
  int? _planWeeks;

  // Computed
  int _vdot = 40;
  bool _vdotProvisional = true;

  late AnimationController _loopCtrl;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);

    if (widget.shortenedMode) {
      _prefillFromExistingProfile();
    }

    Analytics.onboardingStepViewed(_sequence.first.name, 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillFromExistingProfile() async {
    if (_prefilledFromMemory) return;
    _prefilledFromMemory = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final memory = await EngineMemoryService().load();

      _experience = prefs.getString('race_experience');
      _raceGoal = prefs.getString('race_goal');

      final paceMin = prefs.getInt('pace_minutes');
      final paceSec = prefs.getInt('pace_seconds') ?? 0;
      if (paceMin != null) {
        _paceHours = prefs.getInt('pace_hours') ?? 0;
        _paceMinutes = paceMin;
        _paceSeconds = paceSec;
        _paceDistance = prefs.getString('pace_distance') ?? '5k';
      }
      _vdot = memory.vdotScore;
      _vdotProvisional = memory.vdotIsProvisional;

      final storedDays = await TrainingDaysService.load();
      if (storedDays != null && storedDays.isNotEmpty) {
        _selectedDays = storedDays;
        _runsPerWeek = storedDays.length;
      }
      _longRunDayIndex =
          prefs.getInt('long_run_day_index') ?? memory.longRunDayIndex;

      final lastMonthKm = prefs.getDouble('past_month_km');
      if (lastMonthKm != null && lastMonthKm > 0) {
        _pastMonthKm = lastMonthKm;
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[Onboarding] Prefill error: $e');
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  static const _fullSequence = OPage.values;

  static const _shortSequence = [
    OPage.racePicker,
    OPage.experience,
    OPage.pastMonth,
    OPage.raceGoal,
    OPage.targetTime,
    OPage.runsPerWeek,
    OPage.dayPicker,
    OPage.longRunDay,
    OPage.currentTime,
    OPage.planStart,
    OPage.review,
    OPage.buildPlan,
    OPage.welcome,
  ];

  List<OPage> get _sequence =>
      widget.shortenedMode ? _shortSequence : _fullSequence;

  int get _total => _sequence.length;
  OPage get _currentPage => _sequence[_current];

  bool get _needsTargetTime => _raceGoal == 'pr' || _raceGoal == 'target_time';

  bool get _showTopBar =>
      _currentPage != OPage.buildPlan && _currentPage != OPage.welcome;

  bool get _showBottom =>
      _currentPage != OPage.goal &&
      _currentPage != OPage.review &&
      _currentPage != OPage.buildPlan &&
      _currentPage != OPage.welcome;

  double get _progress => 0.05 + (_current / max(1, _total - 1)) * 0.95;

  void _next() {
    int next = _current + 1;
    if (next < _total &&
        _sequence[next] == OPage.targetTime &&
        !_needsTargetTime) {
      next++;
    }
    if (next < _total) {
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prev() {
    int prev = _current - 1;
    if (prev >= 0 &&
        _sequence[prev] == OPage.targetTime &&
        !_needsTargetTime) {
      prev--;
    }
    if (prev >= 0) {
      _ctrl.animateToPage(
        prev,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int p) {
    setState(() => _current = p);
    HapticFeedback.selectionClick();
    Analytics.onboardingStepViewed(_sequence[p].name, p);
  }

  // ── Validation ───────────────────────────────────────────────────────────

  bool get _canContinue {
    switch (_currentPage) {
      case OPage.goal:
        return false; // auto-advances on tap; no Continue button
      case OPage.racePicker:
        return _raceDate != null && _goal != null;
      case OPage.experience:
        return _experience != null;
      case OPage.pastMonth:
        return _pastMonthBucket != null;
      case OPage.raceGoal:
        return _raceGoal != null;
      case OPage.targetTime:
        return _raceGoal == 'pr'
            ? _timeToBeatSec != null
            : _targetFinishSec != null;
      case OPage.runsPerWeek:
        return true;
      case OPage.dayPicker:
        return _selectedDays.length == _runsPerWeek;
      case OPage.longRunDay:
        return _longRunDayIndex != null;
      case OPage.currentTime:
        return _paceMinutes > 0 || _paceHours > 0;
      case OPage.planStart:
        return _planWeeks != null;
      case OPage.review:
      case OPage.buildPlan:
      case OPage.welcome:
        return false;
    }
  }

  // ── Distance helpers ─────────────────────────────────────────────────────

  /// Goal key -> OPageBestTime's distance key ('half' vs 'half_marathon').
  static String _paceDistFor(String? goal) => switch (goal) {
    '10k' => '10k',
    'half_marathon' => 'half',
    'marathon' => 'marathon',
    _ => '5k',
  };

  double get _paceDistanceKm => switch (_paceDistance) {
    '10k' => 10.0,
    'half' => 21.0975,
    'marathon' => 42.195,
    _ => 5.0,
  };

  int get _currentTimeSec =>
      _paceHours * 3600 + _paceMinutes * 60 + _paceSeconds;

  // ── Plan-start options ───────────────────────────────────────────────────

  List<PlanStartOption> _planStartOptions() {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final race = _raceDate ?? today.add(const Duration(days: 84));

    int weeksBetween(DateTime from) =>
        max(4, race.difference(from).inDays ~/ 7);

    // Next Monday strictly after today.
    final daysToMon = (8 - today.weekday) % 7 == 0 ? 7 : (8 - today.weekday) % 7;
    final nextMon = today.add(Duration(days: daysToMon));

    final wToday = weeksBetween(today);
    var wMon = weeksBetween(nextMon);
    if (wMon >= wToday) wMon = max(4, wToday - 1);

    return [
      PlanStartOption(startDate: today, weeks: wToday, isToday: true),
      PlanStartOption(startDate: nextMon, weeks: wMon, isToday: false),
    ];
  }

  // ── vDOT computation ─────────────────────────────────────────────────────

  (int, bool) _computeVdot() {
    if (widget.shortenedMode && !_vdotProvisional && _currentTimeSec == 0) {
      return (_vdot, false);
    }
    final totalSec = _currentTimeSec;
    if (totalSec > 0) {
      final vdot = vdotFromPr(
        prTimeSeconds: totalSec,
        prDistanceKm: _paceDistanceKm,
        confidence: PrConfidence.high,
      );
      return (vdot, false);
    }
    return (_vdot, _vdotProvisional);
  }

  int get _effectivePlanWeeks => _planWeeks ?? 12;

  // ── Save & complete ──────────────────────────────────────────────────────

  Future<void> _saveAll() async {
    final (vdot, provisional) = _computeVdot();
    _vdot = vdot;
    _vdotProvisional = provisional;

    final double effectiveBaselineKm = _pastMonthKm > 0
        ? _pastMonthKm / 4.345
        : _runsPerWeek * 8.0;

    final goalRace = _goal ?? '5k';
    final exp = _bridgeExperience(_experience);
    final intent = _bridgeGoalIntent(_raceGoal);
    final raceDate =
        _raceDate ?? _startDate.add(Duration(days: _effectivePlanWeeks * 7));

    try {
      final prefs = await SharedPreferences.getInstance();

      // ── Race + goal ────────────────────────────────────────────────────
      await prefs.setString('goal_race', goalRace);
      await prefs.setString('experience_level', exp);
      await prefs.setString('goal_intent', intent);

      // New-vocab values (source of truth going forward)
      if (_experience != null) {
        await prefs.setString('race_experience', _experience!);
      }
      if (_raceGoal != null) await prefs.setString('race_goal', _raceGoal!);
      if (_raceName != null) await prefs.setString('race_name', _raceName!);
      if (_raceId != null) {
        await prefs.setString('race_id', _raceId!);
      } else {
        await prefs.remove('race_id');
      }
      if (_raceCity != null) await prefs.setString('race_city', _raceCity!);
      if (_timeToBeatSec != null) {
        await prefs.setInt('time_to_beat_seconds', _timeToBeatSec!);
      }
      if (_targetFinishSec != null) {
        await prefs.setInt('target_finish_seconds', _targetFinishSec!);
      }
      await prefs.setDouble('past_month_km', _pastMonthKm);

      // ── Schedule ───────────────────────────────────────────────────────
      await prefs.setInt('runs_per_week', _runsPerWeek);
      await TrainingDaysService.save(_selectedDays);
      if (_longRunDayIndex != null) {
        await prefs.setInt('long_run_day_index', _longRunDayIndex!);
      }

      // ── Timeline ───────────────────────────────────────────────────────
      await prefs.setString('race_date', raceDate.toIso8601String());
      if (_planWeeks != null) await prefs.setInt('plan_weeks', _planWeeks!);
      await prefs.setString('plan_start_date', _startDate.toIso8601String());

      // ── vDOT inputs ────────────────────────────────────────────────────
      await prefs.setString('pace_distance', _paceDistance);
      await prefs.setInt('pace_hours', _paceHours);
      await prefs.setInt('pace_minutes', _paceMinutes);
      await prefs.setInt('pace_seconds', _paceSeconds);

      await prefs.setDouble('weekly_mileage_km', effectiveBaselineKm);
      await prefs.setInt('vdot_score', _vdot);
      await prefs.setBool('vdot_is_provisional', _vdotProvisional);

      // ── Engine memory ──────────────────────────────────────────────────
      final memService = EngineMemoryService();
      final mem = await memService.load();
      await memService.save(
        mem.copyWith(
          vdotScore: _vdot,
          vdotIsProvisional: _vdotProvisional,
          longRunDayIndex: _longRunDayIndex,
          baselineWeeklyKm: effectiveBaselineKm,
          previousWeekTargetKm: effectiveBaselineKm,
          firstRunDate: _startDate,
          clearPlanCompletedAt: true,
          isInMaintenance: false,
          currentPhase: TrainingPhase.base,
        ),
      );

      // ── Race plan ──────────────────────────────────────────────────────
      try {
        final plan = RacePlanBuilder.build(
          currentWeeklyKm: effectiveBaselineKm,
          goalRace: goalRace,
          raceDate: raceDate,
          experienceLevel: exp,
        );
        await EngineMemoryService().saveRacePlan(plan);
      } catch (e) {
        debugPrint('[Onboarding] Race plan error: $e');
      }

      // ── Supabase profile — name/gender/dob dropped from this flow ───────
      await ProfileService.instance.saveProfile(
        UserProfile(
          firstName: null,
          gender: null,
          dob: null,
          goal: goalRace,
          runsPerWeek: _runsPerWeek,
          trainingDays: _selectedDays,
          paceDistance: _paceDistance,
          paceHours: _paceHours,
          paceMinutes: _paceMinutes,
          paceSeconds: _paceSeconds,
          raceDate: raceDate,
          useMetric: true,
          baselineWeeklyKm: effectiveBaselineKm,
          planStartDate: _startDate,
          planWeeks: _planWeeks,
          vdotScore: _vdot,
          vdotIsProvisional: _vdotProvisional,
          experienceLevel: exp,
          goalIntent: intent,
          longRunDayIndex: _longRunDayIndex,
        ),
      );

      await Analytics.onboardingCompleted(
        goal: goalRace,
        level: exp,
        runsPerWeek: _runsPerWeek,
        planWeeks: _effectivePlanWeeks,
      );
    } catch (e) {
      debugPrint('[Onboarding] Save error: $e');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EC.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (_showTopBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _prev();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: EC.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 3,
                            backgroundColor: EC.surface2,
                            valueColor: const AlwaysStoppedAnimation(EC.teal),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 34),
                  ],
                ),
              ),

            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: _onPageChanged,
                physics: const NeverScrollableScrollPhysics(),
                children: _buildPages(),
              ),
            ),

            if (_showBottom)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _canContinue ? _next : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EC.teal,
                      foregroundColor: EC.black,
                      disabledBackgroundColor: EC.surface2,
                      disabledForegroundColor: EC.muted,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ET.radius),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Page builder ─────────────────────────────────────────────────────────

  List<Widget> _buildPages() {
    final previewVdot = _computeVdot();
    return _sequence.map((page) => _buildPage(page, previewVdot)).toList();
  }

  Widget _buildPage(OPage page, (int, bool) previewVdot) {
    return switch (page) {
      OPage.goal => OPageGoal(
        selected: _goal,
        onOpenRaceFunnel: _next,
      ),

      OPage.racePicker => OPageRacePicker(
        raceName: _raceName,
        raceDate: _raceDate,
        goal: _goal,
        onSelect: ({id, required name, city, required date, distanceKey}) {
          setState(() {
            _raceId = id;
            _raceName = name;
            _raceCity = city;
            _raceDate = date;
            _goal = distanceKey ?? _goal;
            _paceDistance = _paceDistFor(_goal);
          });
        },
        onDistanceKey: (k) => setState(() {
          _goal = k;
          _paceDistance = _paceDistFor(k);
        }),
      ),

      OPage.experience => OPageExperience(
        selected: _experience,
        onSelect: (v) => setState(() => _experience = v),
      ),

      OPage.pastMonth => OPagePastMonth(
        selected: _pastMonthBucket,
        onSelect: (bucket, km) => setState(() {
          _pastMonthBucket = bucket;
          _pastMonthKm = km;
        }),
      ),

      OPage.raceGoal => OPageRaceGoal(
        selected: _raceGoal,
        onSelect: (v) => setState(() {
          _raceGoal = v;
          if (v != 'pr') _timeToBeatSec = null;
          if (v != 'target_time') _targetFinishSec = null;
        }),
      ),

      OPage.targetTime => OPageTargetTime(
        mode: _raceGoal == 'pr' ? TargetTimeMode.beat : TargetTimeMode.finish,
        goal: _goal ?? '5k',
        seconds: _raceGoal == 'pr' ? _timeToBeatSec : _targetFinishSec,
        onChanged: (s) => setState(() {
          if (_raceGoal == 'pr') {
            _timeToBeatSec = s;
          } else {
            _targetFinishSec = s;
          }
        }),
      ),

      OPage.runsPerWeek => OPageRunsPerWeek(
        runsPerWeek: _runsPerWeek,
        pastMonthKm: _pastMonthKm,
        goal: _goal ?? '5k',
        onChanged: (n) => setState(() {
          _runsPerWeek = n;
          _selectedDays = TrainingDaysService.defaultsFor(n);
          _longRunDayIndex = null;
        }),
      ),

      OPage.dayPicker => OPageDayPicker(
        runsPerWeek: _runsPerWeek,
        selectedDays: _selectedDays,
        onChanged: (days) => setState(() {
          _selectedDays = days;
          _longRunDayIndex = null;
        }),
      ),

      OPage.longRunDay => OPageLongRunDay(
        availableDays: _selectedDays,
        selectedDayIndex: _longRunDayIndex,
        onSelect: (i) => setState(() => _longRunDayIndex = i),
      ),

      OPage.currentTime => OPageBestTime(
        distance: _paceDistance,
        hours: _paceHours,
        minutes: _paceMinutes,
        seconds: _paceSeconds,
        onDistChanged: (v) => setState(() => _paceDistance = v),
        onHoursChanged: (v) => setState(() => _paceHours = v),
        onMinsChanged: (v) => setState(() => _paceMinutes = v),
        onSecsChanged: (v) => setState(() => _paceSeconds = v),
      ),

      OPage.planStart => OPagePlanStart(
        options: _planStartOptions(),
        selectedStart: _planWeeks == null ? null : _startDate,
        onSelect: (opt) => setState(() {
          _startDate = opt.startDate;
          _planWeeks = opt.weeks;
        }),
      ),

      OPage.review => OPageGeneratePlan(
        firstName: 'you',
        goal: _goal ?? '5k',
        startDate: _startDate,
        planWeeks: _planWeeks,
        raceDate: _raceDate,
        raceDayIndex: (_raceDate?.weekday ?? 7) - 1,
        runsPerWeek: _runsPerWeek,
        selectedDays: _selectedDays,
        intensity: _bridgeGoalIntent(_raceGoal),
        vdotScore: previewVdot.$1,
        onGenerate: _next,
      ),

      OPage.buildPlan => OPageBuildPlan(
        firstName: 'you',
        goal: _goal ?? '5k',
        onComplete: () async {
          await _saveAll();
          if (mounted) _next();
        },
      ),

      OPage.welcome => OPageWelcome(
        firstName: 'Runner',
        goal: _goal ?? '5k',
        vdot: previewVdot.$1,
        planWeeks: _effectivePlanWeeks,
        experienceLevel: _bridgeExperience(_experience),
        currentTimeSec: _currentTimeSec,
        paceDistanceKm: _paceDistanceKm,
        onContinue: widget.onComplete,
      ),
    };
  }
}
