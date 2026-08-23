/// PreRunCheck — three-question pre-run gate.
///
/// Questions:
///   1. How was your sleep? (good / poor)
///   2. Any pain? (none / upper body / leg / chest) — skipped if need rest
///
/// Outcomes:
///   good sleep + no/upper pain → run as planned
///   poor sleep or leg pain     → PreRunScaler adjusts dose + downgrade recorded
///   chest pain                 → blocked, doctor message
library;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../engines/daily/pre_run_scaler.dart';
import '../engines/daily/weather_scaler.dart';
import '../engines/config/workout_template_library.dart';
import '../services/coach_message_builder.dart' as message;
import '../services/weather_service.dart';
import '../engines/memory/engine_memory_service.dart';

// ============================================================================
// ENTRY POINT
// ============================================================================

Future<void> showPreRunCheck({
  required BuildContext context,
  required message.CoachMessage coachMessage,
  required void Function(message.CoachMessage scaled) onProceed,
  required VoidCallback onSkip,
  WeatherSnapshot? weather,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PreRunCheckSheet(
      coachMessage: coachMessage,
      onProceed: onProceed,
      onSkip: onSkip,
      weather: weather,
    ),
  );
}

// ============================================================================
// SHEET
// ============================================================================

enum _Step { sleep, pain, restChoice, chestWarning }

class _PreRunCheckSheet extends StatefulWidget {
  final message.CoachMessage coachMessage;
  final void Function(message.CoachMessage scaled) onProceed;
  final VoidCallback onSkip;
  final WeatherSnapshot? weather;

  const _PreRunCheckSheet({
    required this.coachMessage,
    required this.onProceed,
    required this.onSkip,
    this.weather,
  });

  @override
  State<_PreRunCheckSheet> createState() => _PreRunCheckSheetState();
}

class _PreRunCheckSheetState extends State<_PreRunCheckSheet> {
  _Step _step = _Step.sleep;
  PreRunSleep? _sleep;

  // ── Step handlers ────────────────────────────────────────────────────────

  void _onSleepSelected(PreRunSleep sleep) {
    _sleep = sleep;
    setState(() => _step = _Step.pain);
  }

  void _onPainSelected(PainLocation pain) {
    if (pain == PainLocation.chest) {
      setState(() => _step = _Step.chestWarning);
      return;
    }
    _finalize(pain);
  }

  void _finalize(PainLocation pain) {
    final sleep = _sleep ?? PreRunSleep.good;
    final inputs = PreRunInputs(
      feeling: PreRunFeeling.normal,
      sleep: sleep,
      pain: pain,
    );
    final scaler = const PreRunScaler();
    final result = scaler.scale(widget.coachMessage.resolvedWorkout, inputs);

    var finalWorkout = result.workout;
    var finalNote = result.coachNote;
    final weather = widget.weather;
    debugPrint('[WeatherDebug] weather=$weather');
    if (weather != null) {
      final weatherResult = const WeatherScaler().scale(finalWorkout, weather);
      debugPrint('[WeatherDebug] apparentTempC=${weather.apparentTempC} humidity=${weather.humidityPercent} wasAdjusted=${weatherResult.wasAdjusted}');
      if (weatherResult.wasAdjusted) {
        finalWorkout = weatherResult.workout;
        finalNote = finalNote != null
            ? '$finalNote ${weatherResult.coachNote}'
            : weatherResult.coachNote;
      }
    }

    final scaled = _rebuildMessage(finalWorkout, finalNote);

    // ── Record downgrade if workout was actually reduced ──────────────────
    // Poor sleep OR leg pain causes PreRunScaler to reduce the workout.
    final wasDowngraded =
        sleep == PreRunSleep.poor || pain == PainLocation.leg;
    if (wasDowngraded) {
      // Fire and forget — non-blocking
      EngineMemoryService().recordPreRunDowngrade();
    }

    Navigator.pop(context);
    widget.onProceed(scaled);
  }

  void _onTakeFullRest() {
    Navigator.pop(context);
    widget.onSkip();
  }

  void _onTakeRecoveryRun() {
    Navigator.pop(context);
    widget.onProceed(widget.coachMessage);
  }

