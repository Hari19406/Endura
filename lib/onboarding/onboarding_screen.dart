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
  weeklyMileage,   // ← NEW — after long run day
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
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _ctrl = PageController();
  int _current = 0;

  // ── Collected data ───────────────────────────────────────────────────────
  String?   _goal;
  String?   _experience;

  // Best time
  String    _paceDistance = '5k';
  int       _paceHours    = 0;
  int       _paceMinutes  = 25;
  int       _paceSeconds  = 0;
  bool      _knowsTime    = true;

  // Training days
  int        _runsPerWeek      = 4;
  List<int>  _selectedDays     = TrainingDaysService.defaultsFor(4);
  int?       _longRunDayIndex;

  // Weekly mileage — NEW
  double     _weeklyKm         = 0;

  // Intensity / goal intent
  String?   _intensity;

  // Plan timeline
  DateTime  _startDate  = DateTime.now();
  int?      _planWeeks;
  DateTime? _raceDate;

  // Personal
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
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  List<OPage> get _sequence => OPage.values;
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
      case OPage.weeklyMileage:  return _weeklyKm >= 5;   // ← NEW
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
    return (40, true);
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

    try {
      final prefs = await SharedPreferences.getInstance();
      final exp   = _experience ?? 'intermediate';

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

      // ── Weekly mileage — NEW ───────────────────────────────────────────
      await prefs.setDouble('weekly_km', _weeklyKm);

      await prefs.setInt('vdot_score', _vdot);
      await prefs.setBool('vdot_is_provisional', _vdotProvisional);

      // ── Engine memory ──────────────────────────────────────────────────
      final memService = EngineMemoryService();
      final mem        = await memService.load();
      await memService.save(mem.copyWith(
        vdotScore:         _vdot,
        vdotIsProvisional: _vdotProvisional,
        longRunDayIndex:   _longRunDayIndex,
      ));

      // ── Race plan — uses real weekly km now ────────────────────────────
      final effectiveRaceDate = _raceDate ??
          _startDate.add(Duration(days: (_planWeeks ?? 12) * 7));
      try {
        final plan = RacePlanBuilder.build(
          currentWeeklyKm: _weeklyKm > 0 ? _weeklyKm : _runsPerWeek * 8.0,
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
        gender:       _gender,
        dob:          _dob,
        goal:         _goal,
        runsPerWeek:  _runsPerWeek,
        trainingDays: _selectedDays,
        paceDistance: _knowsTime ? _paceDistance : null,
        paceMinutes:  _knowsTime ? _paceMinutes : null,
        paceSeconds:  _knowsTime ? _paceSeconds : null,
        raceDate:     _raceDate,
        useMetric:    true,
        displayName:  displayName,
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

    return [
      // 1. Intro
      OPageIntro(loopCtrl: _loopCtrl),

      // 2. Goal
      OPageGoal(
        selected: _goal,
        onSelect: (v) => setState(() => _goal = v),
      ),

      // 3. Experience
      OPageExperience(
        selected: _experience,
        onSelect: (v) => setState(() => _experience = v),
      ),

      // 4. Best Time
      OPageBestTime(
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

      // 5. Days count
      OPageDaysCount(
        runsPerWeek: _runsPerWeek,
        onChanged: (n) => setState(() {
          _runsPerWeek     = n;
          _selectedDays    = TrainingDaysService.defaultsFor(n);
          _longRunDayIndex = null;
        }),
      ),

      // 6. Day picker
      OPageDayPicker(
        runsPerWeek:  _runsPerWeek,
        selectedDays: _selectedDays,
        onChanged: (days) => setState(() {
          _selectedDays    = days;
          _longRunDayIndex = null;
        }),
      ),

      // 7. Long run day
      OPageLongRunDay(
        availableDays:    _selectedDays,
        selectedDayIndex: _longRunDayIndex,
        onSelect: (i) => setState(() => _longRunDayIndex = i),
      ),

      // 8. Weekly mileage — NEW
      OPageWeeklyMileage(
        weeklyKm:  _weeklyKm,
        onChanged: (v) => setState(() => _weeklyKm = v),
      ),

      // 9. Intensity
      OPageIntensity(
        selected: _intensity,
        onSelect: (v) => setState(() => _intensity = v),
      ),

      // 10. Plan timeline
      OPagePlanTimeline(
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

      // 11. DOB
      OPageDob(
        dob:       _dob,
        onChanged: (d) => setState(() => _dob = d),
      ),

      // 12. Gender
      OPageGender(
        selected: _gender,
        onSelect: (v) => setState(() => _gender = v),
      ),

      // 13. Name
      OPageName(
        firstName:      _firstName,
        lastName:       _lastName,
        onFirstChanged: (v) => setState(() => _firstName = v),
        onLastChanged:  (v) => setState(() => _lastName = v),
      ),

      // 14. Generate plan
      OPageGeneratePlan(
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

      // 15. Build plan (saving fires here)
      OPageBuildPlan(
        firstName:  _firstName.trim().isNotEmpty ? _firstName.trim() : 'you',
        goal:       _goal ?? '5k',
        onComplete: () async {
          await _saveAll();
          if (mounted) _next();
        },
      ),

      // 16. Welcome — full projection card
      OPageWelcome(
        firstName:       _firstName.trim().isNotEmpty ? _firstName.trim() : 'Runner',
        goal:            _goal ?? '5k',
        vdot:            previewVdot.$1,
        planWeeks:       _effectivePlanWeeks,
        experienceLevel: _experience ?? 'intermediate',
        currentTimeSec:  _currentTimeSec,
        paceDistanceKm:  _paceDistanceKm,
        onContinue:      widget.onComplete,
      ),
    ];
  }
}