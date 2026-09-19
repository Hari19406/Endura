import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/training_days_service.dart';
import '../../engines/planner/race_plan_builder.dart';
import '../../engines/config/archetype_envelope.dart';
import '../../engines/memory/engine_memory_service.dart';
import '../../engines/plan/plan_materialization_coordinator.dart';
import '../../engines/plan/plan_store.dart' show PlanSyncOutcome;
import '../../models/race_plan.dart';
import '../../models/plan_config_state.dart';
import '../../engines/core/vdot_calculator.dart';
import '../../services/profile_service.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ambient_scaffold.dart';
import 'onboarding_pages.dart';
import 'plan_reveal_data.dart';
import 'plan_reveal_page.dart';
import 'plan_runway.dart';
import 'race_time_defaults.dart';
import 'short_notice_sheet.dart';
import '../../models/training_phase.dart';

class EC {
  static const bg = Color(0xFF0D0D0D);
  static const surface = Color(0xFF1A1A1A);
  static const surface2 = Color(0xFF242424);
  static const border = Color(0xFF2E2E2E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9A9A9A);
  static const muted = Color(0xFF555555);
  // Primary accent — named "teal" historically; now Night Ultra Hyper Violet
  // (matches AppColors.workoutTempo / dark heroGradientEnd family).
  static const teal = Color(0xFF8C52FF);
  static const tealDim = Color(0xFF5A34A6);
  static const red = Color(0xFFE84040);
  static const amber = Color(0xFFF0A800);
  static const violet = Color(0xFF7C6EF0);
  static const orange = Color(0xFFFF7A3D);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  /// Dimmed icon-background swatches paired with the accent foregrounds
  /// above (e.g. [tealBg] behind a [teal] icon). Named here instead of
  /// repeating the same literals across onboarding_pages.dart.
  static const tealBg = Color(0x268C52FF); // ~15% violet wash
  static const tealBgAlt = Color(0x408C52FF); // ~25% violet wash
  static const blueBg = Color(0xFF10202E);
  static const violetBg = Color(0xFF1E1040);
  static const redBg = Color(0xFF3D0000);
  static const orangeBg = Color(0xFF3D1A00);
  static const amberBg = Color(0xFF1A1400);
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
  raceGoal, // what's the goal for this race (this flow's own vocab)
  targetTime, // shown only for pr / target_time goals
  weeklyVolume, // typical km/week → baseline weekly volume (every funnel)
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

  // Weekly-volume intake (clean km/week tiers → baseline weekly km directly)
  String? _weeklyVolumeTier;
  double _weeklyBaselineKm = 0;

  // Race goal — this flow's own vocab
  String? _raceGoal;
  int? _timeToBeatSec; // for 'pr'
  int? _targetFinishSec; // for 'target_time'

  /// Set when the athlete picks a "Train for your first …" goal. Forces the
  /// completion-focused path: experience → beginner, race goal → finish, no
  /// target-time step, baseline anchored to the distance's safe minimum, and
  /// the race picker / experience / weekly-volume / race-goal pages skipped.
  bool _isFirstTimeRunner = false;

  // Training days
  int _runsPerWeek = 4;
  List<int> _selectedDays = TrainingDaysService.defaultsFor(4);
  int? _longRunDayIndex;

  // Current race time (vDOT inputs) — OPageBestTime uses 'half' not 'half_marathon'
  String _paceDistance = '5k';
  int _paceHours = 0;
  int _paceMinutes = 30;
  int _paceSeconds = 0;

  /// True once the athlete changes the time on the current-time page. Until
  /// then the distance's placeholder time is not evidence of fitness.
  bool _paceTouched = false;

  /// While the time is untouched, keep the placeholder in step with the
  /// distance so a 10K/half/marathon never shows a 5K-sized time.
  void _syncPaceDefaults() {
    if (_paceTouched) return;
    final t = defaultRaceTimeFor(_paceDistance);
    _paceHours = t.hours;
    _paceMinutes = t.minutes;
    _paceSeconds = t.seconds;
  }

  // Plan start
  DateTime _startDate = DateTime.now();
  int? _planWeeks;

  /// Ease weeks 1–4 in from ~75% volume. The plan-reveal fine-tune switch
  /// feeds this via [_tunedConfig]; this field is the pre-tune default.
  final bool _gradualStart = false;

  /// Set by the plan-reveal fine-tune sliders (weekly range, long-run range,
  /// runs/week, gradual start). Null until the athlete touches a control;
  /// `_saveAll` then builds the plan from these instead of the raw answers.
  PlanConfigState? _tunedConfig;