  message.CoachMessage _rebuildMessage(ResolvedWorkout scaled, String? note) {
    final original = widget.coachMessage;
    return message.CoachMessage(
      reflectionText: note ?? original.reflectionText,
      acknowledgementText: original.acknowledgementText,
      workoutTitle: scaled.name,
      workoutSteps: original.workoutSteps,
      resolvedWorkout: scaled,
      workoutIntent: scaled.intent,
      goalText: original.goalText,
      feelText: original.feelText,
      phaseLabel: original.phaseLabel,
      weekNumber: original.weekNumber,
      movedFromDay: original.movedFromDay,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 20, 24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      _Step.sleep        => _SleepStep(onSleep: _onSleepSelected),
      _Step.pain         => _PainStep(onPain: _onPainSelected, onBack: () => setState(() => _step = _Step.sleep)),
      _Step.restChoice   => _RestChoiceStep(onFullRest: _onTakeFullRest, onRecoveryRun: _onTakeRecoveryRun, onBack: () => setState(() => _step = _Step.sleep)),
      _Step.chestWarning => _ChestWarningStep(onDismiss: () { Navigator.pop(context); widget.onSkip(); }),
    };
  }
}

// ============================================================================
// STEP WIDGETS
// ============================================================================

class _SleepStep extends StatelessWidget {
  final void Function(PreRunSleep) onSleep;

  const _SleepStep({required this.onSleep});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'How was your sleep?',
      subtitle: 'Poor sleep affects recovery and performance.',
      children: [
        _OptionCard(emoji: '😴', label: 'Slept well', subtitle: '7+ hours, felt rested', onTap: () => onSleep(PreRunSleep.good)),
        _OptionCard(emoji: '🥱', label: 'Poor sleep', subtitle: 'Broken or under 6 hours', onTap: () => onSleep(PreRunSleep.poor)),
      ],
    );
  }
}

class _PainStep extends StatelessWidget {
  final void Function(PainLocation) onPain;
  final VoidCallback onBack;

  const _PainStep({required this.onPain, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Any pain or discomfort?',
      subtitle: 'Be honest — this keeps you running long term.',
      onBack: onBack,
      children: [
        _OptionCard(emoji: '✅', label: 'No pain', subtitle: 'Feeling physically fine', onTap: () => onPain(PainLocation.none)),
        _OptionCard(emoji: '💪', label: 'Upper body', subtitle: 'Shoulders, arms, back — won\'t affect the run', onTap: () => onPain(PainLocation.upperBody)),
        _OptionCard(emoji: '🦵', label: 'Leg or foot pain', subtitle: 'Shins, knees, calves, feet — dose reduced', onTap: () => onPain(PainLocation.leg)),
        _OptionCard(emoji: '❤️', label: 'Chest or breathing', subtitle: 'Take today off and consider seeing a doctor', onTap: () => onPain(PainLocation.chest)),
      ],
    );
  }
}

class _RestChoiceStep extends StatelessWidget {
  final VoidCallback onFullRest;
  final VoidCallback onRecoveryRun;
  final VoidCallback onBack;

  const _RestChoiceStep({
    required this.onFullRest,
    required this.onRecoveryRun,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'That\'s okay.',
      subtitle: 'What do you want to do today?',
      onBack: onBack,
      children: [
        _OptionCard(emoji: '🛌', label: 'Take full rest', subtitle: 'Skip today, mark as rest day', onTap: onFullRest),
        _OptionCard(emoji: '🚶', label: 'Easy recovery run', subtitle: '20–30 min shakeout at very easy pace', onTap: onRecoveryRun),
      ],
    );
  }
}

class _ChestWarningStep extends StatelessWidget {
  final VoidCallback onDismiss;

  const _ChestWarningStep({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dragHandle(context),
        const SizedBox(height: 24),
        const Text('❤️', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        Text(
          'Take today off',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          'Chest pain or breathing issues during exercise should always be checked. Consider speaking to a doctor before your next run.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                'Got it, taking rest today',
                style: TextStyle(color: c.onAccent, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SHARED COMPONENTS
// ============================================================================

class _StepShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;

  const _StepShell({
    required this.title,
    required this.subtitle,
    required this.children,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _dragHandle(context)),
        const SizedBox(height: 20),
        Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.textPrimary, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 13, color: c.textTertiary, height: 1.4)),
        const SizedBox(height: 20),
        ...children.expand((w) => [w, const SizedBox(height: 10)]).toList()..removeLast(),
        if (onBack != null) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onBack,
            child: Row(
              children: [
                Icon(Icons.arrow_back_ios_rounded, size: 13, color: c.textTertiary),
                const SizedBox(width: 4),
                Text('Go back', style: TextStyle(fontSize: 13, color: c.textTertiary, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Widget _dragHandle(BuildContext context) => Container(
  width: 36, height: 4,
  decoration: BoxDecoration(color: context.colors.border, borderRadius: BorderRadius.circular(2)),
);

class _OptionCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border, width: 1.5),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: c.textTertiary)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 13, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}