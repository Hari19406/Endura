/// Standalone harness for the onboarding plan reveal.
///
/// main_preview.dart drops you at page 0 of onboarding with no way to jump, so
/// checking the reveal meant clicking through ten questions per iteration. This
/// renders the reveal on its own, with switchable personas, and needs no
/// Supabase or device plugins.
///
///   flutter run -t lib/main_preview_reveal.dart -d chrome
library;

import 'package:flutter/material.dart';

import 'onboarding/onboarding_screen.dart' show EC;
import 'onboarding/onboarding_pages.dart'
    show
        OPageRunsPerWeek,
        OPagePlanStart,
        PlanStartOption,
        OPageExperience,
        OPageRaceGoal,
        OPageLongRunDay;
import 'onboarding/plan_reveal_data.dart';
import 'onboarding/plan_reveal_page.dart';
import 'onboarding/plan_runway.dart';
import 'onboarding/short_notice_sheet.dart';
import 'utils/unit_utils.dart';

void main() => runApp(const RevealPreviewApp());

class _Persona {
  final String name;
  final OnboardingAnswers answers;

  const _Persona(this.name, this.answers);
}

OnboardingAnswers _answers({
  required String goal,
  required int weeksOut,
  required double baseline,
  required int runsPerWeek,
  required List<int> days,
  int? longRunDay,
  String experience = 'intermediate',
  String raceGoal = 'finish',
  String? raceName,
  int currentTimeSec = 6600,
  String paceDistance = 'half',
  double paceDistanceKm = 21.0975,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return OnboardingAnswers(
    goal: goal,
    raceName: raceName,
    raceDate: today.add(Duration(days: weeksOut * 7)),
    experienceRaw: experience,
    experienceBridged: experience,
    raceGoalRaw: raceGoal,
    pastMonthKm: baseline * 4.345,
    baselineWeeklyKm: baseline,
    runsPerWeek: runsPerWeek,
    selectedDays: days,
    longRunDayIndex: longRunDay,
    paceDistance: paceDistance,
    paceDistanceKm: paceDistanceKm,
    currentTimeSec: currentTimeSec,
    startDate: today,
    planWeeks: weeksOut,
    vdot: 44,
    vdotProvisional: false,
  );
}

final _personas = <_Persona>[
  _Persona(
    'Half · 4 days',
    _answers(
      goal: 'half_marathon',
      weeksOut: 16,
      baseline: 30,
      runsPerWeek: 4,
      days: const [0, 2, 4, 5],
      longRunDay: 5,
      raceName: 'Dietz & Watson Philadelphia Half Marathon',
    ),
  ),
  _Persona(
    'Marathon · 7 days',
    _answers(
      goal: 'marathon',
      weeksOut: 20,
      baseline: 65,
      runsPerWeek: 7,
      days: const [0, 1, 2, 3, 4, 5, 6],
      longRunDay: 5,
      experience: 'advanced',
      raceGoal: 'pr',
      raceName: 'The NYC Marathon',
      paceDistance: 'marathon',
      paceDistanceKm: 42.195,
      currentTimeSec: 12960,
    ),
  ),
  _Persona(
    'First 5K · 3 days',
    _answers(
      goal: '5k',
      weeksOut: 15,
      baseline: 12,
      runsPerWeek: 3,
      days: const [0, 2, 5],
      longRunDay: 5,
      experience: 'beginner',
      raceName: 'BMW Dallas 5km',
      paceDistance: '5k',
      paceDistanceKm: 5,
      currentTimeSec: 1800,
    ),
  ),
  _Persona(
    'Short notice · 5 wk',
    _answers(
      goal: 'marathon',
      weeksOut: 5,
      baseline: 45,
      runsPerWeek: 5,
      days: const [0, 1, 3, 4, 5],
      longRunDay: 5,
      raceName: 'Bank of America Chicago Marathon',
      paceDistance: 'marathon',
      paceDistanceKm: 42.195,
    ),
  ),
  _Persona(
    'Long run day unset',
    _answers(
      goal: '10k',
      weeksOut: 10,
      baseline: 25,
      runsPerWeek: 4,
      days: const [0, 2, 4, 6],
      raceName: 'Aquarium of the Pacific 10K',
      paceDistance: '10k',
      paceDistanceKm: 10,
      currentTimeSec: 3000,
    ),
  ),
];

class RevealPreviewApp extends StatefulWidget {
  const RevealPreviewApp({super.key});

  @override
  State<RevealPreviewApp> createState() => _RevealPreviewAppState();
}

enum _Screen { reveal, slider, planStart, experience, raceGoal, longRunDay }

class _RevealPreviewAppState extends State<RevealPreviewApp> {
  int _index = 0;
  bool _skeleton = false;
  _Screen _screen = _Screen.reveal;
  int _runs = 4;
  DateTime? _pickedStart;
  String? _experiencePick;
  String? _raceGoalPick;
  int? _longRunPick;

  bool get _showSlider => _screen == _Screen.slider;

  int _weeksTo(DateTime race) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final w = race.difference(today).inDays ~/ 7;
    return w < 0 ? 0 : w;
  }

  List<PlanStartOption> _startOptions(OnboardingAnswers a) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final toMon = (8 - today.weekday) % 7 == 0 ? 7 : (8 - today.weekday) % 7;
    final nextMon = today.add(Duration(days: toMon));
    final wToday = _weeksTo(a.raceDate);
    return [
      PlanStartOption(startDate: today, weeks: wToday, isToday: true),
      PlanStartOption(
        startDate: nextMon,
        weeks: wToday > 1 ? wToday - 1 : wToday,
        isToday: false,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final persona = _personas[_index];
    PlanProjection? projection;
    Object? error;
    if (!_skeleton) {
      try {
        projection = PlanProjection.build(persona.answers);
      } catch (e) {
        error = e;
      }
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: EC.bg,
        body: SafeArea(
          child: Column(
            children: [
              _Toolbar(
                personas: _personas,
                index: _index,
                skeleton: _skeleton,
                showSlider: _showSlider,
                showStart: _screen == _Screen.planStart,
                showExperience: _screen == _Screen.experience,
                showRaceGoal: _screen == _Screen.raceGoal,
                showLongRunDay: _screen == _Screen.longRunDay,
                onPersona: (i) => setState(() => _index = i),
                onSkeleton: (v) => setState(() => _skeleton = v),
                onShowSlider: (v) => setState(
                  () => _screen = v ? _Screen.slider : _Screen.reveal,
                ),
                onShowStart: (v) => setState(
                  () => _screen = v ? _Screen.planStart : _Screen.reveal,
                ),
                onShowExperience: (v) => setState(
                  () => _screen = v ? _Screen.experience : _Screen.reveal,
                ),
                onShowRaceGoal: (v) => setState(
                  () => _screen = v ? _Screen.raceGoal : _Screen.reveal,
                ),
                onShowLongRunDay: (v) => setState(
                  () => _screen = v ? _Screen.longRunDay : _Screen.reveal,
                ),
                onShortNotice: () => showShortNoticeSheet(
                  context,
                  raceName: _personas[3].answers.raceName ?? 'that race',
                  goal: 'marathon',
                  runway: PlanRunway.resolve(
                    goal: 'marathon',
                    weeksAvailable: 5,
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Projection threw: $error',
                    style: const TextStyle(color: EC.red),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    // Roughly a phone, so overflow shows up here rather than
                    // on device.
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: switch (_screen) {
                      _Screen.slider => OPageRunsPerWeek(
                        runsPerWeek: _runs,
                        baselineWeeklyKm: persona.answers.baselineWeeklyKm,
                        goal: persona.answers.goal,
                        experienceBridged: persona.answers.experienceBridged,
                        onChanged: (n) => setState(() => _runs = n),
                      ),
                      _Screen.planStart => OPagePlanStart(
                        options: _startOptions(persona.answers),
                        selectedStart: _pickedStart,
                        goal: persona.answers.goal,
                        runway: PlanRunway.resolve(
                          goal: persona.answers.goal,
                          weeksAvailable: _weeksTo(persona.answers.raceDate),
                        ),
                        onSelect: (o) =>
                            setState(() => _pickedStart = o.startDate),
                      ),
                      _Screen.experience => OPageExperience(
                        selected: _experiencePick,
                        goal: persona.answers.goal,
                        onSelect: (v) => setState(() => _experiencePick = v),
                      ),
                      _Screen.raceGoal => OPageRaceGoal(
                        selected: _raceGoalPick,
                        goal: persona.answers.goal,
                        onSelect: (v) => setState(() => _raceGoalPick = v),
                      ),
                      _Screen.longRunDay => OPageLongRunDay(
                        availableDays: persona.answers.selectedDays,
                        selectedDayIndex:
                            _longRunPick ?? persona.answers.longRunDayIndex,
                        onSelect: (i) => setState(() => _longRunPick = i),
                      ),
                      _Screen.reveal => OPagePlanReveal(
                        key: ValueKey('$_index-$_skeleton'),
                        answers: persona.answers,
                        projection: projection,
                        onEdit: (t) => _toast(context, 'Edit → ${t.name}'),
                        onGenerate: () => _toast(context, 'Start training'),
                      ),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final List<_Persona> personas;
  final int index;
  final bool skeleton;
  final bool showSlider;
  final bool showStart;
  final bool showExperience;
  final bool showRaceGoal;
  final bool showLongRunDay;
  final ValueChanged<int> onPersona;
  final ValueChanged<bool> onSkeleton;
  final ValueChanged<bool> onShowSlider;
  final ValueChanged<bool> onShowStart;
  final ValueChanged<bool> onShowExperience;
  final ValueChanged<bool> onShowRaceGoal;
  final ValueChanged<bool> onShowLongRunDay;
  final VoidCallback onShortNotice;

  const _Toolbar({
    required this.personas,
    required this.index,
    required this.skeleton,
    required this.showSlider,
    required this.showStart,
    required this.showExperience,
    required this.showRaceGoal,
    required this.showLongRunDay,
    required this.onPersona,
    required this.onSkeleton,
    required this.onShowSlider,
    required this.onShowStart,
    required this.onShowExperience,
    required this.onShowRaceGoal,
    required this.onShowLongRunDay,
    required this.onShortNotice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EC.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < personas.length; i++)
            ChoiceChip(
              label: Text(personas[i].name),
              selected: i == index,
              onSelected: (_) => onPersona(i),
            ),
          const SizedBox(width: 12),
          FilterChip(
            label: const Text('Runs slider'),
            selected: showSlider,
            onSelected: onShowSlider,
          ),
          FilterChip(
            label: const Text('Plan start'),
            selected: showStart,
            onSelected: onShowStart,
          ),
          FilterChip(
            label: const Text('Experience'),
            selected: showExperience,
            onSelected: onShowExperience,
          ),
          FilterChip(
            label: const Text('Race goal'),
            selected: showRaceGoal,
            onSelected: onShowRaceGoal,
          ),
          FilterChip(
            label: const Text('Long run day'),
            selected: showLongRunDay,
            onSelected: onShowLongRunDay,
          ),
          ActionChip(
            label: const Text('Short notice'),
            onPressed: onShortNotice,
          ),
          FilterChip(
            label: const Text('Skeleton'),
            selected: skeleton,
            onSelected: onSkeleton,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: UnitUtils.useMilesNotifier,
            builder: (_, useMiles, __) => FilterChip(
              label: const Text('Miles'),
              selected: useMiles,
              onSelected: (v) => UnitUtils.useMilesNotifier.value = v,
            ),
          ),
        ],
      ),
    );
  }
}