  /// The race-plan skeleton built in [_saveAll]. Held so the build screen's
  /// [_persistMaterializedPlan] can materialise + persist the full plan and
  /// await the result, rather than firing it off unawaited.
  RacePlan? _builtSkeleton;

  // Computed
  int _vdot = 40;
  bool _vdotProvisional = true;

  // ── Plan reveal ──────────────────────────────────────────────────────────
  // The projection is expensive enough that it must never be computed in
  // build(): WeekResolver logs a multi-line block per resolve() under assert,
  // and _buildPages() rebuilds every page every frame.
  PlanProjection? _projection;
  String? _projectionKey;
  bool _revealTracked = false;

  // Edit-and-return: set while the athlete is editing one answer from the
  // reveal and must bounce back to it. A flag, not a stack — the only return
  // target is the reveal, and there is no nested-edit case.
  bool _editReturn = false;
  PlanEditTarget? _editingTarget;
  String? _fingerprintAtEditStart;

  /// Set when runs-per-week actually changed during an edit, which is what
  /// wipes the selected days and long-run day. Without it, opening the row and
  /// changing nothing would still drag the athlete through two more pages.
  bool _daysResetDuringEdit = false;

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
    _longRunDayIndex = _defaultLongRunDay(_selectedDays);

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
      // A stored time only counts as evidence if it produced a real VDOT.
      _paceTouched = paceMin != null && !memory.vdotIsProvisional;

      final storedDays = await TrainingDaysService.load();
      if (storedDays != null && storedDays.isNotEmpty) {
        _selectedDays = storedDays;
        _runsPerWeek = storedDays.length;
      }
      _longRunDayIndex =
          prefs.getInt('long_run_day_index') ?? memory.longRunDayIndex;

      final savedTier = prefs.getString('weekly_volume_tier');
      final savedBaseline = prefs.getDouble('weekly_baseline_km');
      if (savedTier != null && savedTier.isNotEmpty) {
        _weeklyVolumeTier = savedTier;
        _weeklyBaselineKm = savedBaseline ?? _weeklyBaselineKm;
      }

      _isFirstTimeRunner = prefs.getBool('is_first_time_runner') ?? false;

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
    OPage.raceGoal,
    OPage.targetTime,
    OPage.weeklyVolume,
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

  /// Pages the wizard walks past without stopping. `targetTime` is skipped
  /// unless the race goal needs it; a first-time runner has already answered
  /// (implicitly) the race-picker, experience, weekly-volume and race-goal
  /// questions, so those are skipped too.
  bool _isSkipped(OPage p) {
    if (p == OPage.targetTime && !_needsTargetTime) return true;
    if (_isFirstTimeRunner &&
        (p == OPage.racePicker ||
            p == OPage.experience ||
            p == OPage.raceGoal)) {
      return true;
    }
    return false;
  }

  bool get _showTopBar =>
      _currentPage != OPage.racePicker &&
      _currentPage != OPage.buildPlan &&
      _currentPage != OPage.welcome;

  bool get _showBottom =>
      _currentPage != OPage.goal &&
      _currentPage != OPage.racePicker &&
      _currentPage != OPage.review &&
      _currentPage != OPage.buildPlan &&
      _currentPage != OPage.welcome;

  // Hold the bar full while editing — otherwise tapping "Edit" on the reveal
  // visibly rewinds progress, which reads as losing your place.
  double get _progress =>
      _editReturn ? 1.0 : 0.05 + (_current / max(1, _total - 1)) * 0.95;

  int _indexOf(OPage page) => _sequence.indexOf(page);

  // Update _current (and everything gated on it — chrome, haptics, analytics)
  // only AFTER the page-turn animation has fully settled, never mid-flight.
  // Belt-and-suspenders alongside the fixed-shape Column below (see the
  // comment on the Column's `children` in build()): that fix is what actually
  // keeps the PageView's Element — and therefore _ctrl's ScrollPosition —
  // alive across every navigation; this just avoids also flipping
  // _showTopBar/_showBottom while animateToPage's scroll activity is still
  // active, in case that timing ever matters on some future layout.
  Future<void> _animateTo(int index) async {
    if (index < 0 || index >= _total || _navigating) return;
    _navigating = true;
    try {
      await _slideTo(index);
    } finally {
      _navigating = false;
    }
    if (!mounted) return;
    _finishNavigation(index);
  }

