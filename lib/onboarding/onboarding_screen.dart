import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/training_days_service.dart';
import '../../engines/planner/race_plan_builder.dart';
import '../../engines/memory/engine_memory_service.dart';
import '../../engines/core/vdot_calculator.dart';
import '../../services/profile_service.dart';
import 'onboarding_pages.dart';
import '../../models/training_phase.dart';

class EC {
  static const bg       = Color(0xFF0D0D0D);
  static const surface  = Color(0xFF1A1A1A);
  static const surface2 = Color(0xFF242424);
  static const border   = Color(0xFF2E2E2E);
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9A9A9A);
  static const muted         = Color(0xFF555555);
  static const teal    = Color(0xFF00C2A8);
  static const tealDim = Color(0xFF00856F);
  static const red    = Color(0xFFE84040);
  static const amber  = Color(0xFFF0A800);
  static const violet = Color(0xFF7C6EF0);
  static const orange = Color(0xFFFF7A3D);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
}

class ET {
  static const radius      = 14.0;
  static const cardRadius  = 16.0;
  static const borderWidth = 0.75;
  static const pagePad     = EdgeInsets.symmetric(horizontal: 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum OPage {
  intro,
  goal,
  experience,
  bestTime,
  daysCount,
  dayPicker,
  longRunDay,
  weeklyMileage,
  intensity,
  planTimeline,
  dob,
  gender,
  name,
  generatePlan,
  buildPlan,
  welcome,
}

// ─────────────────────────────────────────────────────────────────────────────
// SHELL
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  /// When true, skips intro, experience, bestTime, dob, gender, name.
  /// Used for post-plan re-onboarding. Carries over existing profile data.
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
  String?   _goal;
  String?   _experience;

  // Best time (carried over in shortened mode)
  String    _paceDistance = '5k';
  int       _paceHours    = 0;
  int       _paceMinutes  = 25;
  int       _paceSeconds  = 0;
  bool      _knowsTime    = true;

  // Training days
  int        _runsPerWeek      = 4;
  List<int>  _selectedDays     = TrainingDaysService.defaultsFor(4);
  int?       _longRunDayIndex;

  // Weekly mileage
  double     _weeklyKm         = 0;

  // Intensity / goal intent (carried over)
  String?   _intensity;

  // Plan timeline
  DateTime  _startDate  = DateTime.now();
  int?      _planWeeks;
  DateTime? _raceDate;

  // Personal (carried over in shortened mode)
  DateTime? _dob;
  String?   _gender;
  String    _firstName = '';
  String    _lastName  = '';

  // Computed
  int  _vdot            = 40;
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
    _startDate = DateTime(now.year, now.month, now.day + 1);

    if (widget.shortenedMode) {
      _prefillFromExistingProfile();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  /// Load carried-over values from prefs + EngineMemory for shortened mode.
  Future<void> _prefillFromExistingProfile() async {
    if (_prefilledFromMemory) return;
    _prefilledFromMemory = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final memory = await EngineMemoryService().load();

      // Carry over experience + personal info
      _experience = prefs.getString('experience_level') ?? 'intermediate';
      _intensity  = prefs.getString('goal_intent');
      _gender     = prefs.getString('gender');
      _firstName  = prefs.getString('first_name') ?? '';
      _lastName   = prefs.getString('last_name') ?? '';
      final dobRaw = prefs.getString('dob');
      if (dobRaw != null) _dob = DateTime.tryParse(dobRaw);

      // Carry over best time (vDOT used instead of re-entering time)
      final paceMin = prefs.getInt('pace_minutes');
      final paceSec = prefs.getInt('pace_seconds') ?? 0;
      if (paceMin != null) {
        _paceMinutes = paceMin;
        _paceSeconds = paceSec;
        _paceDistance = prefs.getString('pace_distance') ?? '5k';
        _knowsTime = true;
      } else {
        _knowsTime = false;
      }
      _vdot = memory.vdotScore;
      _vdotProvisional = memory.vdotIsProvisional;

      // Pre-fill training days from last plan
      final storedDays = await TrainingDaysService.load();
      if (storedDays != null && storedDays.isNotEmpty) {
        _selectedDays = storedDays;
        _runsPerWeek  = storedDays.length;
      }
      _longRunDayIndex = prefs.getInt('long_run_day_index') ??
          (memory.longRunDayIndex);

      // Pre-fill weekly mileage from last plan's final week volume
      final lastWeekKm = memory.previousWeekTargetKm ??
          memory.baselineWeeklyKm;
      if (lastWeekKm != null && lastWeekKm > 0) {
        _weeklyKm = lastWeekKm;
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[Onboarding] Prefill error: $e');
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  /// Full sequence (first-time onboarding).
  static const _fullSequence = OPage.values;

  /// Shortened sequence (post-plan re-onboarding).
  /// Skips: intro, experience, bestTime, dob, gender, name.
  static const _shortSequence = [
    OPage.goal,
    OPage.planTimeline,
    OPage.daysCount,
    OPage.dayPicker,
    OPage.weeklyMileage,
    OPage.generatePlan,
    OPage.buildPlan,
    OPage.welcome,
  ];

  List<OPage> get _sequence =>
      widget.shortenedMode ? _shortSequence : _fullSequence;

  int get _total => _sequence.length;
  OPage get _currentPage => _sequence[_current];

  bool get _showTopBar =>
      _currentPage != OPage.intro &&
      _currentPage != OPage.buildPlan &&
      _currentPage != OPage.welcome;

  bool get _showBottom =>
      _currentPage != OPage.buildPlan &&
      _currentPage != OPage.welcome &&
      _currentPage != OPage.generatePlan;

  double get _progress =>
      0.05 + (_current / max(1, _total - 1)) * 0.95;

  void _next() {
    if (_current < _total - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prev() {
    if (_current > 0) {
      _ctrl.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int p) {
    setState(() => _current = p);
    HapticFeedback.selectionClick();
  }

  // ── Validation ───────────────────────────────────────────────────────────

  bool get _canContinue {
    switch (_currentPage) {
      case OPage.intro:          return true;
      case OPage.goal:           return _goal != null;
      case OPage.experience:     return _experience != null;
      case OPage.bestTime:       return !_knowsTime || _paceMinutes > 0;
      case OPage.daysCount:      return true;
      case OPage.dayPicker:      return _selectedDays.length == _runsPerWeek;
      case OPage.longRunDay:     return _longRunDayIndex != null;
      case OPage.weeklyMileage:  return _weeklyKm >= 5;
      case OPage.intensity:      return _intensity != null;
      case OPage.planTimeline:   return _planWeeks != null || _raceDate != null;
      case OPage.dob:            return _dob != null;
      case OPage.gender:         return _gender != null;
      case OPage.name:           return _firstName.trim().isNotEmpty;
      case OPage.generatePlan:   return false;
      case OPage.buildPlan:      return false;
      case OPage.welcome:        return false;
    }
  }

  // ── vDOT computation ─────────────────────────────────────────────────────

  (int, bool) _computeVdot() {
    // In shortened mode use existing vDOT directly — don't re-derive from time.
    if (widget.shortenedMode && !_vdotProvisional) {
      return (_vdot, false);
    }

    if (_knowsTime) {
      final totalSec =
          _paceHours * 3600 + _paceMinutes * 60 + _paceSeconds;
      if (totalSec > 0) {
        final distKm = switch (_paceDistance) {
          '10k'      => 10.0,
          'half'     => 21.0975,
          'marathon' => 42.195,
          _          => 5.0,
        };
        final vdot = vdotFromPr(
          prTimeSeconds: totalSec,
          prDistanceKm: distKm,
          confidence: PrConfidence.high,
        );
        return (vdot, false);
      }
    }
    return (_vdot, _vdotProvisional);
  }

  // ── Helpers for welcome page ─────────────────────────────────────────────

  int get _currentTimeSec =>
      _paceHours * 3600 + _paceMinutes * 60 + _paceSeconds;

  double get _paceDistanceKm => switch (_paceDistance) {
        '10k'      => 10.0,
        'half'     => 21.0975,
        'marathon' => 42.195,
        _          => 5.0,
      };

  int get _effectivePlanWeeks {
    if (_planWeeks != null) return _planWeeks!;
    if (_raceDate != null) {
      return _raceDate!.difference(DateTime.now()).inDays ~/ 7;
    }
    return 12;
  }

  // ── Save & complete ──────────────────────────────────────────────────────

  Future<void> _saveAll() async {
    final (vdot, provisional) = _computeVdot();
    _vdot = vdot;
    _vdotProvisional = provisional;

    final double effectiveBaselineKm =
        _weeklyKm > 0 ? _weeklyKm : _runsPerWeek * 8.0;

    try {
      final prefs = await SharedPreferences.getInstance();
      final exp = _experience ?? 'intermediate';

      await prefs.setString('goal_race', _goal ?? '5k');
      await prefs.setString('experience_level', exp);
      await prefs.setInt('runs_per_week', _runsPerWeek);
      await TrainingDaysService.save(_selectedDays);

      if (_longRunDayIndex != null) {
        await prefs.setInt('long_run_day_index', _longRunDayIndex!);
      }
      if (_intensity != null) {
        await prefs.setString('goal_intent', _intensity!);
      }
      if (_raceDate != null) {
        await prefs.setString('race_date', _raceDate!.toIso8601String());
      }
      if (_planWeeks != null) {
        await prefs.setInt('plan_weeks', _planWeeks!);
      }
      await prefs.setString('plan_start_date', _startDate.toIso8601String());

      // Personal fields — only persist in full mode (shortened carries existing values).
      if (!widget.shortenedMode) {
        if (_dob != null) {
          await prefs.setString('dob', _dob!.toIso8601String());
        }
        if (_gender != null) await prefs.setString('gender', _gender!);
        await prefs.setString('first_name', _firstName.trim());
        await prefs.setString('last_name', _lastName.trim());
        if (_knowsTime) {
          await prefs.setString('pace_distance', _paceDistance);
          await prefs.setInt('pace_hours', _paceHours);
          await prefs.setInt('pace_minutes', _paceMinutes);
          await prefs.setInt('pace_seconds', _paceSeconds);
        }
      }

      await prefs.setDouble('weekly_km', effectiveBaselineKm);
      await prefs.setInt('vdot_score', _vdot);
      await prefs.setBool('vdot_is_provisional', _vdotProvisional);

      // ── Engine memory — clear post-plan state, seed new plan ───────────
      final memService = EngineMemoryService();
      final mem = await memService.load();
      await memService.save(mem.copyWith(
        vdotScore:            _vdot,
        vdotIsProvisional:    _vdotProvisional,
        longRunDayIndex:      _longRunDayIndex,
        baselineWeeklyKm:     effectiveBaselineKm,
        previousWeekTargetKm: effectiveBaselineKm,
        // Clear post-plan flags so normal flow resumes.
        clearPlanCompletedAt: true,
        isInMaintenance:      false,
        currentPhase:         TrainingPhase.base,
      ));

      // ── Race plan ──────────────────────────────────────────────────────
      final effectiveRaceDate = _raceDate ??
          _startDate.add(Duration(days: (_planWeeks ?? 12) * 7));
      try {
        final plan = RacePlanBuilder.build(
          currentWeeklyKm: effectiveBaselineKm,
          goalRace:        _goal ?? '5k',
          raceDate:        effectiveRaceDate,
          experienceLevel: exp,
        );
        await EngineMemoryService().saveRacePlan(plan);
      } catch (e) {
        debugPrint('[Onboarding] Race plan error: $e');
      }

      // ── Supabase profile ───────────────────────────────────────────────
      final displayName =
          '${_firstName.trim()} ${_lastName.trim()}'.trim();
      await ProfileService.instance.saveProfile(UserProfile(
        gender:           _gender,
        dob:              _dob,
        goal:             _goal,
        runsPerWeek:      _runsPerWeek,
        trainingDays:     _selectedDays,
        paceDistance:     _knowsTime ? _paceDistance : null,
        paceMinutes:      _knowsTime ? _paceMinutes : null,
        paceSeconds:      _knowsTime ? _paceSeconds : null,
        raceDate:         _raceDate,
        useMetric:        true,
        displayName:      displayName.isNotEmpty ? displayName : null,
        baselineWeeklyKm: effectiveBaselineKm,
      ));
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
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18, color: EC.textSecondary),
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
                            valueColor:
                                const AlwaysStoppedAnimation(EC.teal),
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
                    child: Text(
                      _currentPage == OPage.intro ? "Let's go" : 'Continue',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
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

    // Build a widget for every page in the active sequence.
    return _sequence.map((page) => _buildPage(page, previewVdot)).toList();
  }

  Widget _buildPage(OPage page, (int, bool) previewVdot) {
    return switch (page) {
      OPage.intro => OPageIntro(loopCtrl: _loopCtrl),

      OPage.goal => OPageGoal(
          selected: _goal,
          onSelect: (v) => setState(() => _goal = v),
        ),

      OPage.experience => OPageExperience(
          selected: _experience,
          onSelect: (v) => setState(() => _experience = v),
        ),

      OPage.bestTime => OPageBestTime(
          knowsTime:      _knowsTime,
          distance:       _paceDistance,
          hours:          _paceHours,
          minutes:        _paceMinutes,
          seconds:        _paceSeconds,
          onToggleKnows:  (v) => setState(() => _knowsTime = v),
          onDistChanged:  (v) => setState(() => _paceDistance = v),
          onHoursChanged: (v) => setState(() => _paceHours = v),
          onMinsChanged:  (v) => setState(() => _paceMinutes = v),
          onSecsChanged:  (v) => setState(() => _paceSeconds = v),
        ),

      OPage.daysCount => OPageDaysCount(
          runsPerWeek: _runsPerWeek,
          onChanged: (n) => setState(() {
            _runsPerWeek     = n;
            _selectedDays    = TrainingDaysService.defaultsFor(n);
            _longRunDayIndex = null;
          }),
        ),

      OPage.dayPicker => OPageDayPicker(
          runsPerWeek:  _runsPerWeek,
          selectedDays: _selectedDays,
          onChanged: (days) => setState(() {
            _selectedDays    = days;
            _longRunDayIndex = null;
          }),
        ),

      OPage.longRunDay => OPageLongRunDay(
          availableDays:    _selectedDays,
          selectedDayIndex: _longRunDayIndex,
          onSelect: (i) => setState(() => _longRunDayIndex = i),
        ),

      OPage.weeklyMileage => OPageWeeklyMileage(
          weeklyKm:  _weeklyKm,
          goalRace:  _goal,
          onChanged: (v) => setState(() => _weeklyKm = v),
        ),

      OPage.intensity => OPageIntensity(
          selected: _intensity,
          onSelect: (v) => setState(() => _intensity = v),
        ),

      OPage.planTimeline => OPagePlanTimeline(
          startDate:      _startDate,
          planWeeks:      _planWeeks,
          raceDate:       _raceDate,
          onStartChanged: (d) => setState(() => _startDate = d),
          onWeeksChanged: (w) => setState(() {
            _planWeeks = w;
            _raceDate  = null;
          }),
          onRaceDate: (d) => setState(() {
            _raceDate  = d;
            _planWeeks = null;
          }),
        ),

      OPage.dob => OPageDob(
          dob:       _dob,
          onChanged: (d) => setState(() => _dob = d),
        ),

      OPage.gender => OPageGender(
          selected: _gender,
          onSelect: (v) => setState(() => _gender = v),
        ),

      OPage.name => OPageName(
          firstName:      _firstName,
          lastName:       _lastName,
          onFirstChanged: (v) => setState(() => _firstName = v),
          onLastChanged:  (v) => setState(() => _lastName = v),
        ),

      OPage.generatePlan => OPageGeneratePlan(
          firstName:    _firstName.trim().isNotEmpty ? _firstName.trim() : 'you',
          goal:         _goal ?? '5k',
          startDate:    _startDate,
          planWeeks:    _planWeeks,
          raceDate:     _raceDate,
          runsPerWeek:  _runsPerWeek,
          selectedDays: _selectedDays,
          intensity:    _intensity,
          vdotScore:    previewVdot.$1,
          onGenerate:   _next,
        ),

      OPage.buildPlan => OPageBuildPlan(
          firstName:  _firstName.trim().isNotEmpty ? _firstName.trim() : 'you',
          goal:       _goal ?? '5k',
          onComplete: () async {
            await _saveAll();
            if (mounted) _next();
          },
        ),

      OPage.welcome => OPageWelcome(
          firstName:       _firstName.trim().isNotEmpty ? _firstName.trim() : 'Runner',
          goal:            _goal ?? '5k',
          vdot:            previewVdot.$1,
          planWeeks:       _effectivePlanWeeks,
          experienceLevel: _experience ?? 'intermediate',
          currentTimeSec:  _currentTimeSec,
          paceDistanceKm:  _paceDistanceKm,
          onContinue:      widget.onComplete,
        ),
    };
  }
}