  bool _navigating = false;

  /// Always a single-page slide in the direction of travel. Skipped pages are
  /// jumped over first (invisibly), so a multi-page hop never sweeps through
  /// the pages in between.
  Future<void> _slideTo(int index) async {
    if (_ctrl.hasClients && (index - _current).abs() > 1) {
      _ctrl.jumpToPage(index > _current ? index - 1 : index + 1);
    }
    await _ctrl.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  void _finishNavigation(int index) {
    setState(() => _current = index);
    HapticFeedback.selectionClick();
    Analytics.onboardingStepViewed(_sequence[index].name, index);
    // Kept here too (on top of _next()'s pre-fetch) — fingerprint-memoized so
    // a second call is a no-op. The edit round-trip's return to OPage.review
    // goes through _jumpTo(), which pre-fetches there itself; this just keeps
    // the normal forward path covered.
    if (_sequence[index] == OPage.review) _ensureProjection();
  }

  /// Instant page swap — no scroll through the pages in between.
  ///
  /// Used for the edit round-trip from the plan reveal: the target intake
  /// screen can be a dozen pages back, and `animateToPage` would whip
  /// backward across every one of them (dizzying). `jumpToPage` cuts
  /// straight there. The PageView already uses NeverScrollableScrollPhysics,
  /// so there is no in-between state to preserve. Runs the same post-jump
  /// bookkeeping as [_animateTo].
  void _jumpTo(int index) {
    if (index < 0 || index >= _total) return;
    // Only ever invoked from a user tap on the mounted reveal, so the PageView
    // is on screen and `_ctrl` has a position — but guard anyway: jumpToPage
    // throws synchronously if the controller has no clients, and swallowing a
    // stray call is better than taking down the frame.
    if (_ctrl.hasClients) {
      _ctrl.jumpToPage(index);
    }
    if (!mounted) return;
    setState(() => _current = index);
    HapticFeedback.selectionClick();
    Analytics.onboardingStepViewed(_sequence[index].name, index);
    if (_sequence[index] == OPage.review) _ensureProjection();
  }

  void _goToInstant(OPage page) => _jumpTo(_indexOf(page));

  /// Jump to the question that owns a receipt row, remembering to come back.
  void _startEdit(PlanEditTarget target) {
    final page = _pageForEditTarget(target);
    if (_indexOf(page) < 0) return;
    setState(() {
      _editReturn = true;
      _editingTarget = target;
      _fingerprintAtEditStart = _projectionKey;
    });
    _goToInstant(page);
  }

  OPage _pageForEditTarget(PlanEditTarget target) => switch (target) {
    // Distance is edited through the race picker, not the goal page.
    PlanEditTarget.goal => OPage.raceGoal,
    PlanEditTarget.runsPerWeek => OPage.runsPerWeek,
    PlanEditTarget.trainingDays => OPage.dayPicker,
    PlanEditTarget.longRunDay => OPage.longRunDay,
    PlanEditTarget.currentTime => OPage.currentTime,
    PlanEditTarget.planStart => OPage.planStart,
  };

  OPage _pageForFollowUp(PlanEditFollowUp followUp) => switch (followUp) {
    PlanEditFollowUp.targetTime => OPage.targetTime,
    PlanEditFollowUp.trainingDays => OPage.dayPicker,
    PlanEditFollowUp.longRunDay => OPage.longRunDay,
  };

  /// Returns to the reveal, unless the edit invalidated a downstream answer
  /// that has to be re-confirmed first.
  void _resumeFromEdit() {
    // Evaluate against the page just finished, not where the edit began — a
    // chained edit passes through several pages before returning.
    final edited =
        _editTargetForPage(_currentPage) ??
        _editingTarget ??
        PlanEditTarget.runsPerWeek;

    final followUp = planEditFollowUp(
      edited: edited,
      raceGoal: _raceGoal,
      timeToBeatSec: _timeToBeatSec,
      targetFinishSec: _targetFinishSec,
      needsTargetTime: _needsTargetTime,
      longRunDayIndex: _longRunDayIndex,
      daysNeedConfirming: _daysResetDuringEdit,
    );

    if (followUp != null) {
      _goToInstant(_pageForFollowUp(followUp));
      return;
    }

    _ensureProjection();
    final row = _editingTarget?.name ?? 'unknown';
    Analytics.planRevealEditReturned(
      row: row,
      changed: _projectionKey != _fingerprintAtEditStart,
    );
    _clearEditState();
    _goToInstant(OPage.review);
  }

  void _clearEditState() {
    setState(() {
      _editReturn = false;
      _editingTarget = null;
      _fingerprintAtEditStart = null;
      _daysResetDuringEdit = false;
    });
  }

  /// Which edit a given page represents, so the chain can be evaluated against
  /// the page the athlete actually just finished rather than where they began.
  PlanEditTarget? _editTargetForPage(OPage page) => switch (page) {
    OPage.raceGoal => PlanEditTarget.goal,
    OPage.runsPerWeek => PlanEditTarget.runsPerWeek,
    OPage.dayPicker => PlanEditTarget.trainingDays,
    OPage.longRunDay => PlanEditTarget.longRunDay,
    OPage.currentTime => PlanEditTarget.currentTime,
    OPage.planStart => PlanEditTarget.planStart,
    _ => null,
  };

  /// A half marathon or marathon needs an existing base. If the athlete had
  /// picked a lower weekly-volume tier (e.g. 0 km for a 10K) and then changed
  /// distance, lift the selection to the distance's lowest allowed tier.
  void _clampBaselineToGoal() {
    if (_weeklyVolumeTier == null) return;
    final min = OPageWeeklyVolume.minBaselineFor(_goal);
    if (_weeklyBaselineKm >= min) return;
    final (key, km) = OPageWeeklyVolume.lowestTierFor(_goal);
    _weeklyVolumeTier = key;
    _weeklyBaselineKm = km;
  }

  /// The athlete tapped a "Train for your first …" option on the goal page.
  /// Lock in the completion-focused path and advance — `_isSkipped` then walks
  /// the wizard past race-picker / experience / weekly-volume / race-goal.
  void _selectFirstTimer(String distanceKey) {
    setState(() {
      _goal = distanceKey;
      _isFirstTimeRunner = true;
      // First timer ⇒ new to the distance. Force the beginner archetype (the
      // engine already routes beginners to threshold-only quality — no VO2 max
      // or hard intervals) and a "just finish" race goal (no target-time step).
      _experience = 'just_starting';
      // A first-timer can't have run 40+ km weeks — drop a stale higher tier.
      if (_weeklyBaselineKm > OPageWeeklyVolume.firstTimerMaxBaselineKm) {
        _weeklyVolumeTier = null;
        _weeklyBaselineKm = 0;
      }
      _raceGoal = 'finish';
      _timeToBeatSec = null;
      _targetFinishSec = null;
      // No specific race — the plan builder falls back to a synthetic race
      // date from the chosen start + plan length.
      _raceId = null;
      _raceName = null;
      _raceCity = null;
      _raceDate = null;
      _paceDistance = _paceDistFor(distanceKey);
      _syncPaceDefaults();
      _clampBaselineToGoal();
    });
    Analytics.onboardingStepViewed('goal_first_timer_$distanceKey', _current);
    _next();
  }

  void _next() {
    if (_editReturn) {
      _resumeFromEdit();
      return;
    }
    int next = _current + 1;
    while (next < _total && _isSkipped(_sequence[next])) {
      next++;
    }
    // Have the projection ready before the slide finishes, so the reveal never
    // flashes its skeleton.
    if (next < _total && _sequence[next] == OPage.review) _ensureProjection();
    _animateTo(next);
  }

  /// The race picker's ✕. In the full flow it steps back to the goal screen;
  /// in the shortened (re-plan) flow the picker is the first page, so there is
  /// nothing to step back to and it leaves the wizard entirely.
  void _closeRacePicker() {
    if (!_editReturn && _current == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    _prev();
  }

  void _prev() {
    // Backing out of an edit abandons it and returns to the reveal rather than
    // walking backwards through the questionnaire.
    if (_editReturn) {
      _clearEditState();
      _goToInstant(OPage.review);
      return;
    }
    int prev = _current - 1;
    while (prev >= 0 && _isSkipped(_sequence[prev])) {
      prev--;
    }
    if (prev < 0) {
      // First page: leave the flow if it was pushed as a route (e.g. from
      // Home). During first-run onboarding it is the root, so there's nowhere
      // to go back to.
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    _animateTo(prev);
  }

  // ── Plan projection ──────────────────────────────────────────────────────

  /// Weekly baseline the plan is seeded from — the chosen weekly-volume tier's
  /// km, straight through (VolumeModel floors a 0 up to min-viable). Shared by
  /// the reveal and by _saveAll so the curve the athlete approves is the plan
  /// they get. Falls back to a rough estimate only if the tier is unanswered.
  ///
  /// First-time runners skip the weekly-volume question, so their baseline is
  /// anchored to the safe minimum of the distance's [RaceArchetypeEnvelope] —
  /// the gentlest honest starting point for the ramp.
  double get _baselineWeeklyKm {
    if (_isFirstTimeRunner && _weeklyVolumeTier == null) {
      final dist = PlanMaterializationCoordinator.raceDistanceFrom(
        _goal ?? '5k',
      );
      return RaceArchetypeEnvelope.of(dist).baselineKm.min;
    }
    return _weeklyVolumeTier != null ? _weeklyBaselineKm : _runsPerWeek * 8.0;
  }

  OnboardingAnswers _buildAnswers() {
    final goalRace = _goal ?? '5k';
    final (vdot, provisional) = _computeVdot();
    return OnboardingAnswers(
      goal: goalRace,
      raceName: _raceName,
      raceCity: _raceCity,
      raceDate:
          _raceDate ?? _startDate.add(Duration(days: _effectivePlanWeeks * 7)),
      experienceRaw: _experience ?? 'regular',
      experienceBridged: _bridgeExperience(_experience),
      raceGoalRaw: _raceGoal,
      timeToBeatSec: _timeToBeatSec,
      targetFinishSec: _targetFinishSec,
      baselineWeeklyKm: _baselineWeeklyKm,
      runsPerWeek: _runsPerWeek,
      selectedDays: _selectedDays,
      longRunDayIndex: _longRunDayIndex,
      paceDistance: _paceDistance,
      paceDistanceKm: _paceDistanceKm,
      currentTimeSec: _effectiveCurrentTimeSec,
      startDate: _startDate,
      planWeeks: _planDurationWeeks,
      vdot: vdot,
      vdotProvisional: provisional,
    );
  }

  /// Recomputes the projection only when an answer actually changed.
  void _ensureProjection() {
    final answers = _buildAnswers();
    if (_projectionKey == answers.fingerprint && _projection != null) return;

    PlanProjection? projection;
    try {
      projection = PlanProjection.build(answers);
    } catch (e) {
      // Degrade to a receipt-only reveal rather than crashing the last screen
      // of onboarding. _saveAll guards the same builder call the same way.
      debugPrint('[PlanReveal] projection failed: $e');
      projection = null;
    }

    setState(() {
      _projection = projection;
      _projectionKey = answers.fingerprint;
    });

    if (projection != null && !_revealTracked) {
      _revealTracked = true;
      Analytics.planRevealViewed(
        goal: answers.goal,
        planWeeks: projection.weeks.length,
        peakWeeklyKm: projection.peakWeeklyKm,
        runsPerWeek: answers.runsPerWeek,
      );
    }
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
      case OPage.weeklyVolume:
        return _weeklyVolumeTier != null;
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

  /// Sensible long-run-day default: keep the current pick if it's still
  /// available, otherwise prefer the weekend, otherwise the latest day in the
  /// week. Pre-answering this (rather than leaving it null) means the athlete
  /// arrives at the page with a real choice already made, matching the
  /// pre-checked-everything pattern the rest of onboarding follows.
  int? _defaultLongRunDay(List<int> days, {int? current}) {
    if (days.isEmpty) return null;
    if (current != null && days.contains(current)) return current;
    if (days.contains(5)) return 5; // Saturday
    if (days.contains(6)) return 6; // Sunday
    final sorted = [...days]..sort();
    return sorted.last;
  }

  // ── Runway ───────────────────────────────────────────────────────────────

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  int get _weeksToRace {
    final race = _raceDate;
    if (race == null) return _effectivePlanWeeks;
    return max(0, race.difference(_today).inDays ~/ 7);
  }

  PlanRunway get _runway =>
      PlanRunway.resolve(goal: _goal ?? '5k', weeksAvailable: _weeksToRace);

  /// Race picked. If it is too close to build real fitness for, say so before
  /// the athlete invests ten more screens in it — and offer a better path
  /// rather than a wall.
  Future<void> _advanceFromRacePicker() async {
    final runway = _runway;
    if (_raceDate == null || !runway.isShortNotice) {
      _next();
      return;
    }

    Analytics.shortNoticeShown(
      goal: _goal ?? '5k',
      weeksAvailable: runway.weeksAvailable,
    );

    final choice = await showShortNoticeSheet(
      context,
      raceName: _raceName ?? 'that race',
      goal: _goal ?? '5k',
      runway: runway,
    );
    if (!mounted) return;

    // Dismissing the sheet is the same as backing out — never silently
    // continue with a race we just said was too close.
    if (choice != ShortNoticeChoice.continueAnyway) {
      Analytics.shortNoticeChoice('pick_another');
      setState(() {
        _raceId = null;
        _raceName = null;
        _raceCity = null;
        _raceDate = null;
      });
      return;
    }

    Analytics.shortNoticeChoice('continue_anyway');
    _next();
  }

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
    final daysToMon = (8 - today.weekday) % 7 == 0
        ? 7
        : (8 - today.weekday) % 7;
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

  /// Current-time input that counts as evidence. Anyone who never touched the
  /// page is still on the placeholder, so it counts as 0 — in every funnel.
  int get _effectiveCurrentTimeSec => _paceTouched ? _currentTimeSec : 0;

  (int, bool) _computeVdot() {
    if (widget.shortenedMode && !_vdotProvisional && !_paceTouched) {
      return (_vdot, false);
    }
    final totalSec = _effectiveCurrentTimeSec;
    if (totalSec == 0 && !_paceTouched) {
      return (fallbackVdotFor(_paceDistance), true);
    }
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

  /// The macrocycle length handed to the generator + reveal + saved profile.
  /// Race goals derive it from the race date; fitness goals (no `_raceDate`)
  /// use the chosen plan-duration weeks. Always clamped to the 3–20 window.
  int get _planDurationWeeks => PlanConfigState.deriveDurationWeeks(
    raceDate: _raceDate,
    startDate: _startDate,
    sliderWeeks: _effectivePlanWeeks,
  );

  // ── Save & complete ──────────────────────────────────────────────────────

  Future<void> _saveAll() async {
    final (vdot, provisional) = _computeVdot();
    _vdot = vdot;
    _vdotProvisional = provisional;

    // Apply the plan-reveal fine-tune sliders, if the athlete touched them.
    // runsPerWeek can move off the day set they picked — regenerate an evenly
    // spread set so the schedule still lines up.
    final tuned = _tunedConfig;
    if (tuned != null && tuned.runsPerWeek != _runsPerWeek) {
      _runsPerWeek = tuned.runsPerWeek;
      _selectedDays = spreadTrainingDays(tuned.runsPerWeek, _longRunDayIndex);
    }

    // Same getter the reveal uses, so the curve the athlete approved is the
    // plan that actually gets saved. The tuned floor wins when present.
    final double effectiveBaselineKm =
        tuned?.weeklyVolumeRange.start ?? _baselineWeeklyKm;

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
      await prefs.setString('weekly_volume_tier', _weeklyVolumeTier ?? '');
      await prefs.setDouble('weekly_baseline_km', _weeklyBaselineKm);
      await prefs.setBool('is_first_time_runner', _isFirstTimeRunner);

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
          // Goal-branch length: race goals derive weeks from the race date,
          // fitness goals use the chosen plan-duration slider — both clamped
          // to 3–20 by PlanConfigState.deriveDurationWeeks.
          durationWeeks: _planDurationWeeks,
          gradualStart: tuned?.gradualStart ?? _gradualStart,
          peakWeeklyKmOverride: tuned?.weeklyVolumeRange.end,
          peakLongRunKmOverride: tuned?.longRunRange.end,
          runsPerWeek: _runsPerWeek,
        );
        await EngineMemoryService().saveRacePlan(plan);
        Analytics.planCreated(goal: goalRace, level: exp);

        // Hand the skeleton to the build screen, which materialises + persists
        // the full plan (local cache + Supabase) and awaits the write so it can
        // show a retry if only the on-device copy landed. See
        // [_persistMaterializedPlan].
        _builtSkeleton = plan;
      } catch (e) {
        _builtSkeleton = null;
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
        planWeeks: _planDurationWeeks,
      );
    } catch (e) {
      debugPrint('[Onboarding] Save error: $e');
    }
  }

  /// Materialise the full plan from the skeleton [_saveAll] built and persist it
  /// (local cache + Supabase), awaiting the cloud write so the build screen can
  /// offer a retry when only the on-device copy landed.
  ///
  /// Returns:
  ///   * [PlanSyncOutcome.syncedRemote]  — local + Supabase both written
  ///   * [PlanSyncOutcome.savedNoRemote] — local written, no signed-in user to
  ///     sync to (or the skeleton was never built); not retry-worthy
  ///   * [PlanSyncOutcome.savedLocalOnly] — local written, cloud push failed or
  ///     timed out; the build screen surfaces a retry
  Future<PlanSyncOutcome> _persistMaterializedPlan() async {
    final skeleton = _builtSkeleton;
    if (skeleton == null) return PlanSyncOutcome.savedNoRemote;

    final goalRace = _goal ?? '5k';
    final exp = _bridgeExperience(_experience);
    try {
      final result = await PlanMaterializationCoordinator.instance
          .buildAndPersist(
            skeleton: skeleton,
            trainingDayIndices: _selectedDays,
            longRunDayIndex: _longRunDayIndex,
            goalRace: goalRace,
            experienceLevel: exp,
            vdot: _vdot,
            goalTimeSeconds: _targetFinishSec ?? _timeToBeatSec,
          )
          .timeout(const Duration(seconds: 20));
      final mem = await EngineMemoryService().load();
      // Local only — the engine memory was already cloud-synced by _saveAll;
      // these three fields ride the next natural save.
      await EngineMemoryService().save(
        mem.copyWith(
          materializedPlanId: result.plan.planId,
          sessionProgress: result.plan.sessionProgress,
          ladderPositions: result.plan.ladderState,
        ),
        syncToCloud: false,
      );
      debugPrint(
        '[Onboarding] Plan materialised: ${result.plan.planId} '
        '(${result.sync.name})',
      );
      return result.sync;
    } on TimeoutException {
      debugPrint('[Onboarding] Materialisation timed out — local copy only');
      return PlanSyncOutcome.savedLocalOnly;
    } catch (e) {
      // An engine failure here won't clear on retry and the runtime still
      // materialises on demand later, so don't trap the user behind a retry.
      debugPrint('[Onboarding] Materialisation error (non-fatal): $e');
      return PlanSyncOutcome.savedNoRemote;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  // Onboarding is a deliberately fixed-dark surface (EC.* tokens, white text),
  // so its subtree is pinned to the dark theme — otherwise AmbientScaffold
  // would paint a light base under white text when the app is in light mode.
  static final ThemeData _darkTheme = AppTheme.dark;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _darkTheme,
      child: AmbientScaffold(
        body: Column(
          // IMPORTANT: the top-bar and bottom-bar slots below are ALWAYS
          // present as Column children — never `if (...) Widget(...)` in this
          // list. Column/Flex reconciles children positionally: when an item
          // is conditionally added or removed, every sibling after it shifts
          // index, so Flutter compares the WRONG old/new widgets at each
          // position and — since PageView sits at a different index whenever
          // the bars toggle — tears down and recreates its Element instead of
          // updating it in place. That destroys the PageView's ScrollPosition
          // along with it, silently resetting it to page 0 on the very
          // transition that's supposed to land on the next question. Keeping
          // a fixed 3-slot shape (top bar, PageView, bottom bar) and toggling
          // only each slot's INTERNAL content preserves the PageView's
          // Element — and therefore _ctrl's scroll position — across every
          // navigation.
          children: [
            _TopBarSlot(
              visible: _showTopBar,
              progress: _progress,
              onBack: () {
                HapticFeedback.lightImpact();
                _prev();
              },
            ),

            Expanded(
              child: PageView(
                controller: _ctrl,
                physics: const NeverScrollableScrollPhysics(),
                children: _buildPages(),
              ),
            ),

            _BottomBarSlot(
              visible: _showBottom,
              enabled: _canContinue,
              label: _editReturn ? 'Back to plan' : 'Continue',
              onPressed: _next,
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
        isFirstTimer: _isFirstTimeRunner,
        onOpenRaceFunnel: () {
          // Re-entering the race funnel abandons a prior first-timer pick.
          if (_isFirstTimeRunner) setState(() => _isFirstTimeRunner = false);
          _next();
        },
        onSelectFirstTimer: _selectFirstTimer,
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
            _clampBaselineToGoal();
            _paceDistance = _paceDistFor(_goal);
            _syncPaceDefaults();
          });
        },
        onClose: _closeRacePicker,
        onAdvance: _advanceFromRacePicker,
      ),

      OPage.experience => OPageExperience(
        selected: _experience,
        goal: _goal ?? '5k',
        onSelect: (v) => setState(() => _experience = v),
      ),

      OPage.weeklyVolume => OPageWeeklyVolume(
        selectedKey: _weeklyVolumeTier,
        goal: _goal,
        minBaselineKm: OPageWeeklyVolume.minBaselineFor(_goal),
        maxBaselineKm: _isFirstTimeRunner
            ? OPageWeeklyVolume.firstTimerMaxBaselineKm
            : null,
        onSelect: (tierKey, baselineKm) => setState(() {
          _weeklyVolumeTier = tierKey;
          _weeklyBaselineKm = baselineKm;
        }),
      ),

      OPage.raceGoal => OPageRaceGoal(
        selected: _raceGoal,
        goal: _goal ?? '5k',
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
        baselineWeeklyKm: _baselineWeeklyKm,
        goal: _goal ?? '5k',
        experienceBridged: _bridgeExperience(_experience),
        onChanged: (n) => setState(() {
          _runsPerWeek = n;
          _selectedDays = TrainingDaysService.defaultsFor(n);
          _longRunDayIndex = _defaultLongRunDay(_selectedDays);
          if (_editReturn) _daysResetDuringEdit = true;
        }),
      ),

      OPage.dayPicker => OPageDayPicker(
        runsPerWeek: _runsPerWeek,
        selectedDays: _selectedDays,
        onChanged: (days) => setState(() {
          _selectedDays = days;
          _longRunDayIndex = _defaultLongRunDay(
            days,
            current: _longRunDayIndex,
          );
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
        onDistChanged: (v) => setState(() {
          _paceDistance = v;
          _syncPaceDefaults();
        }),
        onHoursChanged: (v) => setState(() {
          _paceTouched = true;
          _paceHours = v;
        }),
        onMinsChanged: (v) => setState(() {
          _paceTouched = true;
          _paceMinutes = v;
        }),
        onSecsChanged: (v) => setState(() {
          _paceTouched = true;
          _paceSeconds = v;
        }),
      ),

      OPage.planStart => OPagePlanStart(
        options: _planStartOptions(),
        selectedStart: _planWeeks == null ? null : _startDate,
        runway: _runway,
        goal: _goal ?? '5k',
        raceName: _raceName,
        raceDate: _raceDate,
        onSelect: (opt) => setState(() {
          _startDate = opt.startDate;
          _planWeeks = opt.weeks;
        }),
      ),

      OPage.review => OPagePlanReveal(
        answers: _buildAnswers(),
        projection: _projection,
        onEdit: _startEdit,
        onGenerate: _next,
        initialConfig: _tunedConfig,
        onConfigChanged: (c) => _tunedConfig = c,
      ),

      OPage.buildPlan => OPageBuildPlan(
        firstName: 'you',
        goal: _goal ?? '5k',
        onComplete: () async {
          await _saveAll();
          final outcome = await _persistMaterializedPlan();
          // Only a failed cloud sync is retry-worthy — a local-only save with
          // no signed-in user (savedNoRemote) is expected and proceeds.
          final ok = outcome != PlanSyncOutcome.savedLocalOnly;
          if (ok && mounted) _next();
          return ok;
        },
        onContinueAnyway: () {
          // The plan is already in the local cache; the cloud copy rides the
          // next natural sync. Let the user into the app.
          if (mounted) _next();
        },
      ),

      OPage.welcome => OPageWelcome(
        firstName: 'Runner',
        goal: _goal ?? '5k',
        vdot: previewVdot.$1,
        planWeeks: _planDurationWeeks,
        experienceLevel: _bridgeExperience(_experience),
        currentTimeSec: _effectiveCurrentTimeSec,
        paceDistanceKm: _paceDistanceKm,
        runsPerWeek: _runsPerWeek,
        baselineWeeklyKm: _baselineWeeklyKm,
        raceDate: _raceDate,
        onContinue: widget.onComplete,
      ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHROME SLOTS
//
// Always present as Column children (see build()'s comment on why) — each
// renders SizedBox.shrink() when hidden, so the visual result is identical to
// the old `if (...) Widget(...)` approach (zero height, nothing drawn) while
// keeping the Column's children list a constant length and order.
// ─────────────────────────────────────────────────────────────────────────────

class _TopBarSlot extends StatelessWidget {
  final bool visible;
  final double progress;
  final VoidCallback onBack;

  const _TopBarSlot({
    required this.visible,
    required this.progress,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
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
                  value: progress,
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
    );
  }
}

class _BottomBarSlot extends StatelessWidget {
  final bool visible;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  const _BottomBarSlot({
    required this.visible,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
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
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
